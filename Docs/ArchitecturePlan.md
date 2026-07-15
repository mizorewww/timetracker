# Time Tracker Architecture Plan

Status: current architecture guardrails. Concrete file entry points are maintained in [ProjectMap](ProjectMap.md); completed and remaining structure work is maintained in [CodeRefactorPlan](CodeRefactorPlan.md).

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
  Stores/           Observable domain snapshots and facade wiring
  Features/         Screen-specific SwiftUI
  Shared/           Shared extension-safe models
  SharedUI/         Reusable UI pieces
```

`TimeTrackerStore` is still the SwiftUI facade, but it is now split into lifecycle, read-model, analytics, maintenance, and domain command extensions. The facade is `@MainActor @Observable`. App roots own it with `@State`; injected feature views keep a plain reference, and presentation bindings use a local `@Bindable`. Do not reintroduce `ObservableObject/@Published` on the facade or store action closures in focused values.

Domain stores own state snapshots:

- `TaskStore` owns task tree snapshots.
- `LedgerStore` owns active, today, history, segment/day/session indexes and mutation deltas.
- `ChecklistStore` owns global bootstrap plus task-scoped item/visual replacement indexes.
- `RollupStore` owns exact worked totals, checklist progress, forecast state and the bounded 90-local-day pace index.
- `AnalyticsStore` owns range/period/live-bucket overview and task snapshot caches plus disposable ledger day buckets.
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

`StoreRefreshPlanner` converts those events into a `StoreRefreshPlan`. This keeps refresh behavior testable. When the task topology is stable, `LedgerStore` fetches only invalidated ranges, `ChecklistStore` replaces only affected task buckets, and `RollupStore` consumes segment before/after deltas plus direct/ancestor IDs. `AnalyticsStore` invalidates snapshot caches and only the day buckets intersecting ledger ranges. Full rebuild remains the explicit path for startup, topology/full-sync changes, remote import without a safe scope, and calendar/time-zone changes.

External CloudKit changes enter the same pipeline through remote-store and completed import/export notifications. The observer coalesces bursts before emitting `remoteImportCompleted`; launch and foreground activation remain consistency boundaries. There is no permanent foreground polling timer.

Sync-conflict state is a separate cross-process state machine. A recursive local lock plus POSIX `lockf` serializes app/Shortcuts read-modify-write transactions. Epoch/generation/fingerprint checkpoints tie Cloud export completion to the exact version that started it, so stale or out-of-order callbacks cannot acknowledge newer local mutations. The state uses bounded lightweight checkpoints, not a full snapshot per event.

The 2026-07-14 split established focused owners instead of the former aggregation files:

- Analytics root/category/period/detail lists and store metrics/breakdowns/overlap/task snapshots.
- Settings display/timing, Pomodoro, picker, countdown, sync, data, actions, bindings, and support.
- Task Detail router plus identity, checklist, overview, analytics, navigation, and record sections.
- Ledger Cloud startup, persistence safety, timer DTO, aggregation, formatting, device identity, and summary.
- SyncConflict bootstrap/prompt, local mutation, Cloud import/export, recovery/resolution, state persistence/lock/locations, filtered export, snapshot capture/domain restore/state, and domain record DTOs.
- Facade first configuration/repository-only system-surface attachment versus refresh/mutation/recovery lifecycle.

`SettingsSectionsViews.swift` and `TimeTrackerServices.swift` are retired; do not use those names for new miscellaneous code. Remaining concentrated files and their next boundaries are explicit in `CodeRefactorPlan`.

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
  -> SwiftUI renders observed state
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
  -> domain store exposes immutable view state
  -> SwiftUI view renders
```

Views should render existing snapshots. They should not calculate analytics, tree rollups, or forecast decisions inside `body`. `TimelineView` is acceptable for clock labels; it is not a place to rebuild analytics.

## Feature Ownership Map

| Feature | Durable model | Write owner | Snapshot owner | Pure services | UI owner |
| --- | --- | --- | --- | --- | --- |
| Start and stop timer | `TimeSession`, `TimeSegment` | `TimerCommandHandler`, `LedgerCommandHandler` | `LedgerStore`, `RollupStore` | `LedgerSummaryService` | `Features/Home`, `Features/Tasks/Detail` |
| Manual time and segment editing | `TimeSession`, `TimeSegment` | `LedgerCommandHandler` | `LedgerStore`, `AnalyticsStore` | `TimelineLayoutEngine` | `Features/Ledger`, `Features/Home` |
| Task edit, move, archive, delete | `TaskNode` | `TaskDraftCommandHandler` | `TaskStore`, `RollupStore` | `TaskTreeService`, `TaskTreeFlattener`, `TaskHierarchyMetadataService` | `Features/Tasks`, `Features/Sidebar` |
| Task categories | `TaskCategory`, `TaskCategoryAssignment` | task category commands, task draft command | `TaskStore`, `RollupStore` | `TaskTreeService` | `Features/Tasks`, `Features/Sidebar` |
| Checklist | `ChecklistItem` | `ChecklistCommandHandler` | `ChecklistStore`, `RollupStore` | `ChecklistDraftService`, `TaskRollupService` | `Features/Tasks/Editor`, `Features/Tasks/Detail` |
| Forecast | none, derived | none | `RollupStore` | `TaskRollupService`, `ForecastDisplayService` | `Features/Home`, `Features/Analytics`, `Features/Tasks/Detail` |
| Pomodoro | `PomodoroRun`, ledger models | `PomodoroCommandHandler`, ledger/task commands | `LedgerStore`, Pomodoro read models | persisted-phase deadline/reconciliation helpers | `Features/Pomodoro` |
| Analytics | none, derived | none | `AnalyticsStore` | `AnalyticsEngine`, `TimeAggregationService` | `Features/Analytics` |
| Synced settings | `SyncedPreference` | `PreferenceCommandHandler` | `PreferenceStore` | `AppPreferenceCodec`, `SyncedPreferenceService` | `Features/Settings` |
| Countdown events | `CountdownEvent` | `CountdownCommandHandler` | `TimeTrackerStore` countdown snapshot | date formatting helpers | `Features/Home`, `Features/Settings` |
| JSON export | none | facade maintenance command | none | export DTO encoding | `Features/Settings/Support/SettingsExportDocument` |
| Tombstone maintenance | destructive maintenance, Demo/UI Test only | maintenance facade | affected stores | `DatabaseMaintenanceService` | hidden for production stores |
| Live Activity | ledger snapshot | shared ledger commands/intents | `LedgerStore` | shared activity attributes | extension UI |

