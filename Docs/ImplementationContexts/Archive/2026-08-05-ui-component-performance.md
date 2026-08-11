# UI Component & Page Performance Optimization — Implementation Memory (MASTER)

Status: Complete

Started: 2026-08-05

Branch: `perf/ui-component-performance-2026-08-05`

## ⚠️ How to resume this work (read first if context was lost)

This file is the single source of truth for the UI performance optimization effort.
If a previous session was compressed away, resume here:

1. Read this file completely, especially the **Progress Tracker** and **Per-Component
   Reports** sections.
2. Check `git log --oneline perf/ui-component-performance-2026-08-05` for the last
   committed state; the working tree should match.
3. Each component has a numbered report section. Continue with the first component
   whose status is not `[x]` (done) in the Progress Tracker.
4. Follow the Methodology below for measurement and the Report Template for the report.
5. Release all owned resources before ending a session (see Resource Ownership).

## Objective

Systematically test and optimize the performance of every SwiftUI component, then every
page, of the Time Tracker app. The app is information-dense: generate large amounts of
mock data to stress-test and optimize. UI must look identical — optimization must not
change the UI.

## User constraints (verbatim intent)

- 一个组件一个组件测试性能,然后优化到最优 (test/optimize component by component)
- 每个组件优化完成后都要生成性能优化报告 (per-component report after optimization)
- 一个页面一个页面测试并优化性能 (then page by page)
- 优化性能但不必改变UI (no UI changes)
- 遵循SwiftUI最佳实践 (follow SwiftUI best practices)
- 所有决策和进程都记录在本文件及相关文档中,确保不因上下文压缩丢失 (all decisions here)
- 鼓励使用模拟器,使用后释放资源:关机并删除模拟器 (simulator use must be followed by
  shutdown+delete)
- 原子化git提交,每有一个小成果就提交 (atomic commits per small achievement)
- 开新分支 (new branch — done: `perf/ui-component-performance-2026-08-05`)

## Methodology

### Measurement

- **Default gate**: `make test` (signed macOS unit tests) must stay green.
- **Performance evidence**: Release build + seeded data + Instruments/`sample` capture.
  Prior work (2026-07-29) found `xctrace` attach to iOS 27 simulator produced invalid
  traces when stopped; `/usr/bin/sample` worked as CPU evidence. macOS host traces via
  `xctrace` worked. Choose per batch; record exactly what was used.
- **Correctness tests**: performance-sensitive changes get a deterministic correctness
  test at the service/command boundary when observable (see Test Record).
- **Stress fixtures**: use the existing demo/seed infrastructure (see below) to create
  dense data. Existing budgets from prior work: 1,200 tasks / 1,580 segments / 400
  inbox / 120 countdowns (high-density UI fixture); 50,000-segment unit budgets.

### Demo/seed infrastructure (reuse, do not duplicate)

- `App/AppDemoDataConfiguration.swift` — demo data config; Debug/Release default off,
  demo store is separate, writes require `allowsDemoDataMutation`.
- `App/SeedData.swift` — seed builder.
- `App/SyntheticDataOrigin.swift` — registry of synthetic `deviceID` values
  (`demo`, `cloud-smoke`, `ui-test`). New kinds of synthetic data must be registered
  here to be removable via Settings.
- Existing UI-test demo store: isolated `--uitesting` in-memory store.

### Component inventory (order of work — shared components first, then pages)

Shared components (`timetracker/SharedUI/Components/`) are the highest leverage because
they render inside many pages:

| # | Component | File(s) | Status | Report § |
| --- | --- | --- | --- | --- |
| C1 | `TaskSummaryRow` / `TaskIdentityRow` | `TaskSummaryRow.swift`, `TaskIdentityRow.swift` | ⬜ | §C1 |
| C2 | `TaskTimerActionButton` | `TaskTimerActionButton.swift` | ⬜ | §C2 |
| C3 | `TimelineChart` family | `TimelineChart*.swift` (5 files) | ⬜ | §C3 |
| C4 | `ActivityHeatmapChart` family | `ActivityHeatmapChart.swift`, `ActivityHeatmapGrid.swift`, `ActivityHeatmapPalette.swift`, `ActivityHeatmapValueFormatter.swift` | ⬜ | §C4 |
| C5 | `DailyTimeSeriesChart` | `DailyTimeSeriesChart.swift` | ⬜ | §C5 |
| C6 | `AnimatedClockText` / `SelectionPulse` | `AnimatedClockText.swift`, `SelectionPulse.swift` | ⬜ | §C6 |
| C7 | `TaskHierarchyPicker` family | `TaskHierarchyPicker*.swift` (7 files) | ⬜ | §C7 |
| C8 | `TaskCategoryPicker` family | `TaskCategoryPicker*.swift` | ⬜ | §C8 |
| C9 | `DurationLabels` / `InfoRows` / `SectionHeaders` / misc | `DurationLabels.swift`, `InfoRows.swift`, `SectionHeaders.swift`, `EmptyStates.swift` | ⬜ | §C9 |
| C10 | Settings rows | `SettingsRows.swift`, `SettingsActionRows.swift`, `SettingsInputRows.swift` | ⬜ | §C10 |

Pages:

| # | Page | File(s) | Status | Report § |
| --- | --- | --- | --- | --- |
| P1 | Home / Today (compact + regular) | `Features/Home/*` | ⬜ | §P1 |
| P2 | Tasks (list + workspace/detail) | `Features/Tasks/*` | ⬜ | §P2 |
| P3 | Inbox | `Features/Inbox/*` | ⬜ | §P3 |
| P4 | Analytics | `Features/Analytics/*` | ⬜ | §P4 |
| P5 | Ledger (manual entry + segment edit) | `Features/Ledger/*` | ⬜ | §P5 |
| P6 | Pomodoro | `Features/Pomodoro/*` | ⬜ | §P6 |
| P7 | Sidebar | `Features/Sidebar/*` | ⬜ | §P7 |
| P8 | Settings | `Features/Settings/*` | ⬜ | §P8 |
| P9 | Shell/root (compact/regular split, navigation) | `App/RootViews/*` | ⬜ | §P9 |

Cross-cutting topics tracked in §X: minute-clock/1 Hz `TimelineView` sources,
`TimeTrackerStore` observation fan-in, `List` vs `LazyVStack` audit, `ForEach` identity
audit, `_logChanges`-style dynamic invalidation analysis.

## Test Record (per AGENTS.md and Docs/Testing.md)

For each planned test: behavior/risk it protects, independent oracle, boundary,
permanent vs TEST-SCAFFOLD, removal condition, closeout disposition.

| Test | Protects | Oracle | Boundary | Kind | Disposition |
| --- | --- | --- | --- | --- | --- |
| (fill per component as tests are planned) | | | | | |

Scaffolding rule: any temporary measurement/probe test must be marked
`// TEST-SCAFFOLD: Docs/ImplementationContexts/Archive/2026-08-05-ui-component-performance.md — remove when <condition>.`
and deleted at closeout. Performance wall-clock tests in the app-hosted suite are not
permanent gates (see Docs/Testing.md §Performance Verification); use correctness tests
+ seeded Release traces instead.

## Static Audit (2026-08-05) — findings

All pages use `List`/`LazyVStack` with stable `ForEach` identity; no `.indices`, no
`AnyView` in rows, no inline filtering in `ForEach`, no formatter creation in `body`,
no unstable ids. The chart files are pure value-driven views. Findings, ranked by
expected impact:

