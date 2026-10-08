# Project Map

Status: current source map

First stop for a developer new to this repository: where code lives, which file to open first, and which boundary owns a change. Placement/domain rules also live in [Architecture](Architecture.md); UI rules in [UI-Design](UI-Design.md).

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

`TimeSegment` is the ledger fact; UI state, forecasts, charts, and summaries derive from persisted task, checklist, session, segment, pomodoro, countdown, and preference models. `TimeTrackerStore` is `@MainActor @Observable`: app roots own it with `@State`, feature views keep a plain injected reference, binding sites use local `@Bindable`. macOS has one main `Window` and its Settings scene receives the same store; each visible scene separately owns one typed App-level sheet router and one FIFO feedback router. CloudKit refresh enters through notification observers and the refresh planner, never a foreground polling timer.

## Source Folders

| Path | Owns | Open this when |
| --- | --- | --- |
| `timetracker/App` + `App/RootViews` | Entry, the width-driven compact/regular shells (`AppRootView` keeps only the width band), scene-owned typed sheet/feedback router-host pairs, container/CloudKit startup, recurrence lifecycle scheduling, build info, demo/seed data, bounded deep links, weak multi-scene Watch routing, menu commands | Changing startup, root shell composition or the 720 pt breakpoint, scene presentation/feedback, recurrence foreground/midnight triggers, menu commands, build metadata, deep-link/Watch scene routing, or seeding |
| `timetracker/AppIntents` | Siri/Shortcuts intents and task/timer entities wrapping shared command handlers, then enqueuing exact post-commit events | Adding/changing the five system actions (capture Inbox item, start timer, stop timer, get running timers, stop all timers) |
| `SharedLiveActivity`, `timetracker/Shared` | Shared Activity attributes; target-neutral Widget/Watch transport DTOs, App Group snapshot storage, `DeviceIdentity`, elapsed-clock/hex-color presentation | Changing cross-target DTO compatibility, extension-safe formatting, or shared snapshot persistence |
| `timetrackerLiveActivityExtension` / `timetrackerWidgetExtension` / `timetrackerWatchApp` | ActivityKit/Dynamic Island UI; WidgetKit entry/provider/layouts/support; watchOS vertical-page dashboard plus the `WatchAppStore` family (observable/restored state, durable command queue, WatchConnectivity transport) | Changing extension faces, localization, entitlements, Watch page navigation/command retry, or transport |
| `timetracker/Models` | SwiftData models, V1...V14 schema history, migration plan, registry, deterministic recurrence/quantity identities, shared read models, `TaskEstimatePolicy`, `TrackedTimePolicy` | Adding persisted fields/migrations, shared read models, or estimate/time normalization |
| `timetracker/Repositories` | SwiftData query/write implementations behind repository protocols (rapid-restart canonicalization, recurrence graph writes); `ModelContext+AtomicMutation.swift` is the transaction boundary | Changing fetch predicates, persistence semantics, tombstones, recurrence materialization, or ledger writes |
| `timetracker/Commands` | User-action handlers and use cases | Adding a durable action (start timer, toggle checklist, move task, update preference) |
| `timetracker/Stores/Facade` | `TimeTrackerStore`, first configuration, current-scene refresh/mutation lifecycle, projection-recovery triggers, UI-facing extensions | Wiring a view action, exposing read models, or coordinating app lifecycle |
| `timetracker/Stores/Domains` | Task, indexed ledger/session, task-scoped checklist, incremental rollup/90-day pace, analytics cache, preference snapshots | Changing what state a feature observes after data changes |
| `timetracker/Stores/Navigation` / `Refresh` | Shared selection/destination coordination; refresh event planning and domain refresh | Changing selection invalidation or which snapshots update on a write |
| `timetracker/Services/Analytics` | Aggregation, selection policy, timeline layout, hourly stack layout, daily bucket cache, Today heatmap projection | Changing chart math, overlap, daily/monthly summaries, or timeline lane allocation |
| `timetracker/Services/Checklist` / `Countdown` / `Inbox` / `Forecasting` / `Tasks` / `TimeTracking` | Checklist draft persistence; countdown commands; Inbox identity/suggestion/primary store-scoped writers; forecast/rollup; task tree, recurrence, archive/tombstone, AI workspace capture/overlay + store-scoped atomic apply; pure timer admission/rapid-restart policy and store-scoped coordinators | Changing the corresponding domain rules |
| `timetracker/Services/LLM` | OpenAI-compatible endpoint validation, credential-safe transport, response decoding, suggestion services, complete-workspace planning tools, in-memory proposal execution | Changing model discovery, redirect policy, concurrency/backoff, prompt/tool contracts, or decoding |
| `timetracker/Services/Ledger` / `Preferences` / `Maintenance` / `SystemIntegration` | Device-local CloudKit startup mode, write diagnostics, duration formatting, summary/aggregation; store-scoped preference writes + device-local macOS shortcuts; repair/cleanup; durable local-file/lock primitives, credentials, export | Changing time math, preference commits, repair safety, or recovery-file/Keychain/export primitives |
| `timetracker/Services/Sync` | Sync-conflict orchestration/state, record-level LWW auto-merge, versioned snapshots, restore, Cloud reconciliation import buffering | Changing conflict recovery, auto-merge, snapshot capture/restore, bounded state files, or Cloud import |
| `timetracker/Services/SystemProjection` / `WatchConnectivity` | Committed-mutation scheduling, current-state Widget/Watch/Live Activity materialization, sibling-scene convergence; iPhone Watch command processing, idempotency, ranking/projection, codec, bridge | Changing post-commit projection, event-to-sink routing, per-sink retry, or Watch handoff/payload |
| `timetracker/Features/*` | Screen composition per feature (`Home`, `Inbox`, `Tasks`, `Analytics`, `Pomodoro`, `Settings`, `Sidebar`, `Ledger`) | Changing the corresponding screen's composition or rows |
| `timetracker/SharedUI/Foundation` / `Components` | Design tokens, colors, layout policies, breakpoints; reusable native-styled controls and shared task/timer/settings rows | Changing shared visual constants or a control with a second caller |

