# Time Tracker Architecture

Status: current implementation and architecture guardrails

Reviewed: 2026-08-02

Time Tracker is a local-first SwiftUI app whose source of truth is the time ledger, not a screen-level timer flag. This document answers two practical questions:

1. Where does a new feature belong?
2. Which boundary prevents UI, sync, forecast, and ledger bugs from spreading?

For the practical "which file do I open first?" map, start with [Project Map](ProjectMap.md). UI guardrails live in [UI Design Notes](UI-Design.md), localization rules in [Localization](Localization.md), and verification policy in [Testing](Testing.md).

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

Views may format and present state, but durable business actions should go through the store and use cases. `TimeTrackerStore` is a `@MainActor @Observable` facade split into lifecycle, read-model, analytics, maintenance, and domain command extensions: roots own it with `@State`, views read the injected reference, and only binding sites create `@Bindable`. Do not reintroduce `ObservableObject/@Published` on the facade or store action closures in focused values. This keeps iOS, macOS, widgets, Live Activities, and Watch commands from duplicating timer logic.

The product rule is unchanged: `TimeSegment` is the fact layer. Tasks, checklist items, pomodoro runs, settings, summaries, and forecasts are all supporting structures around that ledger.

### Write Flow

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

Example: a checklist row tap goes through `TimeTrackerStore.toggleChecklistItem(...)` → `ChecklistCommandHandler.toggle(...)` → one SwiftData update → `checklistChanged(taskID, affectedAncestorIDs)` → Checklist, Rollup, and Analytics refresh. Checklist forecast invalidation is not optional: toggling, adding, renaming, deleting, or reordering a checklist item must update the affected task branch immediately because visible remaining time is a direct function of checklist progress.

### Read Flow

```text
Repository query
  -> domain-sized snapshot
  -> pure services derive secondary state
  -> domain store exposes immutable view state
  -> SwiftUI view renders
```

Views should render existing snapshots. They should not calculate analytics, tree rollups, or forecast decisions inside `body`. `TimelineView` is acceptable for clock labels; it is not a place to rebuild analytics.

Responsive geometry is also an invalidation boundary. `AppRootView` retains only
the compact/regular width band because the product shell has one 720 pt
breakpoint; raw live-resize width must not enter root state. The desktop Today
page maps raw geometry to `HomeViewportMeasurement`, whose 8 pt buckets are
anchored at every semantic breakpoint and capped once the 1180 pt content width
is reached. Primary regular-shell destinations replace content inside one stable
outer `NavigationStack`; a page switch must not reconstruct navigation
infrastructure. Domain snapshots and routes remain above all three presentation
choices.

## Domain Stores and Refresh

Domain stores own state snapshots:

- `TaskStore` owns task tree snapshots.
- `LedgerStore` owns active, today, history, segment/day/session indexes and mutation deltas.
- `ChecklistStore` owns global bootstrap plus task-scoped item/visual replacement indexes.
- `RollupStore` owns exact worked totals, checklist progress, forecast state and the bounded 90-local-day pace index.
- `AnalyticsStore` owns pure read-model overview/task snapshot caches keyed by full period, current local day, and optional live-minute identity, plus disposable ledger day buckets; cache operations are split into `AnalyticsStore+Caching`, and cached snapshots do not retain SwiftData segment objects.
- `PreferenceStore` owns synced preference snapshots.

`StoreRefreshCoordinator` owns refresh sequencing after command events. Its committed-mutation boundary first refreshes only the current scene's affected read models and scene-local selection/suggestion state. The facade does not decide the order of task, ledger, checklist, rollup, or analytics refresh inline.

Every committed Scene, App Intent, and Watch mutation submits one receipt to the shared `CommittedMutationSystemProjectionScheduler` for its physical `TimerStoreScope`. The receipt carries the command's exact `StoreDomainEvent` set plus any forced current-state sink, so an iPhone-handled Watch command outcome and its real mutation events cannot become separate generations. The caller does not wait for sync snapshot, Widget, Watch, or Live Activity publication: a Scene first refreshes only its own affected read models, while App Intent and Watch return after the durable command/terminal result. A queued next-MainActor-turn `StoreMutationBroadcaster` independently converges sibling scenes as read-only consumers, so they do not repeat sync recording, system publication, or suggestion work.

The scheduler owns four failure-isolated lanes: sync snapshot, Widget, Watch, and Live Activity. A short-lived persistent-history driver pages chronological transactions, maps changed entity names to conservative ID-free events, and acknowledges each lane's opaque cursor only after that lane succeeds. Sync snapshot consumes only `localMutation` domains; the three system surfaces consume every relevant author. A worker opens a fresh background `@ModelActor` context and materializes one immutable committed-fact DTO bundle for the three surfaces per generation; Widget App Group I/O is serialized by its own actor, while only framework publication returns to the required actor. Work that has started finishes, pending generations coalesce, receipt/event bookkeeping is bounded, and an oversized set degrades safely to `.fullSync`. Forced current-state publication can run one selected sink even with empty or unrelated history; success may acknowledge the genuine scanned frontier but never fabricates a history transaction or `.fullSync` event. Every durable SwiftData transaction therefore needs a stable outer author: business writes use `localMutation`, sync restore uses `syncReconciliation`, and startup migration/seed uses `bootstrapMaintenance`; missing or unknown authors are never inferred as local work.

`StoreDomainEvent` is the write-side invalidation language. Commands emit what happened, not which views should refresh:

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

`StoreRefreshPlanner` converts those events into a `StoreRefreshPlan`, keeping refresh behavior testable. When the task topology is stable, `LedgerStore` fetches only invalidated ranges, `ChecklistStore` replaces only affected task buckets, and `RollupStore` consumes segment before/after deltas plus direct/ancestor IDs. Active and future-ended segments form the time-sensitive set for forward clock movement; a backward clock correction stays in the same pipeline but reevaluates every segment because candidates cannot be narrowed safely. `AnalyticsStore` invalidates snapshot caches and only the day buckets intersecting ledger ranges. Full structural rebuild remains the explicit path for startup, topology/full-sync changes, remote import without a safe scope, and calendar/time-zone changes.

External CloudKit changes enter the same pipeline through remote-store and completed import/export notifications. The observer coalesces bursts before emitting `remoteImportCompleted`; launch, foreground activation, and completed remote import also enqueue history-backed projection catch-up after the ordinary read-model refresh. Launch additionally forces one Watch current-state publication so a forced-only terminal update interrupted by process exit converges on restart. There is no permanent foreground polling timer.

## Feature Ownership Map

