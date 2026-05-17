# Testing

## Baseline Commands

Unit tests on macOS:

```sh
xcodebuild test -project timetracker.xcodeproj -scheme timetracker -destination 'platform=macOS' -only-testing:timetrackerTests
```

Build for iOS device:

```sh
xcodebuild build -project timetracker.xcodeproj -scheme timetracker -destination 'generic/platform=iOS'
```

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
- Task tree moves and cycle prevention.
- Timer start and stop semantics.
- Pomodoro and timer ledger synchronization.
- Manual time edit/delete behavior.
- Demo data and database optimization safety.
- Timeline lane layout for overlaps, adjacent tasks, and cross-day segments.
- Synced user preferences, including legacy UserDefaults import and the local iCloud startup mirror.
- Checklist add/update/delete/sort behavior and recursive rollup forecasting, including `0 completed`, `0 tracked time`, completion to `0` remaining, and parent/child forecast display rules.
- Store refresh planning: each user invalidation event must map to domain-sized refresh scopes, carry affected task IDs where available, and combined invalidations must not silently escalate to a full refresh.
- Command handlers: durable writes such as timer, task, pomodoro, ledger, countdown, checklist, and preference changes must have behavior tests at the command boundary before UI wiring changes.
- Project structure: app and extension schemes must remain shared and source-controlled; filesystem moves should be followed by `xcodebuild -list` plus a generic iOS build.
- Project map: semantic folder moves should update `Docs/ProjectMap.md`, and source layout tests should keep the map aligned with current folders and feature entry points.
- Month analytics labels using real day numbers rather than repeated weekday names.
- Localization key parity across English, Simplified Chinese, and Traditional Chinese.
- No hard-coded Chinese text in Swift source files.

## UI Testing

UI tests should rely on accessibility identifiers for core controls, not translated strings, whenever possible.

Clickable-surface coverage is now a refactor gate. Before moving or rewriting a UI area, add or update UI tests that activate every user-reachable control in that area on the representative platform, then record the result in `Docs/SwiftUIModernizationChecklist-2026-05-17.md`.

The current minimum clickable matrix is:

1. Root navigation: Today, Inbox, Tasks, Pomodoro, Analytics, and Settings.
2. Tasks: every seeded demo task row opens Task Detail without terminating the app.
3. Analytics: every category row opens its detail page, and the period control can be activated without terminating the app.
4. Custom phone bottom chrome: test it as a product-specific navigation surface rather than replacing it with native tabs. It is expected to grow beyond five pages, so improvements should preserve the bottom model unless the product decision changes.
5. Settings: keep it as a primary destination in the current navigation model. Do not hide it inside Today or move it as part of unrelated refactors; improve its native form controls and appearance in place.

## Stress Data UI Test Runner

Use the stress data runner before large refactors to make crashes and slow rendering visible on oversized, deeply nested data. The runner uses the UI test in-memory store through `--uitesting`, so it does not mutate the user's real local database.

Default large profile on macOS:

```sh
./scripts/run_stress_data_ui_test.sh large
```

Fast smoke profile:

```sh
./scripts/run_stress_data_ui_test.sh compact
```

Custom profile:

```sh
TIMETRACKER_STRESS_ROOTS=40 \
TIMETRACKER_STRESS_DEPTH=5 \
TIMETRACKER_STRESS_CHILDREN=3 \
TIMETRACKER_STRESS_CHECKLIST_ITEMS=3 \
TIMETRACKER_STRESS_SEGMENTS=2 \
TIMETRACKER_STRESS_INBOX_ITEMS=1000 \
./scripts/run_stress_data_ui_test.sh custom
```

iPad or iPhone simulator destination:

```sh
TIMETRACKER_STRESS_DESTINATION="platform=iOS Simulator,name=iPad Air 11-inch (M4),OS=26.5" \
./scripts/run_stress_data_ui_test.sh compact
```

Profiles:

1. `compact`: quick launch/click validation with hundreds of tasks.
2. `large`: default performance pass with thousands of tasks plus mutable checklist, ledger, inbox, and countdown records.
3. `extreme`: intentionally heavy stress case; use it after `compact` and `large` are stable.
4. `custom`: starts from `large` and applies environment overrides.

Supported overrides:

- `TIMETRACKER_STRESS_ROOTS`
- `TIMETRACKER_STRESS_DEPTH`
- `TIMETRACKER_STRESS_CHILDREN`
- `TIMETRACKER_STRESS_CHECKLIST_ITEMS`
- `TIMETRACKER_STRESS_SEGMENTS`
- `TIMETRACKER_STRESS_CATEGORIES`
- `TIMETRACKER_STRESS_INBOX_ITEMS`
- `TIMETRACKER_STRESS_COUNTDOWNS`

Each run writes an `.xcresult` bundle under `build/StressDataResults`. Keep the result path in the modernization checklist when the run proves a crash fix or performance change.

## Performance And Smoothness Verification

Runtime smoothness is a product requirement. The app should not feel slower than a native Apple productivity app on macOS, iPad, or iPhone.

Use two complementary checks:

1. Automated performance budget tests for deterministic domain work. These belong in `CorePerformanceBudgetTests` and should cover analytics snapshots, day-bucket summaries, overlap detection, task tree flattening, checklist rollups, and timeline layout. They protect against accidental algorithmic regressions during refactors.
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
6. Switch Today, Tasks, Pomodoro, Analytics, and Settings several times.
7. Verify that no action causes visible multi-frame pauses in Release.

## Device Verification

Before handing a build to manual testing:

1. Run macOS unit tests.
2. Run macOS UI tests.
3. Build a generic iOS device archive or export signed artifacts.
4. Install the exported iOS app bundle on the paired iPad and iPhone with `devicectl`.
5. Launch the app once on each device to catch signing, extension, and launch-time persistence failures.
