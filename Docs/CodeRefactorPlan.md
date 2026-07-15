# Code Refactor Status And Guardrails

Status: current source-structure record after the 2026-07-14 repository-wide split. This document records what was split, what is still concentrated, and the engineering rules that keep the project maintainable. It is not a product feature backlog and it does not substitute for the final build, test, simulator, and Instruments evidence in [Audit-2026-07-14](Audit-2026-07-14.md).

## Review Summary

The current pass established semantic folders, split domain stores and repositories, and then removed the largest mixed-responsibility production files:

- `SyncConflictService.swift` was reduced to bootstrap/prompt ownership; local mutation, Cloud import/export, recovery/resolution, persisted state, file lock/locations, export encoding, snapshot capture/domain restores, snapshot state, and domain record DTOs now have focused files.
- Analytics landing-page composition and `AnalyticsCategoryDetailView` were split; category navigation is typed, while overview-row, metric-list, detail-list, period, group-breakdown, metrics, overlap, and task-snapshot responsibilities have focused owners.
- Pomodoro setup composition was split from its empty state, focus controls, Plan/Task selection controls, and timer face.
- The retired `SettingsSectionsViews.swift` was replaced by focused display/timing, Pomodoro, countdown, sync, data, action, binding, and support files.
- Shared Settings rows were split into foundation/value, action/destructive, input, platform-presentation, and sync-feedback files; each owner stays within the current production source-layout budget.
- Task Detail is now one focused orchestration view plus identity, checklist, overview, analytics, navigation, and record section files.
- The retired `TimeTrackerServices.swift` was replaced by `AppCloudSync`, persistence-write safety, timer command, aggregation, formatting, device identity, and ledger-summary files.
- Facade startup/configuration and post-commit system-surface attachment were split from refresh/mutation/recovery lifecycle; both files now stay under the facade source-layout budget.
- Widget entry/provider/configuration, active-timer layouts, supplementary/error states, and deep-link/localization/color support are separate files.
- Watch dashboard orchestration, timer rows, status/error/empty states, and color support are separate files. `WatchAppStore.swift` now owns observable state and safe restoration, `WatchAppStore+Commands.swift` owns command queue/timeout/persistence, and `WatchAppStore+Connectivity.swift` owns WCSession transport, payload application, freshness, and delegate callbacks.
- Ledger's ordered flat-array mutation/index maintenance is isolated in `LedgerStore+FlatSegmentIndex.swift`; day/change indexing remains in `LedgerStore+SegmentIndex.swift`.
- Incremental rollup state/full rebuild remains in `RollupIncrementalIndex.swift`, while scoped segment/checklist mutation and replacement-delta application lives in `RollupIncrementalIndex+Mutation.swift`.

This structural work is real, but it does not make every production file small or single-purpose. The remaining concentrations below must not be hidden behind a blanket “refactor complete” claim.

Remaining risks are policy-level and should be handled when the related subsystem is touched:

- `TimeTrackerStore` remains a compatibility facade. New business logic should go into command handlers, domain stores, services, or repositories.
- A small number of source-contract tests still protect architecture boundaries. Replace them with behavior/UI tests opportunistically when editing the relevant feature.
- SwiftData schema changes are high-risk because iCloud users can have older stores.
- Custom layout remains allowed only when the behavior is covered by service tests or a manual screenshot/device acceptance checklist.
- Tests are allowed to be larger when they group one subsystem, but production Swift files should stay small enough to review quickly.

## Current Responsibility Concentrations

These are the highest-priority mixed-responsibility owners, not an exhaustive line-count report and not automatic failures. Split them along the named ownership boundaries when the subsystem is next changed, and protect behavior before moving code. Recompute the exact repository-wide line inventory at each review instead of treating this table as a frozen size snapshot:

| Area | Current concentration | Preferred boundary |
| --- | --- | --- |
| `Features/Home/HomeViews.swift` | Desktop wrapper, phone root, priority-ordered Today list, accessibility-size alternatives, and header support remain together | Keep Today section ordering in one composition owner, but move platform wrappers/header support when the next Home change requires it |
| `Features/Tasks/Management/TaskManagementRowViews.swift` | Flat-row presentation and its complete action/menu/accessibility surface remain together | Extract action/menu support from the canonical row without splitting one logical row into unstable identities |
| `Features/Analytics/Sections/AnalyticsDecisionViews.swift` | Insight, forecast, rhythm, quality, and overlap presentation remain in one section family | Split by decision, forecast, and quality/overlap section families if those screens evolve independently |
| `Features/Settings/SettingsViews.swift` | Category navigation, export/confirmation presentation, AI configuration presentation, and category-to-section routing remain together | Keep the category router authoritative; move modal/export orchestration into focused support only when it improves reviewability |

Sync is no longer a line-size concentration, but it remains the highest semantic-risk subsystem because it combines security-, migration-, export-, and synchronization-sensitive behavior. Mechanical file movement alone is not completion: deterministic LWW/tombstone behavior, sensitive-key filtering, atomic restore behavior, force-upload recovery, legacy-state checkpoint invalidation, and per-domain snapshot tests must remain green after every change. The largest remaining production concentrations are the feature composition/row files listed above.

## Completed Structural Work

- App startup is split into container creation, commands, app delegate, settings scene, and root views.
- Settings is split into actions, bindings, data sections, and presentation sections.
- Inbox commands are split between item mutations and LLM suggestion mutations.
- Checklist commands are split between item mutations and LLM visual suggestions.
- Ledger repository code is split into base, query, and mutation files.
- Forecast rollup recursion is isolated in `TaskRollupCalculationContext`.
- Timeline layout models and axis compression are split from the lane-placement engine.
- Home Quick Start and Analytics activity sections are split into smaller reusable files.
- Analytics landing-page routing stays in `AnalyticsViews.swift`; typed category-detail composition lives in `AnalyticsCategoryDetailView.swift`, while overview rows, metric/detail lists, period controls, and decision-support builders are split by responsibility.
- Pomodoro setup is split into `PomodoroSetupViews.swift`, `PomodoroSetupEmptyState.swift`, `PomodoroFocusSetupControls.swift`, `PomodoroSetupSelectionViews.swift`, and `PomodoroTimerFace.swift`; the setup container remains the composition owner.
- Settings timing, Pomodoro, countdown, sync, data, action, binding, and support responsibilities are split; `SettingsSectionsViews.swift` is retired.
- Reusable Settings rows are split into `SettingsRows.swift`, `SettingsActionRows.swift`, `SettingsInputRows.swift`, `SettingsPresentationModifiers.swift`, and `SettingsSyncFeedbackRow.swift`; large Dynamic Type composition and VoiceOver title/value semantics remain part of those shared owners.
- Task Detail identity, checklist, overview, analytics, navigation, and record sections are split from the canonical detail router.
- Ledger cloud mode, transaction diagnostics, timer DTO, aggregation, formatting, device identity, and summary responsibilities are split; `TimeTrackerServices.swift` is retired.
- Sync-conflict bootstrap/prompt, local mutation, Cloud import/export, recovery/resolution, state persistence, file lock/locations, export encoding, snapshot capture/domain restores, snapshot state, and organization/ledger/planning/checklist/Inbox record DTOs are split by responsibility.
- `TimeTrackerStore+Configuration.swift` owns first configuration, repository-only attachment, and committed-mutation surface refresh; `TimeTrackerStore+Lifecycle.swift` owns generic refresh, mutation, recovery, and error boundaries.
- Widget entry/provider/configuration, active-timer views, supplementary states, and support helpers are split into `TimeTrackerWidget.swift`, `ActiveTimerWidgetView.swift`, `WidgetSupplementaryViews.swift`, and `WidgetSupport.swift`.
- Watch UI composition is split into `WatchDashboardView.swift`, `WatchTimerRows.swift`, `WatchStatusViews.swift`, and `WatchColorSupport.swift`; the store family is split into observable state/restore (`WatchAppStore.swift`), commands/queue timeout/persistence (`WatchAppStore+Commands.swift`), and WCSession connectivity/payload/freshness (`WatchAppStore+Connectivity.swift`).
- Ledger ordered-array mutation/index maintenance is split into `LedgerStore+FlatSegmentIndex.swift`; `LedgerStore+SegmentIndex.swift` retains day/change indexing and scoped replacement coordination.
- Rollup scoped mutation/replacement logic is split into `RollupIncrementalIndex+Mutation.swift`; the base type retains state and full rebuild, with pace, topology, and activity in their existing focused extensions.
- Source-layout tests guard the important boundaries so new work does not rebuild the earlier large-file problem; the current focused suite includes file-existence and per-family size contracts for all three splits.

