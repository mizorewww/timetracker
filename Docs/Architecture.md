# Time Tracker Architecture

Status: current implementation

Reviewed: 2026-07-15

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

Views may format and present state, but durable business actions should go through the store and use cases. `TimeTrackerStore` is a `@MainActor @Observable` facade: roots own it with `@State`, views read the injected reference, and only binding sites create `@Bindable`. This keeps iOS, macOS, widgets, Live Activities, and Watch commands from duplicating timer logic.

## Domain Model

`TaskNode` represents a task tree node. All tasks can contain child tasks and all tasks can be timed. `parentID` is the hierarchy authority; `depth` is repairable metadata; `path` is the stable canonical locator `/<task UUID>`, not a persisted ancestor chain or user-facing title path. `TaskTreeService` derives display paths from current titles and caps them at six components. Startup, task refresh, and sync restore repair missing parents/cycles deterministically before rendering. Moving a task prevents cycles and updates only metadata that actually changed.

`TimeSession` represents one work intention. `TimeSegment` represents actual worked time and is the ledger fact used for analytics. Active work has an open segment; stopping closes the segment and its session.

`TrackedTimePolicy` is the single read boundary for persisted tracked time. For a reference `now`, the effective end is `min(endedAt ?? now, now)`; the resulting interval is then intersected with the requested half-open range. A segment starting at or after `now`, or with no positive intersection, contributes zero. Local manual-entry and segment-update writes reject a future end or a future open start with typed `TimeTrackingRepositoryError.futureTime`. Clock-skewed CloudKit/import/legacy facts are retained rather than migrated away, but every aggregation, forecast, timeline, cache, rollup, and range query must clip them through this policy.

`PomodoroRun` represents the pomodoro workflow. Its persisted phase start plus planned duration derives `phaseDeadline`; startup/foreground/scheduled reconciliation clips expired focus ledger records to that deadline. Break completion remains an explicit user action so background suspension never creates a new focus segment. Segment edit/delete, timer stop, and task-tree deletion must keep the run and ledger lifecycle consistent.

`CountdownEvent` stores optional user-defined date milestones. iPhone, iPad, and macOS all derive their Today countdown presentation from the same store state.

`SyncedPreference` stores sync-eligible user-facing settings as JSON values in SwiftData so they travel through the same iCloud-backed store as tasks and timers. The iCloud enablement flag is different: it is a device-local `UserDefaults` startup configuration because the model container must know whether to start in CloudKit mode before SwiftData can fetch cloud values. It is excluded from `SyncedPreference`, conflict snapshots, and export/restore boundaries, and changes take effect on the next launch.

`ChecklistItem` belongs to a `TaskNode`, but it is not a task. Checklist items are for progress and estimation only; timers, manual entries, pomodoros, widgets, and Live Activities still attach time to the task itself.

Task visibility and work eligibility are intentionally separate. Archived or deleted branches are hidden. Completed tasks and descendants stay visible so detail and history remain reachable, but a completed task anywhere on the ancestor path blocks new timers, manual entries, Pomodoro runs, Quick Start, Inbox conversion, App Intents, and create/move destinations. Reopening for work restores every completed blocker on that path to active. An already-running segment remains visible and stoppable if completion arrives from another device or historical state.

The current SwiftData schema is V9 (`1.8.0`). V9 removes the persisted `DailySummary` derived cache through a lightweight V8→V9 migration while preserving ledger and other user facts. The legacy model remains declared only inside V1...V8 schema history; current analytics creates disposable `DailySummarySnapshot` values from ledger facts.

## Forecasting and Analytics

Forecasting is local and explainable. `TaskRollupService` recursively combines direct task time, an explicit task estimate or checklist evidence, and direct child-task rollups. `ForecastDisplayService` decides whether Home, Analytics, and Task Detail should show the selected task, drill into one forecastable child task, or show a parent summary. `AnalyticsEngine` owns pure date/range aggregation for overview metrics, hourly activity, and daily/monthly chart points.

The current task's explicit estimate takes precedence over checklist inference. `TaskEstimatePolicy` accepts `0...600` minutes, treats zero as absent, and clamps positive legacy values to 36,000 seconds. Checklist items use an equal-weight fallback only when there is no explicit estimate:

```text
if task is completed or every checklist item is completed:
  ownRemaining = 0
else if explicitEstimate exists:
  estimatedTotal = max(explicitEstimate, ownWorkedSeconds)
  ownRemaining = max(0, explicitEstimate - ownWorkedSeconds)
else if checklistTotal == 0:
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

An explicit estimate applies only to the current task; forecastable children are added independently. Historical pace is the active-day average within the most recent 90 local calendar days, including today; it is only used to convert already-derived remaining seconds into projected active days for the same task branch. It never invents remaining hours. Without an explicit estimate, insufficient checklist progress or tracked time produces a missing-requirement state instead of a number.

Parent display rules:

```text
Parent has its own forecast source (explicit estimate or checklist evidence):
  show the parent forecast and include forecastable children recursively

