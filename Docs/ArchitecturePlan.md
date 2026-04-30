# Time Tracker Architecture Plan

This document is the working map for keeping Time Tracker understandable as it grows. It should answer two practical questions:

1. Where does a new feature belong?
2. Which boundary should prevent UI, sync, forecast, and ledger bugs from spreading?

The product rule is unchanged: `TimeSegment` is the fact layer. Tasks, checklist items, pomodoro runs, settings, summaries, and forecasts are all supporting structures around that ledger.

## Current Architecture

The app is organized by ownership instead of by one large SwiftUI surface:

```text
timetracker/
  App/              App entry, build info, CloudKit mode
  Models/           SwiftData models, schema, view/store DTOs
  Repositories/     SwiftData query/write implementations
  Commands/         User action handlers and use cases
  Services/         Pure calculations and maintenance logic
  Stores/           Published domain snapshots and facade wiring
  Features/         Screen-specific SwiftUI
  Shared/           Shared extension-safe models
  SharedUI/         Reusable UI pieces
```

`TimeTrackerStore` is still the SwiftUI facade, but it is now split into lifecycle, read-model, analytics, maintenance, and domain command extensions. Domain stores own state snapshots:

- `TaskStore` owns task tree snapshots.
- `LedgerStore` owns active, today, paused, and history ledger snapshots.
- `RollupStore` owns task rollup, checklist progress, and forecast state.
- `AnalyticsStore` owns cached analytics snapshots.
- `PreferenceStore` owns synced preference snapshots.

`StoreRefreshCoordinator` owns refresh sequencing after command events. The facade no longer decides the order of task, ledger, checklist, rollup, analytics, selection validation, and Live Activity side effects inline.

`StoreDomainEvent` is the write-side invalidation language. Commands now emit what happened, not which views should refresh:

```text
taskChanged(taskID, affectedAncestorIDs)
checklistChanged(taskID, affectedAncestorIDs)
ledgerChanged(taskID, dateInterval, isVisible)
pomodoroChanged(runID, sessionID, taskID)
preferenceChanged(key)
countdownChanged
remoteImportCompleted
fullSync
```

`StoreRefreshPlanner` converts those events into a `StoreRefreshPlan`. This keeps refresh behavior testable. `RollupStore` consumes affected task IDs from the plan and refreshes only the changed task branch plus ancestors when the task tree itself did not change. `AnalyticsStore` owns a disposable day-bucket cache for daily summary points and invalidates buckets from ledger date ranges carried by refresh plans.

## Write Flow

Target write flow:

```text
SwiftUI action
  -> TimeTrackerStore facade method
  -> Domain command handler
  -> Repository write
  -> StoreDomainEvent
  -> StoreRefreshPlanner
  -> StoreRefreshCoordinator
  -> Affected domain snapshots refresh in domain order
  -> SwiftUI renders published state
```

Example: checklist toggle

```text
Checklist row tap
  -> TimeTrackerStore.toggleChecklistItem(...)
  -> ChecklistCommandHandler.toggle(...)
  -> SwiftData updates one ChecklistItem
  -> checklistChanged(taskID, affectedAncestorIDs)
  -> Checklist, Rollup, Analytics refresh
```

Checklist forecast invalidation is not optional. Toggling, adding, renaming, deleting, or reordering a checklist item must update the affected task branch immediately because visible remaining time is a direct function of checklist progress.

## Read Flow

Target read flow:

```text
Repository query
  -> domain-sized snapshot
  -> pure services derive secondary state
  -> domain store publishes immutable view state
  -> SwiftUI view renders
```

Views should render existing snapshots. They should not calculate analytics, tree rollups, or forecast decisions inside `body`. `TimelineView` is acceptable for clock labels; it is not a place to rebuild analytics.

## Feature Ownership Map