| Feature | Durable model | Write owner | Snapshot owner | Pure services | UI owner |
| --- | --- | --- | --- | --- | --- |
| Start, stop, and rapid-restart timer | `TimeSession`, `TimeSegment` | `StoreScopedTimerCommandCoordinator`, `TimerCommandHandler`, time-tracking repository | `LedgerStore`, `RollupStore` | `TimerAdmissionPolicy`, `TimerRapidRestartPolicy`, `LedgerSummaryService` | `Features/Home`, `Features/Tasks/Detail` |
| Manual time and segment editing | `TimeSession`, `TimeSegment` | `LedgerCommandHandler` | `LedgerStore`, `AnalyticsStore` | `TimelineLayoutEngine` | `Features/Ledger`, `Features/Home` |
| Task edit, move, archive, restore | `TaskNode` | `TaskDraftCommandHandler` | `TaskStore`, `RollupStore` | `TaskTreeService`, `TaskTreeFlattener`, `TaskHierarchyMetadataService`, `TaskTrackingAvailabilityService` | `Features/Tasks`, `Features/Sidebar` |
| Daily recurrence and quantity configuration | `TaskRecurrenceRule`, `TaskRecurrenceOccurrence`, `TaskQuantityGoal`, `TaskQuantityEntry`, generated `TaskNode` | `StoreScopedTaskRecurrenceCommandCoordinator`, task recurrence repository | `TaskStore`, facade recurrence snapshots | `TaskRecurrenceDayKey`, `TaskTrackingAvailabilityService` | `Features/Tasks/Editor`, `Features/Tasks/Detail` |
| Task categories | `TaskCategory`, `TaskCategoryAssignment` | task category commands, task draft command | `TaskStore`, `RollupStore` | `TaskTreeService` | `Features/Tasks`, `Features/Sidebar` |
| Checklist | `ChecklistItem` | `ChecklistCommandHandler` | `ChecklistStore`, `RollupStore` | `ChecklistDraftService`, `TaskRollupService` | `Features/Tasks/Editor`, `Features/Tasks/Detail` |
| Forecast | none, derived | none | `RollupStore` | `TaskRollupService`, `ForecastDisplayService` | `Features/Home`, `Features/Analytics`, `Features/Tasks/Detail` |
| Pomodoro | `PomodoroRun`, ledger models | `PomodoroCommandHandler`, ledger/task commands | `LedgerStore`, Pomodoro read models | persisted-phase deadline/reconciliation helpers | `Features/Pomodoro` |
| Analytics | none, derived | none | `AnalyticsStore` | `AnalyticsEngine`, `TimeAggregationService` | `Features/Analytics` |
| Synced settings | `SyncedPreference` | `PreferenceCommandHandler` | `PreferenceStore` | `PreferenceJSON`, `AppPreferenceValueSanitizer`, `SyncedPreferenceService` | `Features/Settings` |
| macOS menu shortcuts | device-local `MacKeyboardShortcutPreferencePayload` | `MacKeyboardShortcutPreferenceCommand` | `UserDefaultsMacKeyboardShortcutPreferenceStore` | `KeyboardShortcuts` recorder/conversion plus app conflict policy | `Features/Settings/MacKeyboardShortcutSettingsSection`, `App/TimeTrackerCommands` |
| Countdown events | `CountdownEvent` | `CountdownCommandHandler` | `TimeTrackerStore` countdown snapshot | date formatting helpers | `Features/Home`, `Features/Settings` |
| JSON export | business snapshot + device-local Health replica | facade maintenance command | `AppleHealthReplicaRepository` read snapshot | `UserDataExport` envelope encoding | `Features/Settings/Support/SettingsExportDocument` |
| Tombstone maintenance | destructive maintenance, Demo/UI Test only | maintenance facade | affected stores | `DatabaseMaintenanceService` | hidden for production stores |
| Live Activity | ledger snapshot | shared ledger commands/intents | `LedgerStore` | shared activity attributes | extension UI |

## Domain Model

`TaskNode` represents a task tree node. Tasks can contain child tasks; ordinary visible tasks can be timed, while recurrence templates are organization-only containers whose generated daily children own real work. `parentID` is the hierarchy authority; `depth` is repairable metadata; `path` is the stable canonical locator `/<task UUID>`, not a persisted ancestor chain or user-facing title path. `TaskTreeService` derives display paths from current titles and caps them at six components. Startup, task refresh, and sync restore repair missing parents/cycles deterministically before rendering. Moving a task prevents cycles and updates only metadata that actually changed.

Tasks no longer have a product-facing workflow status. `TaskNode.statusRaw` remains only because V4-era schemas, existing local/CloudKit records, and sync snapshots already contain it. Restore and compatibility boundaries continue accepting `planned`, `active`, `completed`, and `archived` without a migration or bulk CloudKit rewrite. The first three values are inert compatibility bytes; only the historical `archived` value participates in archive compatibility.

`TimeSession` represents one work intention. `TimeSegment` represents actual worked time and is the ledger fact used for analytics. Active work has an open segment; stopping closes the segment and its session.

Ordinary stopwatch restarts use one narrow canonicalization rule. When the same task is restarted from an ordinary timer source in strictly less than 60 seconds, the gap contains no other visible work, and the prior singleton session has no canonical Pomodoro relationship, the fresh store-scoped Start keeps that session, tombstones its closed segment, and creates a new active segment ID whose start extends to the original start. The gap therefore counts as continuous work. Exact 60-second gaps, overlap/clock rollback, `replaceAll`, Manual, Calendar, and Pomodoro records remain separate. The old segment ID is never reopened, so a stale exact Stop cannot close the new timer. The mutation strictly advances beyond any observed future-dated session/segment winner and publishes both the replacement's visible invalidation and the predecessor's ranged history invalidation, preventing Cloud redelivery or a midnight boundary from leaving the old fact visible.

`TrackedTimePolicy` is the single read boundary for persisted tracked time. For a reference `now`, the effective end is `min(endedAt ?? now, now)`; the resulting interval is then intersected with the requested half-open range. A segment starting at or after `now`, or with no positive intersection, contributes zero. Local manual-entry and segment-update writes reject a future end or a future open start with typed `TimeTrackingRepositoryError.futureTime`. Clock-skewed CloudKit/import/legacy facts are retained rather than migrated away, but every aggregation, forecast, timeline, cache, rollup, and range query must clip them through this policy.

`PomodoroRun` represents the pomodoro workflow. Its persisted phase start plus planned duration derives `phaseDeadline`; startup/foreground/scheduled reconciliation clips expired focus ledger records to that deadline. Break completion remains an explicit user action so background suspension never creates a new focus segment. Segment edit/delete, timer stop, and task-archive admission must keep the run and ledger lifecycle consistent.

`CountdownEvent` stores optional user-defined date milestones. iPhone, iPad, and macOS all derive their Today countdown presentation from the same store state.

`SyncedPreference` stores sync-eligible user-facing settings as JSON values in SwiftData so they travel through the same iCloud-backed store as tasks and timers. The iCloud enablement flag is different: it is a device-local `UserDefaults` startup configuration because the model container must know whether to start in CloudKit mode before SwiftData can fetch cloud values. It is excluded from `SyncedPreference`, conflict snapshots, and export/restore boundaries, and changes take effect on the next launch.

`ChecklistItem` belongs to a `TaskNode`, but it is not a task. Checklist items are the product-level completion and progress signal and can provide forecast evidence; completing them never locks the task or blocks later work. Timers, manual entries, pomodoros, widgets, and Live Activities still attach time to the task itself.

Checklist visual suggestion is a latest-input-wins side effect, not part of draft
identity. The facade waits for a short stable-input window, counts pending and
in-flight work against the same concurrency limit, and cancels work whose title,
task context, configuration, or item/visual revision is no longer current.
Completion still passes through the store-scoped fresh-context command boundary.
An unchanged checklist save must not rotate content or visual revisions, and
writing the same icon/color is a durable no-op. Task editing rebases a resulting
visual-only revision onto the existing row identities and user text; it never
replaces the active field, dismisses focus, or overwrites a locally edited visual.

`TaskRecurrenceRule` turns one task into a daily template in a frozen rule timezone. `StoreScopedTaskRecurrenceCommandCoordinator` materializes at most the current local day, never backfills missed dates, and permanently skips days while a rule or template branch is unavailable. The deterministic `TaskRecurrenceOccurrence` is both the idempotency claim and the link to a deterministic generated child task. Physical claims, tombstones, and staged partial CloudKit rows veto background reconstruction, while replay preserves user edits to an existing child. A template remains a legal parent/content task but is excluded from Timer, Pomodoro, manual-segment, and App Intent direct-work admission; its generated child is the work-bearing task. `TaskQuantityGoal` is copied as configuration to a new child, but quantity entries are not copied between days.

`InboxItem` owns an opaque suggestion context UUID plus a title-revision UUID. The context survives a physical SwiftData row rebuild, while a real title edit rotates only the revision. Dismissing a suggestion records that revision, so another synced copy of the same logical item cannot resurrect it; separately created items remain distinct even when their titles match. These identifiers are random or legacy-record UUIDs, never hashes or normalized projections of user text. Logical deletion/restoration and content fields follow last-write-wins with tombstones winning ties; dismissal is a separate field-level OR only for the exact context/revision. Thus an older marker survives sync without rolling back newer notes, completion metadata or ordering, and never crosses a title revision. `InboxCaptureReceipt` is deliberately separate: only a caller-provided external `(origin, UUID)` key can replay one capture; title, timestamp and model IDs never act as a receipt. The item and receipt commit in one store transaction, and V11 snapshot/restore preserves that acknowledgement. Multiple active receipts for one external key must describe the same payload and Inbox item; a disagreement is an explicit sync conflict, never a time-ordered replay choice.