## Refactor Principles

1. Keep canonical `TimeSegment` as the editable/soft-deletable fact source; caches and summaries remain rebuildable projections.
2. Put durable writes in command handlers.
3. Put SwiftData reads/writes in repositories.
4. Put calculations in services.
5. Put observable feature state in domain stores and expose it through the `@Observable` facade.
6. Keep SwiftUI views mostly declarative: render state, do not derive heavy state.
7. Prefer behavior tests, service tests, command tests, and accessibility/UI tests over source-string tests.
8. Prefer new extension models over modifying core SwiftData models.

## Facade Rules

`TimeTrackerStore` should remain a compatibility facade for SwiftUI, but domain behavior should keep moving outward.

Rules:

- Facade methods longer than 30 lines require a documented reason.
- Read-model helpers that do not need observation move out of the facade.
- Domain commands return typed results/events.

Tests:

- Command handler tests for every durable write.
- Refresh planner tests for each emitted event.
- Selection coordinator tests for task deletion, selection invalidation, and navigation preservation.

## Repository Rules

Repositories should provide domain-sized queries. Views and stores should not compensate for broad fetches with repeated in-memory filtering.

Rules:

- Domain stores do not call broad "all" queries during normal user actions unless the event is `fullSync` or a history invalidation has no usable range.
- Range query semantics include explicit `now`.
- Each repository query has a behavior test or integration test.
- Add a persisted ledger bucket cache only when profiling proves range fetches are the bottleneck.

## Test Rules

Source-string tests were useful while the UI was moving quickly, but they are now a maintenance cost.

Rules:

- Keep source-contract tests only for critical architecture boundaries:
  - no recursive task `DisclosureGroup`
  - no direct SwiftData writes in views
  - shared app scheme exists
- Prefer replacing UI source assertions with:
  - pure service tests
  - command tests
  - view model tests
  - accessibility identifier UI tests
  - screenshot/manual acceptance checklists where layout is visual

Acceptance:

- No test asserts exact font, padding, or layout string unless preventing a known regression.
- UI behavior is covered by state and action contracts.

## Schema And Migration Rules

Every schema change must be safe for local-first and iCloud-backed users.

Rules:

- Keep a registry test for cloud-synced user model names.
- For each new model:
  - document whether it syncs
  - add soft-delete rules
  - add cleanup behavior if needed
- Prefer additive relation models over changing existing fact models.

Acceptance:

- A schema PR cannot merge without a migration/compatibility test.
- Demo data can be cleared independently from user data.
- iCloud startup fallback never masks data loss.

## Observability And Performance Rules

Performance fixes should be evidence-driven.

Rules:

- A slow screen can be traced to a domain refresh, service calculation, or SwiftUI layout cause.
- Performance tests protect known high-cost algorithms.
- No timer label causes full-screen refresh every second.
- Profile Release builds on macOS and devices before changing UI architecture.

## File And Folder Rules

The folder structure is now semantic. Keep the family-specific guards in `CoreSourceLayoutTests` aligned with the current owners so new work does not rebuild the earlier large-file problem. A line limit is a review signal, not a substitute for cohesion or behavior coverage.

Rules:

- A new SwiftUI feature file over 250 lines requires a responsibility review; existing larger files require the same review even when they are not among the prioritized mixed-responsibility owners above.
- A facade extension over 250 lines should be split by command/read-model responsibility.
- A test file over 400 lines should be split by subsystem.
- New shared controls belong in `SharedUI` only after a second caller exists or is imminent.
- Do not create `timetracker+Something.swift` style files for unrelated helpers; place them under the semantic folder that owns the behavior.
