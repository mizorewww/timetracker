# Performance Hardening — Implementation Memory

Status: active

Started: 2026-07-29

Branch: `codex/performance-hardening-2026-07-29`

## Objective

Comprehensively profile and improve Time Tracker performance across CPU work, memory
ownership, energy use, SwiftUI invalidation/rendering, launch, and large-data domain
operations. Changes must be evidence-driven, preserve behavior and data safety, and use
the repository's signed verification gates.

## Scope and constraints

- Use the `axiom-performance` routing workflow and repository-local Apple HIG and
  SwiftUI performance guidance.
- Preserve the existing architecture: durable writes remain in Commands/Repositories;
  calculations remain in Services; `TimeTrackerStore` remains the observable facade.
- Add behavior/performance tests before changing covered behavior.
- Prefer existing signposts and deterministic performance budgets; add new measurement
  seams only where a verified bottleneck lacks coverage.
- If macOS UI automation becomes necessary, use a macOS virtual machine rather than the
  physical host.
- Do not use physical Apple devices for UI automation without a separately explicit
  request.
- Every test/profile batch records ownership and releases its app, runner, simulator or
  virtual machine, trace writer, DerivedData/result bundle, and temporary artifacts.

## Baseline plan

1. Map hot paths, existing signposts, performance tests, and relevant accepted decisions.
2. Run independent static audits for memory ownership, energy, and Swift/collection
   efficiency.
3. Establish a clean signed test/performance baseline and record exact timings.
4. Record Release profiling evidence for representative large-data workflows when the
   environment supports a controlled destination.
5. Implement the smallest evidence-backed optimizations with regression tests.
6. Re-run the same measurements, compare results, run the full repository gates, clean
   all owned resources, and commit small coherent checkpoints.

## Working hypotheses

- UI invalidation fan-in may still be broader than the domain snapshot boundaries imply.
- Analytics, task-tree, persistent-history, and system-projection paths may contain
  repeated materialization or collection scans outside existing budgets.
- Long-lived timers, observers, tasks, caches, or bridge closures may have lifecycle or
  energy costs even when correctness tests pass.
- Launch and first-visible-content work may synchronously perform setup that can be
  deferred or coalesced.

## Evidence log

- 2026-07-29: Worktree was clean before branch creation. Local `main` was 124 commits
  ahead of `origin/main`; the branch was created from that exact state.
- 2026-07-29: Existing documentation confirms `CorePerformanceBudgetTests` includes
  large task-tree, analytics, overlap, ledger bucket, timeline, checklist rollup,
  50,000-segment incremental refresh, and cached frequent-task ranking budgets.
- 2026-07-29: Static audit phase started without launching a simulator, UI runner,
  Instruments session, or virtual machine.
- 2026-07-29: Baseline batch `perf-baseline-core-20260729` assigned to the primary
  agent. Command: `make TEST_ONLY=timetrackerTests/CorePerformanceBudgetTests test`;
  destination: host macOS unit-test runner only; no UI automation, simulator, VM, or
  Instruments; Xcode default DerivedData; app bundle `me.mezorewww.timetracker`.
  Cleanup requires the owned `xcodebuild`/`xctest`/test host to exit, no Booted
  simulator, and no owned trace writer.
- 2026-07-29: `perf-baseline-core-20260729` passed 11/11 tests in 6.119 s.
  Reported per-test durations included 0.614 s for 20,000-segment ledger buckets,
  0.224 s for dense overlap analytics, 0.264 s for dense visual projection,
  1.007 s for the 50,000-segment incremental rollup fixture, and 3.697 s for the
  50,000-stored-segment rapid-restart fixture. The internal incremental-refresh and
  cached-ranking thresholds passed. Result bundle:
  `~/Library/Developer/Xcode/DerivedData/timetracker-ccmijjertbbodwfuuctazftvuorp/Logs/Test/Test-timetracker-2026.07.29_14-20-25-+0800.xcresult`.
