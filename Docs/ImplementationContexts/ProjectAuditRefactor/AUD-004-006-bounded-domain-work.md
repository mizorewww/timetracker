# AUD-004/005/006 Bounded Domain Work

Status: complete

## Scope

Close three related serialized-work findings without changing product behavior:

- Recurrence state must not materialize all quantity-entry and Pomodoro history.
  Quantity-entry collision protection becomes a fetch limited to the exact
  generated task/goal claim, while Pomodoro discovery uses active candidates
  plus canonical-ID resolution.
- Checklist reorder must reuse the scoped canonical rows already validated by
  its command coordinator instead of fetching the whole checklist table again.
- Cross-process `flock` and `lockf` retry budgets must measure elapsed time with
  a monotonic clock, while preserving their distinct POSIX error handling and
  bounded exponential backoff.

Out of scope: changing recurrence identity, checklist ordering, lock ownership,
AI workspace performance, or schema/index definitions.

## Performance hotspot map

- Recurrence state construction runs on `@MainActor` while the store-scoped
  writer transaction is held and is reached by lifecycle materialization.
- Its large dictionaries/sets are intentional transaction snapshots; the
  amplified defect is unbounded input cardinality, not value-copy semantics.
- Quantity entries are used only as physical collision claims for a single
  generated task/goal pair during materialization.
- Pomodoro history is used only to derive currently active work task IDs; the
  repository already establishes the active-candidate/canonical-ID pattern.
- Checklist reorder validates a task-scoped canonical array before entering the
  handler, so the handler's second global fetch has no independent oracle.
- Both file-lock loops are synchronous cross-process boundaries and may execute
  for callers on the main thread; their backoff is bounded but wall-clock
  deadline arithmetic is not monotonic.
- Production scans found no `@inlinable`/`@usableFromInline` tuning surface and
  no actor hop inside either affected loop.
- Existentials, weak captures, append loops, and large structs elsewhere did
  not compound these three confirmed findings.

## Test record

| Contract | Risk protected | Independent oracle | Boundary | Lifetime |
| --- | --- | --- | --- | --- |
| An orphan quantity entry that physically claims today's deterministic generated task/goal IDs prevents recurrence materialization | A scoped query optimization could ignore a staged CloudKit half-import and attach old quantity history to a newly generated task | Seed only the template plus an orphan entry for the independently computed generated ID, create the daily rule, and assert no occurrence/generated task is committed | `StoreScopedTaskRecurrenceCommandCoordinator` durable command boundary | Permanent durable-data regression |
| Canonical active Pomodoro work blocks converting its task into a recurrence template, while closed history does not | Active-only candidate filtering could drop a live run or let closed history remain a false blocker | Seed one task/run at a time and assert the documented command outcome (`templateHasActiveWork` for active; successful rule creation for completed) | Recurrence command boundary with real SwiftData models | Permanent cross-model transaction regression |
| Checklist reorder preserves scoped CAS and ordering behavior | Passing validated rows into the handler must not weaken stale-baseline rejection or reorder semantics | Existing `staleReorderCannotOverwriteANewerItemMutation`; add a successful reorder assertion only if current coverage lacks one | Existing checklist command suite | Permanent existing contract; no duplicate test unless needed |

The monotonic deadline change has no deterministic public clock-injection seam;
adding a private-helper mirror test would violate the repository's test policy.
It will be verified by focused/full builds plus direct review that both retry
loops use `ContinuousClock` and retain their error/descriptor cleanup branches.

One temporary `TEST-SCAFFOLD` Release probe seeded 10,000 unrelated rows in
each affected history table and measured recurrence-state construction plus
checklist reorder. It was applied to both commit `3c1f7852` and the working
implementation, then deleted. It was never retained as a product contract.

## Runtime performance evidence

The temporary probe ran as a signed Release test on the macOS host. Each run
seeded 10,000 unrelated `TaskQuantityEntry`, `PomodoroRun`, and `ChecklistItem`
rows, exercised the same recurrence-state and checklist-command boundaries,
and emitted `AUD-PERF` elapsed intervals without adding a timing assertion.

| Revision | Recurrence state | Checklist reorder | Result shape |
| --- | ---: | ---: | --- |
| `3c1f7852` baseline | 307.132 ms | 153.917 ms | Correct; 6 probe/contract tests passed |
| Working implementation | 1.344 ms | 1.422 ms | Correct; 9 probe/contract tests passed |

The result confirms that unrelated history cardinality no longer determines
either serialized operation. The temporary worktree and probe were removed
after capture.

## Scoped Swift performance health

| Dimension | Result |
| --- | --- |
| Value-type efficiency | No copy amplification found in the affected state; the defect was unbounded inputs |
| ARC discipline | Weak-capture scan found no ownership issue in the affected hot paths |
| Generic specialization | Existential scan found no specialization barrier in the affected hot paths |
| Collection efficiency | Exact-entry lookup and active-candidate resolution bound input collections; checklist reuses its scoped array |
| Actor efficiency | No added actor hop or suspension inside the serialized transaction work |
| Hot-path coverage | 3/3 confirmed hot paths bounded after refactor |

Scoped health: optimized. This rating applies to AUD-004/005 only, not to the
remaining AI workspace runtime-verification item.

## Verification and closeout

- Permanent recurrence contracts: 8/8 passed.
- Permanent checklist contracts: 10/10 passed.
- `make format-check`: 716 Swift files clean.
- `make localization-check`: 9/9 resources passed.
- `make test`: 154 tests in 23 suites passed.
- Direct review confirmed both retry loops now share a `ContinuousClock`
  deadline while preserving their distinct POSIX error and descriptor cleanup
  paths.
- Temporary Release probe and baseline worktree removed; no owned simulator,
  `xcodebuild`, `xctest`, or trace process remains.
