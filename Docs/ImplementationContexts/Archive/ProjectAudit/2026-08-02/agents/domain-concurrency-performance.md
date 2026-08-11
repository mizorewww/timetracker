# Domain Concurrency And Performance Audit

Status: Complete

- Assigned scope: read-only review of `Commands`, `Stores`, and domain `Services`, with emphasis on timer/ledger/tasks/checklist/analytics/forecast/recurrence; actor/async/lock/transaction boundaries; memory ownership; performance; and verification of bounded/incremental claims.
- Explicit exclusions: no production or test source modifications; no UI/HIG visual audit; sync/security details only where they directly establish a concurrency, transaction, memory, or performance contract.
- Skills read completely: `axiom-audit-concurrency`, `axiom-audit-memory`, `axiom-analyze-swift-performance`, `axiom-performance`, `axiom-audit-swiftdata`, `axiom-testing`; task-relevant `axiom-performance/skills/memory-debugging.md` and `swift-performance.md`.
- Project documents read: `AGENTS.md`, `Docs/ImplementationContexts/Archive/ProjectAudit/2026-08-02/DocumentationStandard.md`, `Docs/ProjectMap.md`, `Docs/Architecture.md`, `Docs/CodeGuide.md`, `Docs/Testing.md`, `Docs/CodeRefactorPlan.md`, and relevant accepted decisions including AD-017, AD-018, AD-020, AD-023 through AD-026, AD-128 through AD-130, and AD-137.
- Files/directories inspected: repository-wide production Swift inventory (660 files); domain inventory under `Commands`, `Stores`, `Services`, `Repositories`, and `Models` (405 files); containing files/callers will be added below.
- Searches/commands used: initial `wc -l`, full/chunked `cat`/`sed` reads of required skills/docs, `rg` routing over `Docs/AgentDecisions.md`, and every required Axiom grep family for isolation/entry points, concurrency escape hatches, resource ownership/cleanup, Swift allocation/hot-path indicators, and SwiftData container/schema/context/migration indicators. Raw scan logs are under `/tmp/scan-*.txt` for this audit session.
- Current status: complete.

## Audit Method And Evidence Log

- Findings must satisfy `DocumentationStandard.md`; candidates, counter-evidence, and rejected leads remain recorded.
- Axiom phase scans will exclude test/vendor/docs paths initially; direct callers and relevant tests will be inspected for cross-validation of serious candidates.
- No runtime leak or performance claim will be marked confirmed from static evidence alone where Instruments/trace evidence is required.
- Initial concurrency counts: 12 actor declarations, 237 `@MainActor` hits, 73 `Task {}` hits, 1 `Task.detached`, 13 stored `Task` declarations, 3 `DispatchQueue` uses, 12 `@unchecked Sendable`, 1 `nonisolated(unsafe)`, and no `@preconcurrency`.
- Initial memory counts: no scheduled/published timers, Combine sinks/assignments, delegate properties, repeating timer invalidation pairs, or PhotoKit requests; 10 observer registration leads, 13 stored Tasks, and 5 explicit `deinit` blocks require contextual pairing.
- Initial performance counts in the 405-file domain set: 727 `for` hits, 132 `while`, 156 appends versus 25 reservations, 57 existential `any` hits, 132 awaits, and 7 actor declarations. These are leads only; hot-path amplification must be proven.
- Initial SwiftData counts: 27 container construction hits, 10 configurations, 6 explicit `ModelContext` constructions, 15 schema versions/model arrays, 93 direct insert/delete calls versus 5 literal `context.save()` calls. Save ratio is not meaningful until nested `saveAfterMutationStep`/`performAtomicMutation` is cross-checked.
- Primary-agent cross-check request: validate the two file-lock wait loops in `PathFileLock.swift:49-65` and `SyncConflictService+StateLock.swift:47-63`, specifically their `Date()`-based five-second deadline against the declared bounded contract and monotonic-clock behavior; inspect callers/tests and duplication before deciding.

