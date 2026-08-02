# Primary Review Log

Status: complete

## Required Reading Completed

- repository `AGENTS.md`;
- `axiom-health-check`;
- `axiom-testing` and `axiom-audit-testing`;
- repository-local `apple-hig` and its Tier 1/platform routing baseline;
- repository-local `swiftui-expert-skill` and latest API reference;
- `Docs/ProjectMap.md`, `Docs/Architecture.md`, `Docs/CodeGuide.md`, `Docs/UI-Design.md`, `Docs/Testing.md`, `Docs/CodeRefactorPlan.md`, and the accepted-decision register in `Docs/AgentDecisions.md`.

## Primary Scope

- repository-wide hack markers and unsafe-language patterns;
- architecture/documentation-to-code drift;
- cross-validation of every high/critical and over-engineering candidate;
- deduplication and final risk ranking.

## Constraints

- Read-only audit of production and test sources.
- No production/test edits or new tests.
- Build/test execution is diagnostic only and will be scheduled after static findings identify the highest-value gates.

## PRI-001 — Startup suppresses authoritative sync-prompt read failure

- Status: confirmed
- Severity: high
- Category: latent-bug | hack | security/privacy
- Confidence: high
- Evidence: `timetracker/Stores/Facade/TimeTrackerStore+Configuration.swift:47-58`
- Contract: AD-074 requires every `SyncConflictService.prompt()` call site to propagate/readably handle errors and explicitly forbids adding `try?`; Cloud recovery must remain read-only until the protected branch is resolved.
- Execution path: an application-state store starts with a corrupt, oversized, permission-denied, or otherwise unreadable authoritative conflict state; `prompt()` throws; `try?` converts the result to `nil`; startup does not enter `configureCloudRecovery` and proceeds into preference migration, legacy countdown migration, and seed writes before the later bootstrap retry.
- Impact: the app can temporarily treat an unknown conflict state as safe and execute write-side startup work before recovery establishes whether the protected local/cloud branches diverge. The later bootstrap may surface the error, but cannot make the already-attempted writes satisfy the read-only recovery barrier.
- Why this is not intentional: the only other production prompt callers use throwing paths; AD-074 was introduced specifically to remove this failure suppression. `bootstrapSyncConflictStateIfNeeded` running later is recovery logic, not permission to write first.
- Counter-evidence checked: `configureCloudRecovery`, `bootstrapSyncConflictStateIfNeeded`, all `syncConflictService.prompt()` call sites, and startup tests found by prompt/configuration searches. Bootstrap retries and can recover an independent mirror, reducing data-loss likelihood, but it occurs after migrations/seeding in this path.
- Recommendation: make the initial prompt read a throwing startup boundary. On failure, enter the read-only recovery/diagnostic path (or abort write-side configuration) before migrations, seeding, Pomodoro reconciliation, or other startup effects. Add one command/lifecycle contract using an unreadable/corrupt state and an independent sentinel proving zero startup writes.

## PRI-002 — Replaced AI task-plan stack remains compiled production surface

- Status: confirmed
- Severity: medium
- Category: code-smell | over-engineering
- Confidence: high
- Evidence: `timetracker/Services/LLM/LLMTaskPlanService.swift:1`, `timetracker/Services/Tasks/StoreScopedAITaskPlanCommandCoordinator.swift:1`, `timetracker/Stores/Facade/TimeTrackerStore+AITaskPlanCommands.swift:73`
- Contract: `Docs/CodeGuide.md` names `LLMTaskWorkspacePlanningService -> AITaskWorkspaceOverlay -> StoreScopedAITaskAtomicMutationCoordinator` as the production chain and states that the old service/coordinator are compatibility-test-only, not a production entry point.
- Execution path: repository-wide symbol searches find no construction of `LLMTaskPlanService` and no call to `saveAITaskPlan`; the old draft/coordinator path remains compiled into the app target. Together the old service, old coordinator, and obsolete facade method account for approximately 1,125 lines alongside the replacement implementation.
- Impact: two complete plan validation/apply models can drift on limits, field policy, depth, atomicity, and error semantics. Reviewers and future callers can select the obsolete facade method because it remains available in production, expanding maintenance and security review without active product behavior.
- Why this is not intentional: compatibility tests can preserve transport/fixture decoding without leaving a callable legacy mutation path in the shipping module. The current docs explicitly prohibit new production fallback to this flow.
- Counter-evidence checked: all production/test references to `LLMTaskPlanService`, `AITaskPlanDraft`, `StoreScopedAITaskPlanCommandCoordinator`, and `saveAITaskPlan`. Shared `LLMTaskPlanServiceError` and a depth constant are still reused by the new stack, so removal requires first extracting those shared contracts rather than deleting the file wholesale.
- Recommendation: bound a cleanup task that extracts the still-shared error/constants/legacy fixture DTOs, deletes the unused network generation and facade mutation entry, and retains only compatibility decoding tests that protect a documented external contract.

## PRI-003 — Checklist reorder validates a scoped set, then refetches the entire table

