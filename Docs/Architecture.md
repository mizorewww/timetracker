# Time Tracker Architecture

Status: current implementation and architecture guardrails

Reviewed: 2026-07-25

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

## Domain Stores and Refresh

Domain stores own state snapshots:

- `TaskStore` owns task tree snapshots.
- `LedgerStore` owns active, today, history, segment/day/session indexes and mutation deltas.
- `ChecklistStore` owns global bootstrap plus task-scoped item/visual replacement indexes.
- `RollupStore` owns exact worked totals, checklist progress, forecast state and the bounded 90-local-day pace index.
- `AnalyticsStore` owns pure read-model overview/task snapshot caches keyed by full period, current local day, and optional live-minute identity, plus disposable ledger day buckets; cache operations are split into `AnalyticsStore+Caching`, and cached snapshots do not retain SwiftData segment objects.
- `PreferenceStore` owns synced preference snapshots.

`StoreRefreshCoordinator` owns refresh sequencing after command events. The facade does not decide the order of task, ledger, checklist, rollup, analytics, selection validation, and Live Activity side effects inline.

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

External CloudKit changes enter the same pipeline through remote-store and completed import/export notifications. The observer coalesces bursts before emitting `remoteImportCompleted`; launch and foreground activation remain consistency boundaries. There is no permanent foreground polling timer.

## Feature Ownership Map

| Feature | Durable model | Write owner | Snapshot owner | Pure services | UI owner |
| --- | --- | --- | --- | --- | --- |
| Start, stop, and rapid-restart timer | `TimeSession`, `TimeSegment` | `StoreScopedTimerCommandCoordinator`, `TimerCommandHandler`, time-tracking repository | `LedgerStore`, `RollupStore` | `TimerAdmissionPolicy`, `TimerRapidRestartPolicy`, `LedgerSummaryService` | `Features/Home`, `Features/Tasks/Detail` |
| Manual time and segment editing | `TimeSession`, `TimeSegment` | `LedgerCommandHandler` | `LedgerStore`, `AnalyticsStore` | `TimelineLayoutEngine` | `Features/Ledger`, `Features/Home` |
| Task edit, move, archive, restore | `TaskNode` | `TaskDraftCommandHandler` | `TaskStore`, `RollupStore` | `TaskTreeService`, `TaskTreeFlattener`, `TaskHierarchyMetadataService`, `TaskTrackingAvailabilityService` | `Features/Tasks`, `Features/Sidebar` |
| Daily recurrence and quantity configuration | `TaskRecurrenceRule`, `TaskRecurrenceOccurrence`, `TaskQuantityGoal`, `TaskQuantityEntry`, generated `TaskNode` | `StoreScopedTaskRecurrenceCommandCoordinator`, task recurrence repository | `TaskStore`, facade recurrence snapshots | `TaskRecurrenceDayKey`, `TaskTrackingAvailabilityService` | Runtime lifecycle is implemented; creation and quantity-entry UI remain future `Features/Tasks` work |
| Task categories | `TaskCategory`, `TaskCategoryAssignment` | task category commands, task draft command | `TaskStore`, `RollupStore` | `TaskTreeService` | `Features/Tasks`, `Features/Sidebar` |
| Checklist | `ChecklistItem` | `ChecklistCommandHandler` | `ChecklistStore`, `RollupStore` | `ChecklistDraftService`, `TaskRollupService` | `Features/Tasks/Editor`, `Features/Tasks/Detail` |
| Forecast | none, derived | none | `RollupStore` | `TaskRollupService`, `ForecastDisplayService` | `Features/Home`, `Features/Analytics`, `Features/Tasks/Detail` |
| Pomodoro | `PomodoroRun`, ledger models | `PomodoroCommandHandler`, ledger/task commands | `LedgerStore`, Pomodoro read models | persisted-phase deadline/reconciliation helpers | `Features/Pomodoro` |
| Analytics | none, derived | none | `AnalyticsStore` | `AnalyticsEngine`, `TimeAggregationService` | `Features/Analytics` |
| Synced settings | `SyncedPreference` | `PreferenceCommandHandler` | `PreferenceStore` | `AppPreferenceCodec`, `SyncedPreferenceService` | `Features/Settings` |
| Countdown events | `CountdownEvent` | `CountdownCommandHandler` | `TimeTrackerStore` countdown snapshot | date formatting helpers | `Features/Home`, `Features/Settings` |
| JSON export | none | facade maintenance command | none | export DTO encoding | `Features/Settings/Support/SettingsExportDocument` |
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

