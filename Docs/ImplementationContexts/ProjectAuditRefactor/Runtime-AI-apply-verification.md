# Runtime AI Apply Verification

Status: complete

## Scope

Resolve the audit's only runtime-gated lead: complete-workspace AI Apply fetches,
canonicalizes, fingerprints, validates, and mutates synchronously on MainActor.
The complete uncapped workspace and atomic CAS are accepted product contracts;
truncation or weakening validation is out of scope.

Use a seeded Release workload, production signposts, and an attached CPU trace.
Only confirm a performance finding when evidence shows an interaction-scale main
thread stall. If confirmed, move the work off MainActor while preserving the
shared store lock, fresh-context CAS, atomic rollback, and MainActor publication.

## Confirmed Release evidence

The isolated workload contained 50 categories, 5,000 tasks, 5,000 category
assignments, 10,000 checklist items, and 25 reviewed task updates. Three
pre-change Release runs reported:

| Run | Complete capture | Atomic Apply |
| --- | ---: | ---: |
| 1 | 525.907 ms | 9,333.975 ms |
| 2 | 540.766 ms | 9,366.166 ms |
| 3 | 522.936 ms | 9,090.110 ms |

The attached pre-change trace at
`/tmp/timetracker-ai-apply-signpost.boPbV3/ai-apply-release.trace` captured the
`AI workspace atomic apply` end event on `Main Thread` and a system
`ResponsiveCheckFailed` event. The trace started after the interval began, so
duration authority remains the workload's `ContinuousClock` measurement.

This confirms a user-visible freeze, not a speculative micro-optimization.

## Implementation

`StoreScopedAITaskAtomicMutationCoordinator` is now a dedicated actor. The
MainActor facade resolves its store scope and authorization, awaits the actor,
then alone publishes refresh, routing, and errors. Inside the actor the shared
store lock, fresh-context creation, complete recapture/CAS, validation,
repository mutations, checkpoint injection, and one save-or-rollback remain a
single synchronous section with no `await`.

The shared transaction, ModelContext atomic nesting, context-owned task
repository, and the synchronous policy/recurrence graph are caller-isolated
`nonisolated` code. No ModelContext, repository, or SwiftData model is Sendable
or crosses actors. ModelContext nesting is task-local and context-keyed, so
independent MainActor and persistence-actor transactions cannot race through a
mutable global depth table.

## Permanent test record

`AITaskAtomicMutationExecutorTests` retains three command-boundary contracts:

| Test | Risk protected | Independent oracle | Boundary |
| --- | --- | --- | --- |
| `applyRunsPersistenceWorkOutsideMainThread` | a future wrapper silently returns the full transaction to MainActor | the injected in-transaction checkpoint observes `Thread.isMainThread == false`, and a fresh context sees the committed title | persistence actor through durable save |
| `applyRejectsAStaleCompleteBaselineWithoutMutation` | async dispatch weakens the full optimistic CAS | an independent context changes the revision after capture; Apply throws `workspaceChanged` and a fresh context retains only that external edit | lock-held recapture/CAS |
| `checkpointFailureRollsBackEveryReviewedOperation` | actor migration or nested saves permit partial commit | the first checkpoint throws and a fresh context sees both original titles | outer atomic save/rollback |

These are permanent regression contracts, not timing thresholds.

## Temporary test record and cleanup

`timetrackerTests/Performance/AITaskAtomicMutationPerformanceScaffoldTests.swift`
was `TEST-SCAFFOLD`. It seeded the workload above; its oracle checked only that
complete capture and Apply succeeded and emitted one-time durations.

The removal condition was met after the post-change trace, and the file was
deleted. No wall-clock threshold or `TEST-SCAFFOLD` marker remains.

## Post-change Release evidence

The same workload reported 521.540 ms complete capture and 8,632.551 ms atomic
Apply. The full attached trace is
`/tmp/timetracker-ai-apply-post.AlY92b/ai-apply-release.trace`:

- baseline capture: `00:03.529525`–`00:04.050812`, actor thread `0xccee7`;
- atomic Apply: `00:04.050935`–`00:12.683413`, actor thread `0xcd08e`;
- neither interval ran on the labelled Main Thread;
- the exported structured signpost table contained no
  `ResponsiveCheckFailed` event.

Comparable total duration confirms that complete facts, validation, and atomic
commit were preserved; responsiveness comes from isolation, not truncation.

## Verification and closeout

Completed:

- the targeted executor suite passed all 3 permanent contracts;
- the full signed macOS suite passed all 166 tests in 26 suites;
- `make format-check` passed all 720 Swift files and
  `make localization-check` passed all 9 localized resources;
- signed Debug `make build-ios` and `make build-macos` builds succeeded,
  including the Watch, Widget, and Live Activity extensions;
- pre/post Release measurements and attached traces were retained, and the
  temporary performance scaffold was removed;
- every AUD finding is resolved, the implementation index is reconciled, and
  `make check-hooks` confirms the tracked Git hook is active;
- no owned `xcodebuild`, `xctest`, UI runner, or Booted simulator remains. The
  already-running installed app at `/Applications/timetracker.app` was not
  started or terminated by this work.
