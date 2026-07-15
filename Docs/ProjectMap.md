# Project Map

Status: current source map

Reviewed: 2026-07-15

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

`TimeTrackerStore` is `@MainActor @Observable`; app roots own it with `@State`, feature views keep a plain injected reference, and binding sites use local `@Bindable`. macOS has one main `Window`; its Settings scene receives the same application store. CloudKit refresh enters through notification observers and the refresh planner rather than a foreground polling timer.

## Source Folders

| Path | Owns | Open this when | Do not put here |
| --- | --- | --- | --- |
| `timetracker/App` | App entry, root navigation, scenes, CloudKit/container startup, build info, seed/demo data, strict/bounded deep links, weak multi-scene Watch routing, and Live Activity launch helpers | Changing app startup, platform root views, scene layout, menu commands, build metadata, deep link/Watch scene routing, or demo seeding | Screen-specific UI sections or domain algorithms |
| `timetracker/AppIntents` | Siri/Shortcuts App Intents and task entities that wrap shared command handlers | Adding or changing system actions such as capture Inbox item, start timer, or stop timer | Ledger writes, SwiftUI state, or duplicated timer logic |
| `SharedLiveActivity` | App 与扩展共用的 Activity attributes | Changing the versioned task identity or Activity content state contract | Extension layout or ledger writes |
| `timetrackerLiveActivityExtension` | ActivityKit/Dynamic Island UI | Changing Live Activity layout, privacy, stale state, localization, or stop/open links | Durable timer facts or duplicated commands |
| `timetrackerWidgetExtension` | WidgetKit entry/provider/config, active-timer layouts, supplementary/error states, and deep-link/localization/color support | Changing the widget face, widget localization, or widget target plist/entitlements | SwiftData writes, command logic, or app-only models |
| `timetrackerWatchApp` | watchOS dashboard/timer/status UI plus one durable queue/connectivity store for active timers, recent tasks, and start/stop commands | Changing the watch face, watch localization, or WatchConnectivity presentation state | SwiftData writes, full task-tree management, or duplicated timer logic |
| `timetracker/Models` | SwiftData models, V1...V9 schema history, migration plan, registry, shared read models, and `TaskEstimatePolicy` | Adding persisted fields, migrations, shared read models, or estimate normalization | Query code, SwiftUI layout, or business workflows |
| `timetracker/Repositories` | SwiftData query/write implementations behind repository protocols | Changing fetch predicates, persistence semantics, soft delete, or ledger writes | UI decisions or derived analytics formulas |
| `timetracker/Repositories/ModelContext+AtomicMutation.swift` | Store/system action transaction boundary, nested save deferral, rollback | Adding a multi-step durable user action | Read-model refresh or post-commit projection |
| `timetracker/Commands` | User action handlers and use cases | Adding a durable action such as start timer, toggle checklist, move task, or update preference | SwiftUI state formatting or long-lived observable state |
| `timetracker/Stores/Facade` | `TimeTrackerStore`, first configuration, refresh/mutation lifecycle, and UI-facing facade extensions | Wiring a view action to a command handler, exposing read models, attaching repositories for a committed system action, or coordinating app lifecycle | Domain-sized refresh internals or pure algorithms |
| `timetracker/Stores/Domains` | Task, indexed ledger/session, task-scoped checklist, incremental rollup/90-day pace, analytics cache, and preference snapshots | Changing what state a feature observes after repository data changes | Button handlers, SwiftData writes, or view-specific layout |
| `timetracker/Stores/Navigation` | Shared selection and destination coordination | Changing selection invalidation or cross-platform navigation state | Feature layout or persistence writes |
| `timetracker/Stores/Refresh` | Refresh event planning and domain refresh coordination | Adding a new write event or deciding which snapshots should update | Feature UI or direct repository mutation |
| `timetracker/Services/Analytics` | Analytics aggregation, timeline layout, daily bucket cache | Changing charts, overlap math, daily/monthly summaries, or timeline lane allocation | SwiftUI chart styling that does not affect data |
| `timetracker/Services/Checklist` | Checklist draft persistence and checklist-specific editing helpers | Changing how checklist editor drafts are saved, soft-deleted, or visual metadata is preserved | Forecast formulas or task row layout |
| `timetracker/Services/Inbox` | Inbox suggestion state and Inbox-specific derivation helpers | Changing when suggestions are shown, hidden, dismissed, stale, or eligible for regeneration | LLM networking or SwiftUI row layout |
| `timetracker/Services/Forecasting` | Explicit-estimate/checklist fallback, recursive rollups, forecast eligibility, and display selection | Changing remaining-time formulas, parent/child forecast display, or forecast explanations | Checklist editing UI |
| `timetracker/Services/Instrumentation` | Performance signpost names and measured intervals | Adding an Instruments-visible boundary around domain refresh or calculation work | Product analytics, user data logging, or business rules |
| `timetracker/Services/LLM` | OpenAI-compatible endpoint validation, credential-safe transport, response decoding, and suggestion services | Changing model discovery, redirect policy, concurrency/backoff, or suggestion prompt/decoding | Keychain persistence or SwiftUI presentation state |
| `timetracker/Services/Ledger` | Device-local CloudKit startup mode, persistence-write diagnostics, timer command DTOs, duration formatting, summary, and gross/wall-clock aggregation | Changing device-local sync startup, transaction save diagnostics, or shared time math | SwiftData fetches or view layout |
| `timetracker/Services/Maintenance` | Database repair and cleanup support | Changing optimization or repair safety | Normal timer/task write flows or export presentation |
| `timetracker/Services/SystemIntegration` | Sync-conflict orchestration/state/export, versioned data snapshots and per-domain records, credentials, App Group/cache DTOs, Watch command processing, and WatchConnectivity payload/transport | Changing conflict recovery, export/snapshot mappings, Widget-visible state, Watch command idempotency, or extension handoff data | Extension UI or durable ledger writes |
| `timetracker/Services/Tasks` | Task tree validation, canonical metadata repair, title paths, descendants, visible-vs-trackable eligibility, and flat visible rows | Changing task nesting, completed/archived availability, orphan/cycle repair, legal parent choices, or sidebar/tasks row derivation | Persistent task writes |
| `timetracker/Features/Home` | Today screen composition | Changing Today summary, active timers, quick start, forecast, timeline, or countdown presentation | Cross-screen components that should be reused |
| `timetracker/Features/Inbox` | Inbox capture, open/completed rows, suggestion feedback, and suggestion draft UI | Changing capture/list presentation, row actions, or suggestion review flows | Inbox persistence, LLM networking, or task-conversion rules |
| `timetracker/Features/Tasks` | Task browsing, read-first detail and task editing | Changing task list rows, detail evidence, editor fields, checklist editing, icon/color picking, or parent selection UI | Time ledger algorithms |
| `timetracker/Features/Analytics` | Analytics screen composition | Changing analytics tabs, chart sections, forecast list presentation, or timeline chart UI | Analytics math that can be unit tested in services |
| `timetracker/Features/Pomodoro` | Pomodoro setup, active run, recent ledger UI | Changing pomodoro screen layout or controls | Pomodoro ledger writes; use commands/repositories |
| `timetracker/Features/Settings` | Settings form and support rows | Changing user preferences, export UI, sync controls, maintenance UI, or About display | Preference persistence codecs or CloudKit startup |
| `timetracker/Features/Sidebar` | App navigation sidebar | Changing navigation row presentation, sidebar task tree display, or split-view navigation behavior | Task tree algorithms |
| `timetracker/Features/Ledger` | Manual time entry and segment editing UI | Changing manual entry sheets or ledger row editor UI | Ledger query semantics |
| `timetracker/Shared` | Extension-safe shared helpers and app strings | Changing localization access or non-UI helpers shared by app/extension | Feature-specific components |
| `timetracker/SharedUI/Foundation` | Design tokens, colors, layout policies, responsive breakpoints | Changing spacing, card metrics, platform breakpoints, or shared visual constants | Feature-specific row contents |
| `timetracker/SharedUI/Components` | Reusable native-styled controls, badges, rows, metric cards, info popovers | Reusing a control in two or more features | One-off feature layout that has no second caller |