Mutation refresh is incremental after initial/full load. `LedgerStore` replaces only segments overlapping invalidated ranges and related sessions; `ChecklistStore` replaces affected task buckets; `RollupIncrementalIndex` applies segment before/after deltas and recalculates direct tasks plus ancestors. Active and future-ended segments are time-sensitive: forward clock movement reevaluates that bounded set, while a backward wall-clock correction reevaluates all ledger rows because a previously completed row can cross the reference boundary again. Full-history worked seconds remain exact, while only the 90-day pace buckets are bounded. `CorePerformanceBudgetTests` includes a 50,000-segment single-record mutation and cached frequent-task ranking budget.

Checklist quick add, completion, and reorder commands share the store-scoped mutation lock with task-editor replacement and task lifecycle writes. The coordinator creates a fresh context after acquiring the lock, rejects stale item/order mutation baselines, validates the canonical task before inserting related rows, and derives refresh ancestors from the fresh hierarchy. This prevents stale scenes from resurrecting checklist tombstones, creating checklist/visual orphans, overwriting newer completion state, or invalidating only an obsolete parent chain.

Task-category create, update, delete, and task-draft assignment also share that lock domain. Category editors carry an immutable category mutation baseline; stale edit/delete commands are rejected, creation derives ordering from a fresh context, and deletion tombstones every assignment visible inside the same transaction. A task draft cannot assign a category after its deletion, while deletion that follows an assignment observes and removes that assignment.

`AnalyticsStore` caches overview and task snapshots by range, true calendar period start, and optional minute live bucket. A live bucket exists only when an active segment overlaps the selected range, so historical views do not recompute for clock ticks. Ledger events invalidate snapshots and only intersecting day buckets; every cache remains disposable and reconstructable from ledger facts.

Analytics ranking and single-value selections are deterministic. Task ties resolve by gross time, wall time, localized title, then UUID; peak-hour ties choose the earliest local hour. Deleted-task titles use the latest valid session snapshot by start time, update time, and UUID, shared by task breakdown and overlap participants. Collection input order and dictionary iteration order are never product semantics.

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

iCloud sync is controlled by `AppCloudSync` and the SwiftData model container configuration. Eligible user preferences sync through `SyncedPreference`; iCloud enablement, device identity, migration flags, build info, secrets, automatic-AI consent, and CloudKit error text stay local. The app refreshes on launch, foreground, SwiftData remote changes, and completed CloudKit import/export events. Consecutive notifications are coalesced before entering the refresh planner; there is no permanent foreground polling loop. Local/Demo/UI Test mutations do not capture conflict snapshots; in CloudKit/recovery mode `StoreDomainEvent` refreshes only affected snapshot domains unless a full baseline/import is required.

Cloud recovery has two distinct intents. Automatic fallback recovery uses `reconcileWithCloud`: it protects the local branch, creates a fresh CloudKit cache, waits for authoritative hydration, and compares local/cloud fingerprints without exporting first. Explicit “replace iCloud with this device” uses `explicitlyReplaceCloud` and may restore the protected local winner exactly once before export. Upload, download, and reconciliation requests are mutually exclusive, and commands from a stale Settings scene are rejected after a recovery container has attached.

Authoritative hydration is a persisted setup-to-initial-import barrier. `CloudRecoveryImportSession` binds one recovery UUID and kind to one store identifier and accepts only successful completed events from the current epoch. A successful setup must precede a successful import for the same store. `CloudRecoveryImportBuffer` begins observing before `ModelContainer` creation so an early event is not lost, then drains into the scene store after normal observers attach. Recovery remains read-only until the matching session completes; an incomplete session after a crash triggers another fresh-store reset, while a completed session can converge safely after restart. Recovery-only store configuration defers migrations, seeding, Pomodoro/background work, and other write-side startup effects.

Settings reports recent Cloud activity with a typed `SyncActivityOutcome(kind, completedAt, result)`, not a generic local refresh timestamp. Only a completed import, export, or setup event with no CloudKit error can become success, and only after the local read-model refresh and conflict update also succeed. A remote-store signal alone triggers refresh but never claims a completed cloud operation. CloudKit, export-checkpoint, or local post-processing failures remain typed failures with their diagnostic message. Account availability is tracked separately, and a future completion date or one older than the 120-second recent window cannot appear as recent success.

