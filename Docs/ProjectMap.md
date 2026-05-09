# Project Map

This document is the first stop for a developer who has not worked in this repository before. It explains where code lives, which file to open first, and which boundary should own a change.

## How To Read The App

Time Tracker is organized by feature ownership and data flow:

```text
SwiftUI Feature
  -> TimeTrackerStore facade
  -> Domain command handler
  -> SwiftData repository
  -> SwiftData model
  -> Domain store snapshot
  -> Pure services derive secondary state
```

The most important rule is still: `TimeSegment` is the ledger fact. UI state, forecasts, charts, and summaries are derived from persisted task, checklist, session, segment, pomodoro, countdown, and preference models.

## Source Folders

| Path | Owns | Open this when | Do not put here |
| --- | --- | --- | --- |
| `timetracker/App` | App entry, root navigation, scenes, CloudKit/container startup, build info, seed/demo data, deep links, Live Activity launch helpers | Changing app startup, platform root views, scene layout, menu commands, build metadata, deep link routing, or demo seeding | Screen-specific UI sections or domain algorithms |
| `timetracker/AppIntents` | Siri/Shortcuts App Intents and task entities that wrap shared command handlers | Adding or changing system actions such as capture Inbox item, start timer, or stop timer | Ledger writes, SwiftUI state, or duplicated timer logic |
| `timetrackerWidgetExtension` | WidgetKit extension UI and timeline provider for glanceable active-timer state | Changing the widget face, widget localization, or widget target plist/entitlements | SwiftData writes, command logic, or app-only models |
| `timetrackerWatchApp` | watchOS companion UI for active timers, recent tasks, and queued start/stop commands | Changing the watch face, watch localization, or WatchConnectivity presentation state | SwiftData writes, full task-tree management, or duplicated timer logic |
| `timetracker/Models` | SwiftData models, schema versions, migration plan, registry, and store/view DTOs | Adding persisted fields, migrations, or shared read models | Query code, SwiftUI layout, or business workflows |
| `timetracker/Repositories` | SwiftData query/write implementations behind repository protocols | Changing fetch predicates, persistence semantics, soft delete, or ledger writes | UI decisions or derived analytics formulas |
| `timetracker/Commands` | User action handlers and use cases | Adding a durable action such as start timer, toggle checklist, move task, export, or update preference | SwiftUI state formatting or long-lived published state |
| `timetracker/Stores/Facade` | `TimeTrackerStore` and UI-facing facade extensions | Wiring a view action to a command handler, exposing read models, or coordinating app lifecycle | Domain-sized refresh internals or pure algorithms |
| `timetracker/Stores/Domains` | Published task, ledger, checklist, rollup, analytics, and preference snapshots | Changing what state a feature observes after repository data changes | Button handlers, SwiftData writes, or view-specific layout |
| `timetracker/Stores/Refresh` | Refresh event planning and domain refresh coordination | Adding a new write event or deciding which snapshots should update | Feature UI or direct repository mutation |
| `timetracker/Services/Analytics` | Analytics aggregation, timeline layout, daily bucket cache | Changing charts, overlap math, daily/monthly summaries, or timeline lane allocation | SwiftUI chart styling that does not affect data |
| `timetracker/Services/Checklist` | Checklist draft persistence and checklist-specific editing helpers | Changing how checklist editor drafts are saved, soft-deleted, or visual metadata is preserved | Forecast formulas or task row layout |
| `timetracker/Services/Inbox` | Inbox suggestion state and Inbox-specific derivation helpers | Changing when suggestions are shown, hidden, dismissed, stale, or eligible for regeneration | LLM networking or SwiftUI row layout |
| `timetracker/Services/Forecasting` | Checklist rollups, forecast eligibility, forecast display selection | Changing remaining-time formulas, parent/child forecast display, or forecast explanations | Checklist editing UI |
| `timetracker/Services/Ledger` | Duration formatting, summary, and gross/wall-clock aggregation utilities | Changing time math used across features | SwiftData fetches or view layout |
| `timetracker/Services/Maintenance` | CSV export, database repair, cleanup support | Changing export columns or optimization safety | Normal timer/task write flows |
| `timetracker/Services/SystemIntegration` | App Group/cache DTOs, Watch command processors, WatchConnectivity payload/transport, and system-surface snapshots | Changing Widget-visible active timer or recent-task snapshots, Watch command idempotency, Watch app handoff data, or extension handoff data | Extension UI or durable ledger writes |
| `timetracker/Services/Tasks` | Task tree validation, paths, descendants, flat visible rows | Changing task nesting, legal parent choices, or sidebar/tasks row derivation | Persistent task writes |
| `timetracker/Features/Home` | Today screen composition | Changing Today metrics, active timers, quick start, progress tiles, forecast, or timeline presentation | Cross-screen components that should be reused |
| `timetracker/Features/Tasks` | Task management and task editing | Changing task list rows, editor fields, checklist editing, icon/color picking, or parent selection UI | Time ledger algorithms |
| `timetracker/Features/Analytics` | Analytics screen composition | Changing analytics tabs, chart sections, forecast list presentation, or timeline chart UI | Analytics math that can be unit tested in services |
| `timetracker/Features/Pomodoro` | Pomodoro setup, active run, recent ledger UI | Changing pomodoro screen layout or controls | Pomodoro ledger writes; use commands/repositories |
| `timetracker/Features/Settings` | Settings form and support rows | Changing user preferences, export UI, sync controls, maintenance UI, or About display | Preference persistence codecs or CloudKit startup |
| `timetracker/Features/Sidebar` | App navigation sidebar | Changing navigation row presentation, sidebar task tree display, or split-view navigation behavior | Task tree algorithms |
| `timetracker/Features/Inspector` | Right-side task detail inspector | Changing selected-task details, checklist panel, forecast panel, action buttons, or stats | Task edit sheet internals |
| `timetracker/Features/Ledger` | Manual time entry and segment editing UI | Changing manual entry sheets or ledger row editor UI | Ledger query semantics |
| `timetracker/Shared` | Extension-safe shared helpers and app strings | Changing localization access or non-UI helpers shared by app/extension | Feature-specific components |
| `timetracker/SharedUI/Foundation` | Design tokens, colors, layout policies, responsive breakpoints | Changing spacing, card metrics, platform breakpoints, or shared visual constants | Feature-specific row contents |
| `timetracker/SharedUI/Components` | Reusable native-styled controls, badges, rows, metric cards, info popovers | Reusing a control in two or more features | One-off feature layout that has no second caller |