- 2026-07-29: Baseline cleanup audit found no owned app/test host, `xcodebuild`,
  `xctest`, Instruments, or `xctrace` process and zero Booted simulators. The
  repository's shared Xcode DerivedData was retained for incremental build reuse; no
  task-specific simulator, result directory, or trace artifact was created.
- 2026-07-29: Regression batch `perf-ledger-old-update-red-20260729` assigned to
  the primary agent. It re-runs `CorePerformanceBudgetTests` on the host macOS unit
  runner after adding a 50,000-segment old-record update budget. No UI automation,
  simulator, VM, or Instruments resource is involved; cleanup requirements match the
  baseline batch.
- 2026-07-29: The red batch failed only the new budget: updating one old segment
  took 0.057431 s because `unindexRecord` sorted all 50,000 task segments even though
  the changed ID was not in the bounded recent index. The other 11 budgets passed.
  Cleanup found no owned runtime process or Booted simulator.
- 2026-07-29: Verification batch `perf-ledger-old-update-green-20260729` assigned
  to the primary agent after making recent-index refill conditional on the removed ID
  actually belonging to the bounded recent set. Host macOS unit runner only; no UI,
  simulator, VM, or Instruments resource.
- 2026-07-29: `perf-ledger-old-update-green-20260729` passed 12/12 budgets.
  The new 50,000-segment old-record update now stays below its 50 ms alarm and the
  existing recent-index refill correctness test remains applicable. The batch cleanup
  found no owned app/test host, `xcodebuild`, `xctest`, Instruments, or `xctrace`
  process and zero Booted simulators.
- 2026-07-29: Regression batch `perf-recurrence-closed-history-red-20260729`
  assigned to the primary agent. It adds 50,000 closed segments plus one active
  segment, then times fresh recurrence-state construction. Host macOS unit runner
  only; no UI automation, simulator, VM, or Instruments resource.
- 2026-07-29: A too-narrow Swift Testing selector executed zero tests and was
  explicitly treated as inconclusive. The subsequent full performance suite produced
  the real red evidence: recurrence-state construction took 0.697751 s against a
  0.1 s alarm, while the other 12 budgets passed. Both batches exited their test
  hosts and left zero Booted simulators.
- 2026-07-29: `perf-recurrence-closed-history-green-20260729` passed 13/13
  budgets after the recurrence state began fetching active segment candidates and
  canonical rows for only those IDs. The new 50,000-closed-row query stayed below
  100 ms. Cleanup found no owned runtime process and zero Booted simulators.
- 2026-07-29: `sync-export-catch-up-red-20260729` first failed compilation on the
  new `requiresReadModelCatchUp` contract, proving the batch had no such distinction.
  After implementation, `CoreSyncActivityOutcomeTests` passed 10/10 and
  `CommittedMutationProjectionRecoveryTests` passed 5/5. A pure successful export
  leaves all four projection sink call counts unchanged; remote/import/setup and
  conflict batches still request catch-up. Each batch was followed by a clean process
  and simulator audit.
- 2026-07-29: `checklist-failure-metadata-red-20260729` populated both metadata
  maps with 10,000 stale item IDs plus one current ID. The new test failed with all
  stale IDs retained while the other 11 LLM lifecycle tests passed. The green batch
  passed 12/12 after invalid-item reconciliation pruned both maps and global
  cancellation released their storage. Cleanup found no runtime resource.
- 2026-07-29: `pomodoro-session-query-red-20260729` took 2.890953 s to cancel one
  first-round focus in a store containing 50,000 unrelated segments. After replacing
  `allSegments()` with the existing canonical `segments(sessionIDs:)` query,
  `pomodoro-session-query-green-20260729` passed all 14 performance budgets and the
  cancellation stayed below 100 ms. Both runs released the signed macOS test host and
  left zero Booted simulators.
