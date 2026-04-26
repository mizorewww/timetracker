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

## Deletion Rules

Tasks are soft-deleted by default. Historical ledger rows stay visible because time already happened. The settings action "Optimize Database" permanently removes orphaned ledger rows whose task has been deleted and is no longer visible.

## Sync Assumptions

iCloud sync is controlled by `AppCloudSync` and the SwiftData model container configuration. The app refreshes on launch, foreground, remote import notifications, and periodic foreground polling. Start/stop actions remain idempotent at the repository/use-case level where possible.

## UI Structure

The current UI still has a large `ContentView.swift` file. New refactors should prefer small feature files under folders such as:

```text
timetracker/Home
timetracker/Tasks
timetracker/Pomodoro
timetracker/Analytics
timetracker/Settings
timetracker/Shared
```

Pure layout and formatting logic belongs in `timetracker/Shared` with unit tests.

## Shared UI Logic

`TimelineLayoutEngine` owns Today timeline clipping, display interval, and lane allocation. Keep this logic out of SwiftUI view bodies so chart behavior can be tested without launching the app.

Task tree display should be treated as derived UI state. The durable model remains `TaskNode.parentID/path/depth/sortOrder`; the Tasks screen derives a flat list of currently visible rows from that tree so native list interactions remain reliable on iPhone.

## Feature Status

The first app version includes local SwiftData persistence, task creation/editing/status, soft delete/archive, nested task browsing, multi-segment timers, manual time entry, pomodoro-ledger synchronization, Today timeline, analytics overview, CSV export, demo data management, database optimization, iCloud configuration, and Live Activity display for running timers.

Future work should preserve the ledger contract: every timer, pomodoro, manual entry, widget action, Live Activity action, or Watch command must ultimately create or update `TimeSession` and `TimeSegment` records through shared use cases.
