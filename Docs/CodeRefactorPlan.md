# Code Refactor Status And Guardrails

Status: current source-structure guardrails. The completed 2026-07-14 repository-wide split, the 2026-07-17 writer/analytics closure (W0/R1, commits `e30fd6a`/`55f19ae`), and their final evidence are recorded in git history and [Audit-2026-07-14](Audit-2026-07-14.md); they are not repeated here.

## Active-Work Rule

Only one active refactor project may run at a time, and it must be a bounded, user-authorized task. Recorded-but-not-implemented candidates:

- Inbox reorder and suggestion apply/discard action hierarchy: valuable, but lower priority than completed daily-fluency and writer-correctness work. Implement only if the user authorizes it as a separate task.
- Facade lifecycle/sync-observer responsibility split: reduces maintenance cost but has no user-observable failure or measured bottleneck. Implement only with user authorization or new reproducible/measured evidence.

Any new P0/P1 must first be written as an independent, bounded task and confirmed by the user. Do not keep driving refactors from this document.

## Policy-Level Remaining Risks

Handle these when the related subsystem is touched:

- `TimeTrackerStore` remains a compatibility facade. New business logic should go into command handlers, domain stores, services, or repositories.
- SwiftData schema changes are high-risk because iCloud users can have older stores.
- Custom layout remains allowed only when the behavior is covered by service tests or a manual screenshot/device acceptance checklist.
- Tests are allowed to be larger when they group one subsystem, but production Swift files should stay small enough to review quickly.

## Current Responsibility Concentrations

These are the highest-priority mixed-responsibility owners, not an exhaustive line-count report and not automatic failures. Split them along the named ownership boundaries when the subsystem is next changed, and protect behavior before moving code. Recompute the exact repository-wide line inventory at each review instead of treating this table as a frozen size snapshot:

| Area | Current concentration | Preferred boundary |
| --- | --- | --- |
| `Stores/Facade/TimeTrackerStore+Lifecycle.swift` | Generic refresh, mutation authorization/post-commit work, repository requirements, errors, and sync snapshot finishing share one owner | Split refresh/account/conflict lifecycle, mutation orchestration, and repository/error support without widening private helpers |
| `Stores/Facade/TimeTrackerStore+PreferenceCommands.swift` | Display/timing, Focus, cloud/Quick Start, and LLM preferences share one command facade | Split by preference family while retaining one validated `setPreference` support boundary |
| `Stores/Facade/TimeTrackerStore+SyncObservers.swift` | Observer installation, event decoding, batch drain, conflict processing, and recovery presentation share one owner | Separate observer/event intake from batch processing and recovery presentation; keep the fixed-deadline bounded coalescer semantics |
| `Features/Tasks/Management/TaskRowComponents.swift` | Row action policy, context menu, swipe actions, and destructive confirmation remain coupled | Extract one shared action context before separating menu and swipe presentation, so they cannot acquire divergent confirmation state |
| `Features/Analytics/AnalyticsPeriodSelectionViews.swift` | Period selector views, date text/policy, navigation bounds, and snapshot requests share one file | Separate pure period/navigation policy from SwiftUI presentation when this screen next changes |

Sync remains the highest semantic-risk subsystem because it combines security-, migration-, export-, and synchronization-sensitive behavior. Mechanical file movement alone is not completion: deterministic LWW/tombstone behavior, sensitive-key filtering, atomic restore behavior, recovery intent/session barriers, legacy-state checkpoint invalidation, and per-domain snapshot tests must remain green after every change. The current concentrations are the real files listed above; retired names must not remain in this table.

## Refactor Principles

1. Keep canonical `TimeSegment` as the editable/soft-deletable fact source; caches and summaries remain rebuildable projections. Ordinary rapid-restart canonicalization is split into `TimerRapidRestartPolicy.swift` and `SwiftDataTimeTrackingRepository+RapidRestart.swift` instead of being duplicated in UI/system entry points or hidden in read-side grouping.
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
- Selection coordinator tests for task archive/restore, historical-tombstone invalidation, and navigation preservation.

## Repository Rules

Repositories should provide domain-sized queries. Views and stores should not compensate for broad fetches with repeated in-memory filtering.

Rules:

- Domain stores do not call broad "all" queries during normal user actions unless the event is `fullSync` or a history invalidation has no usable range.
- Range query semantics include explicit `now`.
- Each repository query has a behavior test or integration test.
- Add a persisted ledger bucket cache only when profiling proves range fetches are the bottleneck.

## Test Rules

Source-string contract tests were removed on 2026-07-25 because they false-positived on equivalent refactors and had become a maintenance cost.

Rules:

- Cover UI behavior with pure service tests, command tests, view model tests, and accessibility-identifier UI tests.
- Use screenshot/manual acceptance checklists where layout is visual.

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

The folder structure is semantic. A line limit is a review signal, not a substitute for cohesion or behavior coverage.

Rules:

- A new SwiftUI feature file over 250 lines requires a responsibility review; existing larger files require the same review even when they are not among the prioritized mixed-responsibility owners above.
- A facade extension over 250 lines should be split by command/read-model responsibility.
- A test file over 400 lines should be split by subsystem.
- New shared controls belong in `SharedUI` only after a second caller exists or is imminent.
- Do not create `timetracker+Something.swift` style files for unrelated helpers; place them under the semantic folder that owns the behavior.