## Common Change Entry Points

| Task | Start here | Then check |
| --- | --- | --- |
| Start/pause/resume/stop timer behavior | `Commands/TimerCommands.swift` | `Repositories/SwiftDataTimeTrackingRepository+Mutations.swift`, `Repositories/SwiftDataTimeTrackingRepository+Queries.swift`, `Stores/Domains/LedgerStore.swift`, `Services/Ledger/TimeTrackerServices.swift` |
| Manual time entry or segment edit | `Commands/LedgerCommands.swift` | `Features/Ledger`, `Stores/Domains/LedgerStore.swift`, analytics invalidation tests |
| Task create/edit/move/delete | `Commands/TaskCommands.swift` | `Services/Tasks/TaskTreeServices.swift`, `Repositories/SwiftDataTaskRepository+TaskMutations.swift`, `Repositories/SwiftDataTaskRepository+Hierarchy.swift`, `Features/Tasks` |
| Task categories | `Stores/Facade/TimeTrackerStore+TaskCategoryCommands.swift` | `Models/TaskModels.swift`, `Repositories/SwiftDataTaskRepository+Categories.swift`, `Features/Tasks`, `Features/Sidebar` |
| Checklist UI or persistence | `Commands/ChecklistCommands.swift` | `Stores/Domains/ChecklistStore.swift`, `Features/Tasks/Editor`, `Features/Inspector/Sections/InspectorChecklistViews.swift`, `Services/Checklist/ChecklistDraftService.swift`, `Services/Forecasting/TaskRollupService.swift` |
| Forecast math | `Services/Forecasting/TaskRollupService.swift` | `Services/Forecasting/TaskRollupCalculationContext.swift`, `Services/Forecasting/ForecastDisplayService.swift`, Home/Analytics/Inspector forecast sections |
| Analytics chart data | `Stores/Domains/AnalyticsStore.swift` | `Stores/Domains/AnalyticsStore+SnapshotBuilding.swift`, `Services/Analytics/AnalyticsEngine.swift`, `Services/Analytics/LedgerBucketCache.swift`, `Features/Analytics` |
| Today layout | `Features/Home/HomeViews.swift` | `Features/Home/Sections`, `Features/Home/Rows`, `SharedUI/Foundation/LayoutPolicies.swift` |
| Task row layout | `Features/Tasks/Management/TaskManagementRowViews.swift` | `SharedUI/Components/TaskVisuals.swift`, task UI contract tests |
| Settings | `Features/Settings/SettingsViews.swift` | `Features/Settings/SettingsSectionsViews.swift`, `Features/Settings/SettingsDataSectionsViews.swift`, `Features/Settings/SettingsViewBindings.swift`, `Features/Settings/SettingsViewActions.swift`, `Features/Settings/Support`, `Commands/PreferenceCommands.swift` |
| iCloud/user settings sync | `Commands/PreferenceCommands.swift` | `Models/SyncedPreferences.swift`, `Stores/Domains/PreferenceStore.swift`, `App/AppModelContainerFactory.swift` |
| Demo data seeding or clearing | `App/SeedData.swift` | `App/SeedData+DemoBuild.swift`, `App/SeedData+Cleanup.swift`, lifecycle tests |
| AI model configuration | `Features/Settings/SettingsDataSectionsViews.swift` | `Services/LLM/LLMModelService.swift`, `Models/SyncedPreferences.swift`, `Stores/Facade/TimeTrackerStore+PreferenceCommands.swift` |
| Siri/Shortcuts App Intents | `AppIntents/TimeTrackerAppIntents.swift` | `Commands/SystemActionCommands.swift`, relevant command handlers, localization |
| Deep links from Widget or system surfaces | `App/AppDeepLinkRouter.swift` | `Stores/Facade/TimeTrackerStore+DeepLinks.swift`, `App/ContentView.swift`, `timetracker/Info.plist` |
| Widget active timer/recent task snapshot | `Services/SystemIntegration/WidgetSnapshotCache.swift` | `Stores/Facade/TimeTrackerStore+WidgetSnapshot.swift`, `timetrackerWidgetExtension` |
| Widget extension UI | `timetrackerWidgetExtension/TimeTrackerWidget.swift` | `Shared/WidgetSnapshotModels.swift`, widget localization files, WidgetKit target settings |
| Watch timer command handoff | `Services/SystemIntegration/WatchCommandProcessor.swift` | `Stores/Facade/TimeTrackerStore+WatchSnapshot.swift`, `Shared/WatchCommandModels.swift`, `Shared/WatchStateSnapshotModels.swift`, `Services/SystemIntegration/WatchConnectivityPayloadCodec.swift`, `Services/SystemIntegration/WatchConnectivityBridge.swift`, `Commands/SystemActionCommands.swift`, `Commands/TimerCommands.swift` |
| Watch app UI | `timetrackerWatchApp/WatchDashboardView.swift` | `timetrackerWatchApp/WatchAppStore.swift`, `Shared/WatchCommandModels.swift`, `Shared/WatchStateSnapshotModels.swift`, watch localization files |
| Live Activity display/stop deep link | `timetrackerLiveActivityExtension` | `Shared/TimeTrackingActivityAttributes.swift`, `App/AppDeepLinkRouter.swift`, app Live Activity helpers |
| Localization | `Shared/AppStrings.swift` | `*.lproj/Localizable.strings`, localization parity tests |

