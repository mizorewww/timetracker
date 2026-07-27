# Testing

Status: current verification policy

Reviewed: 2026-07-26

## Baseline Commands

Run these through the Makefile (see [DevelopmentTools](DevelopmentTools.md)); the explicit `xcodebuild` forms are shown as equivalents for CI or override contexts.

Unit tests on macOS:

```sh
make test
# equivalent:
# xcodebuild test -project timetracker.xcodeproj -scheme timetracker -destination 'platform=macOS' -only-testing:timetrackerTests
```

聚焦诊断仍通过同一 Makefile 入口，例如
`make TEST_ONLY=timetrackerTests/CoreLLMResponseTransportTests test`；最终默认门禁必须不带
`TEST_ONLY` 运行完整 `timetrackerTests`。

AI task-plan acceptance uses the production DeepSeek endpoint and production
`LLMTaskWorkspacePlanningService`; provider fakes and prebuilt plans are not
accepted as evidence. The live gate is opt-in so the ordinary test suite never
spends API credit:

```sh
export TIMETRACKER_LIVE_LLM_API_KEY="your-provider-key"
make test-llm-live
TIMETRACKER_LIVE_LLM_SCENARIO=prompts make test-llm-live
TIMETRACKER_LIVE_LLM_SCENARIO=prompt150 make test-llm-live
TIMETRACKER_LIVE_LLM_SCENARIO=all make test-llm-live
```

For repeated local runs, put the same assignment in the repository-root `.env`;
the Makefile loads that ignored file automatically. Live tests read only
`TIMETRACKER_LIVE_LLM_API_KEY` and never fall back to
`Docs/userfeedback.md`.

The default scenario sends the exact feedback prompt for Checklist 1–28 through
the production service. `prompts` sends the inbox-routing and checklist-visual
catalog prompts through their production services, and `prompt150` additionally
applies the real returned operations to an isolated in-memory SwiftData store.
The endpoint and model default to `https://api.deepseek.com` and
`deepseek-v4-flash`; optional
`TIMETRACKER_LIVE_LLM_ENDPOINT` and `TIMETRACKER_LIVE_LLM_MODEL` overrides exist
for an explicitly requested provider run. The Makefile bridges the environment
value into the isolated Xcode test process and removes that bridge when the test
finishes.

Build for iOS device:

```sh
make build-ios
# equivalent:
# xcodebuild build -project timetracker.xcodeproj -scheme timetracker -destination 'generic/platform=iOS'
```

Final signed Release builds:

```sh
CONFIGURATION=Release make build-ios
CONFIGURATION=Release make build-macos
# equivalents:
# xcodebuild build -project timetracker.xcodeproj -configuration Release -destination 'generic/platform=iOS'
# xcodebuild build -project timetracker.xcodeproj -configuration Release -destination 'platform=macOS,arch=arm64'
```

Keep `CODE_SIGN_STYLE=Automatic` and team `LT98S43NKA`. Do not add `CODE_SIGNING_ALLOWED=NO`, `CODE_SIGNING_REQUIRED=NO`, or an empty team to make these commands pass. Simulator `Sign to Run Locally` is expected and is not device entitlement evidence.

Unit tests must construct the facade with `makeTestStore(...)`. That factory
uses an explicit in-process write authorization for in-memory fixtures; it does
not read, overwrite, or clear the developer's real `TimeTrackerPersistenceMode`
or recovery flags. Production and system-action stores keep the default
`applicationState` authorization and still enforce recovery read-only mode.
Tests that exercise external commands use `makeTestSystemActionCommandHandler()`
and `makeTestWatchCommandProcessor(...)` for the same reason; safety tests that
verify recovery blocking deliberately retain the production defaults.
The hosted unit-test app also selects `TimeTrackerUnitTestHost`, an isolated
in-memory container, before any production persistence or recovery path runs.

Scheme visibility check:

```sh
xcodebuild -list -project timetracker.xcodeproj
```

The output must include the app scheme `timetracker`. Shared schemes live in `timetracker.xcodeproj/xcshareddata/xcschemes` and must be committed with project changes.

Signed export:

```sh
make export-artifacts
```

Targeted UI verification enters through the Makefile and retains its `.xcresult` under
`build/UITestResults`:

```sh
make UI_TEST_ONLY=timetrackerUITests/timetrackerUITests/testName test-ui-ios
make UI_TEST_ONLY=timetrackerUITests/timetrackerUITests/testName test-ui-macos
```

`test-ui-ios` creates, records, boots, shuts down, and deletes one explicit simulator.
Override `UI_TEST_DEVICE_TYPE` and `UI_TEST_RUNTIME` for an iPad or another reviewed
runtime; do not borrow an existing Booted device implicitly.

Wide Today layout coverage pairs behavior and real geometry. `HomeLayoutPolicy`
tests fix the 1000 pt content-width breakpoint and the 678...748 / 300...410 pt
column conservation. The macOS UI fixture may request a deterministic test window
with `TIMETRACKER_UI_TEST_WINDOW_WIDTH` and
`TIMETRACKER_UI_TEST_WINDOW_HEIGHT`; the AppDelegate honors these values only
during UI testing. The iPad fixture uses an explicitly owned 13-inch landscape
simulator and hides the sidebar so the Today detail crosses the breakpoint. On
both platforms, assert that the real Weekly Gross Time and Quick Start headings
are horizontally separated and vertically overlap, then retain a normal-size
screenshot. Run the compact-shell Today regression separately on iPhone.

## What Must Stay Covered

The default UI matrix uses normal text sizes and ordinary interaction paths. The accessibility-specific invariants below protect already-implemented behavior, but maximum Dynamic Type, VoiceOver traversal, and dedicated accessibility screenshot/trace batches run only when the changed code affects text reflow/semantics, a regression is reported, or the release risk explicitly calls for them.

