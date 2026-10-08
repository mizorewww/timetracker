# Time Tracker Architecture

Status: current implementation and architecture guardrails

Time Tracker is a local-first SwiftUI app whose source of truth is the time ledger, not a screen-level timer flag. This document answers: where does a new feature belong, and which boundary prevents UI/sync/forecast/ledger bugs from spreading? For the "which file do I open first?" map, start with [Project Map](ProjectMap.md). UI guardrails live in [UI Design Notes](UI-Design.md), localization in [Localization](Localization.md), verification in [Testing](Testing.md).

## Layers

```text
SwiftUI View
  -> TimeTrackerStore / focused view state
  -> UseCase (domain command)
  -> Repository protocol
  -> SwiftData repository
  -> SwiftData model
```

Views may format and present state, but durable business actions go through the store and use cases. `TimeTrackerStore` is a `@MainActor @Observable` facade split into lifecycle, read-model, analytics, maintenance, and domain-command extensions: roots own it with `@State`, views read the injected reference, and only binding sites create `@Bindable`. Do not reintroduce `ObservableObject/@Published` or store action closures in focused values.

The product rule is unchanged: `TimeSegment` is the fact layer; tasks, checklist items, pomodoro runs, settings, summaries, and forecasts are supporting structures around that ledger.

### Write Flow

```text
SwiftUI action
  -> TimeTrackerStore facade method
  -> Domain command handler
  -> Repository write
  -> StoreDomainEvent
  -> StoreRefreshPlanner / StoreRefreshCoordinator
  -> Affected domain snapshots refresh in domain order
  -> SwiftUI renders observed state
```

A checklist row tap goes through `TimeTrackerStore.toggleChecklistItem(...)` → `ChecklistCommandHandler.toggle(...)` → one SwiftData update → `checklistChanged(taskID, affectedAncestorIDs)` → Checklist/Rollup/Analytics refresh. Checklist forecast invalidation is not optional: toggling, adding, renaming, deleting, or reordering an item must update the affected task branch immediately because visible remaining time is a direct function of checklist progress.

### Read Flow

```text
Repository query
  -> domain-sized snapshot
  -> pure services derive secondary state
  -> domain store exposes immutable view state
  -> SwiftUI view renders
```

Views render existing snapshots; they must not calculate analytics, tree rollups, or forecast decisions inside `body`. `TimelineView` is acceptable for clock labels, not for rebuilding analytics. Responsive geometry is also an invalidation boundary: `AppRootView` retains only the compact/regular width band (one 720 pt breakpoint); raw live-resize width must not enter root state. The desktop Today page maps raw geometry to `HomeViewportMeasurement` (8 pt buckets anchored at semantic breakpoints, capped at 1180 pt content width). Primary regular-shell destinations replace content inside one stable outer `NavigationStack`.

## Domain Stores And Refresh

Domain stores own state snapshots:

- `TaskStore` — task tree snapshots.
- `LedgerStore` — active, today, history, segment/day/session/array indexes and mutation deltas.
- `ChecklistStore` — global bootstrap plus task-scoped item/visual replacement indexes.
- `RollupStore` — exact worked totals, checklist progress, forecast state, bounded 90-local-day pace.
- `AnalyticsStore` — pure read-model overview/task caches keyed by full period, current local day, and optional live-minute identity, plus disposable ledger day buckets; cache operations live in `AnalyticsStore+Caching`, cached snapshots do not retain SwiftData segment objects.
- `PreferenceStore` — synced preference snapshots.

`StoreRefreshCoordinator` owns refresh sequencing after command events: the committed-mutation boundary first refreshes only the current scene's affected read models and scene-local selection/suggestion state. The facade does not decide refresh order inline.

