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
- Timer pause, resume, and stop semantics.
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
5. Start, pause, resume, and stop timers while Today is visible.
6. Switch Today, Tasks, Pomodoro, Analytics, and Settings several times.
7. Verify that no action causes visible multi-frame pauses in Release.

## Device Verification

Before handing a build to manual testing:

1. Run macOS unit tests.
2. Run macOS UI tests.
3. Build a generic iOS device archive or export signed artifacts.
4. Install the exported iOS app bundle on the paired iPad and iPhone with `devicectl`.
5. Launch the app once on each device to catch signing, extension, and launch-time persistence failures.