- 2026-07-29: `make CONFIGURATION=Release build-macos` succeeded with automatic
  signing and team `LT98S43NKA`. The first Release build compiled both architectures
  and emitted pre-existing actor-isolation warnings in `AITaskWorkspaceModels.swift`;
  no build, app, trace, or simulator process remained afterward.
- 2026-07-29: Two initial App Launch attempts were rejected as evidence because
  `xctrace --launch` resolved the installed `/Applications/timetracker.app` by bundle
  identity, not the branch build. `ps` and `lsof` identified the exact owned PIDs;
  both were terminated, waited, audited absent, and the inconclusive traces were moved
  to Trash.
- 2026-07-29: Valid Release Time Profiler batch
  `release-time-profiler-20260729` launched the exact DerivedData executable, verified
  it with `lsof`, attached by PID 70130 for 8.667 s, then sent TERM and waited. The
  trace TOC confirms the branch executable path. It reported no `potential-hangs`
  rows (threshold 250 ms) and only one 1 ms running sample during the idle window,
  in AppKit persistent-state file cleanup; no app-owned hot stack appeared. This
  makes the large-data command/query regressions, rather than idle rendering, the
  actionable measured bottlenecks in this controlled scenario.
- 2026-07-29: Valid Release Allocations batch
  `release-allocations-20260729` used the same exact-binary/PID verification for
  8.742 s, then terminated and waited for PID 70396. The CLI trace TOC preserved the
  allocation recording but did not expose allocation summary rows for numeric export,
  so it is supporting inspection evidence rather than a claimed byte delta. No
  process, trace writer, or Booted simulator remained after recording.

## Ranked static findings

1. Recurrence lifecycle state fetched all historical `TimeSegment` rows on startup,
   foreground activation, and midnight even though it only retained active work.
   Fixed with a measured 50,000-row red/green query budget.
2. Cloud export completion entered the same debounced remote-import pipeline as actual
   imports, causing a redundant full read-model refresh and system-surface projection
   after ordinary local writes. Fixed with batch semantics and projection-call tests.
3. Timer start/manual add/rebind validates one target by materializing all tasks,
   recurrence rules, and occurrences on the MainActor command path.
4. Ledger recent-index removal sorted every segment for a task even when the removed
   ID was outside the bounded recent set. This finding now has a red/green performance
   regression and an implemented fix.
5. Pomodoro short-cancel scanned all segments for one session. Fixed from a measured
   2.890953 s to below 100 ms with a 50,000-row regression. Quantity-entry commands
   and checklist reorder still fetch unrelated history and remain follow-up candidates.
6. AI workspace tool mutations repeatedly copy, normalize, and sort the complete
   workspace on MainActor. This is high potential impact but is a larger,
   concurrency-sensitive follow-up than the bounded storage/query fixes.
7. Once HealthKit background delivery is enabled, disabling the visible timeline does
   not currently unregister its observer; background delivery uses `.immediate`.
8. Checklist visual-suggestion failure/retry dictionaries retained deleted or invalid
   item IDs indefinitely. Fixed with a 10,000-ID pruning regression and full-clear
   behavior on global cancellation.
9. macOS blossom presentation lacks a `deinit` cleanup fallback for its global event
   monitor; sync-conflict and system-projection tasks can retain owner graphs if an
   injected worker never returns. These need injectable lifecycle seams before a safe
   behavior-tested change.
10. Today can render one active timer through two or three independent 1 Hz
    `TimelineView` sources; idle metrics/timeline sections also wake periodically.
    This requires a focused UI clock design plus simulator evidence and is intentionally
    separated from the verified storage/query checkpoint.

## Checkpoints

- [ ] Static audit findings ranked by measured/expected impact.
- [ ] Baseline test and profile evidence recorded.
- [ ] First verified optimization committed.
- [ ] Remaining verified optimizations committed in coherent checkpoints.
- [ ] Final same-worktree performance comparison and full gates green.
- [ ] Owned resources audited empty and implementation memory closed.