- Status: confirmed
- Severity: medium
- Category: performance | code-smell
- Confidence: high
- Evidence: `timetracker/Services/Checklist/StoreScopedChecklistCommandCoordinator.swift:130-155`, `timetracker/Commands/ChecklistCommands.swift:89-109`
- Contract: normal checklist mutations are documented as task-scoped and expected to avoid full-database materialization; repository/domain queries should be bounded to the affected domain identity.
- Execution path: any checklist reorder acquires the store-scoped writer, fetches and validates only rows for `baseline.taskID`, then calls `ChecklistCommandHandler.reorder`, which immediately performs an unpredicated `FetchDescriptor<ChecklistItem>()`, materializes every checklist row in the store, deduplicates all of them, and filters back to the same task.
- Impact: reorder cost grows with every checklist item in the database rather than the reordered task. It also duplicates canonical-set derivation within one lock/transaction, increasing the chance that the handler and coordinator acquire divergent order or dedup semantics.
- Why this is not intentional: the coordinator already owns a fresh scoped set after CAS validation. Other global Inbox fetches can be justified by logical identity reconstruction across physical rows; this checklist path has a direct `taskID` predicate and no cross-task identity requirement.
- Counter-evidence checked: `visibleItems(taskID:context:)`, coordinator call sites, handler implementation, and current checklist command tests. Existing tests verify outcomes but not bounded query shape.
- Recommendation: pass the already validated scoped items into the command handler, or apply the same task predicate inside the handler. Retain a deterministic correctness contract and add an observable bounded-query integration check only if it can avoid implementation/source scanning.

## PRI-004 — “Bounded” cross-process lock waits use adjustable wall time

- Status: confirmed
- Severity: medium
- Category: latent-bug | concurrency | code-smell
- Confidence: high
- Evidence: `timetracker/Services/SystemIntegration/PathFileLock.swift:46-65`, `timetracker/Services/SystemIntegration/SyncConflictService+StateLock.swift:45-63`
- Contract: both implementations explicitly promise a bounded acquisition budget so a Widget/Shortcuts-held lock cannot freeze the caller, often the main thread.
- Execution path: a competing process holds the file lock while the app is retrying; during the five-second wait, automatic/manual clock correction moves wall time backwards or forwards. Both loops compare `Date()` against a `Date` deadline.
- Impact: a backward adjustment can extend the wait beyond the documented bound (large corrections can make it effectively hang); a forward adjustment can cause premature timeout. This affects recovery/state operations that are designed to fail predictably instead of blocking UI/system actions.
- Why this is not intentional: elapsed-time deadlines should use a monotonic clock. Calendar time is not part of the lock protocol and no persisted timestamp needs to be compared here.
- Counter-evidence checked: complete acquisition/release functions and test references. No injected clock or separate monotonic guard exists. The `usleep` backoff itself is bounded, but the loop termination condition is not monotonic.
- Recommendation: share a small monotonic acquisition helper based on `ContinuousClock`/`clock_gettime(CLOCK_MONOTONIC, ...)`, preserving distinct `flock` versus `lockf` error handling. Add deterministic clock/backoff seam coverage if practical; otherwise keep a focused unit around elapsed deadline calculation.

## Verification Log

- `make format-check`: passed; 0/716 files require formatting.
- `make localization-check`: passed; all 9 resources have parity.
- `make test`: passed; 147 tests in 23 suites, signed macOS test host. The run emitted repeated SQLite API-violation warnings from tests deleting store files while descriptors remained open; delegated for test-quality validation.
- `make build-ios`: passed with automatic signing, Apple Development identity, and the configured HealthKit development profile.

## Cross-Validation And Disposition

- Independently confirmed the persistence sub-audit's attempt-file result: `loadAttemptWithExclusiveAccess` quarantines both read and decode failures and returns `nil`; `load(for:)` consequently accepts an old ready cursor instead of forcing the full reconciliation promised by AD-137.
- Independently confirmed the reset-fence result: decoding is shared by registration, cursor checks, and `advanceForStoreReset`; malformed bytes therefore fail closed, but no locked repair transition can invalidate lanes and publish a fresh nonzero epoch.
- Independently confirmed the recurrence result against `Docs/Architecture.md:207`: active segments use a bounded candidate query, while quantity entries and Pomodoro runs are unpredicated and filtered/materialized in memory on every fresh recurrence state.
- Accepted the UI/test findings after reading the owner lifetimes and protocol consumers. The Watch identity issue remains low because the current processor ignores the field; the SQLite cleanup issue remains test-only because all assertions passed and production data is not exposed.
- Accepted the AI review-presentation concentration as a concrete verification/coupling smell, not on line count alone. Accepted the old AI plan stack as the audit's only over-engineering finding because it has no production caller, duplicates an active replacement, and retains a callable shipping facade.
- Kept full-workspace AI Apply as `needs-runtime-verification`: complete atomic CAS is an accepted requirement, so a Release trace is required before calling its MainActor cost a confirmed performance failure.
- Deduplicated PRI-001/PSS-001, PRI-003/DCP-002, and PRI-004/DCP-001. Final stable IDs are in `FindingsIndex.md`.
