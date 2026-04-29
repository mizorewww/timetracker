# Time Tracker Architecture Plan

This document is the working map for keeping Time Tracker understandable as the app grows. It answers two questions:

1. Where should a future feature live?
2. What boundaries prevent UI bugs, sync bugs, and ledger bugs from spreading?

The short version: `TimeSegment` remains the fact layer, repositories own persistence, pure services own calculations, domain stores own published snapshots, and SwiftUI views render state.

## Current Direction

The app is moving from one broad facade toward feature-owned modules. `TimeTrackerStore` may remain the compatibility facade for views, but it should not keep absorbing business rules.

Current progress:

- `LedgerStore` owns visible and history ledger snapshots.
- `AnalyticsStore` owns cached analytics snapshots.
- `RollupStore` owns task rollup and forecast state.
- `PreferenceStore` owns synced user preference loading.
- `MaintenanceServices` owns CSV export and database cleanup rules.
- `TaskTreeService`, `TaskTreeFlattener`, and related pure services own task tree derivation.
- `StoreRefreshPlanner` maps user invalidation events to domain-sized refresh scopes.
- `StoreRefreshPlan` centralizes derived refresh rules for rollups, analytics, selection validation, and Live Activity sync, while preserving affected task IDs and ledger ranges for future incremental refresh.
- `TimerCommandHandler`, `TaskDraftCommandHandler`, `PomodoroCommandHandler`, `LedgerCommandHandler`, `CountdownCommandHandler`, `ChecklistCommandHandler`, and `PreferenceCommandHandler` own the first layer of user write commands.
- `DailySummaryService` clips raw `TimeSegment` rows into daily summary snapshots and feeds daily analytics without replacing the ledger fact layer.
- Repository protocols and SwiftData implementations are split by persistence owner: task tree, ledger, and pomodoro.
- Sidebar and inspector SwiftUI are separated into navigation, reusable task row commands, inspector shell, checklist panel, and forecast panel files.
- Editor SwiftUI is separated into task editing, task editor components, manual time entry, segment editing, and symbol/color picking.
- Forecast code is split into rollup models, the rollup calculation service, optional pace forecasting helpers, and display selection rules.

Remaining risk:

- `TimeTrackerStore.refresh(plan:)` still invokes multiple domain refresh methods, but the refresh decision table lives in tested `StoreRefreshPlan`.
- Command handlers still call use cases and repositories directly, but business sequences are no longer embedded in SwiftUI-facing methods.
- Some repository methods still need range caches or bucket indexes before very large ledgers feel cheap.
- Analytics and Home are now split by component family, but layout policy still lives close to SwiftUI views and should eventually move into small layout policy types.

## Target Module Shape

The codebase should converge on this structure over several safe refactor rounds:

```text
timetracker/
  App/
    timetrackerApp.swift
    AppBuildInfo.swift
    AppCloudSync.swift

  Models/
    TimeTrackerModels.swift
    SchemaMigration.swift
    StoreModels.swift

  Repositories/
    RepositoryProtocols.swift
    SwiftDataTaskRepository.swift
    SwiftDataLedgerRepository.swift
    SwiftDataPomodoroRepository.swift
    SwiftDataPreferenceRepository.swift

  Commands/
    TaskCommands.swift
    LedgerCommands.swift
    ChecklistCommands.swift
    PomodoroCommands.swift
    PreferenceCommands.swift

  Stores/
    TimeTrackerStore.swift
    TaskStore.swift
    LedgerStore.swift
    RollupStore.swift
    AnalyticsStore.swift
    PreferenceStore.swift

  Services/
    TaskTreeService.swift
    LedgerSummaryService.swift
    TaskRollupModels.swift
    TaskRollupService.swift
    ForecastingService.swift
    ForecastDisplayService.swift
    AnalyticsEngine.swift
    TimelineLayoutEngine.swift
    MaintenanceServices.swift

  Features/
    Home/
    Tasks/
    Pomodoro/
    Analytics/
    Settings/
    Sidebar/
    Inspector/

  SharedUI/
    Metrics/
    Rows/
    Timeline/
    Forms/
    EmptyStates/
```