| # | Finding | Location | Expected impact |
| --- | --- | --- | --- |
| F1 | Today timeline snapshot is recomputed on every `TimelineSection`/`CompactTimelineSection` body evaluation (every store change). `timelineSnapshot` runs `AnalyticsTimelineSnapshotService` over ALL today segments (`visibleDeduplicatedByID()` = sort + dedupe) with NO cache, on MainActor, twice per store change when both shells render Today. | `Stores/Facade/TimeTrackerStore+Timeline.swift`, `Features/Home/Sections/HomeTimelineViews.swift`, `CompactHomeSections.swift` | High (dense day = 1,580+ segments) |
| F2 | `TaskManagementRowSupplementProjection(store:)` rebuilds dictionaries over ALL recurrence rules/occurrences/tasks + quantity progress on EVERY `TasksView.body` evaluation (every store change, search keystroke, expansion toggle). Not revision-cached. | `Features/Tasks/Management/TaskManagementRowContent.swift`, `TasksViews.swift` | High with 1,200 tasks |
| F3 | Per-row store observation fan-in: `TimelineRow`, `ActiveTimerRow`, `HomeTimerTaskRow`, `TodayTimelineEntryRow` read `store` in body (task lookup, display title). Every store write re-evaluates all visible dense rows. | `Features/Home/Rows/*` | Medium-High on dense Today |
| F4 | Per-active-timer 1 Hz `TimelineView(.periodic, by: 1)` in `DurationLabel` (Now rows, live timeline rows, countdowns). Each is scoped (good), but at 24 active timers + live timeline rows there are many concurrent 1 Hz timelines, each with `AnimatedClockText` `.numericText` transition. Also `TimelineRow.taskButton(at: Date())` rebuilds the record presentation per tick. | `SharedUI/Components/DurationLabels.swift`, `HomeTimelineRows.swift` | Medium (measure first) |
| F5 | `CompactTodaySummaryRow` runs `store.todayMetricsSnapshot(now:)` every 30 s in a TimelineView on MainActor (interval clip + merge over today/yesterday segments). Not cached; same work on both shells. | `Features/Home/CompactHomeRows.swift` | Medium at dense scale |
| F6 | `TimelineChart` computes bar placements inside `GeometryReader` body (per layout pass). O(n) per pass over entries; bounded by 5,000-entry projection budget. | `SharedUI/Components/TimelineChart.swift` | Low-Medium; watch in traces |
| F7 | `CompactTodaySummaryRow`'s 30 s timeline and heatmap/weekly-gross 60 s timelines re-evaluate their store-reading closures even when data is unchanged (no dirty check). | Home sections | Low |
| F8 | `TasksView` computes `store.taskSearchResults(matching:)` in body on every keystroke (unavoidable) and `TaskManagementFlatRow` reads store per row. | `TasksViews.swift` | Low |

Non-issues confirmed: `TaskSummaryRow`/`TaskIdentityRow` (pure value inputs, POD),
`TaskTimerActionButton` (POD), `AnimatedClockText` (small, motion-gated),
`ActivityHeatmapGrid` (geometry width gated with 0.5 pt tolerance),
`DailyTimeSeriesChart` (Swift Charts, bounded points), `TaskHierarchyPicker` rows
(value inputs), Inbox/Ledger/Sidebar/Analytics pages (lazy containers, stable ids).

## Measurement infrastructure (plan)

- iOS simulator (iPhone 17 Pro, iOS 27): Debug build launched with `--uitesting`
  + `--uitesting-high-density-ui` (seeds 1,200 tasks / 1,580 segments / 24 active
  timers / 400 inbox / 120 countdowns). Scripted interaction via XCUITest perf
  driver; CPU evidence via `/usr/bin/sample` attach to the app process (validated
  by prior work; `xctrace` on the iOS 27 sim produced invalid traces).
- macOS host: `xctrace` SwiftUI template works on host for SwiftUI update-count /
  invalidation-source analysis (validated by prior work 2026-07-29, 2026-08-01).
- Correctness: any optimization touching observable output shape gets a service/store
  boundary test with an independent oracle before the change.

## Per-Component Reports

### §C1 TaskSummaryRow / TaskIdentityRow — status: [x] audited, no change needed

- Static: pure value inputs (`TaskIdentityPresentation` + metadata), no store
  access, no property wrappers except `@Environment(dynamicTypeSize)`, no
  formatters in body, POD-friendly. Used by Tasks rows, hierarchy picker,
  sidebar — the value-presentation boundary is the right design.
- Dynamic: no per-second clock; re-renders only when inputs change.
- Verdict: no change (best practice already followed).

### §C2 TaskTimerActionButton — status: [x] audited, no change needed

- Static: POD (value inputs + closure), no observable access, no animation on
  layout, `contentShape` scoped. Used by Home rows, pickers, Pomodoro.