## Placement Rules

1. Put durable write behavior in `Commands`, not in SwiftUI button closures.
2. Put SwiftData fetch/write implementation in `Repositories`, not in feature views.
3. Put testable calculations in `Services`, not in `body`.
4. Put screen-specific composition in `Features/<Feature>`.
5. Put shared styling and controls in `SharedUI` only when at least two features use or are about to use them.
6. Keep `TimeTrackerStore` as a facade. If a method grows domain logic, move that logic into a command handler, domain store, or service.
7. If a directory starts collecting unrelated files, split it before adding more.
8. After moving files, run the scheme visibility check, macOS tests, and generic iOS build from `Docs/Testing.md`.
9. For schema changes, prefer additive extension models over changing core ledger/task models. Update `Docs/ArchitecturePlan.md` schema rules and add migration/compatibility tests before UI work.

## Naming Rules

- `*Commands.swift`: durable write actions and use-case-style command handlers.
- `*Store.swift`: published snapshots and refresh logic for one domain.
- `*Service.swift`: pure calculations or maintenance helpers that can be unit tested without SwiftUI.
- `*Views.swift`: SwiftUI composition for one feature or one section group.
- `*RowViews.swift`: reusable rows inside one feature.
- `*SupportViews.swift`: small support controls that are not the feature's main screen.
- `TimeTrackerStore+*.swift`: facade extensions only; these live in `Stores/Facade`.

## Before Adding A Feature

1. Add expected behavior to `Docs/Architecture.md`, `Docs/ArchitecturePlan.md`, this map, or a focused feature document.
2. Add or update tests for the service, command, store, or UI contract boundary.
3. Implement the smallest domain owner first.
4. Wire SwiftUI last.
5. Run the baseline checks listed in `Docs/Testing.md`.

## Planning Documents

Use these before starting larger work:

| Document | Purpose |
| --- | --- |
| `Docs/NextDevelopmentPlan.md` | Product backlog and feature acceptance criteria for the next development cycles. |
| `Docs/CodeRefactorPlan.md` | Code review findings and architecture refactor order. |
| `Docs/NativeUIPlan.md` | Native-first UI rules, screen-by-screen UI cleanup plan, and screenshot checklist. |