| Feature | Durable model | Write owner | Snapshot owner | Pure services | UI owner |
| --- | --- | --- | --- | --- | --- |
| Start, pause, resume, stop timer | `TimeSession`, `TimeSegment` | `TimerCommandHandler`, `LedgerCommandHandler` | `LedgerStore`, `RollupStore` | `LedgerSummaryService` | `Features/Home`, `Features/Inspector` |
| Manual time and segment editing | `TimeSession`, `TimeSegment` | `LedgerCommandHandler` | `LedgerStore`, `AnalyticsStore` | `TimelineLayoutEngine` | `Features/Ledger`, `Features/Home` |
| Task edit, move, archive, delete | `TaskNode` | `TaskDraftCommandHandler` | `TaskStore`, `RollupStore` | `TaskTreeService`, `TaskTreeFlattener` | `Features/Tasks`, `Features/Sidebar` |
| Checklist | `ChecklistItem` | `ChecklistCommandHandler` | `RollupStore` | `ChecklistDraftService`, `TaskRollupService` | `Features/Tasks`, `Features/Inspector` |
| Forecast | none, derived | none | `RollupStore` | `TaskRollupService`, `ForecastDisplayService` | `Features/Home`, `Features/Analytics`, `Features/Inspector` |
| Pomodoro | `PomodoroRun`, ledger models | `PomodoroCommandHandler` | `LedgerStore` | Pomodoro state helpers | `Features/Pomodoro` |
| Analytics | none, derived | none | `AnalyticsStore` | `AnalyticsEngine`, `TimeAggregationService` | `Features/Analytics` |
| Synced settings | `SyncedPreference` | `PreferenceCommandHandler` | `PreferenceStore` | `AppPreferenceCodec`, `SyncedPreferenceService` | `Features/Settings` |
| Countdown events | `CountdownEvent` | `CountdownCommandHandler` | `TimeTrackerStore` countdown snapshot | date formatting helpers | `Features/Home`, `Features/Settings` |
| CSV export | none | none | none | `CSVExportService` | `Features/Settings` |
| Database optimize | destructive maintenance | `MaintenanceCommands` | affected stores | `DatabaseMaintenanceService` | `Features/Settings` |
| Live Activity | ledger snapshot | shared ledger commands/intents | `LedgerStore` | shared activity attributes | extension UI |

## Forecast Rules

Forecast is checklist-driven. Do not invent remaining hours from unrelated history.

```text
Eligible = task has checklist + at least one completed item + tracked time on that task
Completed checklist = own remaining time is zero
Manual estimate = planning metadata only
Historical time = used only to turn remaining hours into projected days
```

Parent tasks follow one display rule across Home, Analytics, and Inspector:

- If the parent has its own checklist, show the parent and include child forecast recursively.
- If the parent has no checklist and exactly one forecastable child branch, drill into that child so the user sees the task that owns the checklist.
- If the parent has no checklist and multiple forecastable child branches, show an aggregate parent forecast and label it as a summary.

## Ledger Query Strategy

Current range queries intentionally use simple SwiftData predicates plus deterministic in-memory clipping. This is correct and testable. `AnalyticsStore` now adds a disposable date-bucket cache for daily summary points so Month and long-range analytics do not repeatedly rebuild the same day summaries during normal view refreshes.

Rules:

1. Keep raw `TimeSegment` as the source of truth and rebuild buckets when summary rules change.
2. Keep active timer queries direct and fresh; active timers must never wait for a cache.
3. Invalidate day buckets from `ledgerChanged` date ranges rather than clearing the whole analytics cache by default.

## UI Rules

The UI should feel like a native Apple productivity app: predictable navigation, system controls first, restrained custom drawing, and clear information hierarchy.

- Prefer `NavigationSplitView`, `List`, `Form`, `Table`, `.inspector`, `Menu`, `Picker`, and system toolbar items before custom containers.
- Cards are only for grouped content that benefits from framing. Avoid nested cards.
- iPhone rows may use two lines; iPad and macOS rows should prioritize scanability and alignment.
- Expensive derived values should be passed in, not recalculated by rows.
- User-facing copy should explain outcomes, not internal model names.
- Repeated cards, metric cells, chart containers, checklist controls, and layout breakpoints belong in `SharedUI` or layout policy types before a second feature copies them.

## Localization Rules

All user-facing text must come from `AppStrings` or localized string resources. Enums shown in UI must expose localized display APIs and should not use `rawValue` for display.

Tests should cover:

- Key parity across English, Simplified Chinese, and Traditional Chinese.
- No hard-coded Chinese in Swift source outside previews/tests.
- A small whitelist for non-user-facing English identifiers.
- Localized labels for task status, pomodoro state, analytics range, sync state, forecast state, and forecast confidence.

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

Performance budgets currently cover:

- Large task-tree flattening.
- Large analytics snapshot generation.
- Dense overlapping analytics snapshots.
- Large ledger bucket summaries.
- Large timeline layout inputs.
- Long checklist rollup calculations.
- Affected branch rollup refresh.

Before merging a feature:

1. Can the feature be found from the ownership table?
2. Does every durable write go through a command or repository boundary?
3. Does the view avoid expensive work in `body`?
4. Are active timers still derived from open `TimeSegment` rows?
5. Are soft-deleted tasks and historical ledger rows handled intentionally?
6. Does iCloud remote import coalesce refresh work?
7. Are compact iPhone, iPad split view, and macOS inspector layouts considered separately?
8. Are all strings localized in English, Simplified Chinese, and Traditional Chinese?
9. Are tests behavior-based rather than fragile source scans?
10. Did macOS tests and generic iOS build pass?
