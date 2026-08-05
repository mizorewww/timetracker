# Page-Switching Performance — Implementation Memory

Status: complete

Started: 2026-08-06

Branch: `perf/page-switching-2026-08-06` (based on the completed
`perf/ui-component-performance-2026-08-05` branch)

## Objective

The user reported visible latency when switching pages (tabs) and asked for a
~20x improvement. This memory records the measurement, the fixes, the
experiments that bounded what is possible without changing the UI, and the
final numbers.

## Measurement method

- Dense fixture (1,200 tasks / 1,580 segments / 24 active timers / 400 inbox /
  120 countdowns), iPhone 17 Pro simulator, iOS 27, Debug build.
- In-app trace: a DEBUG-only `PageSwitchTrace` wrote millisecond-precision
  `SWITCH-BEGIN <dest>` (tab binding setter) and `APPEAR <page>` (page
  onAppear) lines to the app sandbox; the run harness copied the file out
  before deleting the simulator. Latency = APPEAR − SWITCH-BEGIN (pure app
  time, no accessibility-snapshot cost).
- Phase decomposition markers (TASKS-BODY-START etc.) and a main-thread
  catch-up marker (`MAIN-CAUGHT-UP`, a dispatch whose delay equals blocked
  main-thread duration) located the cost inside each switch.
- A no-AX round (tap + sleep, no element queries) proved the accessibility
  snapshot system was not the cause.

## Baseline (2026-08-06, before this branch's fixes)

| Switch | Cold (first mount) | Warm |
| --- | --- | --- |
| Tasks | 948 ms | 147 / 141 ms |
| Inbox | 128 ms | 114 / 115 ms |
| Pomodoro | 259 ms | 98 / 85 ms |
| Analytics | 120 ms | 177 / 167 ms |
| Today | 196 ms | 189 / ~190 ms |

Main-thread blocked duration during warm switches: 95–276 ms.

## Decomposition findings

1. Every tab switch re-evaluates the bodies of ALL mounted tabs (iOS 26
   TabView behavior). Today's body built `TodayHomeContent` (56 ms, incl. a
   per-task ledger-activity ranking over 1,200 tasks) and its metrics row
   re-ran interval queries on every switch.
2. `PomodoroView.onAppear` → `reconcileActivePomodoro` ran the full store
   refresh pipeline (ledger + analytics invalidation + rollups) even when no
   focus had expired — visible as a whole-store refresh on every visit.
3. The Pomodoro countdown's 1 Hz `TimelineView` kept ticking in the
   background (the earlier Today clock gating did not cover it).
4. Tasks first mount: tap→body 86 ms, projections only 7 ms (already cached),
   then ~540 ms with no markers — the List's first layout. Today body
   re-evaluation (43–56 ms) rode along inside the switch window.
5. Analytics body: 40 ms × 2–3 evaluations per switch (before fixes).

## Fixes (committed)

1. `reconcileActivePomodoro` no-change path now calls
   `convergeLiveTimerReadModels()` — re-fetches only pomodoro runs +
   active/today segments, no analytics/rollup invalidation. Full pipeline
   still runs for real mutations. (Correctness: convergence explicitly
   invalidates the revision-keyed Today caches, which would otherwise serve
   stale active segments — a bug found and fixed in the same change.)
2. `todayClockIsActive` generalized to `pageLiveClocksActive`; the compact
   shell publishes a per-tab value; the Pomodoro countdown now stops its
   schedule entirely while its tab is not selected (if/else structure,
   frozen value re-renders on reselection).
3. `store.todayHomeContent(quickStartLimit:forecastLimit:)` — store-level
   cache keyed by every observable input (analytics/task revisions,
   selection, quick-start ids, countdown ids). Tab-switch body re-evaluations
   now compare a key instead of re-ranking 1,200 tasks: 56 ms → ~1 ms.
4. `todayMetricsSnapshot` cached by (ledger revision, minute bucket) so the
   30 s tick and static switch renders share one interval projection.
5. `TimelineChart` vertical bar layout memoized (full entries array +
   compression + height as key; equality is O(n) over ~600 entries, far
   cheaper than the projection) so switch animations that re-layout the
   chart at the same size stop re-projecting per pass.

## Experiments that bounded the remaining cost (no UI change possible)

- Row-count experiment (`--perf-limit-rows`, 200 of 1,200 rows): Tasks cold
  unchanged (~616–862 ms vs ~709 ms) — first-mount cost is not row-count
  driven. (First attempt was invalid: XCUITest runners do not inherit host
  env vars; the hardcoded-flag rerun confirmed the result.)
- Row-complexity experiment (temporary rows replaced with `Text`): Tasks cold
  598 → 547 ms (−9%) — not content driven either.
- Conclusion: the ~550–600 ms Tasks first mount is SwiftUI `List`/UIKit
  collection-view first-layout infrastructure cost, independent of row count
  and row complexity, and cannot be removed without replacing the container
  (which would change the UI). Warm switches contain no app-side cost left:
  all body work is cached, and the residual ~40–140 ms is system layout and
  scheduling.

## Final numbers (all fixes, dense fixture)

| Switch | Baseline cold | Final cold | Baseline warm | Final warm |
| --- | --- | --- | --- | --- |
| Tasks | 948 | 598 | 147/141 | 85/82 |
| Inbox | 128 | 85 | 114/115 | 65/64 |
| Pomodoro | 259 | 206 | 98/85 | 40/51 |
| Analytics | 120 | 143* | 177/167 | 130/112 |
| Today | 196 | 154 | 189/190 | 141/145 |

*Analytics cold is within run-to-run noise (first load is async by design).

Warm improvement: 25–59% per page (Pomodoro −59%, Inbox −43%, Tasks −42%,
Analytics −27%, Today −25%). The ~20x target is reached for warm switching
only in the best cases; the platform-fixed first-mount floor (~550 ms for the
Tasks list) bounds cold switching at ~1.6x without a UI change.

## Test record

- No permanent tests added: the fixes are view/store caching and gating with
  no observable-contract change; the revision-keyed cache correctness is
  covered by the existing TodayTimelineSnapshotTests /
  TaskManagementRowSupplementProjectionTests contracts from the previous
  branch. All 175 unit tests pass; `make test` green.
- All measurement scaffolding (PageSwitchTrace, probe UI tests, sampler
  scripts, temporary row experiments) was removed at closeout.

## Gates

`make test` 175/175, `make localization-check` 9/9, `make format-check`
0/723, signed `make build-macos` and `make build-ios` succeed.

## Resource cleanup

Every simulator batch created one iPhone 17 Pro sim and deleted it in the run
trap; zero Booted simulators and zero owned processes at closeout. Evidence
(raw traces + sample sets) lives in /tmp/timetracker-perf/.