Parent has no own forecast source and exactly one forecastable child branch:
  show that child task directly

Parent has no own forecast source and multiple forecastable child branches:
  show a parent summary labeled as an aggregate

No forecastable source exists:
  do not show a forecast card; show guidance in task detail
```

Mutation refresh is incremental after initial/full load. `LedgerStore` replaces only segments overlapping invalidated ranges and related sessions; `ChecklistStore` replaces affected task buckets; `RollupIncrementalIndex` applies segment before/after deltas and recalculates direct tasks plus ancestors. Active and future-ended segments are time-sensitive: forward clock movement reevaluates that bounded set, while a backward wall-clock correction reevaluates all ledger rows because a previously completed row can cross the reference boundary again. Full-history worked seconds remain exact, while only the 90-day pace buckets are bounded. `CorePerformanceBudgetTests` includes a 50,000-segment single-record mutation and cached frequent-task ranking budget.

`AnalyticsStore` caches overview and task snapshots by range, true calendar period start, and optional minute live bucket. A live bucket exists only when an active segment overlaps the selected range, so historical views do not recompute for clock ticks. Ledger events invalidate snapshots and only intersecting day buckets; every cache remains disposable and reconstructable from ledger facts.

## Deletion Rules

Tasks are soft-deleted by default. Deleting a task tree first stops its active timers and ends active Pomodoro runs, then tombstones the tasks while retaining historical ledger/Pomodoro facts. Production Local, iCloud, fallback, and emergency stores never physically purge tombstones: CloudKit has no per-device deletion acknowledgement, so an offline device could otherwise resurrect old rows. Permanent cleanup is available only to isolated Demo/UI Test stores and only for expired tombstone graphs; a temporarily missing parent during staged import is not deletion evidence.

## Sync Assumptions

iCloud sync is controlled by `AppCloudSync` and the SwiftData model container configuration. Eligible user preferences sync through `SyncedPreference`; iCloud enablement, device identity, migration flags, build info, secrets, automatic-AI consent, and CloudKit error text stay local. The app refreshes on launch, foreground, SwiftData remote changes, and completed CloudKit import/export events. Consecutive notifications are coalesced before entering the refresh planner; there is no permanent foreground polling loop. Local/Demo/UI Test mutations do not capture conflict snapshots; in CloudKit/recovery mode `StoreDomainEvent` refreshes only affected snapshot domains unless a full baseline/import is required.

Every `SyncConflictState.json` read-modify-write runs under a recursive process lock plus POSIX `lockf` advisory file lock, so app and Shortcuts processes share one serialized state transaction. JSON replacement is atomic, and the forced-upload mirror cannot override an existing authoritative state. A corrupt authoritative file is quarantined for explicit recovery; a corrupt pending-forced-upload mirror is also quarantined but ignored so it cannot block an otherwise usable main store. Local generations, sync epochs, and per-export event checkpoints ensure only the exact exported fingerprint/generation is acknowledged; failed, stale, or out-of-order callbacks cannot mark newer local work clean. Scrubbing a legacy excluded preference recomputes the fingerprint and invalidates checkpoints for the old payload. Checkpoints are bounded to 16 entries and 24 hours.

Snapshot restore treats transport data as untrusted historical input. Duplicate UUID records are deterministically collapsed before three-way dictionaries are built, preventing a malformed/legacy snapshot from triggering a duplicate-key trap. Restored Pomodoro plans clamp focus, break, and long-break durations to at least one second, round targets to `1...24`, and completed rounds to `0...target` before creating domain models.

On iOS, the authoritative state, pending forced-upload recovery mirror, and corrupt-state quarantine files use `FileProtectionType.completeUntilFirstUserAuthentication`. They remain unavailable before the first unlock after boot, then stay available to background Shortcuts/CloudKit coordination. This protection applies to sensitive JSON files, not the advisory lock file; macOS does not receive the iOS attribute.

One user mutation is committed through `ModelContext.performAtomicMutation`. Nested command/repository steps defer their saves until the outer boundary and rollback together on failure. Read-model refresh and sync/Widget projection happen after commit; failure there must be reported as “saved but refresh failed,” not as a rolled-back business action.

Keychain is intentionally outside SwiftData's ACID boundary. Saving LLM configuration batches endpoint, model list, and selected model into one preference transaction, while preserving the previous Keychain value for compensating restore if that transaction fails. A compensation failure is a separate error, never proof of atomic cross-storage rollback. “Clear all data” likewise clears the Keychain API key and device-local automatic-suggestion consent, attempts to restore them if the SwiftData reset fails, and leaves the device-local iCloud startup switch unchanged.

App Intents use the application model container and the same commands. After an intent commits, a narrow post-commit synchronizer refreshes only task/ledger/preference state needed by Widget, Watch, and Live Activity; it does not start the full app lifecycle or automatic LLM jobs. A projection failure never turns a committed, potentially non-idempotent action into an intent failure.

System input routing is lifecycle-safe and bounded. `AppDeepLinkRouter` validates a small URL grammar before immediate execution or enqueue; each scene owns a semantic-deduplicating `PendingDeepLinkQueue` capped at 16 entries and drains it only after repositories are ready. `WatchCommandRouter` owns the process-wide Watch bridge callback but retains scene stores weakly, prefers the most recently active scene, removes released registrations, and uninstalls the callback when no scene remains. This prevents startup URLs from bypassing validation and prevents a singleton connectivity closure from leaking or targeting a stale scene.

System-surface projections are also untrusted transport boundaries. Widget and Watch producers cap record counts, clamp summaries and anomalous timer starts, and shorten projected title/path/style values at Unicode character boundaries. Each snapshot has a 128 KiB aggregate text budget. `SharedWidgetSnapshotStore` then validates before save and after load, rejects encoded data over 256 KiB, caps active timers and recent tasks at 64 each, and requires bounded fields/time values and unique timer/task IDs; invalid loads are reported as corrupted rather than empty. `WatchStateSnapshot` allows at most 64 active timers and 256 recent tasks under equivalent field/time/identity/text-budget validation. Independently, iPhone incoming and Watch pending/failed command queues each cap at 64 entries, and persisted queue JSON caps at 512 KiB. Projection shaping changes only extension DTOs; canonical task and ledger facts remain untouched.

Persistent deduplication and synced preferences use deterministic last-write-wins ordering. A newer `updatedAt` wins; at an equal timestamp a tombstone wins; `createdAt`, `deviceID`, `clientMutationID`, or a stable TimeSegment content key resolve the remaining tie. Select the winner before filtering tombstones so stale active rows cannot resurrect deleted data.

## UI Structure

The app source is organized by ownership. New files should land next to the domain they affect:

```text
timetracker/App
timetracker/Models
timetracker/Repositories
timetracker/Commands
timetracker/Stores
  Domains/        Observable snapshots for tasks, ledger, rollups, analytics, preferences
  Facade/         TimeTrackerStore shell, configuration/lifecycle, UI-facing extensions
  Navigation/     Shared selection and destination coordination
  Refresh/        Refresh planning and coordination
