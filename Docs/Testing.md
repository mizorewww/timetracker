# Testing

Status: current verification policy

Reviewed: 2026-07-16

## Baseline Commands

Unit tests on macOS:

```sh
xcodebuild test -project timetracker.xcodeproj -scheme timetracker -destination 'platform=macOS' -only-testing:timetrackerTests
```

Build for iOS device:

```sh
xcodebuild build -project timetracker.xcodeproj -scheme timetracker -destination 'generic/platform=iOS'
```

Final signed Release builds:

```sh
xcodebuild build -project timetracker.xcodeproj -scheme timetracker -configuration Release -destination 'generic/platform=iOS'
xcodebuild build -project timetracker.xcodeproj -scheme timetracker -configuration Release -destination 'platform=macOS,arch=arm64'
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
./scripts/export_signed_artifacts.sh
```

## What Must Stay Covered

- Every new feature should first document its expected behavior in `Docs/Architecture.md`, `Docs/ArchitecturePlan.md`, or a focused feature note, then add failing tests before implementation. If the behavior is UI-only, write the acceptance checklist before changing layout code.
- Gross vs wall-clock aggregation.
- Reference-time integrity: local manual/update writes reject future ends and future active starts; every read clips through `TrackedTimePolicy`. Cover `startedAt == now`, future-only rows, future-ended growth until its end, half-open range boundaries, DST elapsed seconds, gross/wall/summary/analytics/forecast/timeline/cache/range-query consistency, time-sensitive forward ticks, backward clock correction, and incremental equality with a full rebuild. UI contracts must also cover DatePicker `...now` bounds, shared validation/duration, clipped Today/Task Detail rows, zero future-only labels, and no periodic timer for fixed closed durations.
- Task tree moves and cycle prevention.
- Task hierarchy normalization: missing parent/cycle repair, canonical `/<UUID>` locator, derived title paths, bounded display depth, and no descendant write amplification on same-depth moves.
- Task availability boundaries: archived/deleted branches are hidden, while completed branches stay visible but are excluded from new work. Today picker, Quick Start, Pomodoro, manual entry, Inbox suggestion, App Intent, create/move destinations, and task actions agree on completed/archived/deleted ancestors; completion/archive of a running subtree requires stopping first, existing active timers remain stoppable, one reopen action restores every completed blocker on the selected path, and historical segment editing may retain its original task.
- Timer start and stop semantics.
- Pomodoro persisted-phase deadline reconciliation: background/startup clipping, idempotency, explicit break continuation, generic timer stop, active segment edit/delete, and task-tree deletion consistency. Break continuation must re-evaluate canonical task-tree admission inside the mutation; completed, archived, deleted, missing, or ancestor-blocked tasks are exact no-ops that preserve the break run and every unrelated active timer without refresh/sync events.
- Manual time edit/delete behavior, including active Pomodoro rebind/cancel/tombstone invariants.
- Demo data isolation: Debug/Release default off, separate local demo store, no CloudKit, UI-test in-memory store. Production tombstone purge must stay disabled; isolated Demo/UI Test purge only removes expired tombstone graphs.
- Timeline lane layout for overlaps, adjacent tasks, and cross-day segments.
- Inbox capture commit semantics: blank input does not attempt a write; store/recovery/save failure returns false and preserves the exact visible draft; successful commit clears it once. Keep a behavior test for the draft state and a UI contract preventing the row from unconditionally clearing its binding.
- Synced user preferences, including legacy UserDefaults import. Every command batch must prevalidate all values by declared key type before mutation; malformed JSON, JSON `null`, wrong types, values over 256 KiB, and an invalid later entry leave all existing rows/timestamps/mutation IDs unchanged. Canonicalized valid values must persist once. Use a real read-only disk store to prove standalone command save failure rolls back and legacy oversized values are skipped instead of stored as `null`. A logical-key LWW tombstone counts as already migrated and must block stale UserDefaults from resurrecting that preference. Failed ordinary migration leaves its completion flag false and source value intact; failed secret redaction leaves SwiftData unchanged while retaining the safe Keychain copy. Test iCloud enablement separately as device-local startup state, including next-launch behavior and filtering of the historical synced key.
- Checklist add/update/delete/sort behavior and recursive rollup forecasting, including explicit estimates without checklist evidence, `TaskEstimatePolicy` zero/negative/overflow normalization, worked time exceeding estimate, completed task/checklist to `0` remaining, checklist fallback with `0 completed` or `0 tracked time`, own estimate versus child rollups, and parent/child display rules.
- Schema compatibility: current registry is V10. Runtime-generated on-disk V8 and V9 stores prove the current migration path preserves user facts, removes the legacy `DailySummary` cache, and carries Inbox identity/dismissal through V9→V10; V4 category coverage remains. These are not immutable release-generated fixtures. The missing higher-confidence layer must use a released binary/tag and contemporaneous toolchain to generate a synthetic SQLite bundle, checkpoint/close it, record fixed IDs and SHA-256 hashes in a manifest, then migrate a fresh copy in each test. Never label a store generated from current schema declarations as an immutable historical artifact.
- Inbox suggestion identity: cover same-ID and different-ID siblings with newer content fields plus exact-revision dismissal, revision isolation, same-title unrelated items, title rotation, delete/apply/discard/reorder cleanup (including same-ID SwiftData objects), logical LWW delete/restore, old snapshot fields omitted, and full/partial capture round-trip. Async success and failure both need A→B→A stale-result tests. Apply tests must reject tombstones, non-canonical active siblings, detached old refresh IDs and title mismatches before creating checklist rows. Suggestion ordering uses `updatedAt` then UUID consistently. Identity remains opaque UUID metadata rather than a title-derived hash, and storage stays constant per record.
- Legacy Countdown migration: accept at most 256 KiB of JSON and 256 source records; allow titles up to 4 KiB by UTF-8 byte count and finite dates in `[1900-01-01, 2201-01-01)`; preserve valid UUIDs, keep the first valid record for duplicate UUIDs, retain distinct no-ID records, suppress import when SwiftData already has Countdown facts, and finalize the flag/payload only after a successful import save. Exercise a real read-only SwiftData store so a thrown `save()` proves the migration flag remains false and the legacy payload remains available for retry.
- Store refresh planning: each user invalidation event must map to domain-sized refresh scopes, carry affected task IDs where available, and combined invalidations must not silently escalate to a full refresh.
- Observation and external refresh: the main facade stays `@Observable` without `@Published`; CloudKit/remote-store notifications coalesce correctly, foreground activation refreshes once, and no permanent polling timer is reintroduced.
- Deterministic sync: entity and preference LWW behavior is input-order independent, equal-time tombstones win, restored newer rows remain active, and duplicate cleanup cannot overwrite the canonical row.
- Atomic writes: a multi-step store/system action saves once, rolls back all pending changes when any step/final save fails, and does not call an already committed mutation a failure when only post-commit refresh fails.
- Sync snapshot scope: Local/Demo/UI Test writes skip conflict capture; CloudKit/recovery writes refresh only domains selected by `StoreDomainEvent`; full import/baseline still captures all domains.
- Sync state serialization: same-process and external-process file-lock mutual exclusion, no lost update between service instances, authoritative-state quarantine/mirror precedence, corrupt pending-mirror quarantine without blocking the main store, 128 MiB authoritative-state and 64 MiB recovery-mirror read/write limits, metadata preflight plus `FileHandle` `limit + 1` growth detection, oversized sparse-file quarantine without whole-file loading, write-side state/mirror preflight before any file mutation, exact-boundary acceptance, old-file preservation after either payload is rejected, bounded checkpoints, epoch/generation matching, failed and out-of-order export callbacks, and legacy excluded-preference scrubbing that invalidates checkpoints tied to the old fingerprint.
- Snapshot restore hardening: before any atomic per-domain mutation, reject per-table/total record overflow, duplicate UUIDs, field/aggregate UTF-8 overflow, unsupported dates/raw values, non-finite or non-advancing sort orders, invalid Pomodoro duration/round values, malformed typed or unknown preference JSON, and provable session/task or Inbox suggestion-identity mismatches. Preserve staged imports with missing referenced records, and assert every rejection leaves sentinel facts and tombstones unchanged; malformed transport must not be silently collapsed or clamped. Keep the explicit-snapshot scope separate from initial CloudKit records materialized directly into a SwiftData context.
- Local file protection: on iOS the authoritative sync state, pending forced-upload mirror, and corrupt-state quarantine files resolve to `completeUntilFirstUserAuthentication`; test the first-unlock/background availability contract without treating the lock file as user data.
- System actions: App Intents reuse the application model container, respect the parallel-timer preference, filter non-trackable completed/tombstone/archived tasks, obey recovery read-only mode, and refresh Widget/Watch/Live Activity only after commit without converting projection failure into mutation failure.
- Widget/Watch snapshot boundary: producer count caps, Unicode-safe projected title/path/style prefixes, nonnegative summary and timer-start clamping, shared 128 KiB aggregate text budget, Widget JSON at or below 256 KiB, Watch 64 active/256 recent, validator save/load rejection, finite/future-skewed dates, active age, unique timer/task IDs, missing versus corrupted versus unavailable Widget results, and no standard-UserDefaults fallback. Shaping changes DTOs only; canonical facts remain unchanged.
- System input routing: deep-link URL length/authority/path/query/UUID validation, semantic deduplication, 16-entry FIFO pending capacity, drain/clear lifecycle, and no execution before repositories are ready. The Watch bridge router must retain stores weakly, prefer the most recently active scene, fall back deterministically, remove released registrations, and uninstall its callback when no scene remains.
- Calendar boundaries and caching: 23/25-hour DST days, cross-midnight intervals, same-day clipped subranges, cache-key separation, and local invalidation.
- LLM transport: valid localhost/IPv4/IPv6 loopback, spoofed loopback names, remote HTTP, same-origin redirect, cross-host/port redirect, HTTPS downgrade, ephemeral/no-cache/no-cookie configuration, 60-second resource timeout, exact 2 MiB acceptance, first over-limit byte cancellation, Content-Length preflight, non-2xx body avoidance, waiting/streaming cancellation, typed timeout, injected-transport defense, and HTTP-status error priority.
- Device identity: accept and stably reuse only the current platform prefix plus canonical UUID; reject/regenerate cross-platform, malformed, noncanonical, control-character and oversized persisted values, and prove generated identifiers contain no host or account name.
- LLM suggestion request projection: Inbox prioritizes Quick Start then indexed frequent/recent tasks before stable fill; the normalized set is input-order independent, unique, at most 48 candidates and 16 KiB JSON. Inbox/checklist field, prompt (24 KiB), and body (32 KiB) caps are UTF-8/Unicode safe; the picker keeps its full catalogue while prompts and returned icons use the curated set. Cover oversized credentials, non-candidate task IDs, bounded reason/model output, canonical source text remaining untouched, and the invariant that a 256-byte persisted model ID passes snapshot restore while an oversized Unicode ID is safely bounded first.
- LLM configuration: Test→Save draft normalization, stale request cancellation, valid model gating, one batched preference save, Keychain compensation on preference failure, discard confirmation, device-only Keychain migration/filtering, and automatic suggestions default-off/local-only consent.
- Privacy-complete reset: successful “clear all” removes the Keychain API key and device-local automatic-suggestion consent; an injected SwiftData failure restores both external values and leaves the device-local iCloud startup switch unchanged.
- Watch command lifecycle: persistent queue encoding, seven terminal statuses, durable result payload, 20-second timeout, 30-second maximum command age, bounded future clock skew, stale-command rejection before receipt/ledger mutation, retry with the same ID and refreshed issue date, discard, duplicate idempotency, and legacy snapshot-reflection compatibility. Treat payload/restore data as untrusted: cover non-finite/future dates, UTF-8 field bytes, summary/active-age bounds, the 64-active/256-recent snapshot counts, duplicate IDs, command/result ID mismatch, 64-item incoming/pending/failed queue limits, 512 KiB encoded queue limit, safe-boundary round trips, unsafe-state clearing, and `queueOverflow` behavior.
- Incremental read models: range-scoped ledger/session replacement, task-scoped checklist/visual replacement, rollup delta plus ancestor propagation, 90-local-day active-day pace window, active/future-ended time-sensitive ticks, backward-clock full reevaluation, and equality with a full rebuild.
- Analytics caches: same-period hits, cross-day/week/month misses, task-specific keys, active-only minute buckets, mutation invalidation, and intersecting ledger day-bucket invalidation.
- Command handlers: durable writes such as timer, task, pomodoro, ledger, countdown, checklist, and preference changes must have behavior tests at the command boundary before UI wiring changes.
- Project structure: app and extension schemes must remain shared and source-controlled; filesystem moves should be followed by `xcodebuild -list` plus a generic iOS build.
- Platform declarations: verify main App `1C8F.1`/`CA92.1`, Widget `1C8F.1`, and Watch `CA92.1` Privacy manifest reasons against actual UserDefaults/App Group use, and verify no `CADisableMinimumFrameDurationOnPhone` override is reintroduced without a measured, reviewed need.
- Project map: semantic folder moves should update `Docs/ProjectMap.md`, and source layout tests should keep the map aligned with current folders and feature entry points.
- Month analytics labels using real day numbers rather than repeated weekday names.
- Localization key parity across English, Simplified Chinese, and Traditional Chinese. `Localizable.strings` is covered for the main app, Live Activity, Widget, and Watch; main-app `AppShortcuts.strings` and every target's `InfoPlist.strings` also require a direct parity/plist check because the current localization unit suite does not cover those two resource families.
- No hard-coded Chinese text in Swift source files.

