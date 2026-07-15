# Next Development Plan

Status: current future roadmap only. Completed 2026-07-14 restructuring and UI changes belong in [Audit-2026-07-14](Audit-2026-07-14.md), not in this backlog.

This document is the working roadmap for the next development cycle. It is separate from the architecture documents: architecture explains where code belongs; this plan explains what to build next, what to avoid, and what "done" means.

## Product Direction

Time Tracker should become a reliable local-first time ledger for everyday work and life. The next stage should improve trust and daily usefulness rather than adding isolated screens.

The product goals are:

- Capture loose items quickly in Inbox.
- Organize work and life into user-defined categories and task trees.
- Track real time through `TimeSegment` as the ledger fact.
- Use checklist progress only when there is enough evidence.
- Explain forecasts instead of inventing numbers.
- Keep iCloud, App Intents, Live Activity, Widget, Watch, and any future system entry points using the same command layer.
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

## Open External Verification Gates

Code-side system integrations and provisioning are in place, but these release criteria still require signed runtime/hardware verification outside a source-only review:

- Validate App Group-backed Widget snapshot sharing on a real device now that profiles include `group.me.mezorewww.timetracker`.
- Validate Watch durable command queue, typed terminal result, offline recovery, retry/discard, Always On and power behavior on a paired Watch/iPhone.
- Validate Live Activity permission, Dynamic Island, stale/end, concurrent activities and low-power behavior on a supported iPhone.
- Validate CloudKit concurrent edits with an offline old device and mixed app/schema versions.

Rules for resolving these gates:

- Keep the app and widget entitlements aligned to the same App Group.
- Widget snapshot sharing requires a real App Group entitlement; do not silently fall back to app-local storage.
- 2026-07-14: CLI automatic signing refreshed profiles successfully. Remaining work is real-device shared-container and Widget timeline verification, not profile creation.
- Automatic signing stays enabled with team `LT98S43NKA`; none of these gates may be bypassed by disabling signing.

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

1. Full macOS unit and UI suites pass on the final source state, with xcresult evidence.
2. Generic iOS and macOS Release builds pass with automatic signing, team `LT98S43NKA`, real identities/profiles, and expected entitlements; do not disable signing.
3. iPhone and iPad manual smoke test passes for Inbox, Tasks, Today, Pomodoro, Analytics, Settings.
4. macOS manual smoke test passes for sidebar selection, canonical task detail, Settings scene, timeline, and window resizing.
5. No new user-facing string is missing from English, Simplified Chinese, or Traditional Chinese.
6. New features have documented behavior and tests before UI wiring.
7. Any schema change has an old-store compatibility test.
8. No performance budget test regresses without a documented reason.
9. No new large production Swift file violates `CoreSourceLayoutTests`.
10. Accessibility Extra Large screenshots pass on iPhone for Today, Tasks, Task Detail, Analytics, and Settings; iPad split-view screenshots remain clean.
11. A nonempty SwiftUI/Time Profiler trace from the frozen source state has no unexplained application-owned hitch or invalidation hotspot.
12. A Countdown created in Settings remains visible from Today on iPhone, iPad, and macOS, with compact and wide screenshots guarding against platform regressions.
13. App Intent titles, descriptions, parameters, shortcut short titles, task entity type names, and all interpolated App Shortcut phrase templates are localized in English, Simplified Chinese, and Traditional Chinese and verified in Shortcuts/Siri discovery surfaces.
14. Every Keychain configuration/read/write error shown through the global alert uses localized user copy in all three languages while retaining the OSStatus for diagnostics.
15. Duration, clock, and date-range text follows locale and the system 12/24-hour preference; tests cover at least English and both Chinese locales instead of asserting fixed `h/m`, `HH:mm`, or `MM/dd` output.
16. AI configuration preserves Test→Save draft semantics, automatic suggestions default to off/local-only consent, and the actual default/recommended endpoint's operator, purpose, retention, training, cross-border processing, and deletion channel are reflected in product privacy disclosures.
17. Production Local/iCloud/local-fallback/emergency stores never physically purge tombstones; Demo/UI Test cleanup and demo-store isolation tests stay green.
18. App/Shortcuts sync-state file locking and epoch/generation export acknowledgement tests pass under concurrent and out-of-order events.
