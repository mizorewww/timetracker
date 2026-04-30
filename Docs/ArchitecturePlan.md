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

## Completed Architecture Phase

The current architecture-plan phase is complete. The items that used to be open have been moved into code or into permanent engineering rules:

- Refresh sequencing is owned by `StoreRefreshCoordinator`.
- Rollup refresh supports affected task branches and ancestors.
- Analytics daily summaries use `LedgerBucketCache`.
- Home, Tasks, Analytics, Pomodoro, split-view, and inspector sizing choices use layout policy types.
- Common metric/chart card containers live in `SharedUI`.
- Performance budget tests cover analytics snapshots, task tree flattening, and affected rollup refresh.
- UI automation smoke tests cover launch, primary navigation, settings, task editor, and pomodoro entry.

New architecture work should be added as a specific, testable finding before implementation rather than kept as a vague backlog.

## Next Development Roadmap

The next four phases should be executed in order. Each phase must start from documented expectations, add or update tests before risky implementation, and leave the app buildable on macOS and generic iOS. Do not mix new product features into these phases unless they directly support the phase goal.

### Phase 1: Reduce File Size And Nesting

Goal: make the codebase easier to navigate and lower the chance of layout or command bugs caused by large files and deeply nested SwiftUI bodies.

Scope:

- Continue splitting large SwiftUI files by stable sections:
  - `Features/Tasks`: editor shell, parent picker, checklist editor, symbol/color picker.
  - `Features/Home`: empty states, range header, remaining feature-specific row groups.
- Any SwiftUI `body` that needs more than three nested layout containers should extract named subviews or small helper builders.
- No behavior change is expected in this phase.

Tests and checks:

- Existing unit tests must keep passing.
- Generic iOS build must keep passing after file moves.
- `xcodebuild -list -project timetracker.xcodeproj` must still show the shared `timetracker` app scheme after filesystem moves.
- Add behavior tests only when extracting code reveals undocumented behavior.

Completed in this phase:

- `Models/TimeTrackerModels.swift` was split into domain model files for task, ledger, pomodoro, checklist, preferences, countdown events, summaries, and schema registration.
- `Commands/DomainCommands.swift` was split into command-owner files for timer, task, checklist, pomodoro, ledger, preference, and countdown writes.
- `Features/Pomodoro/PomodoroViews.swift` was split into setup, active-run, and recent-ledger view files under `Features/Pomodoro/Sections`.
- `Features/Inspector/InspectorViews.swift` was split into info, panels, actions, checklist, forecast, and summary view files under `Features/Inspector/Sections`.
- `Features/Tasks/Management/TasksViews.swift` now owns the task-management screen shell while task list rows and progress lines live beside it in the management folder.
- `Features/Tasks/Editor` owns task editing, checklist editing, symbol picking, and editor-specific controls.
- `Features/Home` now separates page composition, controls, rows, and sections so Today layout changes do not touch timer row internals.
- `Features/Analytics/Timeline` keeps chart composition separate from reusable timeline support shapes and lane entries, while other analytics sections live under `Features/Analytics/Sections`.
- `Features/Analytics/AnalyticsViews.swift` now owns only page lifecycle/composition; header, overview metrics, range dispatch, daily trend, and overlap sections live in `Features/Analytics/Sections/AnalyticsOverviewViews.swift`.
- `Stores`, `Services`, and `SharedUI` now use semantic subfolders instead of flat utility drawers; extension files such as `TimeTrackerStore+ReadModels.swift` live under `Stores/Facade`.
- `App/ContentView.swift` now keeps app shell responsibilities separate from macOS focused-scene action definitions.
- Core tests were split by subsystem so command handlers, refresh planning, ledger refresh, performance budgets, preferences, and checklist forecast rules are easier to find.

Exit criteria:

- No production Swift file should exceed roughly 350 lines unless it is a generated or intentionally table-like resource.
- The largest test files should be split by subsystem until a developer can find ledger, forecast, analytics, localization, and UI contract tests without scanning one giant file.
- `Architecture.md` ownership guidance remains accurate after moves.

