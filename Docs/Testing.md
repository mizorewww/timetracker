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

## UI Testing

UI tests should rely on accessibility identifiers for core controls, not translated strings, whenever possible.