Task visibility and work eligibility derive only from reversible archive markers and historical tombstones. A task is archived when `archivedAt != nil` or its compatibility raw value is `archived`; archive commands write both markers so older clients still understand the result. Archived or tombstoned branches are hidden and cannot accept new work. Archiving a branch requires its active timers and Pomodoro work to stop first. Legacy `planned`, `active`, and `completed` raw values do not change visibility, editing, hierarchy, or work eligibility. Tombstone sync semantics and historical ledger ownership remain unchanged even though ordinary task Delete is no longer a product action.

The current SwiftData schema is V14 (`1.13.0`). V9 removed the persisted `DailySummary` derived cache through a lightweight V8→V9 migration. V10 adds optional opaque Inbox suggestion identity fields; the V9→V10 migration deterministically initializes legacy rows and preserves the old "generated with no active suggestion" dismissal state. V11 adds durable Inbox capture receipts, and V12 persists the Inbox suggestion destination kind. V13 adds recurrence rules, materialization receipts, quantity goals, and additive quantity entries through a lightweight V12→V13 migration. V14 adds `ChecklistItem.sortOrderBeforeCompletion` through a lightweight V13→V14 migration; V13-and-older schemas resolve `ChecklistItem` to a frozen V13 snapshot so installed stores keep opening. Rule, receipt, generated-task, and goal identities use frozen deterministic UUIDv8 domains so retries and independent devices converge without CloudKit uniqueness constraints. The V13/V14 snapshot tables are optional only for backward compatibility: a missing key means unknown legacy state, while an explicit empty array authoritatively clears that table. Legacy Inbox model shapes remain frozen for migration, and current analytics still creates disposable `DailySummarySnapshot` values from ledger facts.

## Forecasting and Analytics

Forecasting is local and explainable. `TaskRollupService` recursively combines direct task time, an explicit task estimate or checklist evidence, and direct child-task rollups. `ForecastDisplayService` decides whether Home, Analytics, and Task Detail should show the selected task, drill into one forecastable child task, or show a parent summary. `AnalyticsEngine` owns pure date/range aggregation for overview metrics, hourly activity, and daily/monthly chart points.

The current task's explicit estimate takes precedence over checklist inference. `TaskEstimatePolicy` accepts `0...600` minutes, treats zero as absent, and clamps positive legacy values to 36,000 seconds. Checklist items use an equal-weight fallback only when there is no explicit estimate:

```text
if every checklist item is completed:
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

Checklist completion is the only task-level completion/progress semantic and never makes a task unavailable for later work. The task editor, rows, and detail surface therefore do not expose a workflow-status picker, status badge, Complete action, or Reopen action.

Mutation refresh is incremental after initial/full load. `LedgerStore` replaces only segments overlapping invalidated ranges and related sessions; an old segment outside a task's bounded recent set is removed without rebuilding and sorting that complete task history. `ChecklistStore` replaces affected task buckets; `RollupIncrementalIndex` applies segment before/after deltas and recalculates direct tasks plus ancestors. Active and future-ended segments are time-sensitive: forward clock movement reevaluates that bounded set, while a backward wall-clock correction reevaluates all ledger rows because a previously completed row can cross the reference boundary again. Full-history worked seconds remain exact, while only the 90-day pace buckets are bounded. Recurrence lifecycle state discovers active work with active-row predicates plus canonical-ID resolution rather than materializing closed ledger history, and Pomodoro short-cancel policy queries only the current run's session. Timer, Pomodoro, and segment admission resolve only the target task, its visible ancestor branch, target-related recurrence claims, and the one synced admission preference; unrelated task and preference rows are never materialized inside the serialized writer boundary. Performance changes on these paths require observable bounded-query or incremental-equivalence checks plus seeded Release Instruments evidence; host wall-clock microbenchmarks are not permanent correctness contracts.

The deterministic Apple Health task catalogue is ordinary Task/Category navigation metadata, not protected Health sample data. Reconciliation runs before the optional timeline-read gate. These fixed sync-only rows are not user-owned tasks: a confirmed tombstone for a canonical Category, Task, or Assignment is restored with a strictly newer active replacement even when it arrived from CloudKit and the current device has no device-local Clear All receipt. A missing row accompanied by a local receipt remains pending until its tombstone arrives, so a seed-timestamp recreation cannot lose to a delayed delete. Archiving remains distinct from deletion and is preserved. If CloudKit, another scene, or another sibling context has already committed the canonical catalogue, a no-op reconciliation must still refresh the current scene's task read models. This is convergence-only work: it does not record another sync mutation, request Health authorization, fetch Health samples, or start post-refresh suggestion/system-surface effects.

Protected Health samples live in a separate `AppleHealthReplicaSchemaV1` SwiftData store with CloudKit disabled. `AppleHealthReplicaRepository` is its sole persistence owner; incremental apply fetches only changed/deleted UUIDs in bounded predicate chunks, and interval snapshots push overlap predicates into SwiftData instead of materializing the full replica. Apply and snapshot paths expose OS signpost intervals for Release profiling. `AppleHealthReplicaSyncService` supplies saved workout/sleep anchors to the HealthKit change reader and commits both streams' upserts, explicit deletions, anchors, and successful-sync metadata only after both queries succeed. The service tracks dirty generations and coalesces concurrent consumers onto one anchored sync; a clean generation serves ordinary range and analytics projections directly from the local replica. Startup demand, foreground entry, explicit retry/refresh, authorization, Clear All, and `HKObserverQuery` change delivery invalidate the generation. Registering observer/background delivery is an idempotent store-owned lifetime task and never gates the initial anchored sync or its terminal UI state. Observer completion waits for the anchored refresh, then advances a store revision so visible timeline and task analytics re-project immutable local snapshots without issuing a second HealthKit query. There is no timer-driven HealthKit polling. The repository preserves HealthKit point samples whose start and end dates are equal so their anchors can advance; reverse intervals remain invalid and roll back the whole generation. Duration-based timeline and analytics projections ignore zero-width intervals without discarding the source fact. The main V14 registry, `SyncDataSnapshot`, Cloud conflict merge/fingerprint, and restore paths never contain replica models. Hiding the timeline keeps the replica; Clear All removes its records and anchors.

Canonical Apple Health task detail is a read-only analytics projection, not an ordinary task editor. Its visible content composes Summary, Task Analysis, and Recent Records only; range and historical-period navigation are children of Task Analysis. The canonical catalogue identity bypasses ordinary identity/editing, availability explanation, quantity, heatmap tracking, forecast, toolbar mutation, autosave failure, and draft-recovery presentation. Ordinary task composition remains independent of analytics readiness.

Task, category, Checklist, and Pomodoro visual editors share one `SymbolColorWell` and one `BlossomColorPickerModel` presentation boundary. iOS/iPadOS keep the scene-owned SwiftUI popover and scaled public Blossom Core. macOS also reuses the public Core, but its thin `MacBlossomColorPresenter` owns only AppKit positioning and dismissal: an anchor `NSView` is converted through its actual owner window into screen coordinates, and the transparent picker is attached as that owner's child window. It must not infer coordinates from `NSApp.keyWindow`, duplicate Blossom geometry, or change six-digit sRGB persistence. Screen-edge clamping, owner close, app deactivation, outside click, and SwiftUI disappearance are presentation lifecycle concerns, not color-domain behavior.

Checklist quick add, completion, and reorder commands share the store-scoped mutation lock with task-editor replacement and task lifecycle writes. Checklist UI registers native `onMove` continuously, so direct row drag reaches the same draft/command boundary without a separate edit-mode state; incomplete and completed groups remain separate ordering scopes. The coordinator creates a fresh context after acquiring the lock, rejects stale item/order mutation baselines, validates the canonical task before inserting related rows, and derives refresh ancestors from the fresh hierarchy. This prevents stale scenes from resurrecting checklist tombstones, creating checklist/visual orphans, overwriting newer completion state, or invalidating only an obsolete parent chain.

Task-editor checklist deletion is a draft mutation keyed by the row's stable UUID, not a direct View write or a captured source index. The shared row has no permanent Delete or More button. iOS/iPadOS expose Delete through a leading-edge `swipeActions` button, which is revealed by a rightward swipe in left-to-right layouts, with full-swipe disabled; touch long press and macOS right-click expose the same command through the row context menu. Saving continues through task-editor replacement and `ChecklistDraftService`, so removed persisted rows receive the existing tombstone/visual cleanup semantics and stale baselines remain rejected.

Task-category create, update, delete, and task-draft assignment also share that lock domain. Category editors carry an immutable category mutation baseline; stale edit/delete commands are rejected, creation derives ordering from a fresh context, and deletion tombstones every assignment visible inside the same transaction. A task draft cannot assign a category after its deletion, while deletion that follows an assignment observes and removes that assignment. Category ordering and Quick Start pinned ordering use native `ForEach.onMove` without custom up/down buttons. Quick Start translates visible offsets through stable task IDs before updating its complete selection array, so filtered stale or unavailable selections cannot shift the wrong task.

`AnalyticsStore` caches overview and task snapshots by range, true calendar period start, and optional minute live bucket. A live bucket exists only when an active segment overlaps the selected range, so historical views do not recompute for clock ticks. Ledger events invalidate snapshots and only intersecting day buckets; every cache remains disposable and reconstructable from ledger facts.

Analytics presentation keeps the loaded snapshot and its request as one atomic value. An exact evaluation-cache hit may render synchronously. Once any snapshot has displayed, a cold range/interval switch preserves the landing/detail section shells while redacting, disabling, and accessibility-hiding the old data content; only the first load may replace data content with a loading row. Same-period revision or live refresh may keep the real snapshot visible. The refresh indicator has a fixed layout slot, and request cancellation is checked before the single presentation publish.

Activity Heatmaps are an Analytics standalone destination, not an `AnalyticsCategory`. The landing page owns only a typed navigation entry; `AnalyticsHeatmapView` reuses the Today Heatmap projection and its Settings-owned range directly. It therefore does not load an unrelated `AnalyticsSnapshot` or show the Analytics Day/Week/Month controls, and native navigation preserves the landing state on return.

Analytics ranking and single-value selections are deterministic. Task ties resolve by gross time, wall time, localized title, then UUID; peak-hour ties choose the earliest local hour. Deleted-task titles use the latest valid session snapshot by start time, update time, and UUID, shared by task breakdown and overlap participants. Collection input order and dictionary iteration order are never product semantics.

Bounded serialized work is a domain contract. Recurrence state discovers active Segment and Pomodoro work with active-row predicates plus canonical-ID resolution; closed Pomodoro history is never materialized. Quantity-entry partial-import protection queries only the exact deterministic generated task/goal claim with a one-row limit. Checklist reorder passes the task-scoped canonical rows already validated by its mutation baseline into the handler and performs no second global checklist fetch. Performance changes on these paths require durable correctness coverage plus seeded Release Instruments or signpost evidence; wall-clock thresholds are not permanent unit contracts.

## Ledger Query Strategy

Initial/full range queries use SwiftData predicates plus deterministic clipping. Normal mutations use `LedgerStore` day/ID indexes to fetch and replace only segments overlapping `StoreInvalidationRange`, update related session IDs, and emit coalesced `LedgerSegmentChange` values. `AnalyticsStore` caches daily summaries plus full overview/task snapshots by range and `AnalyticsEvaluationCacheKey`: complete calendar interval, current local-day identity, and an optional minute key only when an active segment overlaps that range. The day identity makes idle current weeks/months miss at midnight without making completed history follow the wall clock.

Rules:

1. Keep raw `TimeSegment` as the source of truth and rebuild buckets when summary rules change.
2. Route every persisted-time read through `TrackedTimePolicy` with an explicit reference `now`; never derive duration from raw `endedAt` in a view, formatter, cache, or store.
3. Reject local future writes, but retain and safely clip clock-skewed CloudKit/import/legacy facts.
4. Keep active timer queries direct and fresh; active timers must never wait for a cache.
5. Coalesce only a new ordinary stopwatch Start with the immediately preceding same-task singleton session when the non-overlapping gap is strictly below 60 seconds and contains no other visible work. Keep a new active segment identity, tombstone the predecessor, and never apply this repair to Manual, Calendar, Pomodoro, `replaceAll`, import, or read paths.
6. Invalidate full overview/task snapshots after relevant facts change, and invalidate only intersecting day buckets from `ledgerChanged` ranges.
7. Keep rollup full-history totals exact; only forecast pace is bounded to 90 local days.
8. Preserve the 50,000-segment single-mutation budget and equality with a full rebuild, including time advance and clock rewind. Ordinary rapid restart must also remain store-query bounded: reuse the coordinator's canonical active snapshot, fetch the open Pomodoro working set once before filtering relevant sessions, never scan full history or issue N+1 session queries, and cover the real SwiftData path with a 50,000-row budget.

## Schema Evolution Rules

SwiftData models must stay compatible with existing local and iCloud stores. New features should not casually add columns to `TaskNode`, `TimeSession`, `TimeSegment`, or other fact-layer models.

Rules:

1. Prefer extension models with explicit UUID references for new feature data. Example: task categories use `TaskCategory` plus `TaskCategoryAssignment(taskID, categoryID)` instead of adding `categoryID` to `TaskNode`.
2. If an existing core model truly needs a new persisted field, add a new schema version, make the field optional or give it a stable default, and add a migration/compatibility test before wiring UI.
3. Old `VersionedSchema` definitions must keep their historical model shape. A new feature must not mutate older schema versions by reusing a changed model shape without a migration strategy. If the live model gains a field, older versions resolve that model to a frozen legacy snapshot type (see the V13 `ChecklistItem` snapshot behind V14).
4. Never reuse a schema version identifier for a different model shape. If a bad schema reached a build or branch that may have been installed, the next compatible schema must use a new version number.
5. CloudKit-backed models should keep `id`, timestamps, `deletedAt`, `deviceID`, and `clientMutationID` semantics stable. Synced entities that still expose Delete, authoritative reset, and deduplication use tombstones; ordinary tasks expose Archive/Restore, while `TaskNode.deletedAt` remains compatibility protocol only.
6. Every schema change must update `TimeTrackerModelRegistry.cloudSyncedUserModelNames` expectations and add a test proving old stores can still open or that the change is isolated in a new extension model.

Current examples: V9 (`1.8.0`) removes the derived `DailySummary` cache from the active schema with a lightweight V8→V9 migration. V10 (`1.9.0`) freezes the V9 Inbox model shape and uses a custom V9→V10 migration to initialize optional opaque suggestion context/revision UUIDs while preserving legacy dismissal state. V11 adds durable Inbox capture receipts, V12 persists suggestion destination kind, V13 (`1.12.0`) lightweight-adds recurrence rules, occurrence claims, quantity goals, and additive quantity entries without changing `TaskNode`, and V14 (`1.13.0`) adds `ChecklistItem.sortOrderBeforeCompletion` behind a frozen V13 checklist snapshot. Real V8, V9, V11, and V12 disk fixtures must continue to open. Removing a reconstructable cache must never remove its source facts, adding sync identity must not derive it from user text, and a background materializer must treat tombstones and staged partial rows as authoritative claims rather than silently repairing them.

`TaskNode.statusRaw` is a frozen compatibility field for old schemas, snapshots, and CloudKit records. Preflight continues to accept all four V4 raw values without bulk rewriting existing data. `planned`, `active`, and `completed` have no product behavior. Archive reads accept either `archivedAt` or raw `archived`, while archive writes set both markers for older clients.

The guiding principle is forward migration, not feature rollback: existing user data opens first, then new feature data is added in a compatible layer.

## Task Archive and Tombstone Rules

Ordinary tasks expose one reversible lifecycle: Archive hides a branch, Restore returns it, and active timer/Pomodoro work must stop before Archive can commit. The product does not expose a task Delete command. `TaskNode.deletedAt` remains a compatibility and sync-protocol tombstone for older clients, CloudKit/import records, authoritative reset/restore, and LWW deduplication; these rows stay hidden and cannot receive new work while their historical ledger/Pomodoro facts remain readable. Production Local, iCloud, fallback, and emergency stores never physically purge tombstones: CloudKit has no per-device deletion acknowledgement, so an offline device could otherwise resurrect old rows. Permanent cleanup is available only to isolated Demo/UI Test stores and only for expired tombstone graphs; a temporarily missing parent during staged import is not deletion evidence.

## Sync Assumptions

Cross-process file-lock acquisition budgets measure elapsed time with `ContinuousClock`. The shared store's `flock` loop and sync-conflict state's `lockf` loop reuse the same monotonic deadline primitive while preserving their distinct POSIX contention/error handling and descriptor cleanup. A wall-clock adjustment must never extend or prematurely expire the documented bounded wait.

iCloud sync is controlled by `AppCloudSync` and the SwiftData model container configuration. Eligible user preferences sync through `SyncedPreference`; iCloud enablement, device identity, migration flags, build info, secrets, automatic-AI consent, CloudKit error text, and the Apple Health replica stay local. The replica's “sync” is only incremental refresh from HealthKit on the same device and must never be attached to CloudKit. The app refreshes business read models on launch, foreground, SwiftData remote changes, and completed CloudKit import/export events. Consecutive notifications are coalesced before entering the refresh planner; there is no permanent foreground polling loop. Local/Demo/UI Test mutations do not capture conflict snapshots; in CloudKit/recovery mode `StoreDomainEvent` refreshes only affected snapshot domains unless a full baseline/import is required.

Cloud recovery has two distinct intents. Automatic fallback recovery uses `reconcileWithCloud`: it protects the local branch, creates a fresh CloudKit cache, waits for authoritative hydration, and compares local/cloud fingerprints without exporting first. Explicit “replace iCloud with this device” uses `explicitlyReplaceCloud` and may restore the protected local winner exactly once before export. Upload, download, and reconciliation requests are mutually exclusive, and commands from a stale Settings scene are rejected after a recovery container has attached.

A physical Cloud recovery reset removes SQLite/WAL/SHM under the store mutation lock and durable-root file lock. The projection registry checks its container revision around asynchronous current-state materialization and publication, discards cached DTOs when the registered container changes, and lets the next startup or surface catch-up converge the replacement store. Framework publication is not atomically excluded from a concurrent replacement, so every payload remains idempotent and one sink's failure or retry never acknowledges or blocks a sibling.

Diverged local/cloud branches merge automatically before any prompt. When fingerprints diverge (ordinary import handling, pending-conflict follow-up imports, and fallback reconciliation), `SyncDataSnapshot.mergedForAutoResolution` unions both branches by record identity under the same deterministic LWW ordering used for deduplication — newer `updatedAt` wins, an equal-timestamp tombstone wins, then `createdAt`, then canonical content bytes; synced preferences merge by logical key. If the merged snapshot equals the cloud branch it is accepted without a restore, which also lets the acknowledged baseline advance again; otherwise the merged snapshot is validated and restored as the local winner, clearing any pending conflict. Only a merge that fails validation or restore (for example unrecoverable record content) still surfaces the explicit copy-choice prompt. Explicit user-directed replace flows never auto-merge.

Authoritative hydration is a persisted setup-to-initial-import barrier. `CloudRecoveryImportSession` binds one recovery UUID and kind to one store identifier and accepts only successful completed events from the current epoch. A successful setup must precede a successful import for the same store. `CloudRecoveryImportBuffer` begins observing before `ModelContainer` creation so an early event is not lost, then drains into the scene store after normal observers attach. Recovery remains read-only until the matching session completes; an incomplete session after a crash triggers another fresh-store reset, while a completed session can converge safely after restart. Before the normal startup path attaches facade repositories, it must successfully read the authoritative conflict prompt; failure exposes the existing recovery safety state and returns with startup incomplete, so direct commands, migrations, seeding, Pomodoro/background work, and system projection publication cannot race an unknown conflict state. Recovery-only store configuration likewise defers every write-side startup effect.

Settings reports recent Cloud activity with a typed `SyncActivityOutcome(kind, completedAt, result)`, not a generic local refresh timestamp. Only a completed import, export, or setup event with no CloudKit error can become success, and only after the local read-model refresh and conflict update also succeed. A remote-store signal alone triggers refresh but never claims a completed cloud operation. CloudKit, export-checkpoint, or local post-processing failures remain typed failures with their diagnostic message. Account availability is tracked separately, and a future completion date or one older than the 120-second recent window cannot appear as recent success.

Every `SyncConflictState.json` read-modify-write runs under a recursive process lock plus POSIX `lockf` advisory file lock, so app and Shortcuts processes share one serialized state transaction. JSON replacement is atomic, and the forced-upload mirror cannot override an existing authoritative state. Reads and writes cap authoritative state at 128 MiB and the recovery mirror at 64 MiB. Reads use metadata preflight plus `FileHandle.read(upToCount: limit + 1)` to catch growth between checks without an unbounded allocation. Writes encode and preflight the authoritative state and required mirror before resolving paths, creating directories, or replacing either file; an independent mirror rewrite checks its final bytes again. Either rejection preserves the previous valid files. An oversized or corrupt authoritative file is quarantined for explicit recovery; an oversized or corrupt pending-forced-upload mirror is quarantined and ignored so it cannot block an otherwise usable main store. Oversized quarantine moves the file without loading its complete JSON into memory. Prompt assembly is a throwing read boundary, so an unreadable authoritative state is never reported as “no conflict.” A successful async sync-snapshot recording broadcasts that the prompt may have changed; every Scene reads through one serialized reader with single-flight/trailing coalescing, bounded retry, and latest-request-wins application. A transient read failure preserves the last known prompt and foreground activation retries; successful conflict resolution broadcasts prompt clearing to sibling scenes. Local generations, sync epochs, and per-export event checkpoints ensure only the exact exported fingerprint/generation is acknowledged; failed, stale, or out-of-order callbacks cannot mark newer local work clean. At-least-once replay of an already-recorded local snapshot remains a successful recording but compares the complete postcondition under the same state lock, so it neither advances the generation nor rewrites the manifest or slot files. `pendingConflictID` is also the compare-and-swap token for the exact local/cloud summaries a person reviewed: material changes to either resolution branch rotate it, and resolution validates the expected optional ID under the same state lock before any model, epoch, reset, or state mutation. Scrubbing a legacy excluded preference recomputes the fingerprint and invalidates checkpoints for the old payload. Checkpoints are bounded to 16 entries and 24 hours.

Snapshot restore treats transport data as untrusted historical input. A pure preflight runs before the atomic mutation and rejects per-table/aggregate record overflow, duplicate UUIDs, unknown enum raw values, malformed typed or unknown preference JSON, provable session/task or Inbox suggestion-identity inconsistencies, and V13 task-progress records whose deterministic identity, canonical day key, timezone, quantity range, or provable rule/goal references do not hold. Missing referenced records remain legal for staged CloudKit import; a relationship is rejected only when both records exist and disagree. Rejection leaves existing facts and tombstones unchanged; restore never silently deduplicates invalid transport. Limits are 100,000 records per table and 250,000 total. Per-field text byte budgets (4 KiB titles, 64 KiB notes/reasons, 256-byte compact fields, 256 KiB preference JSON), the persistent date range, sort-order advanceability, and Pomodoro plan bounds are writer-side contracts enforced and tested at the command/persistence boundary, so the restore preflight does not re-check them per record. This boundary covers explicit `SyncDataSnapshot.restoreAsLocalWinner` calls, not records already materialized directly into a SwiftData context by the initial CloudKit import path.

On iOS, the authoritative state, pending forced-upload recovery mirror, and corrupt-state quarantine files use `FileProtectionType.completeUntilFirstUserAuthentication`. They remain unavailable before the first unlock after boot, then stay available to background Shortcuts/CloudKit coordination. This protection applies to sensitive JSON files, not the advisory lock file; macOS does not receive the iOS attribute.

One user mutation is committed through `ModelContext.performAtomicMutation`. Nested command/repository steps defer their saves until the outer boundary and rollback together on failure. A failure while the initiating Scene refreshes its own required read models may be reported as “saved but refresh failed,” never as rollback. Background sync-snapshot, Widget, Watch, and Live Activity failures remain per-sink diagnostics and retry state; they do not write the shared `errorMessage`, reverse the commit, or turn an App Intent/Watch terminal success into a retryable business failure.

Preference writes add a pure batch-preparation boundary before that mutation. `PreferenceJSON` rejects payloads above 256 KiB and decodes each value according to its `AppPreferenceKey`; `PreferenceCommandHandler` canonicalizes the complete batch before fetching or touching any `SyncedPreference`. JSON `null`, malformed syntax, type mismatches, and oversized values therefore cannot leave earlier batch entries pending. The prepared batch is then committed atomically, including standalone command calls. Legacy encoding failures are skipped rather than persisted as `null`.

The editable AI instructions are bounded synced string preferences. The sanitizer normalizes line endings, treats blank input as the built-in default, rejects unsupported control characters, and validates the JSON-encoded value against the existing 256 KiB synced-preference payload boundary at editor, command, JSON, and migration boundaries. It does not impose a smaller request-only limit. The fixed response schemas and safety contracts remain service-owned and are never stored in these editable preferences.

Keychain is intentionally outside SwiftData's ACID boundary. Saving LLM configuration batches endpoint, model list, selected model, and the synced `LLMReasoningEffort` (`high`/`max`, default `high`) into one preference transaction, while preserving the previous Keychain value for compensating restore if that transaction fails. A compensation failure is a separate error, never proof of atomic cross-storage rollback. “Clear all data” likewise clears the Keychain API key and device-local automatic-suggestion consent, attempts to restore them if the SwiftData reset fails, and leaves the device-local iCloud startup switch unchanged.

Inbox and checklist AI requests send the complete normalized context required for the requested decision. Inbox includes every eligible Task and visible Category in deterministic, de-duplicated order; neither flow applies an artificial candidate-count, candidate-JSON, field, prompt, or request-body projection cap. All AI prompts advertise the same complete canonical SF Symbols catalogue used by the on-device picker. Returned task/category IDs must belong to the transmitted candidates, and returned icons must belong to that advertised catalogue. Real persistence and transport boundaries remain enforced: opaque model IDs are validated whole at 256 UTF-8 bytes, endpoint/API-key configuration remains bounded, provider responses remain capped at 2 MiB, and returned reasons are normalized to their persisted 512-byte field. Request construction never mutates canonical Task, Inbox, or Checklist text.

`LLMChatRequestPolicy` is the single provider-control boundary for all three production AI services. For `deepseek-v4-flash` and `deepseek-v4-pro`, it sends `thinking.type=enabled` plus the selected official `reasoning_effort`, omits temperature, and makes task planning omit `tool_choice`; every assistant tool-call message carries its full `reasoning_content` into subsequent rounds. Other model IDs retain the existing compatible temperature and required-tool controls without DeepSeek-specific fields. Changing effort cancels in-flight Inbox/checklist work, and request completion/fingerprints compare effort so a late response cannot cross the configuration boundary.

AI task planning is explicit, complete-context, and proposal-first. Immediately before Generate, `StoreScopedAITaskAtomicMutationCoordinator.captureBaseline()` reads a fresh canonical workspace containing every visible Category, Task, and Checklist item. The provider-facing `AITaskWorkspaceSnapshot` has stable UUIDs, relationships, full Task paths, titles/notes and other editable fields, archived state, quantity goals, and daily recurrence metadata in deterministic order; it does not apply an arbitrary entity-count or path-depth window. Its visible canonical content has a deterministic context fingerprint for correlating one request and review, while local mutation revisions remain beside the snapshot in `AITaskAtomicMutationBaseline` and never enter the provider DTO. The request sheet discloses Category/Task/Checklist counts before sending. The person's request, synced planning instructions, complete workspace, and complete SF Symbols catalogue are encoded without a smaller client request cap. Encoding failure sends no request; provider HTTP 400/413/422 rejection becomes a typed failure that reports the attempted entity counts and actual encoded request bytes instead of dropping facts or silently reverting to the legacy plan format.

Complete AI baseline capture and reviewed Apply execute on the dedicated `StoreScopedAITaskAtomicMutationCoordinator` actor, not MainActor. The actor synchronously holds the existing physical-store mutation lock, creates its fresh context only after acquisition, recaptures the complete baseline, performs exact CAS and validation, and finishes one atomic save or rollback without an actor hop inside the critical section. Only Sendable baseline/plan/outcome values cross the actor boundary; no ModelContext, repository, or persistent model does. `TimeTrackerStore` resumes on MainActor only after commit to refresh read models, publish events, update routing, or expose errors. Cancelling the presenting UI stops it from consuming the result, but does not interrupt or reinterpret a lock-held transaction; a transaction that has begun still reaches one authoritative save or rollback.

`LLMTaskWorkspacePlanningService` conducts an OpenAI-compatible function-calling conversation against a private `AITaskWorkspaceOverlay`. Its non-editable system contract and Task/Checklist tool descriptions define one shared semantic boundary: a root or child Task is an independently timed work unit, while a Checklist item is an untimed completion step inside exactly one Task; the same work must never be represented as both. The editable default repeats that rule and includes a mixed `create_task` / `create_checklist_item` worked example, but user customization cannot remove the fixed boundary. Strict tool schemas require every declared argument and reject additional properties. Read tools list or fetch exact UUIDs; mutation tools can reuse/create/update/delete Categories, create/update/archive Tasks, and create/update/delete Checklist items. The App allocates new UUIDs and returns them in tool results, so later rounds can read their own proposed writes. Task removal always compiles to Archive. Existing Task and Checklist identities are never guessed from names; a normalized Category name can be reused only when it resolves uniquely, and ambiguity fails explicitly. Workspace titles, notes, paths, and other text are untrusted data rather than instructions.

Assistant `tool_calls`, matching tool replies, duplicate call IDs, finish reasons, and reasoning passback are validated. Invalid tool arguments, including an unadvertised icon or color, produce a zero-mutation `{ok:false}` tool result so the same model session can correct them; unknown tools, duplicate call IDs, mixed finalize, prose/create-only JSON, or incompatible finish behavior still fail explicitly. `finalize_plan` asks the model to audit the Task/Checklist granularity before ending. The conversation has no fixed round or tool-call count: parallel and serialized providers may emit every operation the request needs, and only `finalize_plan` ends generation. User cancellation, the hardened transport timeout/2 MiB per-response boundary, provider context rejection, tool validation, and proposal-only atomic Apply remain the resource and safety boundaries; none silently truncate a plan by component count.

Finalize produces a deterministic baseline-to-overlay diff, not facts. `AITaskWorkspaceReviewPolicy` is the Foundation-only safety boundary for create/update/archive/delete/reuse counts, mutation totals, destructive classification, stable operation identity, and complete user-facing before→after field mapping. `AITaskWorkspaceReviewPresentation` converts that policy into read-only rows, while `AITaskWorkspaceReviewViews` renders them; `AITaskWorkspacePlanGeneratorViews` owns only request, generation/cancellation, confirmation, and Apply orchestration. The primary action is `Apply N Changes`; Category/Checklist deletion, Task archival, quantity-goal removal, and other destructive impact require a native destructive confirmation. Generation cancellation preserves the request. Provider/tool failures and apply conflicts preserve the preview where one exists; the feature never falls back to the removed create-only JSON stack or lets the model write SwiftData.

Apply passes the reviewed operations and original `AITaskAtomicMutationBaseline` to one store-scoped coordinator. Under the shared store lock, a fresh context captures the complete workspace again and requires exact equality across provider-visible canonical content plus Category, Task, assignment, Checklist, visual, quantity-goal, and recurrence mutation revisions. It then replays the exact reviewed operations and revalidates identity kind, protected Health identities, hierarchy/placement, archive admission, active Timer/Pomodoro work, and persistent field policy before one `performAtomicMutation`. Any stale fact, invalid operation, identity collision, injected checkpoint failure, or final save failure produces zero writes and zero mutation events; a stale result remains in review for explicit regeneration. Targeted Checklist edits rotate only their own content/visual revisions, and Task removal retains the product's Archive-only lifecycle.

AI responses use one dedicated ephemeral `URLSession`, with cache and cookies disabled and a 60-second resource timeout; the SSE streaming session uses the same hardening with a 300-second resource budget because reasoning generations legitimately exceed the buffered budget. `AsyncBytes` enforces a 2 MiB actual-body ceiling even when Content-Length is missing or false; oversized declarations and non-2xx status are rejected at headers and the task is cancelled before body consumption. Structured cancellation propagates to the URLSession task. Service-level validation repeats the byte ceiling for injected transports without changing HTTP status priority. The SSE parser is byte-fed, frame-decoded UTF-8-safe, and enforces the identical ceiling mid-stream.

`DeviceIdentity` is an opaque local tie-break identifier, not a device fingerprint. Only the current platform prefix plus a canonical UUID is reusable; malformed, cross-platform, controlled-character, or oversized persisted values are replaced with a fresh random identifier. The Watch command producer uses the same shared policy and persists `watch-<UUID>` in the Watch app's own defaults. Every new command carries that stable per-install metadata, while command UUID—not device identity—remains the idempotency key; restored legacy commands are not rewritten.

App Intents use the application model container and the same store-scoped commands. After a commit, `SystemActionPostCommitEffects` queues sibling-scene read-model convergence and submits the exact outcome events to the same store-scoped projection scheduler used by Scene and Watch mutations. It creates no temporary facade/read-model context, starts no application lifecycle or automatic LLM job, and returns without waiting for projection. A later projection failure never turns a committed, potentially non-idempotent action into an intent failure.

System input routing is lifecycle-safe and bounded. `AppDeepLinkRouter` validates a small URL grammar before immediate execution or enqueue; each scene owns a semantic-deduplicating `PendingDeepLinkQueue` capped at 16 entries and drains it only after repositories are ready and its typed presentation slot is available. Navigation/modal deep links acquire that slot before mutating destination state, while direct timer start/stop actions do not wait for an unrelated sheet. `WatchCommandRouter` owns the process-wide Watch bridge callback but retains scene stores weakly, prefers the most recently active scene, removes released registrations, and uninstalls the callback when no scene remains. This prevents startup URLs from bypassing validation and prevents a singleton connectivity closure from leaking or targeting a stale scene.

System-surface projections are also untrusted transport boundaries. Widget and Watch producers cap record counts, clamp summaries and anomalous timer starts, and shorten projected title/path/style values at Unicode character boundaries. Each snapshot has a 128 KiB aggregate text budget. `SharedWidgetSnapshotStore` then validates before save and after load, rejects encoded data over 256 KiB, caps active timers and recent tasks at 64 each, and requires bounded fields/time values and unique timer/task IDs; invalid loads are reported as corrupted rather than empty. `WatchStateSnapshot` allows at most 64 active timers and 256 recent tasks under equivalent field/time/identity/text-budget validation. Independently, iPhone incoming and Watch pending/failed command queues each cap at 64 entries, and persisted queue JSON caps at 512 KiB. Projection shaping changes only extension DTOs; canonical task and ledger facts remain untouched.

Persistent deduplication and synced preferences use deterministic last-write-wins ordering. A newer `updatedAt` wins; at an equal timestamp a tombstone wins; `createdAt`, `deviceID`, `clientMutationID`, or a stable TimeSegment content key resolve the remaining tie. Select the winner before filtering tombstones so stale active rows cannot resurrect deleted data.

## UI Structure

`AppRootView` is the only root-shell decision boundary. It measures the actual scene
width and combines it with the system horizontal size class: below 720 pt or when the
system reports compact, it renders the shared tab-based compact shell; otherwise it
renders the shared sidebar/detail regular shell. The app-level Store and scene-owned
presentation/feedback routers remain above that branch. Feature views consume
`layoutShell` or their own finite container width and never read device idiom, screen
model, or platform identity to choose product layout. Conditional compilation in UI is
limited to unavailable platform APIs, native scene/menu/window plumbing, system chrome,
input modality, and framework capabilities; equal product roles share semantic
typography across platforms.

Task navigation has one store-owned route. In the regular sidebar/detail shell, that
route directly chooses the detail column content; replacing task A with task B must not
clear the route through the Tasks root first. The compact shell mirrors the same route
into a typed `NavigationStack` path so system Back can request a guarded route close.
Every detail dismissal is fenced by the task identity that created it, preventing a
stale disappearing workspace from clearing a newer replacement route. Unsaved editor
confirmation completes before either a replacement or a close mutates the route.

Application data is app-scoped, while presentation and transient feedback are scene-scoped. Each visible scene owns one `AppPresentationRouter`/`AppPresentationHost` pair for typed sheets and one `AppSceneFeedbackRouter`/`AppSceneFeedbackHost` pair for alerts. The feedback router is FIFO and dismisses only the matching feedback UUID, so a stale callback cannot clear a later message. Settings export, database maintenance, and sync recovery use throwing boundaries: successes stay inline and failures enter only the initiating scene. `ContentView` bridges the remaining shared Store error slot into its own queue only for legacy callers; new work must not expand that bridge.

Task-editor conflict recovery is typed and session-local. A stale draft never retries against its old mutation baseline. The editor may retain the user's current draft or, after explicit confirmation, replace it with a freshly projected task/checklist/category baseline and rebuilt parent candidates; that replacement also becomes the new discard baseline. Ordinary save failures continue through scene feedback and never silently mutate the editor draft.

The app source is organized by ownership. New files should land next to the domain they affect:

```text
timetracker/App       Startup, scene roots, typed presentation and feedback router/hosts, and commands
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
  Sync/           Conflict state, snapshots, restore, and Cloud reconciliation
  SystemProjection/
                   Post-commit current-state scheduling and external surface publication
  SystemIntegration/
                   Apple Health integration, durable files, credentials, and export
  Tasks/          Task tree derivation and validation helpers
  WatchConnectivity/
                   iPhone Watch commands, state projection, codec, and transport