## Isolation Architecture Map

- The dominant domain boundary is `@MainActor`: the store facade and store-scoped command coordinators synchronously create fresh SwiftData contexts only after acquiring the store mutation lock. `StoreScopedTimerMutationTransaction` couples the in-process recursive lock, cross-process file lock, fresh context, and atomic save/rollback boundary; the examined mutation paths do not let a `ModelContext` escape that scope.
- Background ownership is explicit where it exists: persistent-history readers/drivers, sync snapshot/materialization, widget writing, and prompt reading use actors. Analytics has one `Task.detached` path, but it receives immutable `Sendable` snapshot DTOs rather than SwiftData models.
- Unstructured tasks are primarily lifecycle/debounce work. Stored tasks inspected in the store and Live Activity paths are cancelled during teardown. No `@concurrent` or task-group based domain implementation was found.
- Concurrency escape-hatch scan found 12 `@unchecked Sendable` declarations and one `nonisolated(unsafe)` declaration. Contextual review did not establish a race in the sampled cases: the `AppDefaults.shared` escape hatch wraps an immutable `UserDefaults` reference, is explicitly justified by Foundation's thread-safe API, and is replaced only through test runtime isolation.

## Resource Ownership Map

- `TimeTrackerStore` cancels its stored lifecycle/materialization tasks during teardown (`TimeTrackerStore.swift:139-160`). Live Activity task owners likewise cancel stored work in `deinit`.
- `SyncNotificationObserverToken` removes its `NotificationCenter` token in `deinit`, and inspected observer closures use weak ownership (`TimeTrackerStore+SyncObservers.swift:4-13`).
- No production scheduled/published `Timer`, Combine `sink`/`assign`, delegate property, repeating-timer, or PhotoKit request ownership pattern was found by the required memory scan.
- The static store-mutation broadcaster task is a finite next-turn drain with a bounded queue (64), not an unbounded repeating owner. Static review found no confirmed retain cycle or resource leak in this scope; runtime leak claims were intentionally not inferred without Instruments evidence.

## Performance Hotspot Map

- **Every checklist reorder:** one scoped fetch and validation is followed by an unnecessary whole-table `ChecklistItem` fetch in the handler. Cost scales with unrelated checklist history.
- **Every recurrence state transaction/materialization:** the state builder fetches every recurrence-domain row, every quantity entry, and every Pomodoro run. Active time segments already use a bounded candidate-ID pattern, making the unbounded Pomodoro/history materialization conspicuous.
- **AI workspace capture/apply:** the intentionally uncapped workspace is synchronously fetched, deduplicated, normalized, sorted, fingerprinted, and validated on `@MainActor`; apply also runs under the global writer transaction. This is a strong jank risk for large workspaces, but needs a seeded Release trace before claiming a measured stall.
- Ledger/rollup paths examined use incremental indexes and bounded canonical-ID resolution. The single detached analytics computation operates on a value snapshot, which is the appropriate confinement pattern.

## SwiftData Map

- The repository uses versioned schemas through V14 plus a separately scoped Apple Health replica. Store-scoped writers generally construct a fresh `ModelContext` only after lock acquisition and route saves through `saveAfterMutationStep`/`performAtomicMutation`.
- The raw count of five literal `context.save()` calls is a rejected metric: command paths save through nested helpers, so comparing it with 93 `insert`/`delete` hits would falsely imply missing saves.
- No SwiftData model crossing into the examined detached analytics task was found. This scoped review produced performance/query-shape findings, not a confirmed schema-registration or migration correctness defect.

## Confirmed Findings

### DCP-001 — File-lock timeout uses wall time and is not actually bounded

