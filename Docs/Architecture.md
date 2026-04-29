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

The current UI still has large feature files, especially Home, Analytics, Inspector, and Editor surfaces. New refactors should prefer small feature files under folders such as:

```text
timetracker/Home
timetracker/Tasks
timetracker/Pomodoro
timetracker/Analytics
timetracker/Settings
timetracker/Shared
```

Pure layout and formatting logic belongs in `timetracker/Shared` with unit tests.

For the longer-term architecture roadmap and feature ownership map, see `Docs/ArchitecturePlan.md`.

## Shared UI Logic

`TimelineLayoutEngine` owns Today timeline clipping, display interval, and lane allocation. Keep this logic out of SwiftUI view bodies so chart behavior can be tested without launching the app.

Task tree display should be treated as derived UI state. The durable model remains `TaskNode.parentID/path/depth/sortOrder`; the Tasks screen derives a flat list of currently visible rows from that tree so native list interactions remain reliable on iPhone.

## Feature Status

The first app version includes local SwiftData persistence, iCloud-backed user preferences, task creation/editing/status, task checklists, soft delete/archive, nested task browsing, multi-segment timers, manual time entry, pomodoro-ledger synchronization, Today timeline, local task forecasting, analytics overview, CSV export, demo data management, database optimization, iCloud configuration, and Live Activity display for running timers.

Future work should preserve the ledger contract: every timer, pomodoro, manual entry, widget action, Live Activity action, or Watch command must ultimately create or update `TimeSession` and `TimeSegment` records through shared use cases.

## Version and Build Info

Settings includes an About section with the app icon, `MARKETING_VERSION`, build number, Git branch, short commit hash, and build date. The app target writes `AppBuildInfo.plist` during the build using `scripts/write_build_info_plist.sh`; do not hard-code Git metadata in Swift source.

Version bumping is automated through `.githooks/pre-commit`. See `Docs/Versioning.md` before changing release or commit automation.