Every `SyncConflictState.json` read-modify-write runs under a recursive process lock plus POSIX `lockf` advisory file lock, so app and Shortcuts processes share one serialized state transaction. JSON replacement is atomic, and the forced-upload mirror cannot override an existing authoritative state. Reads and writes cap authoritative state at 128 MiB and the recovery mirror at 64 MiB. Reads use metadata preflight plus `FileHandle.read(upToCount: limit + 1)` to catch growth between checks without an unbounded allocation. Writes encode and preflight the authoritative state and required mirror before resolving paths, creating directories, or replacing either file; an independent mirror rewrite checks its final bytes again. Either rejection preserves the previous valid files. An oversized or corrupt authoritative file is quarantined for explicit recovery; an oversized or corrupt pending-forced-upload mirror is quarantined and ignored so it cannot block an otherwise usable main store. Oversized quarantine moves the file without loading its complete JSON into memory. Prompt assembly is a throwing read boundary, so an unreadable authoritative state is never reported as “no conflict.” Local generations, sync epochs, and per-export event checkpoints ensure only the exact exported fingerprint/generation is acknowledged; failed, stale, or out-of-order callbacks cannot mark newer local work clean. `pendingConflictID` is also the compare-and-swap token for the exact local/cloud summaries a person reviewed: material changes to either resolution branch rotate it, and resolution validates the expected optional ID under the same state lock before any model, epoch, reset, or state mutation. Scrubbing a legacy excluded preference recomputes the fingerprint and invalidates checkpoints for the old payload. Checkpoints are bounded to 16 entries and 24 hours.

Snapshot restore treats transport data as untrusted historical input. A pure preflight runs before the atomic mutation and rejects per-table/aggregate record overflow, duplicate UUIDs, per-field/aggregate UTF-8 overflow, unsupported dates/raw values, unsafe sort orders, invalid Pomodoro bounds, malformed typed or unknown preference JSON, and provable session/task or Inbox suggestion-identity inconsistencies. Missing referenced records remain legal for staged CloudKit import; a relationship is rejected only when both records exist and disagree. Rejection leaves existing facts and tombstones unchanged; restore never silently deduplicates or clamps invalid transport. Limits are 100,000 records per table, 250,000 total, 4 KiB titles, 64 KiB notes/reasons, 256-byte compact fields, 256 KiB preference JSON, and 32 MiB total text. This boundary covers explicit `SyncDataSnapshot.restoreAsLocalWinner` calls, not records already materialized directly into a SwiftData context by the initial CloudKit import path.

On iOS, the authoritative state, pending forced-upload recovery mirror, and corrupt-state quarantine files use `FileProtectionType.completeUntilFirstUserAuthentication`. They remain unavailable before the first unlock after boot, then stay available to background Shortcuts/CloudKit coordination. This protection applies to sensitive JSON files, not the advisory lock file; macOS does not receive the iOS attribute.

One user mutation is committed through `ModelContext.performAtomicMutation`. Nested command/repository steps defer their saves until the outer boundary and rollback together on failure. Read-model refresh and sync/Widget projection happen after commit; failure there must be reported as “saved but refresh failed,” not as a rolled-back business action.

Preference writes add a pure batch-preparation boundary before that mutation. `PreferenceJSON` rejects payloads above 256 KiB and decodes each value according to its `AppPreferenceKey`; `PreferenceCommandHandler` canonicalizes the complete batch before fetching or touching any `SyncedPreference`. JSON `null`, malformed syntax, type mismatches, and oversized values therefore cannot leave earlier batch entries pending. The prepared batch is then committed atomically, including standalone command calls. Legacy encoding failures are skipped rather than persisted as `null`.

The editable AI task-planning instructions are a bounded synced string preference. The sanitizer normalizes line endings, treats blank input as the built-in default, rejects unsupported control characters, and enforces a 4 KiB UTF-8 limit at editor, command, JSON, migration, snapshot-preflight, and request boundaries. The fixed response schema and safety contract remain service-owned and are never stored in this editable preference.

Keychain is intentionally outside SwiftData's ACID boundary. Saving LLM configuration batches endpoint, model list, and selected model into one preference transaction, while preserving the previous Keychain value for compensating restore if that transaction fails. A compensation failure is a separate error, never proof of atomic cross-storage rollback. “Clear all data” likewise clears the Keychain API key and device-local automatic-suggestion consent, attempts to restore them if the SwiftData reset fails, and leaves the device-local iCloud startup switch unchanged.

