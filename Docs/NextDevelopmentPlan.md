# Next Development Plan

This document is the working roadmap for the next development cycle. It is separate from the architecture documents: architecture explains where code belongs; this plan explains what to build next, what to avoid, and what "done" means.

## Product Direction

Time Tracker should become a reliable local-first time ledger for everyday work and life. The next stage should improve trust and daily usefulness rather than adding isolated screens.

The product goals are:

- Capture loose items quickly in Inbox.
- Organize work and life into user-defined categories and task trees.
- Track real time through `TimeSegment` as the ledger fact.
- Use checklist progress only when there is enough evidence.
- Explain forecasts instead of inventing numbers.
- Keep iCloud, Live Activity, and future system entry points using the same command layer.
- Prefer native Apple controls and predictable platform behavior over custom UI that is difficult to debug.

## Development Rules For This Cycle

1. Document expected behavior before implementation.
2. Write or update tests before wiring UI.
3. Keep durable writes in command handlers.
4. Keep SwiftData reads/writes in repositories.
5. Keep calculations in services.
6. Keep SwiftUI views mostly declarative.
7. Add localization keys for English, Simplified Chinese, and Traditional Chinese with every user-facing string.
8. Do not change SwiftData schema without an old-store compatibility test.
9. Do not add custom gestures, animations, or layout engines unless the native component cannot express the interaction.
10. Do not ship demo-data or fallback-storage behavior that can hide real user data.

## Open External Blocker

The code-side system integration work is in place. The only remaining item needs an Apple Developer profile update outside the repository:

- Enable App Group-backed Widget snapshot sharing after provisioning profiles include `group.me.mezorewww.timetracker`.

Rules for resolving this blocker:

- Add the entitlement only after the app and widget provisioning profiles include the same App Group.
- Widget snapshot sharing requires a real App Group entitlement; do not silently fall back to app-local storage.
- CLI currently cannot refresh the App Group provisioning profile: `xcodebuild -allowProvisioningUpdates` reports no Xcode accounts, and the installed profiles do not include App Groups. Keep default entitlements buildable until the profile is refreshed in Xcode or Apple Developer.

## Not In The Next Minor Version

These are intentionally deferred:

- Team collaboration.
- Billing/invoicing workflows.
- Full calendar two-way sync.
- HealthKit-driven automatic categorization.
- Black-box Core ML forecasting.
- Web app.
- Drag-and-drop category reassignment unless native behavior is reliable on all target platforms.

## Release Criteria For The Next Minor Version

Before shipping the next minor version:

1. macOS unit tests pass.
2. Generic iOS build passes with real signing and entitlements.
3. iPhone and iPad manual smoke test passes for Inbox, Tasks, Today, Pomodoro, Analytics, Settings.
4. macOS manual smoke test passes for sidebar, inspector, settings, timeline, and window resizing.
5. No new user-facing string is missing from English, Simplified Chinese, or Traditional Chinese.
6. New features have documented behavior and tests before UI wiring.
7. Any schema change has an old-store compatibility test.
8. No performance budget test regresses without a documented reason.
9. No new large production Swift file violates `CoreSourceLayoutTests`.