The exact folders can be introduced gradually. The important rule is ownership: a feature file should be easy to find from the screen name, while business rules should be easy to test without SwiftUI.

## Ownership Rules

`Models` define persisted shape and migration compatibility. They should not contain workflow logic beyond small computed conveniences.

`Repositories` translate queries and writes to SwiftData. They should push safe predicates to SwiftData where possible, but avoid clever predicates that break optional date semantics. When a query remains intentionally in-memory, document the expected replacement such as a date bucket or summary cache.

`Commands` are the write boundary. A command should express one user action: start timer, stop timer, move task, toggle checklist item, complete pomodoro round, or update a setting. Commands decide which domain snapshots must be invalidated after a write.

`Stores` publish already-prepared state to SwiftUI. Stores should not be large calculation engines. They may compose repositories, commands, and pure services, then publish snapshots.

`Services` are pure or mostly pure logic. They should be tested directly. Examples: tree flattening, overlap detection, rollup estimation, date clipping, CSV formatting, and timeline lane allocation.

`Features` render and collect user input. Views may choose layout, but they should not perform durable business rules or expensive analytics calculations in `body`.

## Write Flow

Target write flow:

```text
SwiftUI action
  -> TimeTrackerStore facade method
  -> Domain command handler
  -> Repository write
  -> Domain store invalidation
  -> Only affected snapshots refresh
  -> SwiftUI renders published state
```

Example: checklist toggle

```text
Checklist row tap
  -> TimeTrackerStore.toggleChecklistItem(...)
  -> ChecklistCommandHandler.toggle(...)
  -> Checklist repository updates one item
  -> TaskStore refreshes affected task checklist
  -> RollupStore recomputes affected task branch
  -> AnalyticsStore invalidates ranges only if the estimate surface needs it
```

This prevents a small checklist edit from refetching every timer, pomodoro, preference, and analytics snapshot.

Checklist forecast invalidation is not optional. Toggling, adding, renaming, deleting, or reordering a checklist item must invalidate the affected task branch in `RollupStore` immediately, because the visible remaining time is a direct function of checklist progress.

Forecast rules:

```text
Forecast eligibility = task has checklist + at least one completed item + tracked time on that task
Completed checklist = own remaining time is zero
Manual estimates = planning metadata only, not a forecast trigger
Historical time = projected days only, never remaining hours by itself
```

Parent tasks follow one display rule across Home, Analytics, and Inspector: show the parent when it has its own checklist or multiple forecastable child branches; otherwise drill into the single forecastable child branch so the user sees the task that actually owns the checklist.

## Read Flow

Target read flow:

```text
Repository query
  -> domain-sized snapshot
  -> pure services derive secondary state
  -> domain store publishes immutable view state
  -> SwiftUI view renders
```

Views should prefer published snapshots over calling calculation methods during rendering. `TimelineView` is acceptable for visual clock text, but not for full analytics recomputation.

## Feature Ownership Map

Use this table when adding or debugging features.