timetracker/Services
  Analytics/      Aggregation, summary cache, and timeline layout algorithms
  Checklist/      Checklist draft persistence helpers
  Forecasting/    Checklist forecast and rollup display rules
  Inbox/          Inbox suggestion eligibility and state derivation
  Instrumentation/
                   Performance signposts around measured domain work
  LLM/            OpenAI-compatible transport, validation, and suggestion decoding
  Ledger/         Cloud startup mode, persistence safety, timer DTO, duration and aggregation utilities
  Maintenance/    Database repair, export, and cleanup support
  SystemIntegration/
                   Sync conflict orchestration/state/export, versioned snapshots,
                   Widget/Watch handoff, credentials, and connectivity transport
  Tasks/          Task tree derivation and validation helpers
timetracker/Features/Home
  Controls/       Start/new-task controls and task selection sheets
  Rows/           Active timer and timeline rows
  Sections/       Metrics, forecast, quick start, and timeline sections
timetracker/Features/Inbox
                  Capture, list rows, suggestion feedback, and suggestion editor
timetracker/Features/Tasks
  Detail/         Canonical detail router plus identity, checklist, overview,
                   analytics, navigation, and record sections
  Editor/         Task editor, symbol picker, checklist editing, and editor-specific controls
  Management/     Task browsing screen and reusable task rows
timetracker/Features/Pomodoro
  Sections/       Setup composition, empty state, focus controls, Plan/Task selection,
                   timer face, active-run, and recent-ledger sections
timetracker/Features/Analytics
  root files      Landing page, typed category model/detail destination, summary rows,
                   metric/detail lists, and period controls
  Sections/       Overview, forecast, distribution, and activity sections
  Timeline/       Timeline chart composition and support views
timetracker/Features/Settings
  root files      Category router plus timing, Pomodoro, countdown, sync, and data sections
  Support/        Export documents and settings support rows