Inbox and checklist AI requests use one bounded network-projection policy. Inbox selects at most 48 trackable candidates by Quick Start pin, indexed frequent/recent use, then stable path; normalized candidate JSON is capped at 16 KiB. Both flows cap the user prompt at 24 KiB and the final request body at 32 KiB, bound each transmitted field by UTF-8 bytes, and shorten only at complete `Character` boundaries. The full on-device symbol catalogue remains available to the picker, while prompts advertise a 78-symbol semantic subset. Returned task IDs must belong to the transmitted candidates, and returned icons must belong to the advertised subset. Projection shaping never mutates canonical Task, Inbox, or Checklist text.

AI task-plan generation is explicit and draft-first. `LLMTaskPlanService` sends only the user's 4 KiB request, the sanitized 4 KiB planning instructions, and icon/color allowlists under an immutable system contract. It accepts one flat response capped at 128 KiB, maps textual references to locally generated UUIDs, and rejects duplicate/orphan references, cycles, child-task categories, depth beyond six, invalid fields, more than 8 categories, 64 tasks, 32 checklist items per task, or 256 checklist items total. The SwiftUI sheet owns the mutable preview; it can rename or remove proposed items but cannot write facts directly.

One explicit Create action passes the reviewed draft to `StoreScopedAITaskPlanCommandCoordinator`. After acquiring the store mutation scope, a fresh context validates the complete graph and persistent field policies, checks proposed category/task UUIDs for all-present idempotent replay versus mixed identity conflict, then creates categories, topologically ordered tasks, assignments, and checklist rows in one `performAtomicMutation`. Any failure rolls back every proposed fact. The feature only creates new facts; it never updates or deletes existing tasks.

AI responses use one dedicated ephemeral `URLSession`, with cache and cookies disabled and a 60-second resource timeout. `AsyncBytes` enforces a 2 MiB actual-body ceiling even when Content-Length is missing or false; oversized declarations and non-2xx status are rejected at headers and the task is cancelled before body consumption. Structured cancellation propagates to the URLSession task. Service-level validation repeats the byte ceiling for injected transports without changing HTTP status priority.

`DeviceIdentity` is an opaque local tie-break identifier, not a device fingerprint. Only the current platform prefix plus a canonical UUID is reusable; malformed, cross-platform, controlled-character, or oversized persisted values are replaced with a fresh random identifier.

App Intents use the application model container and the same commands. After an intent commits, a narrow post-commit synchronizer refreshes only task/ledger/preference state needed by Widget, Watch, and Live Activity; it does not start the full app lifecycle or automatic LLM jobs. A projection failure never turns a committed, potentially non-idempotent action into an intent failure.

System input routing is lifecycle-safe and bounded. `AppDeepLinkRouter` validates a small URL grammar before immediate execution or enqueue; each scene owns a semantic-deduplicating `PendingDeepLinkQueue` capped at 16 entries and drains it only after repositories are ready and its typed presentation slot is available. Navigation/modal deep links acquire that slot before mutating destination state, while direct timer start/stop actions do not wait for an unrelated sheet. `WatchCommandRouter` owns the process-wide Watch bridge callback but retains scene stores weakly, prefers the most recently active scene, removes released registrations, and uninstalls the callback when no scene remains. This prevents startup URLs from bypassing validation and prevents a singleton connectivity closure from leaking or targeting a stale scene.

System-surface projections are also untrusted transport boundaries. Widget and Watch producers cap record counts, clamp summaries and anomalous timer starts, and shorten projected title/path/style values at Unicode character boundaries. Each snapshot has a 128 KiB aggregate text budget. `SharedWidgetSnapshotStore` then validates before save and after load, rejects encoded data over 256 KiB, caps active timers and recent tasks at 64 each, and requires bounded fields/time values and unique timer/task IDs; invalid loads are reported as corrupted rather than empty. `WatchStateSnapshot` allows at most 64 active timers and 256 recent tasks under equivalent field/time/identity/text-budget validation. Independently, iPhone incoming and Watch pending/failed command queues each cap at 64 entries, and persisted queue JSON caps at 512 KiB. Projection shaping changes only extension DTOs; canonical task and ledger facts remain untouched.

Persistent deduplication and synced preferences use deterministic last-write-wins ordering. A newer `updatedAt` wins; at an equal timestamp a tombstone wins; `createdAt`, `deviceID`, `clientMutationID`, or a stable TimeSegment content key resolve the remaining tie. Select the winner before filtering tombstones so stale active rows cannot resurrect deleted data.

## UI Structure

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
  SystemIntegration/
                   Sync conflict orchestration/state/export, versioned snapshots,
                   Widget/Watch handoff, credentials, and connectivity transport
  Tasks/          Task tree derivation and validation helpers
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