timetracker/Features/Home
  Controls/       Start/new-task controls and task selection sheets
  Rows/           Active timer and timeline rows
  Sections/       Metrics, forecast, quick start, and timeline sections
timetracker/Features/Inbox
                  Capture, list rows, suggestion feedback, and apply/discard actions
timetracker/Features/Tasks
  Detail/         Canonical detail router plus identity, checklist, overview,
                  analytics, navigation, and record sections
  Editor/         Task editor composition, hierarchy rows, symbol/color controls,
                  checklist editing, and editor-specific validation
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

Within `Features/Home`, keep the Today screen split by responsibility: `Features/Home/HomeViews.swift` composes the page, `Features/Home/Controls/HomeActionsViews.swift` owns start/new-task controls and the searchable task picker, `Features/Home/Sections/HomeMetricsViews.swift` renders the compact time summary, `Features/Home/Sections/HomeCountdownViews.swift` owns the shared countdown presentation, and forecast, quick start, timeline, and row files own their own sections. On the regular canvas, `HomeLayoutPolicy` keeps Weekly Time and Activity Heatmaps in one bounded visualization group. Weekly Time consumes the existing daily Gross/Wall projection: Gross sums every clipped segment, Wall merges overlaps, and the chart compares both with nonstacked positioned bars in stable Gross→Wall order. Below 1000 pt of content width all later sections stay single-column; from 1000 pt, that group pairs with Quick Start in a 678...748 pt / 300...410 pt row, followed by Timeline paired with the optional fixed 360 pt Forecast/Countdown column. Forecast/countdown availability cannot change chart geometry. Generic day/week/month/year progress tiles were removed; countdown events are a low-priority Today section on every main-app platform. App-level sheet arbitration belongs to one scene-owned `AppPresentationRouter` plus one `AppPresentationHost`; feature views request typed content and never put modal draft state in the application-shared store. Main and macOS Settings scenes share the store but own separate routers. Within `Features/Settings`, `Features/Settings/SettingsViews.swift` owns category navigation, export, alerts, and destructive confirmations; the scene host owns its LLM configuration sheet. Display/timing, Pomodoro, countdown, sync, data, AI draft configuration, macOS shortcut recording, binding, action, and support responsibilities stay focused. Shared rows are split into `SettingsRows.swift` foundation/value semantics, action/destructive labels, text/number inputs, platform presentation modifiers, and sync feedback. `SettingsSectionsViews.swift`, `TimeTrackerServices.swift`, and the unused Inbox suggestion editor are retired names, not extension points.