timetracker/Features/Sidebar
timetracker/Features/Ledger
timetracker/Shared
timetracker/SharedUI
  Foundation/     Design tokens and responsive layout policies
  Components/     Reusable native-styled controls, badges, rows, and cards;
                   Settings foundation/action/input/presentation/sync-feedback owners
```

Within `Features/Home`, keep the Today screen split by responsibility: `Features/Home/HomeViews.swift` composes the page, `Features/Home/Controls/HomeActionsViews.swift` owns start/new-task controls and the searchable task picker, `Features/Home/Sections/HomeMetricsViews.swift` renders the compact time summary, `Features/Home/Sections/HomeCountdownViews.swift` owns the shared countdown presentation, and forecast, quick start, timeline, and row files own their own sections. Generic day/week/month/year progress tiles were removed; countdown events are a low-priority Today section on every main-app platform. Within `Features/Settings`, `Features/Settings/SettingsViews.swift` owns category navigation and presentation; display/timing, Pomodoro, countdown, sync, data, AI draft configuration, binding, action, and support responsibilities stay focused. Shared rows are split into `SettingsRows.swift` foundation/value semantics, action/destructive labels, text/number inputs, platform presentation modifiers, and sync feedback. `SettingsSectionsViews.swift` and `TimeTrackerServices.swift` are retired names, not extension points.

The macOS app owns one main `Window` and one application-level `TimeTrackerStore`; the standard Settings scene receives that same store. Do not return to `WindowGroup` unless per-window persistence coordination is split from scene-local navigation/draft state first, or each window would duplicate observers and background automation.

`SyncConflictService.swift` owns bootstrap and prompt assembly. Focused extensions own local mutation, Cloud import/export, recovery/resolution, state persistence, POSIX lock/locations, and filtered export encoding. `SyncDataSnapshot` plus capture and task/ledger/planning/checklist/Inbox restore files own one atomic domain mapping, while organization and domain record files own versioned transport DTOs. Record DTOs are transport/restore representations only; business truth remains the SwiftData domain model and ledger facts.

Pure layout, formatting, and derivation logic belongs in `Services`, `Shared`, or `SharedUI` with unit tests. SwiftUI feature files should render state and collect input; durable writes go through store facade methods and command handlers.

Within `Stores/Facade`, `TimeTrackerStore+Configuration.swift` owns full first-run configuration plus the narrow repository-only attachment used by committed App Intents; `TimeTrackerStore+Lifecycle.swift` owns refresh, mutation boundaries, recovery operations, and common errors. Do not make the closed-app system-surface path run migrations, demo seeding, observers, or automatic LLM work.

Avoid root-level "miscellaneous" folders that collect unrelated files. If a file name needs a `+` extension suffix, it should usually live under the owning facade or feature directory instead of being left beside unrelated domain stores. If a directory grows beyond one ownership concept, split it by domain before adding more files.

For the practical "where do I put this change?" map, start with `Docs/ProjectMap.md`. For the current architecture and feature ownership map, see `Docs/ArchitecturePlan.md`.

Xcode shared schemes are source-controlled under `timetracker.xcodeproj/xcshareddata/xcschemes`. Do not rely on per-user scheme state for app builds; command-line builds and install scripts must be able to use `-scheme timetracker` from a clean checkout.

## Shared UI Logic

`TimelineLayoutEngine` owns Today timeline clipping, display interval, and lane allocation. Keep this logic out of SwiftUI view bodies so chart behavior can be tested without launching the app.

Task tree display is derived UI state. The durable hierarchy remains `TaskNode.parentID` plus repairable `depth`/canonical locator `path`; the Tasks screen derives a flat list of visible rows and title paths so native list interactions remain reliable without recursive SwiftUI identity.

## Feature Status

The current app includes local SwiftData persistence, iCloud-backed user preferences, task creation/editing/status, task checklists, soft delete/archive, nested task browsing, multi-segment timers, manual time entry, pomodoro-ledger synchronization, Today timeline, local task forecasting, analytics overview, JSON export, isolated demo-data management, production-safe tombstone retention, iCloud configuration, App Intents, Live Activity, Widget code, and a Watch companion. Permanent tombstone maintenance exists only for isolated Demo/UI Test stores.

Future work should preserve the ledger contract: every timer, pomodoro, manual entry, widget action, Live Activity action, or Watch command must ultimately create or update `TimeSession` and `TimeSegment` records through shared use cases.

## Version and Build Info

Settings includes an About section with the app icon, `MARKETING_VERSION`, build number, Git branch, short commit hash, and build date. The app target writes `AppBuildInfo.plist` during the build using `scripts/write_build_info_plist.sh`; do not hard-code Git metadata in Swift source.

Version bumping is automated through `.githooks/pre-commit`. See `Docs/Versioning.md` before changing release or commit automation.