Within `Features/Home`, keep the Today screen split by responsibility: `Features/Home/HomeViews.swift` composes the page, `Features/Home/Controls/HomeActionsViews.swift` owns start/new-task controls and the searchable task picker, `Features/Home/Sections/HomeMetricsViews.swift` renders the compact time summary, `Features/Home/Sections/HomeCountdownViews.swift` owns the shared countdown presentation, and forecast, quick start, timeline, and row files own their own sections. Generic day/week/month/year progress tiles were removed; countdown events are a low-priority Today section on every main-app platform. App-level sheet arbitration belongs to one scene-owned `AppPresentationRouter` plus one `AppPresentationHost`; feature views request typed content and never put modal draft state in the application-shared store. Main and macOS Settings scenes share the store but own separate routers. Within `Features/Settings`, `Features/Settings/SettingsViews.swift` owns category navigation, export, alerts, and destructive confirmations; the scene host owns its LLM configuration sheet. Display/timing, Pomodoro, countdown, sync, data, AI draft configuration, binding, action, and support responsibilities stay focused. Shared rows are split into `SettingsRows.swift` foundation/value semantics, action/destructive labels, text/number inputs, platform presentation modifiers, and sync feedback. `SettingsSectionsViews.swift`, `TimeTrackerServices.swift`, and the unused Inbox suggestion editor are retired names, not extension points.

The macOS app owns one main `Window` and one application-level `TimeTrackerStore`; the standard Settings scene receives that same store. Do not return to `WindowGroup` unless per-window persistence coordination is split from scene-local navigation/draft state first, or each window would duplicate observers and background automation.

`SyncConflictService.swift` owns bootstrap and prompt assembly. Focused extensions own local mutation, Cloud import/export, recovery/resolution, state persistence, POSIX lock/locations, and filtered export encoding. `SyncDataSnapshot` plus capture, preflight structure/content/semantics, and task/ledger/planning/checklist/Inbox restore files own one validated atomic domain mapping, while organization and domain record files own versioned transport DTOs. Record DTOs are transport/restore representations only; business truth remains the SwiftData domain model and ledger facts.

Pure layout, formatting, and derivation logic belongs in `Services`, `Shared`, or `SharedUI` with unit tests. SwiftUI feature files should render state and collect input; durable writes go through store facade methods and command handlers.

Within `Stores/Facade`, `TimeTrackerStore+Configuration.swift` owns full first-run configuration plus the narrow repository-only attachment used by committed App Intents; `TimeTrackerStore+Lifecycle.swift` owns refresh, mutation boundaries, recovery operations, and common errors. Do not make the closed-app system-surface path run migrations, demo seeding, observers, or automatic LLM work.

Avoid root-level "miscellaneous" folders that collect unrelated files. If a file name needs a `+` extension suffix, it should usually live under the owning facade or feature directory instead of being left beside unrelated domain stores. If a directory grows beyond one ownership concept, split it by domain before adding more files.

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
10. Did verification match the change's risk: relevant signed tests/builds for code changes, normal-size screenshots for affected visual flows, and Instruments only for performance-sensitive work? Is dated evidence recorded in the Audit rather than inferred from an earlier batch, and are all owned simulator/test/trace resources released?

## Feature Status

The current app includes local SwiftData persistence, iCloud-backed user preferences, task creation/editing, task checklists, reversible task archive/restore, legacy tombstone compatibility, nested task browsing, multi-segment timers, manual time entry, pomodoro-ledger synchronization, Today timeline, local task forecasting, analytics overview, JSON export, isolated demo-data management, production-safe tombstone retention, iCloud configuration, App Intents, Live Activity, Widget code, and a Watch companion. It also includes the V13 daily-recurrence runtime: rule commands, current-day materialization, lifecycle scheduling, direct-work separation, and iCloud-safe idempotency. The user-facing recurrence creation flow and quantity-entry UI are not yet implemented, so the product feature is not complete. Permanent tombstone maintenance exists only for isolated Demo/UI Test stores.

Future work should preserve the ledger contract: every timer, pomodoro, manual entry, widget action, Live Activity action, or Watch command must ultimately create or update `TimeSession` and `TimeSegment` records through shared use cases.

## Version and Build Info

Settings includes an About section with the app icon, `MARKETING_VERSION`, build number, Git branch, short commit hash, and build date. The app target writes `AppBuildInfo.plist` during the build using `scripts/write_build_info_plist.sh`; do not hard-code Git metadata in Swift source.

Version bumping is automated through `.githooks/pre-commit`. See `Docs/Versioning.md` before changing release or commit automation.