### Phase 2: UI Design System And Interaction Consistency

Goal: make the app feel like one native Apple productivity app instead of several independently styled screens.

Scope:

- Keep source layout semantic before adding more UI code:
  - `Stores/Facade` owns `TimeTrackerStore` and its extension files.
  - `Stores/Domains` owns independently refreshable state stores.
  - `Stores/Refresh` owns refresh planning and coordination.
  - `Services` is split by algorithm domain instead of a flat utility drawer.
  - `SharedUI/Foundation` owns design tokens and layout policies.
  - `SharedUI/Components` owns reusable controls and rows.
- Create or finish shared components in `SharedUI`:
  - section headers
  - metric rows
  - task rows
  - checklist rows
  - inline add rows
  - empty states
  - info popovers
  - settings rows
  - compact action rows
- Prefer system controls before custom drawing:
  - `List`, `Form`, `Table`, `NavigationSplitView`, `.inspector`, `Menu`, `Picker`, native toolbar items, and system button styles.
- Establish responsive layout policies for:
  - compact iPhone
  - regular iPad landscape
  - macOS windowed mode
  - narrow macOS windows
- Normalize spacing and hierarchy:
  - one title scale per screen
  - one row height family per list
  - one metric-card style
  - one primary action style
  - one destructive action style
- Remove confusing copy and internal terms from UI. User-facing text should explain what will happen, not name implementation concepts.
- Review animation sources. Any animation that is not clearly improving comprehension should be removed or delegated to system list/form transitions.

Tests and checks:

- Add UI contract tests for key responsive decisions instead of screenshot-perfect assertions.
- Keep localization parity across English, Simplified Chinese, and Traditional Chinese.
- Add macOS UI smoke checks for settings window, inspector visibility, task editing, and timeline navigation.

Completed so far:

- Source layout now has semantic folders for store facade/domain/refresh code, service algorithms, feature controls/sections/rows, and shared UI foundation/components.
- `Docs/ProjectMap.md` now explains each source folder, common change entry points, and placement rules for new code.
- `SharedUI/Components` no longer has a catch-all component file; task visuals, forecast help, checklist controls, empty states, action labels, and timer labels live in dedicated files.
- Task status and running-state badges now live in `SharedUI/Components/StatusBadges.swift`, so Home, Tasks, and Inspector do not each draw their own status treatment.
- Task checklist and forecast progress lines now live in `SharedUI/Components/TaskProgressViews.swift`, keeping the task list row focused on row layout.
- Metric cells now live in `SharedUI/Components/MetricCards.swift`, so Today and future dashboard sections can share one responsive metric style.
- Section headers now live in `SharedUI/Components/SectionHeaders.swift`, and Home section titles, Settings form headers, `AppSection`, and Analytics chart cards share the same title/subtitle treatment.
- Full-width action labels now live in `SharedUI/Components/ActionControls.swift`, so Home and Inspector buttons share icon/text sizing and compact compression behavior.
- Running timer labels now live in `SharedUI/Components/DurationLabels.swift`, keeping TimelineView-driven clock updates out of feature row files.
- Empty-state rows now live in `SharedUI/Components/EmptyStates.swift`, so Home, Analytics, Pomodoro, Inspector, and Tasks reuse the same quiet system-style placeholder treatment.
- Checklist display rows and inline add rows now live in `SharedUI/Components/ChecklistControls.swift`, keeping checklist touch targets and add behavior consistent across inspector and future task-detail surfaces.
- Settings action labels now live in `SharedUI/Components/SettingsRows.swift`, keeping settings buttons visually consistent while preserving native `Form` and `Button` behavior.
- Checklist completion uses fixed-size SF Symbols without custom animation so row layout stays stable when items are toggled.
- `Features/Settings/SettingsViews.swift` now composes dedicated section views from `Features/Settings/SettingsSectionsViews.swift`, keeping the settings shell smaller and making individual settings groups easier to adjust.