| Feature | Durable model | Write command | Store/snapshot | Pure services | UI owner |
| --- | --- | --- | --- | --- | --- |
| Start/stop timer | `TimeSession`, `TimeSegment` | `LedgerCommands` | `LedgerStore` | `LedgerSummaryService` | `Features/Home`, `Features/Inspector` |
| Manual time | `TimeSession`, `TimeSegment` | `LedgerCommands` | `LedgerStore`, `AnalyticsStore` | `TimelineLayoutEngine` | `Features/Home`, `SharedUI/Forms` |
| Task edit/move/delete | `TaskNode` | `TaskCommands` | `TaskStore`, `RollupStore` | `TaskTreeService`, `TaskTreeFlattener` | `Features/Tasks`, `Features/Sidebar` |
| Checklist | `ChecklistItem` | `ChecklistCommands` | `TaskStore`, `RollupStore` | `ChecklistDraftService`, `TaskRollupService` | `Features/Tasks`, `Features/Inspector` |
| Forecast | none, derived | none | `RollupStore` | `TaskRollupService`, `ForecastDisplayService` | `Features/Home`, `Features/Analytics`, `Features/Inspector` |
| Pomodoro | `PomodoroRun`, ledger models | `PomodoroCommands` | `LedgerStore` | `PomodoroState` helpers | `Features/Pomodoro` |
| Analytics | none, derived | none | `AnalyticsStore` | `AnalyticsEngine`, `TimeAggregationService` | `Features/Analytics` |
| Synced settings | `SyncedPreference` | `PreferenceCommands` | `PreferenceStore` | `AppPreferenceCodec` | `Features/Settings` |
| iCloud mode | `SyncedPreference`, local mirror | `PreferenceCommands` | `PreferenceStore` | `AppCloudSync` | `Features/Settings` |
| CSV export | none | none | none | `CSVExportService` | `Features/Settings` |
| Database optimize | destructive maintenance | `MaintenanceCommands` | all affected stores | `DatabaseMaintenanceService` | `Features/Settings` |
| Live Activity | ledger snapshot | `LedgerCommands` through intent/action | `LedgerStore` | shared activity attributes | extension UI |

## Refresh and Invalidation Plan

The facade should stop deciding global refresh order. The current bridge is `StoreRefreshPlanner`: write methods emit `StoreInvalidationEvent` values with affected task IDs and optional time ranges, and the planner converts those events to refresh scopes. This keeps invalidation intent testable and gives later work a place to narrow refreshes to one task branch or date bucket.

Current invalidation mapping:

| Event | Refresh scopes |
| --- | --- |
| `taskTreeChanged(taskID:)` | Tasks, rollups, analytics, Live Activities |
| `timerChanged(taskID:)` | Visible ledger, pomodoro, rollups, analytics, Live Activities |
| `ledgerHistoryChanged(taskID:range:)` | Ledger history, rollups, analytics, Live Activities |
| `pomodoroChanged(taskID:)` | Visible ledger, pomodoro, rollups, analytics, Live Activities |
| `checklistChanged(taskID:)` | Checklist, rollups, analytics |
| `preferencesChanged` | Preferences |
| `countdownChanged` | Countdown events |
| `fullSync` | Full refresh |

Next step is replacing coarse refresh scopes with explicit domain events:

```text
TaskChanged(taskID, affectedAncestorIDs)
ChecklistChanged(taskID, affectedAncestorIDs)
LedgerChanged(taskID, dateInterval)
PomodoroChanged(runID, sessionID, taskID)
PreferenceChanged(key)
RemoteImportCompleted
```

Each domain store decides if the event matters. For example:

- `LedgerChanged` refreshes active segments and the affected day/range.
- `ChecklistChanged` recomputes only the affected rollup branch.
- `PreferenceChanged(.quickStartPinnedTaskIDs)` refreshes quick start state only.
- `RemoteImportCompleted` may schedule a coalesced background refresh instead of immediate full refresh.

## Ledger Query Strategy

Current range queries intentionally use simple SwiftData predicates plus deterministic in-memory clipping. This is correct but not the final performance shape.

Next options, in order:

1. Add a `LedgerDateBucket` or `DailySummary` cache generated from `TimeSegment`.
2. Use buckets for Month and long-range Analytics.
3. Keep raw `TimeSegment` as the source of truth and rebuild buckets when rules change.
4. Keep all active-segment queries direct and fresh; active timers must never wait for a summary cache.

Do not replace the ledger with summaries. Summaries are disposable derived data.

Current progress:

- `DailySummaryService` can generate in-memory `DailySummarySnapshot` rows from raw segments.
- Daily analytics now uses day-clipped summaries, so cross-day segments are not double-counted.
- Persisted `DailySummary` can be introduced later as a cache using `DailySummaryService.model(from:)`.