## Common Change Entry Points

| Task | Start here | Then check |
| --- | --- | --- |
| Start/stop timer behavior | `Commands/TimerCommands.swift` | `Repositories/SwiftDataTimeTrackingRepository+Mutations.swift`, `Repositories/SwiftDataTimeTrackingRepository+Queries.swift`, `Stores/Domains/LedgerStore.swift`, `Services/Ledger/TimerCommand.swift`, `Services/Ledger/TimeAggregationService.swift`, `Services/Ledger/TimeFormatters.swift` |
| Manual time entry or segment edit | `Commands/LedgerCommands.swift` | `Features/Ledger`, `Stores/Domains/LedgerStore.swift`, `Stores/Domains/LedgerStore+SegmentIndex.swift`, Pomodoro invariants, analytics invalidation tests |
| Task create/edit/move/complete/reopen/archive/delete | `Commands/TaskCommands.swift` | `Services/Tasks/TaskTrackingAvailabilityService.swift`, `Services/Tasks/TaskTreeServices.swift`, `Services/Tasks/TaskHierarchyMetadataService.swift`, `Stores/Facade/TimeTrackerStore+TaskCommands.swift`, repository hierarchy/mutation files, `Features/Tasks` |
| Task categories | `Stores/Facade/TimeTrackerStore+TaskCategoryCommands.swift` | `Models/TaskModels.swift`, `Repositories/SwiftDataTaskRepository+Categories.swift`, `Features/Tasks`, `Features/Sidebar` |
| Checklist UI or persistence | `Commands/ChecklistCommands.swift` | `Stores/Domains/ChecklistStore.swift`, `Features/Tasks/Editor`, `Features/Tasks/Detail/TaskDetailChecklistViews.swift`, `Services/Checklist/ChecklistDraftService.swift`, `Services/Forecasting/TaskRollupService.swift` |
| Forecast math / incremental rollup | `Models/TaskEstimatePolicy.swift`, `Services/Forecasting/TaskRollupService.swift` | forecast helper/resolution files, `Stores/Domains/RollupIncrementalIndex.swift`, pace/activity extensions, `Services/Forecasting/TaskRollupCalculationContext.swift`, `Services/Forecasting/ForecastDisplayService.swift` |
| SwiftData schema migration | `Models/SchemaModels.swift`, `Models/SchemaMigrationPlan.swift` | `Models/TimeTrackerModelRegistry.swift`, legacy model declarations, `timetrackerTests/Support/SchemaCompatibilityFixtures.swift`, lifecycle migration tests |
| Analytics chart data and cache | `Stores/Domains/AnalyticsStore.swift` | `Stores/Facade/TimeTrackerStore+Analytics.swift`, `Stores/Domains/AnalyticsStore+SnapshotBuilding.swift`, `Stores/Domains/AnalyticsStore+TaskSnapshot.swift`, metrics/breakdown/overlap extensions, `Services/Analytics/AnalyticsEngine.swift`, `Services/Analytics/LedgerBucketCache.swift`, `Features/Analytics` |
| Pomodoro setup UI | `Features/Pomodoro/Sections/PomodoroSetupViews.swift` | `PomodoroSetupEmptyState.swift`, `PomodoroFocusSetupControls.swift`, `PomodoroSetupSelectionViews.swift`, `PomodoroTimerFace.swift`, active-run and ledger sections, Pomodoro UI/source-layout contracts |
| Today layout | `Features/Home/HomeViews.swift` | `Features/Home/Sections`, `Features/Home/Rows`, `SharedUI/Foundation/LayoutPolicies.swift` |
| Inbox capture and review UI | `Features/Inbox/InboxViews.swift` | `Commands/InboxCommands.swift`, Inbox store/facade files, suggestion commands/services, `Features/Inbox/InboxListView.swift`, row/editor files |
| Task row layout | `Features/Tasks/Management/TaskManagementRowViews.swift` | `SharedUI/Components/TaskVisuals.swift`, task UI contract tests |
| Read-first task detail | `Features/Tasks/Detail/TaskDetailView.swift` | `Features/Tasks/Detail/TaskDetailIdentityViews.swift`, `Features/Tasks/Detail/TaskDetailChecklistViews.swift`, `Features/Tasks/Detail/TaskDetailOverviewViews.swift`, `Features/Tasks/Detail/TaskDetailAnalyticsViews.swift`, `Features/Tasks/Detail/TaskDetailRecordViews.swift`, `Stores/Facade/TimeTrackerStore+TaskReadModels.swift`, `Features/Tasks/Editor` |
| Settings | `Features/Settings/SettingsViews.swift` | display/timing, Pomodoro, picker, countdown, sync, data, `LLMSettingsViews.swift`, bindings/actions/support, `Commands/PreferenceCommands.swift` |
| iCloud/user settings sync | `Commands/PreferenceCommands.swift` | `Models/SyncedPreferences.swift`, `Stores/Domains/PreferenceStore.swift`, `Stores/Facade/TimeTrackerStore+SyncObservers.swift`, `Services/SystemIntegration/SyncConflictService.swift`, local/cloud/recovery/resolution extensions, `SyncConflictService+StateLock.swift` (file lock), `SyncConflictService+State.swift` (persistence/file protection), `SyncConflictState.swift` (epoch/generation/checkpoints), snapshot capture/domain restore/record families, `App/AppModelContainerFactory.swift`; iCloud enablement itself is device-local startup state |
| Demo data seeding or clearing | `App/AppDemoDataConfiguration.swift` | `App/AppModelContainerFactory.swift`, `App/SeedData.swift`, demo build/cleanup files, lifecycle tests; Debug/Release default off and demo store is separate |
| AI model configuration | `Features/Settings/LLMSettingsViews.swift` | `Services/LLM/LLMModelService.swift`, `Services/SystemIntegration/LLMCredentialStore.swift`, `Models/SyncedPreferences.swift`, `Stores/Facade/TimeTrackerStore+PreferenceCommands.swift` |
| AI Inbox/checklist suggestions | `Services/LLM/LLMInboxSuggestionService.swift` and `Services/LLM/LLMChecklistVisualSuggestionService.swift` | Inbox/checklist facade suggestion files, `Services/Inbox/InboxSuggestionStateService.swift`, request concurrency/backoff tests, privacy documentation |
| Performance signposts and profiling | `Services/Instrumentation/PerformanceSignpost.swift` | `CorePerformanceBudgetTests`, `Docs/Testing.md`, frozen-source trace evidence in the dated Audit |
| JSON export | `Stores/Facade/TimeTrackerStore+MaintenanceCommands.swift` | `Features/Settings/Support/SettingsExportDocument.swift`, sensitive-key filtering tests |
| Siri/Shortcuts App Intents | `AppIntents/TimeTrackerAppIntents.swift` | `Commands/SystemActionCommands.swift` including post-commit snapshot/surface synchronizers, relevant command handlers, localization/discovery tests |
| Deep links from Widget or system surfaces | `App/AppDeepLinkRouter.swift` (`PendingDeepLinkQueue` included) | `Stores/Facade/TimeTrackerStore+DeepLinks.swift`, `App/ContentView.swift`, Widget/Live Activity link builders, `timetracker/Info.plist`, routing tests |
| App/store startup or closed-app post-commit projection | `Stores/Facade/TimeTrackerStore+Configuration.swift` | `Stores/Facade/TimeTrackerStore+Lifecycle.swift`, `Commands/SystemActionCommands.swift`, App container factory, sync observers, Widget/Watch/Live Activity projection tests |
| Widget active timer/recent task snapshot | `Services/SystemIntegration/WidgetSnapshotCache.swift` | `Stores/Facade/TimeTrackerStore+WidgetSnapshot.swift`, `timetrackerWidgetExtension` |
| Widget extension UI | `timetrackerWidgetExtension/TimeTrackerWidget.swift` | `ActiveTimerWidgetView.swift`, `WidgetSupplementaryViews.swift`, `WidgetSupport.swift`, `Shared/WidgetSnapshotModels.swift`, widget localization files, WidgetKit target settings |
| Watch timer command handoff | `Services/SystemIntegration/WatchCommandProcessor.swift` | `App/WatchCommandRouter.swift` (weak multi-scene dispatch), `Shared/WatchCommandModels.swift` (queue/result state), `timetrackerWatchApp/WatchAppStore.swift` (persistence/20 s timeout), `Stores/Facade/TimeTrackerStore+WatchSnapshot.swift`, payload codec/bridge, timer commands |
| Watch app UI | `timetrackerWatchApp/WatchDashboardView.swift` | `WatchTimerRows.swift`, `WatchStatusViews.swift`, `WatchColorSupport.swift`, `timetrackerWatchApp/WatchAppStore.swift`, `Shared/WatchCommandModels.swift`, `Shared/WatchStateSnapshotModels.swift`, watch localization files |
| Live Activity display/stop deep link | `timetrackerLiveActivityExtension` | `SharedLiveActivity/TimeTrackingActivityAttributes.swift`, `App/AppDeepLinkRouter.swift`, `App/TimeTrackerLiveActivities.swift` |
| Localization | `Shared/AppStrings.swift` | every target's `*.lproj/Localizable.strings` and `*.lproj/InfoPlist.strings`, main-app `*.lproj/AppShortcuts.strings`, localization parity tests |

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
- `*Store.swift`: observable snapshots and refresh logic for one domain.
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
| `Docs/CodeRefactorPlan.md` | Completed structural split, current concentration inventory, and architecture guardrails. |
| `Docs/NativeUIPlan.md` | Native-first UI guardrails and future screenshot/device acceptance checklist. |