- Every new feature should first document its expected behavior in `Docs/Architecture.md` or a focused feature note, then add failing tests before implementation. If the behavior is UI-only, write the acceptance checklist before changing layout code.
- Gross vs wall-clock aggregation.
- Reference-time integrity: local manual/update writes reject future ends and future active starts; every read clips through `TrackedTimePolicy`. Cover `startedAt == now`, future-only rows, future-ended growth until its end, half-open range boundaries, DST elapsed seconds, gross/wall/summary/analytics/forecast/timeline/cache/range-query consistency, time-sensitive forward ticks, backward clock correction, and incremental equality with a full rebuild. UI behavior coverage also includes DatePicker `...now` bounds, shared validation/duration, clipped Today/Task Detail rows, zero future-only labels, and no periodic timer for fixed closed durations.
- Task tree moves and cycle prevention.
- Task hierarchy normalization: missing parent/cycle repair, canonical `/<UUID>` locator, derived title paths, bounded display depth, and no descendant write amplification on same-depth moves.
- Task lifecycle compatibility: archive is true when either `archivedAt` or legacy raw `archived` is present; archive writes both markers, hides the branch, rejects new work, and requires active timer/Pomodoro work in the subtree to stop first. Restore is parent-first and clears only archive markers. Ordinary task UI and production command/repository APIs expose no Delete path. Historical/imported tombstones remain hidden, win LWW as before, survive snapshot/reset flows, and are never revived by Restore. Legacy `planned`, `active`, and `completed` raw values remain accepted/round-trippable but behave like ordinary tasks in Today, Quick Start, Pomodoro, manual entry, Inbox suggestion, App Intent, create/move destinations, and task actions. UI behavior must show there is no workflow-status picker, badge, Complete action, Reopen action, completed-task blocker, or ordinary task Delete action.
- Daily recurrence runtime: cover frozen rule timezones and DST day keys, future start dates, current-day-only generation, no historical backfill, pause/replay/resume, archive gaps, foreground/midnight/clock-change rescheduling, and deterministic cross-scene retries. Every failure checkpoint must roll back the rule/task/goal/occurrence graph. Physical claims, tombstones, noncanonical identities, staged goal/task/occurrence rows, and occurrence-before-rule Cloud import must not be repaired or resurrected. Replay preserves user edits. Timer, Pomodoro, manual segment, break resume, and App Intent must reject templates while parent/content selectors retain templates and timer pickers retain unavailable ancestor containers for generated children. Creating a new rule must reject a template with active timer/Pomodoro work.
- Ordinary Task Detail identity: the shared identity row must show the task title and parent/root path. A direct-fixture iPhone/iPad UI test must query `task.detail.identity`, verify both strings and a nonzero frame vertically inside the detail viewport, and capture the ordinary-size screen; finding the same title only in the navigation bar or elsewhere on the page is not sufficient. The icon-only editor link remains a 44 pt target without a disclosure accessory slot; the UI test must constrain its width and the 14 pt gap to `task.editor.title.field`, capture the row before activation, and still prove the shared symbol picker opens.
- Apple Health Task Detail: the canonical Health fixture must expose Summary, Task Analysis, and Recent Records in that order at normal text size. `task.detail.appleHealth.periodFilter` remains after the Task Analysis header and retains Day/Week/Month, previous/next, and Today behavior without a fourth top-level section. A viewport-by-viewport lazy-List scan must prove ordinary identity/editor, availability, quantity, heatmap tracking, forecast, timer, Add Time, More/Archive, autosave, and recovery identifiers never appear. Preserve loading/empty/failure/retry/reactivation coverage, iPhone and iPad screenshots, and the macOS unavailable screenshot; ordinary-task identity/action tests remain the regression gate for the unaffected branch.
- Timer start, stop, and rapid-restart semantics. A new ordinary `.timer/.shortcut/.watch/.widget/.liveActivity` source may coalesce only the same canonical task's immediately preceding positive singleton session when `0 <= gap < 60s`, the gap has no other visible work, no visible PomodoroRun references that session, and admission is not `replaceAll`. Assert a new active segment ID, predecessor tombstone, preserved session/title/note/source/start, gap-inclusive duration, repeated-chain convergence, stale predecessor Stop no-op, current ID Stop success, exact-60/negative/different-task/intervening-work exclusions, and Manual/Calendar/Pomodoro isolation. Canonical Pomodoro duplicates must be resolved globally before relationship filtering. The operation stays inside the store-scoped atomic mutation; it emits a ranged history invalidation for the tombstone so a cross-midnight scene removes the old ID, strictly dominates future-dated duplicate metadata, and keeps subsequent Stop/Edit/Delete mutation dates monotonic so an older active Cloud copy cannot revive the timer. Snapshot/LWW restore plus same-timestamp Cloud redelivery must not revive the predecessor or re-close the session. The store-backed path keeps a 50,000-segment restart bounded and must not repeat the active-segment fetch, materialize all Pomodoro history, or issue one Pomodoro query per stopped session.
- Pomodoro persisted-phase deadline reconciliation: background/startup clipping, idempotency, explicit break continuation, generic timer stop, active segment edit/delete, and task-archive admission. Break continuation must re-evaluate canonical task-tree admission inside the mutation; archived, historical-tombstoned, missing, or unavailable-ancestor tasks are exact no-ops that preserve the break run and every unrelated active timer without refresh/sync events.
- Manual time edit/delete behavior, including active Pomodoro rebind/cancel/tombstone invariants.
- Demo data isolation: Debug/Release default off, separate local demo store, no CloudKit, UI-test in-memory store. Production tombstone purge must stay disabled; isolated Demo/UI Test purge only removes expired tombstone graphs. Seeding and rebuilding demo data additionally require `AppDemoDataConfiguration.allowsDemoDataMutation` — a DEBUG build alone is not enough, because with the shipping mode `off` the open store is the production CloudKit one.
- Test-host isolation: the macOS target is unsandboxed, so an `xctest` host shares the installed app's preference domain, Application Support directory, and App Group container. Never read or write `UserDefaults.standard` from app code or from a test that drives app state — go through `AppDefaults.shared`, which resolves to a private wiped-on-resolve suite under `AppRuntimeEnvironment.isTestHost`. The `SyncConflictService` state directory and the widget snapshot suite are namespaced the same way. `TestHostIsolationTests` is the gate: it asserts recovery flags, demo-mode overrides, and snapshot state written by a test stay invisible to `.standard`. An interrupted run that leaked those flags used to arm a destructive CloudKit reset on the user's next real launch.
- Synthetic rows: every non-user row is stamped with a `SyntheticDataOrigin` device ID (`demo`, `cloud-smoke`, `ui-test`), and maintenance cleanup matches on `SyntheticDataOrigin.marks(_:)`. A new kind of synthetic data must be registered there to be removable.
- Timeline lane layout for overlaps, adjacent tasks, and cross-day segments. Compact vertical fixtures must also expose the intrinsic time-label footprint and prove all surviving tick labels share the chart leading edge while remaining disjoint from localized skipped-gap capsules; measuring a full-width gutter slot is not valid evidence.
- Today Health-first record layout: use a deterministic fixture containing one counted Apple Health workout followed by one ordinary tracked segment. At normal text size, assert the Health time range does not intersect the chart, both record kinds share the real time/title leading edges, rows do not overlap, the ordinary menu remains present, and Health remains read-only. Keep visually reviewed iPhone, iPad, and macOS screenshots; macOS may validate the shared renderer with injected test data because HealthKit itself is unavailable there.
- Inbox capture commit semantics: blank input does not attempt a write; store/recovery/save failure returns false and preserves the exact visible draft; successful commit clears it once. Keep a behavior test for the draft state and UI coverage preventing the row from unconditionally clearing its binding.
- Inbox native-card presentation: launch the dedicated suggestion fixture with `replaceOnLaunch` at `UICTContentSizeCategoryL`, then verify capture/open/completed are native List cells with inset margins. A ready suggestion has three ordered rows: completion circle plus Inbox title; localized Suggested label plus generated icon/color and target; then independent Discard/Apply actions anchored to opposite card edges. On normal-size iPhone and iPad, assert the single-line title and completion button have equal `midY` within 2 pt, and Suggested `minX` equals the completion button `minX` plus the derived inset to the visible 24 pt circle. Both actions own at least a 44 pt target, compact width uses × / ✓, regular width uses icon-plus-text, and the proposal is one readable accessibility element. Applying removes the exact Inbox item. Keep visually reviewed normal-size iPhone and iPad operation-path screenshots plus capture and shared task-picker regressions; unavailable-target, failure, Reduce Motion, leaf-identifier behavior, and the shared circle-size/inset token remain covered by behavior tests.
- Inbox cross-scene reorder: carry the complete open-item order plus every `clientMutationID` into the store-scoped coordinator; after the shared lock and fresh fetch, reject newer completion/title/delete/add/reorder and even an order-only change that failed to rotate a mutation ID. Rejection must refresh the facade without writing any item or advancing sync generation; a fresh drag writes one canonical deterministic order.
- Synced user preferences, including legacy UserDefaults import. Every command batch must prevalidate all values by declared key type before mutation; malformed JSON, JSON `null`, wrong types, values over 256 KiB, and an invalid later entry leave all existing rows/timestamps/mutation IDs unchanged. Canonicalized valid values must persist once. Use a real read-only disk store to prove standalone command save failure rolls back and legacy oversized values are skipped instead of stored as `null`. A logical-key LWW tombstone counts as already migrated and must block stale UserDefaults from resurrecting that preference. Failed ordinary migration leaves its completion flag false and source value intact; failed secret redaction leaves SwiftData unchanged while retaining the safe Keychain copy. Test iCloud enablement separately as device-local startup state, including next-launch behavior and filtering of the historical synced key.
- Checklist add/update/delete/sort behavior and recursive rollup forecasting, including explicit estimates without checklist evidence, `TaskEstimatePolicy` zero/negative/overflow normalization, worked time exceeding estimate, a fully completed checklist producing `0` own remaining without locking the task, legacy completed raw remaining inert, checklist fallback with `0 completed` or `0 tracked time`, own estimate versus child rollups, and parent/child display rules.
- Schema compatibility: current registry is V14. Runtime-generated on-disk V8, V9, V11, and V12 stores prove the current migration path preserves user facts, removes the legacy `DailySummary` cache, carries Inbox identity/dismissal and destination kind forward, and adds empty writable recurrence/quantity tables without changing an existing V12 task; V4 category/status coverage remains. The lightweight V13→V14 migration adds `ChecklistItem.sortOrderBeforeCompletion` while V13-and-older schemas resolve `ChecklistItem` to a frozen snapshot type. V13/V14 snapshot tests distinguish missing optional keys from explicit empty arrays, exercise full and task-domain capture, restore, fingerprint, deterministic identities, future-dominating clear tombstones, and staged-orphan maintenance/read-model behavior. Snapshot preflight accepts all four historical task raw values, preserves them without bulk rewrite, and interprets only raw `archived` as a lifecycle marker. These are not immutable release-generated fixtures. The missing higher-confidence layer must use a released binary/tag and contemporaneous toolchain to generate a synthetic SQLite bundle, checkpoint/close it, record fixed IDs and SHA-256 hashes in a manifest, then migrate a fresh copy in each test. Never label a store generated from current schema declarations as an immutable historical artifact.
- Inbox suggestion identity: cover same-ID and different-ID siblings with newer content fields plus exact-revision dismissal, revision isolation, same-title unrelated items, title rotation, delete/apply/discard/reorder cleanup (including same-ID SwiftData objects), logical LWW delete/restore, old snapshot fields omitted, and full/partial capture round-trip. Async success and failure both need A→B→A stale-result tests. Apply tests must reject tombstones, non-canonical active siblings, detached old refresh IDs and title mismatches before creating checklist rows. Suggestion ordering uses `updatedAt` then UUID consistently. Identity remains opaque UUID metadata rather than a title-derived hash, and storage stays constant per record.
- Legacy Countdown migration: accept at most 256 KiB of JSON and 256 source records; allow titles up to 4 KiB by UTF-8 byte count and finite dates in `[1900-01-01, 2201-01-01)`; preserve valid UUIDs, keep the first valid record for duplicate UUIDs, retain distinct no-ID records, suppress import when SwiftData already has Countdown facts, and finalize the flag/payload only after a successful import save. Exercise a real read-only SwiftData store so a thrown `save()` proves the migration flag remains false and the legacy payload remains available for retry.
- Store refresh planning: each user invalidation event must map to domain-sized refresh scopes, carry affected task IDs where available, and combined invalidations must not silently escalate to a full refresh.
- Observation and external refresh: the main facade stays `@Observable` without `@Published`; CloudKit/remote-store notifications coalesce correctly, foreground activation refreshes once, and no permanent polling timer is reintroduced.
- Typed Cloud activity: cover import/export/setup success and failure, priority coalescing, remote-store-only refresh without success, local refresh/conflict/checkpoint post-processing failure overriding event success, account checks leaving activity untouched, and future or older-than-120-second activity never appearing as recent success.
- Deterministic sync: entity and preference LWW behavior is input-order independent, equal-time tombstones win, restored newer rows remain active, and duplicate cleanup cannot overwrite the canonical row. Automatic conflict resolution unions diverged local/cloud branches by record identity under the same LWW ordering (preferences by logical key, optional tables treating missing as unknown), accepts the merge without restoring when it equals the cloud branch, restores a validated merged winner otherwise, auto-resolves a pending conflict once both branches become mergeable again, and falls back to the explicit copy-choice prompt only when the merged snapshot fails validation or restore.
- Atomic writes: a multi-step store/system action saves once, rolls back all pending changes when any step/final save fails, and does not call an already committed mutation a failure when only post-commit refresh fails.
- Sync snapshot scope: Local/Demo/UI Test writes skip conflict capture; CloudKit/recovery writes refresh only domains selected by `StoreDomainEvent`; full import/baseline still captures all domains.
- Sync state serialization: same-process and external-process file-lock mutual exclusion, no lost update between service instances, authoritative-state quarantine/mirror precedence, corrupt pending-mirror quarantine without blocking the main store, 128 MiB authoritative-state and 64 MiB recovery-mirror read/write limits, metadata preflight plus `FileHandle` `limit + 1` growth detection, oversized sparse-file quarantine without whole-file loading, write-side state/mirror preflight before any file mutation, exact-boundary acceptance, old-file preservation after either payload is rejected, bounded checkpoints, epoch/generation matching, failed and out-of-order export callbacks, and legacy excluded-preference scrubbing that invalidates checkpoints tied to the old fingerprint.
- Snapshot restore hardening: before any atomic per-domain mutation, reject per-table/total record overflow, duplicate UUIDs, field/aggregate UTF-8 overflow, unsupported dates/raw values, non-finite or non-advancing sort orders, invalid Pomodoro duration/round values, malformed typed or unknown preference JSON, and provable session/task or Inbox suggestion-identity mismatches. Preserve staged imports with missing referenced records, and assert every rejection leaves sentinel facts and tombstones unchanged; malformed transport must not be silently collapsed or clamped. Keep the explicit-snapshot scope separate from initial CloudKit records materialized directly into a SwiftData context.
- Local file protection: on iOS the authoritative sync state, pending forced-upload mirror, and corrupt-state quarantine files resolve to `completeUntilFirstUserAuthentication`; test the first-unlock/background availability contract without treating the lock file as user data.
- System actions: App Intents reuse the application model container, respect the parallel-timer preference, filter tombstoned/archived tasks while treating legacy planned/active/completed raw values as ordinary, obey recovery read-only mode, and refresh Widget/Watch/Live Activity only after commit without converting projection failure into mutation failure.
- Live Activity presentation: Lock Screen and expanded Dynamic Island reuse one timer row; the fresh expanded normal-size hierarchy contains only task icon, title, and elapsed time in one row, with a stale-state glyph as the sole status exception and a safe stacked fallback when the system-proposed width cannot fit the complete row. Tapping opens Today; no Live Activity stop intent, extra-timer badge, or app-opening stop copy remains. Compact and minimal keep the canonical start date and a live three-field stopwatch beyond eight hours; a stale label never freezes or shortens the elapsed value, and projected identity text stays below its Unicode-safe payload limits. `LiveActivitySystemSurfaceUITests` is a screenshot slice for explicitly audited Dynamic Island simulator models and skips other destinations rather than treating an iPad or notch-only iPhone as a layout failure. Its geometry checks assert visibility and non-overlap, not exact screen-midline or point-gap coordinates; retained screenshots and whole-surface OCR prove the complete long clock remains visibly present.
- Widget/Watch snapshot boundary: producer count caps, Unicode-safe projected title/path/style prefixes, nonnegative summary and timer-start clamping, shared 128 KiB aggregate text budget, Widget JSON at or below 256 KiB, Watch 64 active/256 recent, validator save/load rejection, finite/future-skewed dates, active age, unique timer/task IDs, missing versus corrupted versus unavailable Widget results, and no standard-UserDefaults fallback. Shaping changes DTOs only; canonical facts remain unchanged.
- System input routing: deep-link URL length/authority/path/query/UUID validation, semantic deduplication, 16-entry FIFO pending capacity, drain/clear lifecycle, and no execution before repositories are ready. The Watch bridge router must retain stores weakly, prefer the most recently active scene, fall back deterministically, remove released registrations, and uninstall its callback when no scene remains.
- Calendar boundaries and caching: 23/25-hour DST days, cross-midnight intervals, same-day clipped subranges, cache-key separation, and local invalidation.
- LLM transport: valid localhost/IPv4/IPv6 loopback, spoofed loopback names, remote HTTP, same-origin redirect, cross-host/port redirect, HTTPS downgrade, ephemeral/no-cache/no-cookie configuration, 60-second resource timeout, exact 2 MiB acceptance, first over-limit byte cancellation, Content-Length preflight, non-2xx body avoidance, waiting/streaming cancellation, typed timeout, injected-transport defense, and HTTP-status error priority.
- Device identity: accept and stably reuse only the current platform prefix plus canonical UUID; reject/regenerate cross-platform, malformed, noncanonical, control-character and oversized persisted values, and prove generated identifiers contain no host or account name.
- LLM complete request serialization: Inbox includes every eligible Task and visible Category in deterministic, de-duplicated order; Inbox/checklist/task planning preserve complete Unicode fields and advertise the same complete canonical SF Symbols catalogue as the picker. Exercise requests above the retired 64 KiB projection without losing the last candidate or symbol. Assert whole-value 256-byte model-ID validation, endpoint/API-key transport boundaries, non-candidate task/category rejection, 512-byte persisted reason normalization, canonical source text remaining untouched, and actual Authorization-header placement without a provider-response mock.
- LLM configuration and thinking policy: Test→Save draft normalization, `high`/`max` effort validation and synced round trip, stale request cancellation including effort changes, valid model gating, one batched endpoint/model/effort preference save, Keychain compensation on preference failure, discard confirmation, device-only Keychain migration/filtering, and automatic suggestions default-off/local-only consent. Decode the actual Inbox/checklist `URLRequest` to prove DeepSeek V4 sends thinking enabled plus the selected effort with no temperature; task-workspace effort is accepted only after the real endpoint gate.
- AI task workspace planning: prove the canonical capture is input-order independent, retains every visible Category/Task/Checklist stable ID and the complete ancestor path without arbitrary count/depth truncation, includes task metadata/quantity goal/daily recurrence, and keeps device IDs plus every local mutation revision outside the encoded provider snapshot. The provider-visible snapshot fingerprint must be deterministic and change when any transmitted fact changes. A large workspace must produce a request above the legacy 64 KiB suggestion budget without losing its final entity; encoding failure must issue no request, while provider HTTP 400/413/422 rejection must be typed and report Category/Task/Checklist counts plus actual encoded request bytes rather than retrying a partial request.
- AI tool protocol and overlay: use deterministic local tests for strict schemas (`required` plus `additionalProperties: false`), assembler mechanics, pure overlay CRUD/read-after-write, App-generated IDs, unique normalized Category reuse, same-name ambiguity, inert prompt-shaped data, cross-kind identity conflicts, orphan/cycle/child-category rejection, depth six acceptance plus depth seven rejection before writes, Task Archive-only, and absence of count-based truncation. Prebuilt provider responses, tool-call sequences, or plans are not model-generation acceptance. `make test-llm-live` must read a short-lived key from the local `.env`/environment and use the three production services against the real endpoint for Inbox, Checklist, prompt28, and prompt150 at `max`; prompt150 must Apply through the production coordinator and re-read 150 persisted items. Never print the key or source it from feedback documentation.
- AI review and atomic apply: test deterministic baseline→overlay diff counts and before→after context, read-only review, `Apply N Changes`, native destructive confirmation, full paths for same-named Tasks, owning Task context for Checklist changes, and preview preservation on stale/provider/tool/apply error. At the command boundary, mixed Category/Task/Checklist CRUD must use one shared-lock fresh-context atomic mutation; exact full-workspace CAS covers provider-visible facts and Category/Task/assignment/Checklist/visual/quantity-goal/recurrence revisions. Cover stale changes in every domain, same-name Category races, protected Health identities, active work, invalid/colliding operation replay, zero events on rejection, rollback after every injected checkpoint, targeted Checklist revision isolation, and successful Task removal leaving `deletedAt` untouched.
- Privacy-complete reset: successful “clear all” removes the Keychain API key and device-local automatic-suggestion consent; an injected SwiftData failure restores both external values and leaves the device-local iCloud startup switch unchanged.
- Watch command lifecycle: persistent queue encoding, seven terminal statuses, durable result payload, 20-second timeout, 30-second maximum command age, bounded future clock skew, stale-command rejection before receipt/ledger mutation, retry with the same ID and refreshed issue date, discard, duplicate idempotency, and legacy snapshot-reflection compatibility. Treat payload/restore data as untrusted: cover non-finite/future dates, UTF-8 field bytes, summary/active-age bounds, the 64-active/256-recent snapshot counts, duplicate IDs, command/result ID mismatch, 64-item incoming/pending/failed queue limits, 512 KiB encoded queue limit, safe-boundary round trips, unsafe-state clearing, and `queueOverflow` behavior.
- Incremental read models: range-scoped ledger/session replacement, task-scoped checklist/visual replacement, rollup delta plus ancestor propagation, 90-local-day active-day pace window, active/future-ended time-sensitive ticks, backward-clock full reevaluation, and equality with a full rebuild. Task-tree coverage must also compare the indexed projection with the former category+flattener semantics; preserve persistent row/section identity; prove store-owned revision invalidation for task/category/assignment changes but not timer or equivalent refreshes; bound hierarchy/search LRU entries; and use a 5,000-node operation count to require one child-bucket lookup per visible task with no repeat build for the same revision/key.
- Analytics period evaluation, comparison, daily trends, overlap excess, caches, and refresh scheduling: current cutoff equals live wall clock; completed historical cutoff equals the exact half-open period end; future cutoff equals period start; 23/25-hour DST periods, final-second inclusion, exact hour totals, zero-length exclusion, historical open-segment clipping, and selected-period cache identity are required. View request and full/task caches must use the same `AnalyticsEvaluationCacheKey`; idle current week/month requests miss across local midnight even though period start and live-minute bucket are unchanged, while completed history remains stable across later wall-clock days. Cached snapshot models must not expose or retain `[TimeSegment]`; duplicate-resolution tests assert through public overview/daily/timeline/task projections. Live today/week/month comparisons must clip both sides to matching calendar progress, exclude later previous-period activity, preserve local wall-clock time across DST, and clamp long-month progress at a shorter previous month's end; completed historical periods compare full against full and future periods compare empty matched windows. A current month emits only elapsed local days while a completed historical month emits every day and a future month emits none; the cache still owns the complete period's bucket set, and subminute points retain fractional-minute chart values. Every overlap suite must assert `sum(window.excessDurationSeconds) == overview.grossSeconds - overview.wallSeconds`, with `(concurrentSegmentCount - 1) × wall duration` semantics across staggered 3+ concurrency, same-task duplicate segments, equal end/start boundaries, adjacent same-task replacement, zero/negative rows, cross-midnight 23/25-hour DST clipping, deterministic tie ordering, and subsecond remainder allocation. A top-window UI must report both hidden window count and hidden excess total. Indexed historical reads must prove their candidate set stays range-scoped when the real clock has not moved backward; a genuine rewind must still widen safely. Also cover same-period hits, cross-day/week/month misses, task-specific keys, historical live-bucket absence, active-only minute buckets, mutation invalidation, and intersecting ledger day-bucket invalidation. The refresh-plan suite must cover exact absolute minute rollover, stale-bucket recovery, historical ranges scheduling no clock task, same-bucket wall-clock rescheduling, and local midnight across DST. Both Analytics landing and detail pages must stay free of full-page `TimelineView`, with active-scene cancellable `.task(id:)` ownership, scene/time-zone/clock resampling, a visible Wall/Gross trend legend, explicit overlap excess labels/hidden totals, and per-point VoiceOver duration values.
- Analytics range-switch presentation acceptance: pure phase tests cover no snapshot, exact request, same-period revision/live refresh, cross-day, and cross-range requests. A normal-text XCUITest uses a test-only cold-reload hold to inspect the actual mid-refresh frame: period controls and Review remain mounted, their vertical positions move by at most 2pt, Week/Month screenshots show stable redacted shells rather than a blank replacement, and returning to an exact cached Day request never exposes the refresh identifier. The hold is enabled only by `--uitesting` plus its dedicated argument and must not affect production or Release.
- Analytics Definitions acceptance: the explanatory source must not contain a repeated `info.circle`; it must expose stable introduction, Gross, Wall, Overlap, and worked-example identifiers. Each metric states a plain-language meaning and calculation, while one concurrent-timer example reconciles Gross 1h, Wall 30m, and Overlap Excess 30m. English, Simplified Chinese, and Traditional Chinese require the same subtitle, calculation, and example keys. The focused UI route must open Analytics → “How much time did I spend?” → Totals & Definitions, find all four semantic rows, and capture the complete card above platform chrome.
- Analytics navigation acceptance: the landing page must use native `List` sections and typed `NavigationLink` rows. Review contains Decisions then Quality; Explore contains Time, Tasks, Pomodoro, then Totals & Definitions, and the two arrays together cover every `AnalyticsCategory` exactly once. Normal-size iPhone and iPad UI runs must read both section title/subtitle pairs, verify every row exposes its question, current answer, and explicit detail destination, then open Tasks & Categories and capture Category Distribution as its first analysis section. Category breakdown buckets remain non-interactive until a real detail route and back path exist; tests must not infer drill-down from a tinted label or decorative disclosure.
- Analytics month navigation: cover Jan 31 → Feb 28 → Mar 31, leap-year Feb 29 recovery, backward month-end traversal, preservation of local hour/minute/second across a DST offset change, and returning `liveNow` while clearing the anchor when entering the current month. One root-owned anchor is shared by landing/detail and every adaptive period-control branch; direct date selection, range changes, and Today reset it.
- Analytics hourly activity scale: verify the shared upper bound stays at 3,600 seconds for ordinary days, expands to the largest cross-day hourly gross total when concurrency exceeds one hour, preserves a fractional height for a 1...59-second bucket, produces zero height for empty/invalid inputs, keeps every positive task slice, and conserves each scaled hour target across those slices. All 24 bars share one scale, with zero layout spacing and overlay-only separators, a Dynamic Type-aware chart height, a horizontally fitting header fallback, 0/12/24 axis markers and a single-column legend at accessibility sizes, explanatory height/color copy in all three locales, and unchanged localized per-hour VoiceOver values.
- Accessibility-size information parity: Today must keep the active-state timer action as a visible, wrapping verb label in the Now content flow. The shared Tasks visual row deliberately retains the title, checklist progress, passive running icon, worked duration, and navigation affordance; it may stack those facts at accessibility sizes but must not add a Stop command to the passive row. Canonical full path, forecast, projected days, and child count remain available through the ordered accessibility value and their corresponding detail surfaces rather than permanently competing with the title in the visual row. Neither projection may reintroduce a workflow-status value. Large-text UI tests must actually pass `UICTContentSizeCategoryAccessibilityXXXL`, not rely on a test name. Automated evidence does not replace a human VoiceOver traversal.
- Shared task-row and timer-action acceptance: Tasks, Sidebar, hierarchy-picker selection rows, and `TaskIdentityRow` all reuse `TaskSummaryRow`; Today, Quick Start, and every timer-picker Start/Switch/Stop reuse `TaskTimerActionButton`. At normal text size, verify a long title grows to two lines before metadata is compressed; a hierarchical row's second summary line is checklist progress, flexible space, passive timer icon, worked duration, then navigation/accessory, while a standard row may insert its parent path before that metadata line. A passive timer icon must never expose Stop, and Start/Switch/Stop must not be reintroduced as metadata accessories. In the timer picker, each row exposes a separate read-only task summary plus one explicit action; Start, Switch, and Stop use the same fixed icon-only control dimensions and trailing edge (54×54 pt on iOS/iPadOS, satisfying the 44 pt minimum target; 28×28 pt on macOS), while Stop never inherits the whole row's hit frame. Every active task has exactly one Stop target and no duplicate per-row Running badge/text beyond the section context. Run the same UI assertion at normal text size on iPhone and iPad, capture the mixed running/available state, then Stop one task and verify its new Start control retains the same width, height, and trailing position while the picker remains presented. Successful Start/Switch may dismiss; Pomodoro and Inbox single selection must not mutate timer state.
- Command handlers: durable writes such as timer, task, pomodoro, ledger, countdown, checklist, and preference changes must have behavior tests at the command boundary before UI wiring changes.
- Project structure: app and extension schemes must remain shared and source-controlled; filesystem moves should be followed by `xcodebuild -list` plus a generic iOS build.
- Platform declarations: verify main App `1C8F.1`/`CA92.1`, Widget `1C8F.1`, and Watch `CA92.1` Privacy manifest reasons against actual UserDefaults/App Group use, and verify no `CADisableMinimumFrameDurationOnPhone` override is reintroduced without a measured, reviewed need.
- Project map: semantic folder moves must update `Docs/ProjectMap.md` in the same change.
- Month analytics labels using real day numbers rather than repeated weekday names.
- Localization key parity across English, Simplified Chinese, and Traditional Chinese. `Localizable.strings` is covered for the main app, Live Activity, Widget, and Watch; main-app `AppShortcuts.strings` and every target's `InfoPlist.strings` also require a direct parity/plist check because the current localization unit suite does not cover those two resource families.
- No hard-coded Chinese text in Swift source files.

