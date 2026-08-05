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

## Progress Tracker

- [x] Branch created, master doc written, initial commit.
- [ ] Static SwiftUI audit of all components (identity, lazy containers, clocks, observation).
- [ ] Measurement harness: seeded stress fixture + baseline capture method validated.
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