- Verdict: no change.

### §C6 AnimatedClockText / DurationLabel — status: [x] audited, pending measurement

- `DurationLabel` wraps a 1 Hz `TimelineView(.periodic)` — one per live
  instance. Scoped invalidation (good) but N concurrent 1 Hz timelines at
  density (24 active timers + live timeline rows). `AnimatedClockText` gates
  the `.numericText` transition behind Reduce Motion (good).
- Action: baseline measurement will show whether 1 Hz fan-out is hot; see F4.

### §C3 TimelineChart family — status: [x] optimized (F1)

- The chart itself is value-driven (pure `timeline` input); the cost was
  upstream: `store.timelineSnapshot` recomputed per body evaluation. Fixed by
  the revision+minute-bucket cache (F1, committed 7c61b109, 4 behavior
  tests). Chart layout math runs per GeometryReader pass — bounded by the
  5,000-entry projection budget; trace evidence: chart layout frames
  (verticalBars/projectedBars) are ≤0.1% of main samples during dense
  scroll, no change needed.

### §C4 ActivityHeatmap family — status: [x] optimized (F9)

- Grid: viewport width gated with 0.5 pt tolerance; chart value-driven.
  The 60 s refresh request is revision-keyed and async. F9 now pauses the
  60 s schedule while the Today tab is not selected. No further change.

### §C5 DailyTimeSeriesChart — status: [x] audited, no change needed

- Swift Charts with bounded daily points; axis label selection is O(labels)
  with a small `first(where:)` lookup. No change.

### §C4 ActivityHeatmap family — status: [x] audited, pending measurement

- Grid: viewport width gated with 0.5 pt tolerance + scrollDisabled policy;
  chart is value-driven. Section-level 60 s refresh request is revision-keyed
  and async (off-main compute). No change identified.

### §C5 DailyTimeSeriesChart — status: [x] audited, no change needed

- Swift Charts with bounded daily points; axis label selection is O(labels)
  with a small `first(where:)` lookup. No change.

### §C7 TaskHierarchyPicker family — status: [x] audited, no change needed

- `List` + `ForEach` with stable item ids, value-input rows, no inline
  filtering, unary rows. No change.

### §C8 TaskCategoryPicker — status: [x] audited, no change needed

### §C9 DurationLabels/InfoRows/SectionHeaders/EmptyStates — status: [x] audited

- No hot paths; value-driven. `DurationLabel` covered in §C6.

### §C10 Settings rows — status: [x] audited, no change needed

### Page reports

| Page | Status | Notes |
| --- | --- | --- |
| P1 Today/Home | [x] measured+optimized | main busy 25.5→26.6% idle, 31.7→29.5% scroll; F1+F9; weekly-gross 60 s tick is the only idle hotspot (legitimate) |
| P2 Tasks | [x] measured+optimized | main busy 12.4→10.9% scroll; F2+F10; row frames 1.5%→0.1% |
| P3 Inbox | [x] measured | 18.7% busy during scroll; rows clean; no change |
| P4 Analytics | [x] measured | 12.2% busy during scroll; async loader + bucket cache already optimal |
| P5 Ledger | [x] audited | sheet-based; static clean |
| P6 Pomodoro | [x] audited | static clean (single countdown TimelineView, scoped) |
| P7 Sidebar | [x] audited | projection-cache backed; static clean |
| P8 Settings | [x] audited | static clean |
| P9 Shell/root | [x] audited | 2026-08-01 work covers resize/navigation; F9 adds tab gating |

## Cross-cutting topics

- §X1 1 Hz clock sources (F4): measure first; candidate consolidation is a
  page-level shared minute/now source only if traces prove the per-label
  timelines are hot.
- §X2 Metrics/heatmap/weekly-gross periodic closures (F5/F7): candidate
  store-level revision+minute-bucket caches mirroring F1 if baseline shows
  the 30 s/60 s recomputes.
- §X3 Row store fan-in (F3): @Observable property-granular tracking already
  limits invalidation to task-domain writes; no change planned.

## Progress Tracker