## UI Testing

UI tests should rely on accessibility identifiers for core controls, not translated strings, whenever possible.

Wide Today current-state layout tests use `home.activeTimers.title`, `home.overview.header.title`, `home.now.card`, and `home.overview.card` as leaf/container probes. With deterministic demo data and a valid visible frame, macOS and landscape iPad must place the two visible title tops and the two first-card tops within 2 pt of each other while preserving separate columns. Do not compare a title leaf to an outer section group or relax the tolerance to hide a real header-slot mismatch. The iPhone compact regression remains single-column and is not subject to the wide geometry assertion.

The default review and runtime matrix prioritizes normal text sizes, normal user workflows, and platform-specific Apple HIG behavior. Keep native control names, roles, values, states, non-color-only communication, and reasonable hit targets as baseline accessibility requirements. Existing large-text adaptations must not regress, but maximum Dynamic Type is a targeted, risk-triggered check rather than the recurring main line: add it when a change affects text reflow/truncation, an accessibility regression is reported, or the release risk calls for it.

The shared app scheme deliberately keeps the unit-test target parallelizable while marking the UI-test target nonparallelizable. UI tests launch one stateful app, seed shared persistence, and capture ordered screenshots; allowing Xcode to clone that runner can duplicate extensions, race the same fixture, and leave orphaned XCTest devices after a launch failure. Do not turn target-level UI parallelization back on. A device matrix may still run concurrently when the primary agent explicitly owns and records each destination. Acceptance screenshot runs should also pass `-parallel-testing-enabled NO -maximum-parallel-testing-workers 1` so the command line makes that ownership unambiguous.