Exit criteria:

- Home, Tasks, Pomodoro, Analytics, Settings, Sidebar, and Inspector use shared row/card/control styles where they present the same kind of information.
- iPhone layouts avoid horizontal crowding by using two-line rows where needed.
- iPad and macOS layouts keep alignment and column behavior stable while resizing.

### Phase 3: Sync Reliability And User Feedback

Goal: make iCloud-backed data feel trustworthy and understandable to ordinary users.

Scope:

- Define user-visible sync states:
  - available
  - syncing
  - recently synced
  - offline
  - needs restart for storage mode change
  - failed with recoverable message
- Add explicit feedback for settings actions:
  - force sync
  - iCloud on/off changes
  - import/export
  - database optimize
  - demo data clearing
- Keep all user-facing settings in `SyncedPreference`; local-only technical state must stay explicitly documented.
- Add conflict-handling documentation for:
  - duplicate active timers from different devices
  - checklist changes arriving while the editor is open
  - deleted task with existing ledger history
  - changed preference values across devices
- Keep command handlers idempotent where possible so Watch, Widget, Live Activity, and future App Intents can reuse the same actions.

Tests and checks:

- Unit-test preference mirroring and migration.
- Add repository/command tests for repeated start/stop/toggle commands.
- Add simulated remote-import tests that verify refresh plans stay domain-sized.
- Add manual device checklist for iPhone + iPad + Mac:
  - create task on one device and see it on another
  - start timer on one device and stop it on another
  - change Pomodoro defaults and Quick Start pinned tasks
  - add checklist and verify forecast refresh on both devices

Exit criteria:

- Sync failures produce visible, localized, non-technical user feedback.
- Force sync has a clear success or failure result.
- Remote changes do not trigger full app refresh unless the domain event requires it.

### Phase 4: Analytics Scale And Runtime Smoothness

Goal: make long histories and native animations stay smooth on real devices and on macOS.

Scope:

- Turn the current disposable day-bucket analytics cache into a documented summary-cache strategy:
  - raw `TimeSegment` remains the fact layer
  - daily/monthly/yearly summaries are rebuildable
  - summary versioning allows recalculation after analytics rule changes
- Add performance fixtures for:
  - thousands of tasks
  - tens of thousands of time segments
  - deep task trees
  - dense overlapping timers
  - long checklist histories
- Audit macOS animation and scrolling smoothness:
  - verify whether hitches come from SwiftData fetches, derived-state recomputation, view identity churn, chart layout, or custom animations
  - remove unnecessary explicit animations
  - stabilize list row identities
  - ensure active timer labels refresh only the text that changes
  - avoid recomputing analytics or rollups from SwiftUI `body`
- Prefer measured fixes over guessing:
  - use Instruments Time Profiler for CPU hitches
  - use SwiftUI body instrumentation or signposts around expensive refresh paths
  - use Core Animation / animation hitches instruments for macOS animation drops
  - compare Debug and Release because SwiftUI Debug builds exaggerate some slowness
- Keep Today and Analytics visualizations readable with long histories:
  - compact idle periods intentionally
  - keep time labels legible on iPhone
  - keep task distribution stable when tiny tasks are present
  - avoid chart work while the view is not visible

Tests and checks:

- Add performance budget tests for large ledger range summaries and summary-cache invalidation.
- Add UI automation smoke tests that exercise scrolling in Today, Tasks, and Analytics.
- Add manual profiling checklist for macOS and real iPhone/iPad.
- Run generic iOS build and macOS unit tests after summary-cache changes.

Exit criteria:

- Scrolling Today, Tasks, and Analytics on macOS does not visibly stutter with large seeded data in Release.
- Timer start/pause/stop does not refresh unrelated domains.
- Analytics Month/Year views render from cached summaries where possible.
- The app remains correct after deleting summaries and rebuilding them from raw ledger rows.

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