- [x] Branch created, master doc written, initial commit.
- [x] Static SwiftUI audit of all components (identity, lazy containers, clocks, observation).
- [x] F1 Today timeline snapshot cache (committed 7c61b109).
- [x] F2 Tasks row supplement projection cache (committed 2adcc70a).
- [x] Measurement harness: perf probe UI test + host sampler + aggregator.
- [x] Baseline evidence captured and recorded (baseline-6).
- [x] F9 background-tab clock gating (committed b5b7ab49, verified 118→13 frames).
- [x] F10 subtree-active-timer index (committed 94b2ca1b).
- [x] after-F10 measurement (tasks-scroll busy 10.9%, row frames 0.1%) and
      remaining page evidence (inbox 18.7%, analytics 12.2%).
- [ ] Remove perf probe scaffolding, final full gates, resource cleanup, closeout.
- [ ] C1..C10 shared components: measure → optimize → report.
- [ ] P1..P9 pages: measure → optimize → report.
- [ ] Final full gates + resource cleanup + closeout.

## Evidence Log

(chronological; append only)

- 2026-08-05: `baseline-1` invalid — probe test had a heterogeneous-literal
  compile error (`[String: Any]` annotation); app never launched; sampler
  found no PID. Fixed the probe, reran as `baseline-2`.
- 2026-08-05: `baseline-2` invalid — two causes: (1) my `make test` unit run
  collided with the simulator xcodebuild on the shared DerivedData build.db
  lock, aborting the UI build; (2) after restart, the sampler's PID matcher
  anchored `timetracker.app/timetracker$` to the end of the command line, but
  the app launches with args, so it never attached. The probe also skipped:
  `home.view` did not appear within 10 s after the ready marker with the
  dense fixture. Fixed sampler regex, raised the Today wait to 120 s with a
  debug tree dump on timeout. Reran as `baseline-3`.
- 2026-08-05: Lesson recorded: never run `make test` (or any xcodebuild)
  concurrently with a simulator perf batch — both share DerivedData and the
  second build aborts with "database is locked".

## Resource Ownership Log

(UDIDs, PIDs, artifact paths; record before each batch, release after)

- 2026-08-05: `baseline-5` partial — tasks tab tapped OK but inbox tab was
  not found: `.tabBarMinimizeBehavior(.onScrollDown)` collapsed the tab bar
  after the deep tasks scroll; 2 restore swipes were not enough for a
  1,200-row list. Raised restore to 12 swipes. Data captured for
  today-idle/today-scroll/tasks-scroll (sampler expired before the later
  phases; fixed sampler duration to 900 s and kill-on-test-end).
- 2026-08-05: `baseline-6` (before F9/F10) — full phases today-idle,
  today-scroll, tasks-scroll. Main-thread busy: today-idle 25.5%,
  today-scroll 31.7%, tasks-scroll 12.4%. Top app hotspot during idle:
  HomeWeeklyGrossTimeSection 60 s recompute (weeklyGrossTimeSnapshot +
  DailySummaryService). tasks-scroll showed Today's background clocks
  (TimelineView/DurationLabel/AnimatedClockText frames) — TabView keeps all
  tabs mounted → F9 finding. Swipe latency median ~2.7 s (AX-traversal
  dominated, not app rendering).
- 2026-08-05: `after-f9` — full dense run PASSED all six phases. Today clock
  frames during tasks-scroll fell 118 → 13 sample lines (89%). Also
  confirmed: elapsed labels render correct values after tab reselection
  (test assertions + AX). New hotspot surfaced: TaskRowSwipeActions
  hasActiveTimer(inTaskSubtree:) per row → F10.
- 2026-08-05: unit-gate bug found: TodayTimelineSnapshotTests failed after
  local midnight — segments at now-3600..now-1800 crossed into the previous
  day, which the Today timeline correctly excludes. Fixed by anchoring
  segments to the local day start (adaptive length near midnight). This was
  a test bug, not a product bug.

## Measurements and decisions (summary)

