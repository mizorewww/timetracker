# Code Refactor Status And Guardrails

Status: current source-structure guardrails. Completed refactors and their verification evidence live in git history; dated `Audit-*.md` snapshots were retired on 2026-07-25.

## Active-Work Rule

Only one active refactor project may run at a time, and it must be a bounded, user-authorized task. Recorded-but-not-implemented candidates:

- Inbox reorder and suggestion apply/discard action hierarchy: valuable, but lower priority than completed daily-fluency and writer-correctness work. Implement only if the user authorizes it as a separate task.
- Facade lifecycle/sync-observer responsibility split: reduces maintenance cost but has no user-observable failure or measured bottleneck. Implement only with user authorization or new reproducible/measured evidence.

Any new P0/P1 must first be written as an independent, bounded task and confirmed by the user. Do not keep driving refactors from this document.

## Current Responsibility Concentrations

These are navigation hints, not automatic failures or a frozen line-count budget. Split them only when the subsystem is next changed, after protecting behavior:

| Area | Current concentration | Preferred boundary |
| --- | --- | --- |
| `Stores/Facade/TimeTrackerStore+Lifecycle.swift` | Mutation authorization, current-scene refresh, repository requirements, common errors, and scheduler enqueue orchestration share one owner | Split mutation orchestration from repository/error support without moving sync/system projection work back into the facade |
| `Stores/Facade/TimeTrackerStore+PreferenceCommands.swift` | Thin preference setters plus one generic dispatcher | Low priority; revisit only if new preference setters accumulate |
| `Stores/Facade/TimeTrackerStore+SyncObservers.swift` | Observer installation, event decoding, batch drain, conflict processing, and recovery presentation share one owner | Separate event intake from batch processing and recovery presentation; keep fixed-deadline coalescing |
| `Features/Tasks/Management/TaskRowComponents.swift` | Row action policy, context menu, swipe actions, and destructive confirmation remain coupled | Extract one shared action context before separating menu and swipe presentation |
| `Features/Analytics/AnalyticsPeriodSelectionViews.swift` | Period selector views, date policy, navigation bounds, and snapshot requests share one file | Separate pure period/navigation policy from SwiftUI presentation when this screen next changes |

Sync remains the highest semantic-risk subsystem. Mechanical movement is never completion: deterministic merge/tombstone behavior, sensitive-key filtering, atomic restore, recovery barriers, checkpoint invalidation, and snapshot tests must remain green.

## Authoritative Rules

- Placement, folder ownership, and the second-caller rule: [ProjectMap](ProjectMap.md#placement-rules)
- Domain, persistence, schema, and facade boundaries: [Architecture](Architecture.md)
- Test ownership, coverage, and resource cleanup: [Testing](Testing.md)
- Task lifecycle and verification workflow: [AGENTS.md](../AGENTS.md)

Recompute repository-wide line inventories during a new review. Do not copy those inventories or the linked rules back into this file.