Every committed Scene, App Intent, and Watch mutation submits one receipt (the command's exact `StoreDomainEvent` set plus any forced current-state sink) to the shared `CommittedMutationSystemProjectionScheduler` for its physical `TimerStoreScope`. The caller does not wait for sync snapshot, Widget, Watch, or Live Activity publication: a Scene first refreshes only its own read models, while App Intent and Watch return after the durable command/terminal result. A queued next-turn `StoreMutationBroadcaster` independently converges sibling scenes as read-only consumers. The scheduler keeps four failure-isolated sinks; a worker opens a fresh background `@ModelActor` context and materializes one immutable committed-fact DTO bundle for the three system surfaces per generation; a Widget App Group write is serialized by its own actor. Each request must carry an explicit cause — `.localCommit`, `.startupCatchUp`, or `.surfaceCatchUp` — and only the first two record a sync recovery snapshot. Launch sends `.startupCatchUp + .fullSync` to close the "committed but process exited before projection" window; foreground/remote import/resolution only re-publish surfaces. Every durable SwiftData transaction sets a stable outer author: business writes `localMutation`, sync restore `syncReconciliation`, startup migration/seed `bootstrapMaintenance`; missing/unknown authors are never inferred as local work.

`StoreDomainEvent` is the write-side invalidation language; commands emit what happened, not which views should refresh:

```text
taskChanged(taskID, affectedAncestorIDs)   checklistChanged(taskID, affectedAncestorIDs)
ledgerChanged(taskID, dateInterval, isVisible)   pomodoroChanged(runID, sessionID, taskID)
preferenceChanged(key)   countdownChanged   remoteImportCompleted   fullSync
```

`StoreRefreshPlanner` converts events into a `StoreRefreshPlan`. When topology is stable, `LedgerStore` fetches only invalidated ranges, `ChecklistStore` replaces only affected task buckets, and `RollupStore` consumes segment before/after deltas plus direct/ancestor IDs. Active and future-ended segments form the time-sensitive set for forward clock movement; a backward clock correction reevaluates every segment because candidates cannot be narrowed safely. `AnalyticsStore` invalidates snapshot caches and only intersecting day buckets. Full structural rebuild remains the explicit path for startup, topology/full-sync changes, remote import without a safe scope, and calendar/time-zone changes.

External CloudKit changes enter the same pipeline through remote-store and completed import/export notifications. The observer coalesces bursts before emitting `remoteImportCompleted`; launch, foreground activation, and completed remote import also enqueue projection catch-up after the read-model refresh. There is no permanent foreground polling timer.

## Feature Ownership Map

| Feature | Durable model | Write owner | Snapshot owner | Pure services | UI owner |
| --- | --- | --- | --- | --- | --- |
| Start/stop/rapid-restart timer | `TimeSession`, `TimeSegment` | `StoreScopedTimerCommandCoordinator`, `TimerCommandHandler`, time-tracking repository | `LedgerStore`, `RollupStore` | `TimerAdmissionPolicy`, `TimerRapidRestartPolicy`, `LedgerSummaryService` | `Features/Home`, `Features/Tasks/Detail` |
| Manual time / segment editing | `TimeSession`, `TimeSegment` | `LedgerCommandHandler`, store-scoped segment coordinator | `LedgerStore`, `AnalyticsStore` | `TimelineLayoutEngine` | `Features/Ledger`, `Features/Home` |
| Task edit/move/archive/restore | `TaskNode` | task draft/lifecycle coordinator | `TaskStore`, `RollupStore` | `TaskTreeService`, `TaskTreeFlattener`, `TaskHierarchyMetadataService`, `TaskTrackingAvailabilityService` | `Features/Tasks`, `Features/Sidebar` |
| Daily recurrence + quantity | `TaskRecurrenceRule`, `TaskRecurrenceOccurrence`, `TaskQuantityGoal`, `TaskQuantityEntry`, generated `TaskNode` | `StoreScopedTaskRecurrenceCommandCoordinator` | `TaskStore` | `TaskRecurrenceDayKey`, `TaskTrackingAvailabilityService` | `Features/Tasks` |
| Task categories | `TaskCategory`, `TaskCategoryAssignment` | `StoreScopedTaskCategoryCommandCoordinator` | `TaskStore`, `RollupStore` | `TaskTreeService` | `Features/Tasks`, `Features/Sidebar` |
| Checklist | `ChecklistItem` | `StoreScopedChecklistCommandCoordinator` | `ChecklistStore`, `RollupStore` | `ChecklistDraftService`, `TaskRollupService` | `Features/Tasks` |
| Forecast | none, derived | none | `RollupStore` | `TaskRollupService`, `ForecastDisplayService` | `Features/Home`, `Features/Analytics`, `Features/Tasks/Detail` |
| Pomodoro | `PomodoroRun`, ledger models | `StoreScopedPomodoroCommandCoordinator` | `LedgerStore`, Pomodoro read models | persisted-phase deadline/reconciliation | `Features/Pomodoro` |
| Analytics | none, derived | none | `AnalyticsStore` | `AnalyticsSelectionPolicy`, `TimeAggregationService`, timeline/overlap engines | `Features/Analytics` |
| Synced settings | `SyncedPreference` | `StoreScopedPreferenceCommandCoordinator`, `PreferenceCommandHandler` | `PreferenceStore` | `PreferenceJSON`, sanitizer, `SyncedPreferenceService` | `Features/Settings` |
| macOS menu shortcuts | device-local `MacKeyboardShortcutPreferencePayload` | `MacKeyboardShortcutPreferenceCommand` | `UserDefaultsMacKeyboardShortcutPreferenceStore` | `KeyboardShortcuts` + app conflict policy | `Features/Settings`, `App/TimeTrackerCommands` |
| Countdown events | `CountdownEvent` | `StoreScopedCountdownCommandCoordinator` | `TimeTrackerStore` countdown snapshot | date formatting | `Features/Home`, `Features/Settings` |
| JSON export | business snapshot | facade maintenance command | `SyncDataSnapshot` capture | `SyncDataExport` encoding | `Features/Settings/Support` |
| Tombstone maintenance | destructive, Demo/UI Test only | maintenance facade | affected stores | `DatabaseMaintenanceService` | hidden for production |
| Live Activity | ledger snapshot | shared ledger commands/intents | `LedgerStore` | shared activity attributes | extension UI |

## Domain Model

`TaskNode` is a task-tree node: ordinary visible tasks can be timed, while recurrence templates are organization-only containers whose generated daily children own real work. `parentID` is the hierarchy authority; `depth` is repairable metadata; `path` is the stable canonical locator `/<task UUID>`, not a persisted ancestor chain or user-facing title path. `TaskTreeService` derives display paths from current titles and caps them at six components; startup, task refresh, and sync restore repair missing parents/cycles deterministically before rendering.

Tasks have no product-facing workflow status. `TaskNode.statusRaw` remains only because V4-era schemas, existing records, and snapshots contain it; restore/compatibility boundaries accept `planned`, `active`, `completed`, and `archived` without migration or bulk rewrite. The first three are inert compatibility bytes; only historical `archived` participates in archive compatibility. A task is archived when `archivedAt != nil` or raw `archived`; archive commands write both markers. Archived or tombstoned branches are hidden and cannot accept new work; archiving a branch requires its active timers/Pomodoro to stop first. `TaskNode.deletedAt` remains a compatibility/sync-protocol tombstone; production Local/iCloud/fallback/emergency stores never physically purge tombstones (CloudKit has no per-device deletion acknowledgement), and permanent cleanup is available only to isolated Demo/UI Test stores for expired tombstone graphs. A temporarily missing parent during staged import is not deletion evidence.

`TimeSession` is one work intention; `TimeSegment` is actual worked time and the ledger fact. Active work has an open segment; stopping closes it. Ordinary stopwatch restarts canonicalize one narrow case: when the same task restarts from an ordinary timer source in strictly less than 60 seconds, the gap contains no other visible work, and the prior singleton session has no canonical Pomodoro relationship, the fresh store-scoped Start keeps that session, tombstones its closed segment, and creates a new active segment ID whose start extends to the original start. The gap counts as continuous work. Exact 60-second gaps, overlap/clock rollback, `replaceAll`, Manual, Calendar, and Pomodoro records stay separate; the old segment ID is never reopened, so a stale exact Stop cannot close the new timer.

`TrackedTimePolicy` is the single read boundary for persisted tracked time: for a reference `now`, effective end is `min(endedAt ?? now, now)` intersected with the requested half-open range; a segment starting at/after `now` or with no positive intersection contributes zero. Local manual-entry/segment-update writes reject future ends/open starts with typed `TimeTrackingRepositoryError.futureTime`. Clock-skewed CloudKit/import/legacy facts are retained rather than migrated away, but every aggregation, forecast, timeline, cache, rollup, and range query clips them through this policy.

`PomodoroRun` derives `phaseDeadline` from persisted phase start + planned duration; startup/foreground/scheduled reconciliation clips expired focus ledger records to that deadline. Break completion stays an explicit user action. Segment edit/delete, timer stop, and task-archive admission keep the run and ledger lifecycle consistent.

`CountdownEvent` stores optional user date milestones; all platforms derive Today countdown presentation from the same store state. `SyncedPreference` stores sync-eligible settings as JSON values in SwiftData. The iCloud enablement flag is different: a device-local `UserDefaults` startup configuration, excluded from `SyncedPreference`, conflict snapshots, and export/restore; changes take effect next launch.

`ChecklistItem` belongs to a task but is not a task: it is the product-level completion/progress signal and forecast evidence, and completing it never locks the task. Checklist visual suggestion is a latest-input-wins side effect, not draft identity: the facade waits a short stable-input window, counts pending+in-flight against one concurrency limit, and cancels work whose title/task context/config/item-visual revision is stale; completion still passes through the store-scoped fresh-context boundary. An unchanged checklist save must not rotate revisions, and writing the same icon/color is a durable no-op.

`TaskRecurrenceRule` turns one task into a daily template in a frozen rule timezone. `StoreScopedTaskRecurrenceCommandCoordinator` materializes at most the current local day, never backfills, and skips days while a rule/template branch is unavailable. The deterministic `TaskRecurrenceOccurrence` is both idempotency claim and link to a deterministic generated child; physical claims, tombstones, and staged partial rows veto background reconstruction, while replay preserves user edits. A template remains a legal parent/content task but is excluded from direct-work admission (Timer/Pomodoro/manual/App Intent); its generated child is the work-bearing task. `TaskQuantityGoal` is copied to a new child as configuration; quantity entries are not copied between days.

`InboxItem` owns an opaque suggestion context UUID plus a title-revision UUID; the context survives a physical row rebuild while a real title edit rotates only the revision. Dismissing records that revision, so another synced copy cannot resurrect it and separately created items stay distinct even with equal titles. These identifiers are random or legacy-record UUIDs, never hashes or normalized projections of user text. Content fields follow LWW with tombstones winning ties; dismissal is a separate field-level OR only for the exact context/revision. `InboxCaptureReceipt` is separate: only a caller-provided external `(origin, UUID)` key can replay one capture; title, timestamp, and model IDs never act as a receipt. The item and receipt commit in one store transaction, and multiple active receipts for one key must describe the same payload/item or raise an explicit sync conflict.

The current SwiftData schema is V14 (`1.13.0`). V9 removed the persisted `DailySummary` cache (lightweight V8→V9); V10 adds opaque Inbox suggestion identity (custom V9→V10 migration initializing legacy rows and preserving the old dismissal state); V11 adds capture receipts; V12 persists the suggestion destination kind; V13 adds recurrence rules, occurrence receipts, quantity goals, and additive entries (lightweight); V14 adds `ChecklistItem.sortOrderBeforeCompletion` (lightweight) and resolves V13-and-older `ChecklistItem` to a frozen snapshot. Rule/receipt/generated-task/goal identities use frozen deterministic UUIDv8 domains so retries and independent devices converge without CloudKit uniqueness constraints. V13/V14 snapshot tables are optional only for backward compatibility; a missing key means unknown legacy state, an explicit empty array authoritatively clears that table. Legacy Inbox model shapes stay frozen, and current analytics still creates disposable `DailySummarySnapshot` values from ledger facts.

## Forecasting And Analytics

Forecasting is local and explainable. `TaskRollupService` recursively combines direct task time, an explicit task estimate or checklist evidence, and direct child rollups; `ForecastDisplayService` decides whether Home/Analytics/Task Detail show the selected task, drill into one forecastable child, or show a parent summary.

The current task's explicit estimate takes precedence over checklist inference. `TaskEstimatePolicy` accepts `0...600` minutes, treats zero as absent, and clamps positive legacy values to 36,000 seconds. Checklist items use an equal-weight fallback only without an explicit estimate:

```text
if every checklist item is completed: ownRemaining = 0
else if explicitEstimate exists:
  estimatedTotal = max(explicitEstimate, ownWorkedSeconds)
  ownRemaining = max(0, explicitEstimate - ownWorkedSeconds)
else if checklistTotal == 0: forecastState = needsChecklist
else if completedChecklistCount == 0: forecastState = needsCompletedItem
else if ownWorkedSeconds == 0: forecastState = needsTrackedTime
else: ownRemaining = (ownWorkedSeconds / completedChecklistCount) * unfinishedChecklistCount

rollupWorked    = direct task time + recursive child rollupWorked
rollupRemaining = ownRemaining + recursive child forecast remaining
```

An explicit estimate applies only to the current task; forecastable children add independently. Historical pace is the active-day average within the most recent 90 local days, including today, and only converts already-derived remaining seconds into projected active days. Without an explicit estimate, insufficient checklist progress or tracked time produces a missing-requirement state instead of a number.

Parent display: with its own forecast source, show the parent forecast including forecastable children recursively; without one and with exactly one forecastable child branch, show that child directly; with multiple forecastable child branches, show an aggregate parent summary; with no forecastable source, show guidance in task detail. Checklist completion is the only task-level completion/progress semantic and never makes a task unavailable for later work.

Mutation refresh is incremental after initial/full load: `LedgerStore` replaces only segments overlapping invalidated ranges and related sessions; an old segment outside a task's bounded recent set is removed without rebuilding that task's complete history. `ChecklistStore` replaces affected task buckets; `RollupIncrementalIndex` applies segment before/after deltas and recalculates direct tasks plus ancestors. Active and future-ended segments are time-sensitive; forward clock movement reevaluates that bounded set, a backward correction reevaluates all rows. Full-history worked seconds stay exact; only the 90-day pace buckets are bounded. Recurrence lifecycle and Pomodoro short-cancel policy query only active rows/current-run sessions rather than materializing closed history. Performance changes on these paths require observable bounded-query/incremental-equivalence checks plus seeded Release Instruments evidence; host wall-clock microbenchmarks are not permanent correctness contracts.

Task/category/Checklist/Pomodoro visual editors share one `SymbolColorWell` boundary: iOS/iPadOS keep the scene-owned SwiftUI popover and scaled public Blossom Core; macOS reuses the same public Core but `MacBlossomColorPresenter` owns only AppKit positioning/dismissal (anchor `NSView` converted through its owner window into screen coordinates; the transparent picker is that owner's child window). It must not infer coordinates from `NSApp.keyWindow`, duplicate geometry, or change six-digit sRGB persistence.

Checklist quick add/completion/reorder share the store-scoped mutation lock with task-editor replacement and lifecycle writes. UI registers native `onMove` continuously (no separate edit mode); incomplete and completed groups are separate ordering scopes. The coordinator creates a fresh context after acquiring the lock, rejects stale baselines, validates the canonical task before inserting related rows, and derives refresh ancestors from the fresh hierarchy. Task-editor checklist deletion is a draft mutation keyed by the row's stable UUID; iOS/iPadOS expose Delete through a leading-edge `swipeActions` with full-swipe disabled, and touch long press / macOS right-click expose the same command through the context menu. Task-category create/update/delete and task-draft assignment share that lock domain with immutable baselines and same-transaction assignment cleanup.

`AnalyticsStore` caches overview/task snapshots by range, true calendar period start, current local-day identity, and optional minute live bucket (only when an active segment overlaps the range). Ledger events invalidate snapshots and only intersecting day buckets; every cache is disposable and reconstructable from ledger facts. Analytics presentation keeps the loaded snapshot and its request as one atomic value: an exact cache hit may render synchronously; once a snapshot has displayed, a cold range/interval switch preserves section shells while redacting/disabling/accessibility-hiding old data, and only the first load may replace content with a loading row. The refresh indicator has a fixed layout slot, and cancellation is checked before the single presentation publish. Activity Heatmaps are a standalone typed destination reusing the Today Heatmap projection and Settings range. Analytics ranking/selections are deterministic (gross, wall, localized title, UUID; earliest local peak hour; latest valid session snapshot) — collection/dictionary order is never product semantics.

## Ledger Query Strategy

Initial/full range queries use SwiftData predicates plus deterministic clipping. Normal mutations use `LedgerStore` day/ID indexes to fetch and replace only segments overlapping an invalidation range, update related session IDs, and emit coalesced `LedgerSegmentChange` values. `AnalyticsStore` caches daily summaries plus overview/task snapshots by range and evaluation key (complete calendar interval, current local-day identity, optional live-minute key only when an active segment overlaps).

1. Keep raw `TimeSegment` as the source of truth; rebuild buckets when summary rules change.
2. Route every persisted-time read through `TrackedTimePolicy` with an explicit reference `now`; never derive duration from raw `endedAt` in a view, formatter, cache, or store.
3. Reject local future writes; retain and safely clip clock-skewed CloudKit/import/legacy facts.
4. Keep active-timer queries direct and fresh; active timers never wait for a cache.
5. Coalesce only a new ordinary stopwatch Start with the immediately preceding same-task singleton session when the non-overlapping gap is strictly below 60 seconds and contains no other visible work; keep a new active segment identity, tombstone the predecessor, and never apply this to Manual/Calendar/Pomodoro/`replaceAll`/import/read paths.
6. Invalidate full overview/task snapshots after relevant facts change; invalidate only intersecting day buckets from `ledgerChanged` ranges.
7. Keep rollup full-history totals exact; only forecast pace is bounded to 90 local days.
8. Preserve the 50,000-segment single-mutation budget and equality with a full rebuild (including time advance and clock rewind); ordinary rapid restart stays store-query bounded (reuse the coordinator's canonical active snapshot, fetch the open Pomodoro working set once, no full-history scan or N+1 queries).

## Schema Evolution Rules

SwiftData models must stay compatible with existing local/iCloud stores. New features should not casually add columns to `TaskNode`, `TimeSession`, `TimeSegment`, or other fact-layer models.

1. Prefer extension models with explicit UUID references (e.g. `TaskCategory` + `TaskCategoryAssignment` instead of `categoryID` on `TaskNode`).
2. If a core model truly needs a new field, add a new schema version, make the field optional or give a stable default, and add a migration/compatibility test before wiring UI.
3. Keep old `VersionedSchema` definitions with their historical model shape; if the live model gains a field, older versions resolve it to a frozen legacy snapshot type (see the V13 `ChecklistItem` snapshot behind V14).
4. Never reuse a schema version identifier for a different model shape; if a bad schema may have been installed, the next compatible schema uses a new version number.
5. Keep `id`, timestamps, `deletedAt`, `deviceID`, and `clientMutationID` semantics stable on CloudKit-backed models.
6. Every schema change updates `TimeTrackerModelRegistry.cloudSyncedUserModelNames` expectations and adds a test proving old stores still open (or that the change is isolated in a new extension model).

Real V8/V9/V11/V12 disk fixtures must continue to open. Removing a reconstructable cache must never remove its source facts; adding sync identity must not derive it from user text; a background materializer must treat tombstones and staged partial rows as authoritative claims rather than silently repairing them. The guiding principle is forward migration: existing user data opens first, then new feature data is added in a compatible layer.

## Sync Assumptions

Cross-process file-lock acquisition budgets measure elapsed time with `ContinuousClock`; the store's `flock` loop and sync-conflict state's `lockf` loop reuse the same monotonic deadline primitive. A wall-clock adjustment must never extend or prematurely expire the bounded wait.

iCloud sync is controlled by `AppCloudSync` and the container configuration. Eligible preferences sync through `SyncedPreference`; iCloud enablement, device identity, migration flags, build info, secrets, automatic-AI consent, and CloudKit error text stay local. The app refreshes read models on launch, foreground, SwiftData remote changes, and completed import/export events; consecutive notifications are coalesced and there is no permanent polling loop. Local/Demo/UI Test mutations do not capture conflict snapshots; in CloudKit/recovery mode `StoreDomainEvent` refreshes only affected snapshot domains unless a full baseline/import is required.

Cloud recovery has two intents: automatic fallback uses `reconcileWithCloud` (protect local branch, create fresh cache, wait for authoritative hydration, compare fingerprints without exporting first); explicit "replace iCloud with this device" uses `explicitlyReplaceCloud` and may restore the protected local winner exactly once before export. Upload/download/reconciliation requests are mutually exclusive, and commands from a stale Settings scene are rejected once a recovery container has attached. A physical reset removes SQLite/WAL/SHM under the store mutation lock and durable-root lock.

Diverged local/cloud branches merge automatically before any prompt: `SyncDataSnapshot.mergedForAutoResolution` unions both branches by record identity under the same deterministic LWW ordering (newer `updatedAt`, equal-timestamp tombstone, then `createdAt`, then canonical content bytes; synced preferences merge by logical key). If the merged snapshot equals the cloud branch it is accepted without a restore; otherwise it is validated and restored as local winner, clearing any pending conflict. Only a merge that fails validation/restore surfaces the explicit copy-choice prompt; explicit user-directed replace flows never auto-merge.

Authoritative hydration is a persisted setup-to-initial-import barrier: `CloudRecoveryImportSession` binds one recovery UUID and kind to one store identifier and accepts only successful completed events from the current epoch (setup before import, same store). `CloudRecoveryImportBuffer` observes before `ModelContainer` creation so early events are not lost. Recovery stays read-only until the matching session completes; an incomplete session after a crash triggers another fresh-store reset. Before attaching facade repositories, the startup path must successfully read the authoritative conflict prompt; failure exposes the recovery safety state and returns with startup incomplete so direct commands, migrations, seeding, Pomodoro/background work, and projection publication cannot race an unknown conflict state. Recovery-only store configuration defers every write-side startup effect.

Settings reports recent Cloud activity with a typed `SyncActivityOutcome(kind, completedAt, result)`, not a local refresh timestamp. Only a completed import/export/setup event with no CloudKit error can become success, and only after the local read-model refresh and conflict update also succeed; a remote-store signal alone never claims a completed cloud operation. Account availability is tracked separately. Sync-conflict state locking, the slot manifest, size limits, `prompt()` throwing boundary, and `pendingConflictID` CAS are owned by [AgentDecisions](AgentDecisions.md) AD-023; recovery gating and post-commit projection causes by AD-142.

Snapshot restore treats transport data as untrusted historical input: a pure preflight rejects per-table/aggregate overflow (100,000/table, 250,000 total), duplicate UUIDs, unknown enum raws, malformed preference JSON, provable relationship inconsistencies, and V13 task-progress records whose deterministic identity/canonical day key/timezone/quantity range/rule-goal references do not hold. Missing referenced records stay legal for staged import; a relationship is rejected only when both records exist and disagree. Rejection leaves facts/tombstones unchanged. Per-field byte budgets, the persistent date range, sort-order advanceability, and Pomodoro plan bounds are writer-side contracts enforced at the command/persistence boundary, so preflight does not re-check them per record. This covers explicit `SyncDataSnapshot.restoreAsLocalWinner` calls, not records already materialized by the initial CloudKit import.

One user mutation commits through `ModelContext.performAtomicMutation`; a failure while the initiating Scene refreshes its read models may be reported as "saved but refresh failed," never as rollback. Preference writes add a batch-preparation boundary (see [CodeGuide](CodeGuide.md)); Keychain is outside SwiftData's ACID boundary and compensates separately. Inbox/checklist AI requests send the complete normalized context with no artificial cap and advertise the complete SF Symbols catalogue; real boundaries are opaque model IDs (256 UTF-8 bytes), bounded endpoint/API-key config, 2 MiB responses, and 512-byte reason fields. `LLMChatRequestPolicy` is the single provider-control boundary (DeepSeek V4 thinking/effort/temperature/reasoning passback). Full AI planning baseline/Apply, CAS, and tool-protocol rules are owned by [AgentDecisions](AgentDecisions.md) AD-132/AD-133 and [CodeGuide](CodeGuide.md).

App Intents use the application model container and the same store-scoped commands. After a commit, `SystemActionPostCommitEffects` queues sibling-scene read-model convergence and submits exact outcome events to the same projection scheduler used by Scene and Watch mutations, then returns without waiting. System input routing is lifecycle-safe and bounded: `AppDeepLinkRouter` validates a small URL grammar before execution/enqueue; each scene owns a semantic-deduplicating `PendingDeepLinkQueue` capped at 16 and drains it only after repositories are ready and its typed presentation slot is available; `WatchCommandRouter` owns the process-wide Watch bridge callback but retains scene stores weakly, prefers the most recently active scene, removes released registrations, and uninstalls the callback when no scene remains.

System-surface projections are untrusted transport boundaries: Widget/Watch producers cap record counts, clamp summaries and anomalous timer starts, and shorten projected title/path/style at Unicode boundaries with a 128 KiB aggregate text budget; `SharedWidgetSnapshotStore` validates before save and after load, rejecting >256 KiB, capping active/recent at 64 each, and requiring bounded fields/time and unique IDs (invalid loads are corrupted, not empty); `WatchStateSnapshot` allows at most 64 active/256 recent under equivalent validation; the Watch pending/failed command queues each cap at 64 with a 512 KiB encoded queue. Projection shaping changes only extension DTOs.

Persistent deduplication and synced preferences use deterministic LWW: newer `updatedAt` wins; at an equal timestamp a tombstone wins; then `createdAt`, `deviceID`, `clientMutationID`, or a stable `TimeSegment` content key. Select the winner before filtering tombstones.

## UI Structure

`AppRootView` is the only root-shell decision boundary: it measures the actual scene width and combines it with the system horizontal size class (below 720 pt or compact → shared tab shell; otherwise shared sidebar/detail shell). The app-level Store and scene-owned presentation/feedback routers stay above that branch. Feature views consume `layoutShell` or their own finite container width and never read device idiom, screen model, or platform identity to choose product layout; conditional compilation is limited to unavailable APIs, native scene/menu/window plumbing, system chrome, input modality, and framework capabilities. Equal product roles share semantic typography across platforms; platform-keyed touch-target sizing stays because it encodes input modality.

Task navigation has one store-owned route: the regular shell selects detail-column content directly (replacing task A with task B must not clear through the Tasks root first), while the compact shell mirrors the same route into a typed `NavigationStack` path so system Back can request a guarded close. Every detail dismissal is fenced by the creating task identity; unsaved-editor confirmation completes before a replacement or close mutates the route.

Application data is app-scoped; presentation and transient feedback are scene-scoped. Each visible scene owns one `AppPresentationRouter`/`AppPresentationHost` pair for typed sheets and one `AppSceneFeedbackRouter`/`AppSceneFeedbackHost` pair for alerts (FIFO, dismissing only the matching feedback UUID). Settings export/database maintenance/sync recovery use throwing boundaries; successes stay inline and failures enter only the initiating scene. The macOS app owns one main `Window` and one application-level `TimeTrackerStore`; the standard Settings scene receives that same store. The macOS root separately owns one `MacKeyboardShortcutSettings` observable injected into the main scene, Settings, and `TimeTrackerCommands`; its device-local state is outside `TimeTrackerStore`, SwiftData, CloudKit, and the `KeyboardShortcuts.Name` global-hotkey path.

`SyncConflictService.swift` owns bootstrap/prompt assembly; focused extensions own local mutation, Cloud import/export, recovery/resolution, state persistence/lock/locations/slots, and filtered export encoding. `SyncDataSnapshot` plus capture/preflight/domain-restore files own one validated atomic domain mapping, while record files own versioned transport DTOs (transport/restore representations only; business truth stays the SwiftData domain model).

The app source is organized by ownership; new files land next to the domain they affect. The concrete folder map, placement rules, naming rules, and current responsibility concentrations are maintained in [Project Map](ProjectMap.md). Xcode shared schemes are source-controlled under `timetracker.xcodeproj/xcshareddata/xcschemes`; do not rely on per-user scheme state.

## Shared UI Logic

`TimelineLayoutEngine` owns Today timeline clipping, display interval, and lane allocation — keep this logic out of SwiftUI view bodies so chart behavior is testable without launching the app. Task-tree display is derived UI state: the durable hierarchy remains `parentID` plus repairable `depth`/canonical `path`, and the Tasks screen derives a flat list of visible rows and title paths so native list interactions remain reliable without recursive SwiftUI identity.

Task-editor conflict recovery is typed and session-local: a stale draft never retries against its old baseline; the editor may retain the user's current draft or, after explicit confirmation, replace it with a freshly projected baseline and rebuilt parent candidates (which also becomes the new discard baseline). Crash/termination recovery is a single local mirror of the unsaved draft: autosave is the only writer of persisted facts, and reopening the task restores the newest mirror silently behind one inline notice with no separate recovery-management surface.

## Testing Strategy

Prefer behavior tests over source-string scans; the full policy (baseline commands, required coverage, UI testing, performance budgets, resource ownership) lives in [Testing](Testing.md). Before merging a feature:

1. Can the feature be found from the ownership table?
2. Does every durable write go through a command or repository boundary?
3. Does the view avoid expensive work in `body`?
4. Are active timers still derived from open `TimeSegment` rows?
5. Are historical/imported tombstones and their ledger rows handled intentionally without reintroducing a product Delete action?
6. Does iCloud remote import coalesce refresh work?
7. Are compact iPhone, iPad split view, and macOS sidebar/detail layouts considered separately?
8. Are all strings localized in English, Simplified Chinese, and Traditional Chinese?
9. Are tests behavior-based rather than fragile source scans?
10. Did verification match the change's risk (relevant signed tests/builds, normal-size screenshots for visual flows, Instruments only for performance-sensitive work), is evidence recorded in the shipping commit/PR, and are all owned simulator/test/trace resources released?

## Version And Build Info

Settings includes an About section with the app icon, `MARKETING_VERSION`, build number, Git branch, short commit hash, and build date. The app target writes `AppBuildInfo.plist` during the build via the `Write Build Info` phase (a thin wrapper around the `timetracker_tools.write_build_info_plist` Python module; see [Versioning](Versioning.md)); do not hard-code Git metadata in Swift source. Versions are bumped manually before a release with `make bump-version`; the pre-commit hook only enforces localization parity.