The macOS app owns one main `Window` and one application-level `TimeTrackerStore`; the standard Settings scene receives that same store. Do not return to `WindowGroup` unless per-window persistence coordination is split from scene-local navigation/draft state first, or each window would duplicate observers and background automation.

The macOS app root separately owns one application-level `MacKeyboardShortcutSettings` observable and injects that same instance into the main scene, Settings scene, and `TimeTrackerCommands`. A stable 16-action registry groups creation, timing, organization, navigation, and data commands; context-dependent commands remain visible in native menus but disable when their selected task or presentation prerequisite is absent. High-frequency actions retain safe defaults, while lower-frequency context actions intentionally default to no assignment and can still be recorded in Settings. The durable command writes one size-limited atomic Codable blob through `AppDefaults.shared`; the read and write paths share semantic assignment validation and the read path falls back without rewriting corrupt, oversized, unsupported, duplicate, or reserved payloads. Shortcut changes increment a revision so SwiftUI reconstructs the affected menu items immediately. This state is intentionally outside `TimeTrackerStore`, SwiftData, CloudKit, scene focus, and the `KeyboardShortcuts.Name` global-hotkey storage path.

`SyncConflictService.swift` owns bootstrap and prompt assembly. Focused extensions own local mutation, Cloud import/export, recovery/resolution, state persistence, POSIX lock/locations, and filtered export encoding. `SyncDataSnapshot` plus capture, preflight structure/semantics, and task/ledger/planning/checklist/Inbox restore files own one validated atomic domain mapping, while organization and domain record files own versioned transport DTOs. Record DTOs are transport/restore representations only; business truth remains the SwiftData domain model and ledger facts.

