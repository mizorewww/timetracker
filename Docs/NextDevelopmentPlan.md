# Next Development Plan

This document tracks product work that is not finished yet. It is intentionally separate from the architecture document: architecture explains where code belongs; this plan explains what to build next and what "done" means.

## Product Direction

Time Tracker should become a reliable local-first time ledger for everyday work and life:

- Capture loose items quickly in Inbox.
- Organize them into user-defined task categories and task trees.
- Track real time through `TimeSegment`.
- Use checklist progress only when it has enough evidence.
- Explain forecasts instead of inventing numbers.
- Keep iCloud, Live Activity, and future system entry points using the same command layer.

## Current Unfinished Areas

### 1. Inbox And LLM Organization

Inbox now exists as its own destination, but the experience still needs product-level polish.

Goals:

- Keep Inbox fast enough for one-handed capture on iPhone.
- Auto-suggest destination tasks after item creation and after meaningful title edits.
- Keep suggestion UI compact: short label, task name only, and two clear actions.
- Let users dismiss a suggestion; editing the item later should make it eligible for a new suggestion.
- Reuse checklist visual editing for icon/color suggestions instead of inventing Inbox-only editors.

Acceptance:

- Adding an item clears the field and keeps focus.
- Suggestion rows do not overflow on the smallest supported iPhone width.
- Swipe actions remain available after a suggestion is dismissed.
- LLM output is sanitized for task ID, SF Symbol, and color.
- The feature works without an API key by simply showing no automatic suggestion.

Tests:

- Inbox command tests for add/edit/dismiss/re-suggest/apply.
- LLM payload sanitizer tests for invalid task IDs, symbols, colors, and malformed JSON.
- UI contract tests for compact suggestion row content.

### 2. Checklist Forecast Quality

Forecasting is checklist-driven, but it still needs more user trust and clearer product behavior.

Goals:

- Forecast only when a task branch has checklist progress and tracked time.
- Make parent task forecasts recursively include eligible child task branches.
- Explain missing evidence: no checklist, no completed item, or no tracked time.
- Keep completed checklist items because they are part of the estimate evidence.

Acceptance:

- Completing all checklist items makes remaining time zero.
- Adding one more unchecked item changes remaining time immediately.
- Parent forecasts match the recursive sum of eligible child branches.
- Home, Analytics, and Inspector use the same forecast display service.

Tests:

- Recursive parent/child forecast tests.
- Store invalidation tests proving checklist edits refresh forecast snapshots.
- UI contract tests for forecast explanation and info entry points.

### 3. Task Categories

Task categories exist as user-defined root-like grouping metadata. They need a stronger product role before more prediction behavior is built on top.

Goals:

- Categories are user-created, not hard-coded.
- Categories can decide whether their task branches participate in checklist forecasting.
- Categories can later hold behavior profiles: linear work, recurring life habit, health, study, or custom.
- Sidebar and Tasks should visually separate categories without making category rows look like normal tasks.

Acceptance:

- A root task can inherit a category or be uncategorized.
- Forecast display respects category settings.
- Category UI uses the same symbol/color picker as tasks and checklist visuals.
- No drag-and-drop reassignment is shipped until it is reliable; use explicit native menus/forms first.

Tests:

- Category assignment and inheritance tests.
- Forecast inclusion/exclusion tests.
- Sidebar/task section ordering tests.

### 4. Analytics Rework

Analytics should be explanatory and calm, not a dense chart showcase.

Goals:

- Today: timeline, distribution, active work, and forecastable branches.
- Week/Month: real date labels, stable gross/wall-clock semantics, task distribution by task color.
- Overlap: expose simultaneous tracking clearly.
- Activity chart: avoid visually collapsing short tasks into unreadable slivers.

Acceptance:

- Today distribution remains legible when tasks are short or overlapping.
- Month charts use real dates and do not repeat weekday labels as identity.
- Empty gaps larger than a threshold are compressed only when the chart explicitly marks the omission.
- Analytics views render cached `AnalyticsSnapshot` data only.

Tests:

- Activity layout tests for short tasks, overlapping tasks, and too many slices.
- Date axis tests for week/month.
- Snapshot performance budget tests.

### 5. iCloud And Persistence Robustness

iCloud is a product feature, not a debug toggle. It must protect existing data across schema changes.

Goals:

- Keep all user-visible settings in synced preferences unless explicitly local.
- Preserve forward compatibility for existing iCloud stores.
- Avoid demo data appearing over real user data.
- Surface sync state only when it helps users fix a problem.

Acceptance:

- App launch never silently falls back to demo data when iCloud startup fails.
- In-memory fallback is clearly labeled and recoverable.
- Schema changes open older stores in tests before UI code lands.
- "Clear demo data" removes demo rows and does not touch real rows.

Tests:

- Schema compatibility tests for every new model version.
- Cloud-synced model registry tests.
- Demo-data cleanup tests.
- Preference sync import/export tests.

### 6. System Integrations

Live Activity exists; Widget, App Intents, Watch, and Shortcuts should be added only after command boundaries are stable.

Order:

1. App Intents for start/stop timer and add Inbox item.
2. Widget for active timers and quick start.
3. Watch app for active timers and recent tasks.
4. Live Activity refinements after timer command behavior is stable.

Rules:

- Extensions must call shared command/use-case entry points.
- Extensions must not reimplement ledger writes.
- Shared models must live in extension-safe files.

## Release Criteria For The Next Minor Version

Before shipping the next minor version:

1. macOS unit tests pass.
2. Generic iOS build passes with real signing and entitlements.
3. iPhone and iPad manual smoke test passes for Inbox, Tasks, Today, Pomodoro, Analytics, Settings.
4. No new user-facing string is missing from English, Simplified Chinese, or Traditional Chinese.
5. New features have documented behavior and tests before UI wiring.
6. Any schema change has an old-store compatibility test.