The root-flow matrix must cover iPhone five-tab navigation plus Today-hosted Settings, iPad/macOS split navigation, sidebar-to-task-workspace routing, in-place workspace edit/save/cancel/stale-reload paths, searchable hierarchical start-task picker, ordinary behavior for legacy planned/active/completed raw tasks, hidden archived branches, absence of workflow status/complete/reopen UI, explicit estimate editing/forecast source copy, visible timeline action menu, Settings categories, AI Test→Save draft/discard, and explicit Pomodoro Plan/Task menus. Resize the same iPad scene through full-screen, split-view compact width, and Stage Manager sizes: it must remain the iPad `NavigationSplitView`, preserve its destination/detail state, and let the system collapse or reveal columns instead of constructing the iPhone tab root. An iPad baseline must use the system “Show Sidebar” control when `NavigationSplitView` starts detail-only; missing sidebar rows are a failure, not a reason to skip the remaining matrix. The automated orientation checkpoint captures the whole iOS screen with `XCUIScreen.main.screenshot()` because `app.screenshot()` can preserve a stale app-window transform during rotation; macOS continues to capture the app window. Rotation proves same-scene identity across two full-screen geometries, while compact Split View and Stage Manager remain required manual checks. On macOS verify there is one main app window and that the standard Settings scene shares live state without duplicating automatic work. The default manual pass uses normal text sizes and inspects light/dark appearance, long localized task names, Settings input/value layout, basic VoiceOver row values and sync feedback, destructive roles/confirmations, chart values, and bottom-of-list actions that could be obscured by the tab bar. Add maximum Dynamic Type only under the risk triggers above. For bottom actions, `isHittable` alone is insufficient: the entire control frame must finish above the current system tab-bar frame before capturing the acceptance screenshot. `testAnalyticsFinalCategoryScrollsAboveSystemChrome` enforces that contract for the final Explore destination by using its stable `analytics.category.overview` identifier.