Layer placement rules (what belongs in `Commands` / `Repositories` / `Services` / `Features` / `SharedUI`, the facade boundary, and directory-split policy) are owned by [ProjectMap](ProjectMap.md#placement-rules).

Within `Stores/Facade`, `TimeTrackerStore+Configuration.swift` owns full first-run configuration and startup projection catch-up; `TimeTrackerStore+Lifecycle.swift` owns mutation boundaries and current-scene refresh, `TimeTrackerStore+RefreshLifecycle.swift` owns launch/foreground recovery triggers, and `TimeTrackerStore+SyncRefreshPipeline.swift` owns remote-import recovery triggers. Closed-app App Intents enqueue directly through `SystemActionPostCommitEffects`; they must not attach facade repositories or run migrations, demo seeding, observers, or automatic LLM work.

Visual and interaction guardrails — native-first control choices, responsive checks, timeline and task-list rules — are maintained in [UI Design Notes](UI-Design.md). User-facing copy rules are maintained in [Localization](Localization.md). Task Detail is currently the canonical selected-task surface; adding an inspector requires an explicit product decision rather than being a default layout assumption.

Xcode shared schemes are source-controlled under `timetracker.xcodeproj/xcshareddata/xcschemes`. Do not rely on per-user scheme state for app builds; command-line builds and install scripts must be able to use `-scheme timetracker` from a clean checkout.

## Shared UI Logic

`TimelineLayoutEngine` owns Today timeline clipping, display interval, and lane allocation. Keep this logic out of SwiftUI view bodies so chart behavior can be tested without launching the app.

Task tree display is derived UI state. The durable hierarchy remains `TaskNode.parentID` plus repairable `depth`/canonical locator `path`; the Tasks screen derives a flat list of visible rows and title paths so native list interactions remain reliable without recursive SwiftUI identity.

## Testing Strategy

Prefer behavior tests over source-string scans. The full verification policy — baseline commands, required coverage, UI testing, performance budgets, and resource ownership — is maintained in [Testing](Testing.md). Performance budgets currently cover large task-tree flattening, analytics snapshot generation (including dense overlap), ledger bucket summaries, timeline layout inputs, checklist rollup calculations, and affected-branch rollup refresh.

Before merging a feature:

1. Can the feature be found from the ownership table?
2. Does every durable write go through a command or repository boundary?
3. Does the view avoid expensive work in `body`?
4. Are active timers still derived from open `TimeSegment` rows?
5. Are historical/imported task tombstones and their ledger rows handled intentionally without reintroducing a product Delete action?
6. Does iCloud remote import coalesce refresh work?
7. Are compact iPhone, iPad split view, and macOS sidebar/detail layouts considered separately?
8. Are all strings localized in English, Simplified Chinese, and Traditional Chinese?
9. Are tests behavior-based rather than fragile source scans?
10. Did verification match the change's risk: relevant signed tests/builds for code changes, normal-size screenshots for affected visual flows, and Instruments only for performance-sensitive work? Is dated evidence recorded in the shipping commit/PR rather than inferred from an earlier batch, and are all owned simulator/test/trace resources released?

## Feature Status

The current app includes local SwiftData persistence, iCloud-backed user preferences, task creation/editing, task checklists, reversible task archive/restore, legacy tombstone compatibility, nested task browsing, multi-segment timers, manual time entry, pomodoro-ledger synchronization, Today timeline, a device-local read-only Apple Health replica with incremental HealthKit refresh, local task forecasting, analytics overview, versioned business/Health JSON export, isolated demo-data management, production-safe tombstone retention, iCloud configuration, App Intents, Live Activity, Widget code, and a Watch companion. Daily recurrence and quantity tracking include rule creation/editing, current-day materialization, lifecycle scheduling, direct-work separation, quantity goals/entries, and iCloud-safe idempotency. Permanent tombstone maintenance exists only for isolated Demo/UI Test stores.

Future work should preserve the ledger contract: every timer, pomodoro, manual entry, widget action, Live Activity action, or Watch command must ultimately create or update `TimeSession` and `TimeSegment` records through shared use cases.

## Version and Build Info

Settings includes an About section with the app icon, `MARKETING_VERSION`, build number, Git branch, short commit hash, and build date. The app target writes `AppBuildInfo.plist` during the build via a build phase that runs `scripts/write_build_info_plist.sh` (a thin wrapper around the `timetracker_tools.write_build_info_plist` Python module; see [DevelopmentTools](DevelopmentTools.md)); do not hard-code Git metadata in Swift source.

Versions are bumped manually before a release with `make bump-version`; the pre-commit hook only enforces localization parity. See `Docs/Versioning.md` before changing release or commit automation.