`Features/Inspector`, `PhoneChromeViews`, `SettingsSectionsViews.swift`, `TimeTrackerServices.swift`, and the retired Inbox suggestion editor are names of deleted code, not extension points.

## Subsystem Entry Anchors

Grep the owning feature folder before adding a file. When a subsystem has one obvious entry, open it first, then follow its extensions:

| Area | Start here |
| --- | --- |
| Start/stop + sub-minute rapid restart | `Services/TimeTracking/TimerAdmissionPolicy.swift`, `TimerRapidRestartPolicy.swift`, `StoreScopedTimerCommandCoordinator.swift`, `Repositories/SwiftDataTimeTrackingRepository+RapidRestart.swift` |
| Manual time / segment edit | `Commands/LedgerCommands.swift`, `Features/Ledger`, `Stores/Domains/LedgerStore*.swift` |
| Tracked-time / future-time / clock-skew | `Models/LedgerModels.swift` (`TrackedTimePolicy`), `Services/Ledger/TimeAggregationService.swift` |
| Tasks, categories, archive/restore | `Commands/TaskCommands.swift`, `Services/Tasks/TaskTrackingAvailabilityService.swift` + `TaskTree*`, repository hierarchy files |
| Daily recurrence + quantity | `Services/Tasks/StoreScopedTaskRecurrenceCommandCoordinator.swift`, `App/TaskRecurrenceLifecycleModifier.swift`, `Repositories/SwiftDataTaskRepository+Recurrence.swift` |
| Checklist | `Commands/ChecklistCommands.swift`, `Services/Checklist/*`, `Stores/Domains/ChecklistStore.swift` |
| Forecast / incremental rollup | `Models/TaskEstimatePolicy.swift`, `Services/Forecasting/TaskRollupService.swift`, `Stores/Domains/RollupIncrementalIndex*.swift` |
| Analytics data + navigation | `Stores/Domains/AnalyticsStore*.swift`, `Stores/Facade/TimeTrackerStore+Analytics*.swift`, `Services/Analytics/*`, `Features/Analytics` |
| Schema migration | `Models/SchemaModels.swift`, `SchemaMigrationPlan.swift`, `TimeTrackerModelRegistry.swift`, `timetrackerTests/Support/*SchemaCompatibilityFixtures.swift` |
| iCloud / sync conflict / recovery | `Commands/PreferenceCommands.swift`, `Services/Sync/SyncConflictService*.swift`, `App/AppModelContainerFactory*.swift` |
| Post-commit system projection | `Services/SystemProjection/CommittedMutationSystemProjectionScheduler.swift` |
| Watch / Widget / Live Activity | `Services/WatchConnectivity/WatchCommandProcessor.swift`, `Services/SystemProjection/CommittedMutationSystemSurfaceMaterializer.swift`, `Shared/WatchStateSnapshotModels.swift`, `Shared/WidgetSnapshotModels.swift`, extension targets |
| AI config / suggestions / planning | `Features/Settings/LLMSettingsViews.swift`, `Services/LLM/LLMModelService.swift` + `LLMPromptCatalog.swift`, `Services/LLM/LLMTaskWorkspacePlanningService.swift` + `Services/Tasks/StoreScopedAITaskAtomicMutationCoordinator.swift` |
| Scene sheet / transient error | `App/AppPresentationRouter.swift`, `App/AppSceneFeedbackRouter.swift` (never store scene-local drafts/alerts in `TimeTrackerStore`) |
| Durable local recovery file/queue | `Services/SystemIntegration/DurableLocalFile.swift`, `PathFileLock.swift` (one stable durable root per state family; JSON/domain validation stays in the caller) |
| Demo/seed data + test isolation | `App/AppDemoDataConfiguration.swift`, `App/SyntheticDataOrigin.swift`, `App/AppRuntimeEnvironment.swift` (tests must never use `UserDefaults.standard` directly; gate is `Lifecycle/TestHostIsolationTests.swift`) |
| Localization | `Shared/AppStrings.swift` + each target's `*.lproj` resources |