## Resource Ownership And Cleanup

Every simulator, UI test, screenshot, profiling, DeviceHub, or Instruments batch has one explicit owner. Before launch, record a batch identifier, agent/owner, every destination UDID, whether each simulator was created or merely borrowed, tested App and runner bundle identifiers, owned `xcodebuild`/`xctest`/trace process or session identifiers, DerivedData/result/trace paths, and whether the batch opened Simulator, Xcode DeviceHub, or Problem Reporter. Parallel device matrices are allowed, but each destination has its own owner and UI tests keep one non-cloned runner per target.

Cleanup is part of the batch result and must run after success, failure, cancellation, or timeout:

1. Stop or cancel only the owned test/profile command and wait for its owned `xcodebuild`, `xctest`, UI runner, and trace writer to finish. Do not use broad `killall` or terminate another agent's process.
2. Terminate the tested App, its owned UI runner, and App extensions started by the batch on the exact destination. Stop every owned Instruments or trace process and confirm the trace has finalized before inspecting it.
3. Shut down every simulator the batch booted. Delete every simulator created for the batch; if a pre-existing device was explicitly borrowed, restore changed orientation/content-size settings and leave it shut down rather than deleting it.
4. Close Simulator, Xcode DeviceHub, and Problem Reporter only when this batch opened them and no other active owner is using them. Prefer CLI cleanup; use UI automation only for state the CLI cannot release safely.
5. Audit `simctl` and the process list: no owned UDID remains `Booted`, and no owned App, `xcodebuild`, `xctest`, UI runner, App extension, DeviceHub task, Problem Reporter window/process, or trace process remains. Record the cleanup result beside the xcresult/screenshots/trace.