## UI Testing

UI tests should rely on accessibility identifiers for core controls, not translated strings, whenever possible.

The root-flow matrix must cover iPhone five-tab navigation plus Today-hosted Settings, iPad/macOS split navigation, sidebar-to-task-detail routing, read-first Task Detail edit entry, searchable start-task picker, visible completed tasks with a working reopen path, unavailable-work explanations, explicit estimate editing/forecast source copy, visible timeline action menu, Settings categories, AI Test→Save draft/discard, and explicit Pomodoro Plan/Task menus. On macOS verify there is one main app window and that the standard Settings scene shares live state without duplicating automatic work. At minimum, manually inspect light/dark appearance, the largest accessibility Dynamic Type size, long localized task names, Settings input/value reflow, VoiceOver row values and sync feedback, destructive roles/confirmations, chart values, and bottom-of-list actions that could be obscured by the tab bar. For those bottom actions, `isHittable` alone is insufficient: the entire control frame must finish above the current system tab-bar frame before capturing the acceptance screenshot. `testAnalyticsFinalCategoryScrollsAboveSystemChrome` enforces that contract for the final Explore destination by using its stable `analytics.category.overview` identifier.

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

Simulator cleanup is part of every screenshot/profile run, not a final courtesy step. Keep the exact UDID in `SIMULATOR_UDID`, then run:

```sh
xcrun simctl shutdown "$SIMULATOR_UDID"
xcrun simctl list devices
```

Confirm the simulator started by the run is no longer `Booted`, and verify no XCTest runner or trace process from that run remains. If multiple sessions share CoreSimulator, shut down only the UDID owned by this run rather than disrupting another session.

## Device Verification

Before handing a build to manual testing:

1. Run macOS unit tests.
2. Run macOS UI tests.
3. Build a generic iOS device archive or export signed artifacts.
4. Install the exported iOS app bundle on the paired iPad and iPhone with `devicectl`.
5. Launch the app once on each device to catch signing, extension, and launch-time persistence failures.

## Final Evidence Record

Only the last run against the frozen source state is the final result. Record its commands, pass/fail/skip counts, xcresult paths, signing identity/profile/entitlement checks, simulator screenshots, trace, and simulator shutdown check in [Audit-2026-07-14](Audit-2026-07-14.md) under “最终证据槽位”. Targeted suites and earlier green builds remain useful diagnostics but cannot be added together and presented as one full pass. As of this documentation pass, the complete unit/UI suites, final signed Release builds, final screenshots, frozen-source trace, and shutdown audit remain explicit placeholders until the main task reruns them.
