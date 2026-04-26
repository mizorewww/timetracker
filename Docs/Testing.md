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

Signed export:

```sh
./scripts/export_signed_artifacts.sh
```

## What Must Stay Covered

- Gross vs wall-clock aggregation.
- Task tree moves and cycle prevention.
- Timer pause, resume, and stop semantics.
- Pomodoro and timer ledger synchronization.
- Manual time edit/delete behavior.
- Demo data and database optimization safety.
- Timeline lane layout for overlaps, adjacent tasks, and cross-day segments.
- Localization key parity across English, Simplified Chinese, and Traditional Chinese.
- No hard-coded Chinese text in Swift source files.

## UI Testing

UI tests should rely on accessibility identifiers for core controls, not translated strings, whenever possible.

## Device Verification

Before handing a build to manual testing:

1. Run macOS unit tests.
2. Run macOS UI tests.
3. Build a generic iOS device archive or export signed artifacts.
4. Install the exported iOS app bundle on the paired iPad and iPhone with `devicectl`.
5. Launch the app once on each device to catch signing, extension, and launch-time persistence failures.