## Current Responsibility Concentrations

Navigation hints, not automatic failures or a line-count budget. Split only when the subsystem is next changed, after protecting behavior:

| Area | Preferred boundary |
| --- | --- |
| `Stores/Facade/TimeTrackerStore+Lifecycle.swift` | Split mutation orchestration from repository/error support without moving sync/system projection back into the facade |
| `Stores/Facade/TimeTrackerStore+SyncObservers.swift` | Separate event intake from batch processing and recovery presentation; keep fixed-deadline coalescing |
| `Features/Tasks/Management/TaskRowComponents.swift` | Extract one shared action context before separating menu and swipe presentation |
| `Features/Analytics/AnalyticsPeriodSelectionViews.swift` | Separate pure period/navigation policy from SwiftUI presentation |
| `Stores/Facade/TimeTrackerStore+PreferenceCommands.swift` | Low priority; revisit only if new preference setters accumulate |

Sync remains the highest semantic-risk subsystem: mechanical movement is never completion — deterministic merge/tombstone behavior, sensitive-key filtering, atomic restore, recovery barriers, checkpoint invalidation, and snapshot tests must remain green.

## Placement Rules

1. Put durable write behavior in `Commands`, not in SwiftUI button closures.
2. Put SwiftData fetch/write implementation in `Repositories`, not in feature views.
3. Put testable calculations in `Services`, not in `body`.
4. Put screen-specific composition in `Features/<Feature>`.
5. Shared styling and controls need a second caller (or an explicit near-term one) before entering `SharedUI`; a one-off layout stays in its feature.
6. Keep `TimeTrackerStore` a facade; domain logic moves to a command handler, domain store, or service.
7. Avoid root-level miscellaneous folders; a file whose name needs a `+` suffix usually belongs under the owning facade/feature directory.
8. For schema changes, prefer additive extension models over changing core ledger/task models; update `Architecture.md` schema rules and add compatibility tests before UI work.

## Naming Rules

- `*Commands.swift`: durable write actions and use cases.
- `*Store.swift`: observable snapshots and refresh logic for one domain.
- `*Service.swift`: pure calculations or maintenance helpers testable without SwiftUI.
- `*Views.swift` / `*RowViews.swift` / `*SupportViews.swift`: SwiftUI composition for a feature/section, reusable rows, and small support controls.
- `TimeTrackerStore+*.swift`: facade extensions only, living in `Stores/Facade`.

## Before Adding A Feature

1. Add expected behavior to `Architecture.md`, this map, or a focused feature document.
2. Add or update tests at the service/command/store/UI boundary.
3. Implement the smallest domain owner first.
4. Wire SwiftUI last.
5. Run the gates in [Testing](Testing.md) and [README](../README.md).

## Planning Documents

- `Docs/NextDevelopmentPlan.md` — product backlog, deferred list, and release gates.
- `Docs/UI-Design.md` — native-first UI guardrails and review/screenshot checklist.
- `Docs/ImplementationContexts/` — in-progress memory for multi-session tasks only; cleaned up at closeout.
