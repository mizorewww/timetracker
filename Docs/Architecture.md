# Time Tracker Architecture

Time Tracker is a local-first SwiftUI app whose source of truth is the time ledger, not a screen-level timer flag.

## Layers

The app follows this flow:

```text
SwiftUI View
  -> TimeTrackerStore / focused view state
  -> UseCase
  -> Repository protocol
  -> SwiftData repository
  -> SwiftData model
```

Views may format and present state, but durable business actions should go through the store and use cases. This keeps iOS, macOS, widgets, Live Activities, and future Watch commands from duplicating timer logic.

## Domain Model

`TaskNode` represents a task tree node. All tasks can contain child tasks and all tasks can be timed. The `parentID`, `path`, `depth`, and `sortOrder` fields make the tree stable for drag/move, sync, and export. Moving a task must prevent cycles and update descendants.

`TimeSession` represents one work intention. `TimeSegment` represents actual worked time and is the ledger fact used for analytics. A paused and resumed session should have multiple segments under the same session.

`PomodoroRun` represents the pomodoro workflow. It must create and update ledger records instead of replacing them.

`CountdownEvent` stores optional user-defined date milestones shown on Today.

`SyncedPreference` stores user-facing settings as JSON values in SwiftData so preferences travel through the same iCloud-backed store as tasks and timers. The only preference mirrored into `UserDefaults` is the iCloud enablement flag, because the model container must know whether to start in CloudKit mode before SwiftData can fetch cloud values.

`ChecklistItem` belongs to a `TaskNode`, but it is not a task. Checklist items are for progress and estimation only; timers, manual entries, pomodoros, widgets, and Live Activities still attach time to the task itself.

## Forecasting and Analytics

Forecasting is local and explainable. `TaskRollupService` recursively combines direct task time, checklist progress, and direct child-task rollups. It does not create forecasts from manual estimates or history alone. `ForecastDisplayService` decides whether Home, Analytics, and Inspector should show the selected task, drill into one forecastable child task, or show a parent summary. `AnalyticsEngine` owns pure date/range aggregation for overview metrics, hourly activity, and daily/monthly chart points.

Checklist estimates are equal-weight:

```text
if checklistTotal == 0:
  forecastState = needsChecklist
else if completedChecklistCount == 0:
  forecastState = needsCompletedItem
else if ownWorkedSeconds == 0:
  forecastState = needsTrackedTime
else:
  averagePerItem = ownWorkedSeconds / completedChecklistCount
  ownRemaining = averagePerItem * unfinishedChecklistCount

rollupWorked = direct task time + recursive child rollupWorked
rollupRemaining = ownRemaining + recursive child forecast remaining
```

If a task is completed, or all of its checklist items are completed, its own remaining time is always zero. Historical time is only used to convert remaining hours into projected days for the same task branch. If there is not enough checklist progress or tracked time, the forecast reports the missing requirement instead of inventing a number.

Parent display rules:

```text
Parent has its own checklist:
  show the parent forecast and include forecastable children recursively

Parent has no checklist and exactly one forecastable child branch:
  show that child task directly

Parent has no checklist and multiple forecastable child branches:
  show a parent summary labeled as an aggregate

No checklist-backed branch exists:
  do not show a forecast card; show guidance in task detail
```

## Deletion Rules

Tasks are soft-deleted by default. Historical ledger rows stay visible because time already happened. The settings action "Optimize Database" only removes ledger rows whose task reference is truly missing from the database; it must not purge history merely because the task itself was soft-deleted.

## Sync Assumptions

iCloud sync is controlled by `AppCloudSync` and the SwiftData model container configuration. User preferences sync through `SyncedPreference`; technical state such as device identity, migration flags, build info, and CloudKit error text stays local. The app refreshes on launch, foreground, remote import notifications, and periodic foreground polling. Start/stop actions remain idempotent at the repository/use-case level where possible.

## UI Structure

The app source is organized by ownership. New files should land next to the domain they affect:

```text
timetracker/App
timetracker/Models
timetracker/Repositories
timetracker/Commands
timetracker/Stores
  Domains/        Published state owners for tasks, ledger, rollups, analytics, preferences
  Facade/         TimeTrackerStore shell and UI-facing extension methods
  Refresh/        Refresh planning and coordination
timetracker/Services
  Analytics/      Aggregation, summary cache, and timeline layout algorithms
  Forecasting/    Checklist forecast and rollup display rules
  Ledger/         Duration and time aggregation utilities
  Maintenance/    Database repair, export, and cleanup support
  Tasks/          Task tree derivation and validation helpers
timetracker/Features/Home
  Controls/       Start/new-task controls and task selection sheets
  Rows/           Active timer, paused session, and timeline rows
  Sections/       Metrics, forecast, progress, quick start, and timeline sections
timetracker/Features/Tasks
  Editor/         Task editor, symbol picker, checklist editing, and editor-specific controls
  Management/     Task browsing screen and reusable task rows
timetracker/Features/Pomodoro
  Sections/       Setup, active-run, and recent-ledger sections
timetracker/Features/Analytics
  Sections/       Overview, forecast, distribution, and activity sections
  Timeline/       Timeline chart composition and support views
timetracker/Features/Settings
  Support/        Export documents and settings support rows
timetracker/Features/Sidebar
timetracker/Features/Inspector
  Sections/       Inspector info, checklist, forecast, panels, and actions
timetracker/Features/Ledger
timetracker/Shared
timetracker/SharedUI
  Foundation/     Design tokens and responsive layout policies
  Components/     Reusable native-styled controls, badges, rows, and cards
```

Within `Features/Home`, keep the Today screen split by responsibility: `HomeViews.swift` composes the page, `Controls/HomeActionsViews.swift` owns start/new-task controls and the compact task picker, `Sections/HomeMetricsViews.swift` renders the compact time summary, `Sections/HomeProgressViews.swift` owns calendar/countdown progress tiles, and forecast, quick start, timeline, and row files own their own sections. Within `Features/Settings`, keep the settings form separate from support rows and export document types.

Pure layout, formatting, and derivation logic belongs in `Services`, `Shared`, or `SharedUI` with unit tests. SwiftUI feature files should render state and collect input; durable writes go through store facade methods and command handlers.

Avoid root-level "miscellaneous" folders that collect unrelated files. If a file name needs a `+` extension suffix, it should usually live under the owning facade or feature directory instead of being left beside unrelated domain stores. If a directory grows beyond one ownership concept, split it by domain before adding more files.

For the longer-term architecture roadmap and feature ownership map, see `Docs/ArchitecturePlan.md`.

Xcode shared schemes are source-controlled under `timetracker.xcodeproj/xcshareddata/xcschemes`. Do not rely on per-user scheme state for app builds; command-line builds and install scripts must be able to use `-scheme timetracker` from a clean checkout.

## Shared UI Logic

`TimelineLayoutEngine` owns Today timeline clipping, display interval, and lane allocation. Keep this logic out of SwiftUI view bodies so chart behavior can be tested without launching the app.

Task tree display should be treated as derived UI state. The durable model remains `TaskNode.parentID/path/depth/sortOrder`; the Tasks screen derives a flat list of currently visible rows from that tree so native list interactions remain reliable on iPhone.

## Feature Status

The first app version includes local SwiftData persistence, iCloud-backed user preferences, task creation/editing/status, task checklists, soft delete/archive, nested task browsing, multi-segment timers, manual time entry, pomodoro-ledger synchronization, Today timeline, local task forecasting, analytics overview, CSV export, demo data management, database optimization, iCloud configuration, and Live Activity display for running timers.

Future work should preserve the ledger contract: every timer, pomodoro, manual entry, widget action, Live Activity action, or Watch command must ultimately create or update `TimeSession` and `TimeSegment` records through shared use cases.

## Version and Build Info

Settings includes an About section with the app icon, `MARKETING_VERSION`, build number, Git branch, short commit hash, and build date. The app target writes `AppBuildInfo.plist` during the build using `scripts/write_build_info_plist.sh`; do not hard-code Git metadata in Swift source.

Version bumping is automated through `.githooks/pre-commit`. See `Docs/Versioning.md` before changing release or commit automation.