## UI Architecture Plan

The UI should feel like a native Apple productivity app: predictable navigation, system controls first, restrained custom drawing, and clear information hierarchy.

Rules:

- Use `NavigationSplitView`, `List`, `Form`, `Table`, `.inspector`, `Menu`, `Picker`, and system toolbar items before custom containers.
- Cards are only for grouped content that benefits from framing. Avoid nested cards.
- Each feature should define a small layout policy for compact, regular, and wide widths.
- Expensive derived values should be passed in, not recalculated by rows.
- User-facing copy should explain outcomes, not internal model names.
- iPhone rows may use two lines; iPad and macOS rows should prioritize scanability and alignment.

Recommended splits:

```text
HomeViews
HomeMetricsViews
HomeTimelineViews
HomeQuickStartViews
HomeForecastViews
TaskListScreen
TaskEditorSheet
TaskEditorComponents
TaskChecklistSection
ManualTimeViews
SegmentEditorViews
SymbolPickerViews
AnalyticsOverviewSection
AnalyticsTimelineSection
AnalyticsDistributionSection
AnalyticsActivityViews
AnalyticsRowsViews
SidebarInspectorViews
TaskRowComponents
InspectorViews
InspectorChecklistViews
InspectorForecastViews
SettingsGeneralPane
SettingsDataPane
SettingsAboutPane
```

## Localization Rules

All user-facing text must come from `AppStrings` or localized string resources. Enums shown in UI must expose localized display APIs and should not use `rawValue` for display.

Tests should cover:

- Key parity across English, Simplified Chinese, and Traditional Chinese.
- No hard-coded Chinese in Swift source outside previews/tests.
- A small whitelist for non-user-facing English identifiers.
- Localized labels for key enums such as task status, pomodoro state, analytics range, sync state, and forecast confidence.

## Testing Strategy

Prefer behavior tests over source-string tests.

Keep tests grouped by subsystem:

```text
LedgerTests
TaskTreeTests
ChecklistTests
ForecastingTests
AnalyticsTests
PreferenceTests
MaintenanceTests
LocalizationTests
UIContractTests
```

Minimum test expectations for future features:

- Pure service tests for calculations and edge cases.
- Store/command tests for refresh invalidation and published state.
- Migration tests when adding fields.
- Localization parity tests for all new user-facing strings.
- At least one iOS generic build after changes touching app extensions, Live Activities, or shared models.

## Bug Prevention Checklist

Before merging a feature:

1. Can the feature be found from the feature ownership table?
2. Does every durable write go through a command or repository boundary?
3. Does the view avoid expensive work in `body`?
4. Are active timers still derived from open `TimeSegment` rows?
5. Are soft-deleted tasks and historical ledger rows handled intentionally?
6. Does iCloud remote import refresh only the needed state or at least coalesce refreshes?
7. Are compact iPhone, iPad split view, and macOS inspector layouts considered separately?
8. Are all strings localized in English, Simplified Chinese, and Traditional Chinese?
9. Are tests behavior-based rather than fragile source scans?
10. Did macOS tests and generic iOS build pass?

## Near-Term Refactor Backlog

P1:

- Move command handlers behind feature stores so writes can publish domain events instead of returning through `TimeTrackerStore.perform`.
- Replace scope-level refresh orchestration with event-based domain invalidation.
- Keep `TimeTrackerStore` as a facade only until views are moved to feature stores.

P2:

- Add ledger date buckets or summary caches for large Month/Year analytics.
- Continue keeping Home feature files narrow as new sections are added.
- Continue splitting Analytics until chart-specific layout code and row components are isolated from the screen entry.
- Replace source-string tests with domain behavior tests where possible.

P3:

- Create a shared UI component library for metrics, rows, empty states, and timeline labels.
- Add lightweight UI automation checks for iPhone compact rows, iPad sidebar collapse/expand, macOS inspector, and settings windows.
- Add performance budgets for analytics snapshot generation and task tree flattening with large mock data.