- **Category / severity / confidence:** latent bug, concurrency, duplicated code smell / medium / high.
- **Evidence:** `PathFileLock.swift:46-65` promises a bounded acquire budget but constructs the deadline with `Date()` at line 49 and tests it with `Date()` at line 60. `SyncConflictService+StateLock.swift:45-63` duplicates the same wall-clock deadline at lines 47 and 58. Both retry a nonblocking POSIX file lock with exponential `usleep` backoff and are called from cross-process mutation paths that may run on the main thread.
- **Trigger and impact:** if system wall time moves backward while waiting, the nominal five-second budget can be extended arbitrarily; a forward adjustment can fail prematurely. The implementation therefore does not satisfy its documented “bounded”/“never hang” contract.
- **Counter-evidence checked:** backoff is capped, non-contention errors close the descriptor, and normal time progression does terminate. Those facts do not protect elapsed-time accounting from clock adjustment. No test or injected clock guard for this behavior was found.
- **Recommendation:** measure elapsed time with `ContinuousClock` or `clock_gettime(CLOCK_MONOTONIC, ...)`. Share only a monotonic-deadline/backoff helper; preserve the distinct `flock` versus `lockf` error handling.

### DCP-002 — Checklist reorder refetches the entire checklist table after scoped validation

- **Category / severity / confidence:** performance, code smell / medium / high.
- **Evidence:** `StoreScopedChecklistCommandCoordinator.swift:130-155` fetches the task-scoped visible items at line 135, validates their mutation IDs and exact requested ID set, then invokes the handler. `ChecklistCommands.swift:89-118` immediately executes an unpredicated `FetchDescriptor<ChecklistItem>()` at line 96, then deduplicates and filters the same task in memory at lines 97-98.
- **Trigger and impact:** every reorder does work proportional to all checklist rows, including unrelated tasks and tombstone/duplicate history, while holding the serialized writer transaction on `@MainActor`.
- **Contract:** Architecture/AD-025 describes checklist task buckets as scoped/incremental; normal mutations should not scale with unrelated rows. The existing coordinator fetch proves the needed canonical set is already available.
- **Tests and counter-evidence:** `StoreScopedChecklistCommandCoordinatorTests.swift:170-193` protects stale-baseline correctness, not query boundedness. The second global fetch is not needed to establish cross-task identity after the coordinator's equality checks.
- **Recommendation:** pass the validated scoped items into the handler or issue a predicate-scoped canonical fetch there. Retain the CAS behavior and add observable seeded scale evidence rather than a source-string test.

### DCP-003 — Recurrence lifecycle materializes closed ledger history despite its bounded-work contract

- **Category / severity / confidence:** performance, latent bug, code smell / medium / high.
- **Evidence:** `TaskRecurrencePersistenceState.swift:22-33` unconditionally fetches all recurrence rules, tasks, occurrences, quantity goals, quantity entries, and Pomodoro runs. All quantity entries are then used only to expand claimed task/goal ID sets (`:46-59`), while all Pomodoro runs are filtered in memory to active work (`:63-70`). In contrast, active segments use a predicate plus canonical-ID resolution (`:78-91`). `StoreScopedTaskRecurrenceCommandCoordinator.withFreshState` builds this state for every recurrence transaction/materialization.
- **Trigger and impact:** startup/foreground/day-boundary/task-revision lifecycle materialization becomes proportional to accumulated quantity-entry and Pomodoro history on `@MainActor`, inside serialized store work. A sufficiently old/imported store can produce foreground latency even when very little work is active.
- **Contract:** `Docs/Architecture.md` states recurrence lifecycle state discovers active work with active-row predicates plus canonical-ID resolution rather than materializing closed ledger history. The Pomodoro fetch directly contradicts that statement.
- **Tests and counter-evidence:** recurrence day-key and work-eligibility unit tests exist, but no query-scale/materialization performance coverage was found. User-facing recurrence UI availability limits ordinary creation today, but lifecycle code is active and imported/synced stores can contain history, so this is latent rather than unreachable.
- **Recommendation:** use the same active-candidate/canonical-ID two-phase query for Pomodoro runs and restrict physical-claim discovery to IDs relevant to active rules/current occurrence work. Verify with a seeded Release trace containing large closed history.