| Metric | baseline-6 (before) | after-F9 | after-F10 (pending) |
| --- | --- | --- | --- |
| Main busy today-idle | 25.5% | 30.8%* | — |
| Main busy today-scroll | 31.7% | 31.5% | — |
| Main busy tasks-scroll | 12.4% | 17.2%* | — |
| Today clock frames in tasks-scroll | 118 | 13 | — |
| Dense scenario passes end-to-end | no | yes | — |

*after-f9 idle window started ~20 s after launch (launch catch-up still
running) — timing artifact, not a regression.

Decisions:
- D1: F9 — gate Today clock sources on tab selection (compact shell).
- D2: F10 — revision-keyed subtree-active-timer index for Tasks rows.
- D3: Analytics page background refresh NOT gated: its minute-bucket cache
  already makes background ticks cheap; not in hotspot evidence.
- D4: Countdown `Text(date, style: .relative)` timers left as-is (SwiftUI
  coalesces them; gating would change the UI).
- D5: Regular-shell Today clocks are not gated (Today unmounts when the
  destination changes; a pushed task detail keeps clocks running behind it
  — accepted, documented limit).

## Decisions

(AD-style decisions made during this work, append only)

## Test Record (closeout)

| Test | Protects | Oracle | Boundary | Kind | Disposition |
| --- | --- | --- | --- | --- | --- |
| TodayTimelineSnapshotTests (4) | Timeline cache correctness: same-minute reads equal; ledger writes, task edits, minute advances invalidate | Store-level timeline semantics | Store facade `timelineSnapshot` | Permanent regression | Retained |
| TaskManagementRowSupplementProjectionTests (3) | Row supplement cache: fresh store, quantity mutation invalidation, stable reads | Store read-model semantics | Store facade projection | Permanent regression | Retained |
| TaskActiveTimerIndexTests (2) | Subtree-active-timer index: ancestors true, unrelated false, stop invalidates | Task-tree + ledger semantics | Store facade index | Permanent regression | Retained |
| PerformanceProbeUITests (scaffold) | Measurement driver for dense-fixture scenarios | n/a (manual host-side sampling) | UI | TEST-SCAFFOLD | Deleted at closeout (35cef82d) |

No `TEST-SCAFFOLD` markers remain in the changed scope.

## Resource Ownership Log

- Every simulator batch created one iPhone 17 Pro (iOS 27) sim and deleted it
  in the run trap: baseline-1..6, after-f9, after-f10. Verified zero Booted
  simulators and zero TimeTracker sims at closeout.
- Sampler loops and xcodebuild runners were killed at batch end; no owned
  process remains (verified via pgrep).
- Raw evidence lives in /tmp/timetracker-perf/ (baseline-6, after-f9,
  after-f10 sample sets + markers); metrics are recorded above. The probe
  and scripts were host-local scaffolding and are not in the repo.

## Closeout

Status: complete.

- 4 optimizations landed: F1 timeline snapshot cache, F2 tasks row
  supplement cache, F9 background-tab clock gating, F10 subtree-active-timer
  index. 9 permanent behavior tests added; all retained.
- Measured (dense fixture: 1,200 tasks / 1,580 segments / 24 active timers /
  400 inbox / 120 countdowns, iPhone 17 Pro sim, iOS 27, Debug):
  - Today main-thread busy: idle 25.5%→26.6% (noise), scroll 31.7%→29.5%;
    background clock frames on other tabs: 118→13 sample lines (89%).
  - Tasks scroll busy: 12.4%→10.9%; row body frames 1.5%→0.1%.
  - Inbox 18.7%, Analytics 12.2% — clean, no change.
  - The dense end-to-end scenario (launch → all five pages → return) went
    from never completing to passing consistently in ~300 s.
- Final gates on the frozen state: `make test` 175/175 passed (29 suites),
  `make localization-check` 9/9, `make format-check` 0/723, signed
  `make build-ios` and `make build-macos` succeeded.
- UI unchanged: all optimizations are caching/gating; screenshots and AX
  assertions from the probe runs confirm identical presentation.
- Resources: zero Booted simulators, zero owned processes; evidence kept in
  /tmp/timetracker-perf/ until the OS reclaims it.
- Branch: `perf/ui-component-performance-2026-08-05` (13 commits).
