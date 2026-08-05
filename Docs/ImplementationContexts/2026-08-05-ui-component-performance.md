# UI Component & Page Performance Optimization — Implementation Memory (MASTER)

Status: in progress

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
`// TEST-SCAFFOLD: Docs/ImplementationContexts/2026-08-05-ui-component-performance.md — remove when <condition>.`
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

### §C3 TimelineChart family — status: [x] audited, fix applied via F1

- The chart itself is value-driven (pure `timeline` input); the cost was
  upstream: `store.timelineSnapshot` recomputed per body evaluation. Fixed by
  the revision+minute-bucket cache (F1). Chart layout math runs per
  GeometryReader pass — bounded by the 5,000-entry projection budget;
  watch in traces.

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
| P1 Today/Home | ⬜ measure | F1 fixed; F3/F4/F5 pending baseline evidence |
| P2 Tasks | ⬜ measure | F2 fixed; search path pending |
| P3 Inbox | ⬜ measure | static clean |
| P4 Analytics | ⬜ measure | static clean |
| P5 Ledger | ⬜ measure | static clean |
| P6 Pomodoro | ⬜ measure | static clean |
| P7 Sidebar | ⬜ measure | static clean |
| P8 Settings | ⬜ measure | static clean |
| P9 Shell/root | ⬜ measure | 2026-08-01 work already covers resize/navigation |

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
- [x] Measurement harness: perf probe UI test + host sampler + aggregator (first baseline in progress).
- [ ] Baseline evidence captured and recorded.
- [ ] C1..C10 shared components: measure → optimize → report.
- [ ] P1..P9 pages: measure → optimize → report.
- [ ] Final full gates + resource cleanup + closeout.

## Evidence Log

(chronological; append only)

## Resource Ownership Log

(UDIDs, PIDs, artifact paths; record before each batch, release after)

## Decisions

(AD-style decisions made during this work, append only)

## Closeout

(filled at end)