## Needs Runtime Verification

### DCP-004 — Full AI workspace apply is synchronous MainActor work under the writer lock

- **Category / severity / confidence:** performance risk / medium / high static confidence, runtime status unverified.
- **Evidence:** the SwiftUI apply closure calls the synchronous store command (`AITaskWorkspacePlanGeneratorViews.swift:421-442`, `AppPresentationHost.swift:140-148`). `StoreScopedAITaskAtomicMutationCoordinator` is `@MainActor`; `apply` captures the current baseline at `:41-85`, and `captureBaseline` performs unpredicated fetches for categories, tasks, assignments, checklist items/visuals, quantity goals, and recurrence rules at `:90-125`. `AITaskWorkspaceCapture` then canonicalizes and builds whole-workspace snapshot/baseline maps, and fingerprinting JSON-encodes the full snapshot. Validation/application performs further fetches and sequential operations before releasing the writer transaction.
- **Trigger and suspected impact:** pressing Apply with a large uncapped workspace can block UI responsiveness and queue unrelated writes. `Docs/ImplementationContexts/Archive/2026-07-29-performance-hardening.md:187-188` independently recorded this same MainActor full-workspace risk as follow-up work.
- **Counter-evidence:** AD-132 intentionally requires an uncapped full workspace and atomic CAS, so full logical coverage is not itself a defect and truncation is not an acceptable fix. No seeded Release trace, signpost budget, or focused coordinator mutation test was found, so this audit does not claim a measured stall.
- **Verification/recommendation:** seed a large realistic workspace and capture Apply signposts plus main-thread heartbeat in Release. If confirmed, move capture/normalization/fingerprinting and the transactional writer onto a dedicated model actor/non-main context owner, preserving the single store lock, full CAS semantics, atomic rollback, and main-actor publication only.

## Rejected Leads And Counter-Evidence

- **`Task.detached` SwiftData confinement:** rejected. The analytics path passes immutable `Sendable` DTOs (`AnalyticsVisualSnapshotModels.swift`) and has cancellation handling; no model/context crosses the boundary.
- **`nonisolated(unsafe) AppDefaults.shared` race:** rejected after contextual review. It is an immutable shared wrapper around documented thread-safe `UserDefaults`; the unsafe annotation addresses missing `Sendable` conformance and test substitution is isolated.
- **Stored task/observer leaks:** rejected. Inspected store/Live Activity tasks cancel in teardown, observer tokens remove registrations, closures use weak ownership, and the mutation broadcaster drains a bounded queue.
- **Missing saves from insert/delete ratio:** rejected. The scan undercounts saves because mutations route through `saveAfterMutationStep` and `ModelContext.performAtomicMutation`; transaction code provides rollback/error handling.
- **Every full-table fetch is automatically wrong:** rejected. Workspace-wide AI CAS is an explicit product contract, while the checklist and recurrence findings are retained because a narrower authoritative set already exists or the architecture explicitly promises active-only discovery.

## Open Questions And Runtime Verification

- Run DCP-004's seeded Release trace before assigning a measured duration or “UI freeze” label.
- For DCP-003, record fetch/result counts and foreground materialization duration against small and large closed-history stores; correctness must retain canonical duplicate/tombstone handling.
- For DCP-002, measure transaction duration with many unrelated checklist rows after converting the handler to a scoped input/query.

## Domain Health Summary

- **Concurrency:** needs work. Lock/context ordering and DTO confinement are generally deliberate, but the duplicated wall-clock timeout breaks a core bounded-wait guarantee.
- **Memory/resource ownership:** clean by static review; no confirmed leak. Instruments remains necessary for a runtime leak claim.
- **Performance:** overhead risks confirmed in checklist and recurrence query shape; AI workspace MainActor cost remains trace-gated.
- **SwiftData correctness:** no scoped schema/migration defect confirmed; the important issues here are fetch cardinality and execution context.