If any owned resource remains, the batch is incomplete even when its assertions passed. Report the residual identifier and continue safe cleanup; never hide a cleanup failure by claiming the run is complete.

## Performance And Smoothness Verification

Runtime smoothness is a product requirement. The app should not feel slower than a native Apple productivity app on macOS, iPad, or iPhone.

Use two complementary checks:

1. Automated performance budget tests for deterministic domain work. These belong in `CorePerformanceBudgetTests` and cover analytics snapshots, day-bucket summaries, overlap detection, task tree flattening, checklist rollups, timeline layout, and a 50,000-segment single-record rollup mutation plus cached recent-task ranking. The current alarms are `< 0.25 s` for incremental refresh and `< 0.10 s` for cached ranking. The incremental result must equal a fresh full rebuild; these wall-time thresholds are regression alarms for the test environment, not a device SLA.
2. Release profiling on macOS and real iPhone/iPad for frame pacing, scrolling, chart drawing, resize behavior, sheet presentation, and touch latency. These cannot be proven reliably by unit tests because SwiftUI rendering, device thermals, refresh rate, and OS scheduling all affect the result.

Before attempting performance fixes:

1. Reproduce the hitch with a seeded large-data profile.
2. Compare Debug and Release behavior.
3. Record whether the issue happens during scrolling, window resize, navigation, sheet presentation, timer text updates, chart rendering, or iCloud refresh.
4. Use Instruments before changing architecture:
   - Time Profiler for CPU-heavy refresh or layout work.
   - Animation Hitches or Core Animation instruments for dropped frames.
   - SwiftUI body/signpost instrumentation around domain refreshes, analytics snapshot creation, rollup refresh, and chart views.