## Forecast Rules

Forecast is checklist-driven. Do not invent remaining hours from unrelated history.

```text
Eligible = task has checklist + at least one completed item + tracked time on that task
Completed checklist = own remaining time is zero
Manual estimate = planning metadata only
Recent pace = active-day average over the latest 90 local days, used only to turn existing remaining seconds into projected active days
```

Parent tasks follow one display rule across Home, Analytics, and Task Detail:

- If the parent has its own checklist, show the parent and include child forecast recursively.
- If the parent has no checklist and exactly one forecastable child branch, drill into that child so the user sees the task that owns the checklist.
- If the parent has no checklist and multiple forecastable child branches, show an aggregate parent forecast and label it as a summary.

## Ledger Query Strategy

Initial/full range queries use SwiftData predicates plus deterministic clipping. Normal mutations use `LedgerStore` day/ID indexes to fetch and replace only segments overlapping `StoreInvalidationRange`, update related session IDs, and emit coalesced `LedgerSegmentChange` values. `AnalyticsStore` caches daily summaries plus full overview/task snapshots by range and true calendar period start; a minute key is added only when an active segment overlaps that range.

Rules:

1. Keep raw `TimeSegment` as the source of truth and rebuild buckets when summary rules change.
2. Keep active timer queries direct and fresh; active timers must never wait for a cache.
3. Invalidate full overview/task snapshots after relevant facts change, and invalidate only intersecting day buckets from `ledgerChanged` ranges.
4. Keep rollup full-history totals exact; only forecast pace is bounded to 90 local days.
5. Preserve the 50,000-segment single-mutation budget and equality with a full rebuild.

## Schema Evolution Rules

SwiftData models must stay compatible with existing local and iCloud stores. New features should not casually add columns to `TaskNode`, `TimeSession`, `TimeSegment`, or other fact-layer models.

Rules:

1. Prefer extension models with explicit UUID references for new feature data. Example: task categories use `TaskCategory` plus `TaskCategoryAssignment(taskID, categoryID)` instead of adding `categoryID` to `TaskNode`.
2. If an existing core model truly needs a new persisted field, add a new schema version, make the field optional or give it a stable default, and add a migration/compatibility test before wiring UI.
3. Old `VersionedSchema` definitions must keep their historical model shape. A new feature must not mutate older schema versions by reusing a changed model shape without a migration strategy.
4. Never reuse a schema version identifier for a different model shape. If a bad schema reached a build or branch that may have been installed, the next compatible schema must use a new version number.
5. CloudKit-backed models should keep `id`, timestamps, `deletedAt`, `deviceID`, and `clientMutationID` semantics stable. Soft delete remains the default for user data that can sync.
6. Every schema change must update `TimeTrackerModelRegistry.cloudSyncedUserModelNames` expectations and add a test proving old stores can still open or that the change is isolated in a new extension model.

The guiding principle is forward migration, not feature rollback: existing user data opens first, then new feature data is added in a compatible layer.

## UI Rules

The UI should feel like a native Apple productivity app: predictable navigation, system controls first, restrained custom drawing, and clear information hierarchy.

- Prefer `NavigationSplitView`, `NavigationStack`, `List`, `Form`, `Table`, `Menu`, `Picker`, and system toolbar items before custom containers. Task Detail is currently the canonical selected-task surface; adding an inspector requires an explicit product decision rather than being a default layout assumption.
- macOS uses one main `Window`, not `WindowGroup`; its Settings scene receives the same application store. Multi-window support requires a prior split between app-scoped persistence/automation and scene-scoped navigation/editor drafts.
- Cards are only for grouped content that benefits from framing. Avoid nested cards.
- iPhone rows may use two lines; iPad and macOS rows should prioritize scanability and alignment. At accessibility Dynamic Type sizes, dense rows must reflow vertically or use a space-efficient native control such as a menu; truncating primary text is not an acceptable substitute.
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
7. Are compact iPhone, iPad split view, and macOS sidebar/detail layouts considered separately?
8. Are all strings localized in English, Simplified Chinese, and Traditional Chinese?
9. Are tests behavior-based rather than fragile source scans?
10. Did the final working-tree macOS tests, UI tests, signed builds, simulator screenshots, and required trace pass, with evidence recorded in the dated Audit rather than inferred from an earlier batch?
