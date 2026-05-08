# Code Refactor Plan

This document records the current architecture state and the engineering rules that keep the project maintainable. It is not a feature backlog. Completed refactor work is removed from the active plan so future development does not keep revisiting the same tasks.

## Review Summary

The current structural refactor pass is complete. The app now has semantic folders, split domain stores, split repositories, split feature views, and source-layout guard tests for the areas that were previously most fragile.

Remaining risks are policy-level and should be handled when the related subsystem is touched:

- `TimeTrackerStore` remains a compatibility facade. New business logic should go into command handlers, domain stores, services, or repositories.
- A small number of source-contract tests still protect architecture boundaries. Replace them with behavior/UI tests opportunistically when editing the relevant feature.
- SwiftData schema changes are high-risk because iCloud users can have older stores.
- Custom layout remains allowed only when the behavior is covered by service tests or a manual screenshot/device acceptance checklist.
- Tests are allowed to be larger when they group one subsystem, but production Swift files should stay small enough to review quickly.

## Completed Structural Work

- App startup is split into container creation, commands, app delegate, settings scene, and root views.
- Settings is split into actions, bindings, data sections, and presentation sections.
- Inbox commands are split between item mutations and LLM suggestion mutations.
- Checklist commands are split between item mutations and LLM visual suggestions.
- Ledger repository code is split into base, query, and mutation files.
- Forecast rollup recursion is isolated in `TaskRollupCalculationContext`.
- Timeline layout models and axis compression are split from the lane-placement engine.
- Home Quick Start and Analytics activity sections are split into smaller reusable files.
- Source-layout tests guard the important boundaries so new work does not rebuild the earlier large-file problem.

## Refactor Principles

1. Keep `TimeSegment` as the immutable fact source.
2. Put durable writes in command handlers.
3. Put SwiftData reads/writes in repositories.
4. Put calculations in services.
5. Put published feature state in domain stores.
6. Keep SwiftUI views mostly declarative: render state, do not derive heavy state.
7. Prefer behavior tests, service tests, command tests, and accessibility/UI tests over source-string tests.
8. Prefer new extension models over modifying core SwiftData models.

## Facade Rules

`TimeTrackerStore` should remain a compatibility facade for SwiftUI, but domain behavior should keep moving outward.

Rules:

- Facade methods longer than 30 lines require a documented reason.
- Read-model helpers that do not need `@Published` state move out of the facade.
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

The folder structure is now semantic. Keep the existing size guards in place so new work does not rebuild the earlier large-file problem.

Rules:

- A SwiftUI feature file over 250 lines should be split by section or row.
- A facade extension over 250 lines should be split by command/read-model responsibility.
- A test file over 400 lines should be split by subsystem.
- New shared controls belong in `SharedUI` only after a second caller exists or is imminent.
- Do not create `timetracker+Something.swift` style files for unrelated helpers; place them under the semantic folder that owns the behavior.