Performance fixes should prefer removing unnecessary work over hiding it with animation:

- Views should render cached snapshots rather than recompute analytics or rollups in `body`.
- Only active duration labels should refresh every second.
- List row identities must be stable.
- Expensive refreshes should be scoped by `StoreDomainEvent` and `StoreRefreshPlan`.
- Custom animations should be removed unless they clarify state changes.

Manual macOS smoothness checklist:

1. Launch with large seeded data.
2. Resize the main window from narrow to wide and back.
3. Scroll Today timeline, Tasks, and Analytics.
4. Open and close task editor, settings, and manual time entry.
5. Start and stop timers while Today is visible.
6. Switch Today, Tasks, Pomodoro, and Analytics several times, then repeatedly open and close Settings from its platform-standard entry.
7. Verify that no action causes visible multi-frame pauses in Release.

For an iOS Simulator, use the Time Profiler template because the SwiftUI instrument lane is empty there. For a real iPhone/iPad or host Mac, use the SwiftUI template. Record the exact app PID/installation used, then confirm the `.trace` is nonempty before drawing conclusions.

Every screenshot/profile run follows the ownership and cleanup contract above. A screenshot or trace without a recorded owner, exact destination, finalized artifact, and empty owned-resource audit is diagnostic only and cannot be final evidence.

## Device Verification

Before handing a build to manual testing:

1. Run macOS unit tests (`make test`).
2. Run macOS UI tests.
3. Build a generic iOS device archive or export signed artifacts (`make build-ios` or `make export-artifacts`).
4. Install the exported iOS app bundle on the paired iPad and iPhone with `devicectl`, or use `make build-install-all` to build and install iOS+Watch+macOS in one step.
5. Launch the app once on each device to catch signing, extension, and launch-time persistence failures.

## Final Evidence Record

Only the last run against a frozen source state may be reported as final evidence for that exact scope. Record commands, pass/fail/skip counts, signing identity/profile/entitlement checks, simulator screenshots, trace, and cleanup in the commit or PR that ships the change (the dated `Audit-*.md` snapshots were retired on 2026-07-25 in favor of git history). Targeted suites and earlier green builds remain useful diagnostics but cannot be added together and presented as one full pass. The 2026-07-17 R1 closure (commits `e30fd6a`/`55f19ae`) recorded its final targeted tests, performance suite, signed Release archive, and empty owned-resource audit; complete unit/UI/device/trace matrices that were not run are explicitly marked “not executed” rather than left as placeholders. Running such a matrix later requires a separate, bounded release-verification task and does not reopen the completed refactor by default.
