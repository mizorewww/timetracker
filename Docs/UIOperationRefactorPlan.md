# UI and Operation Refactor Plan — Archived

Status: historical snapshot, superseded

Original work period: 2026-05-15

Archived: 2026-07-15

This file preserves the rationale of an earlier UI/operation pass. It is not a current specification, acceptance checklist, Agent instruction file, or backlog. The implementation and test surface have changed substantially since the original plan.

## Why The Old Plan Was Retired

The former 749-line working log mixed product intent, transient commands, absolute paths from another home directory, unchecked interaction lists, stale screen descriptions, old CSV/import assumptions, and a mandatory per-screenshot image-generation workflow. Those details were useful during one iteration but became contradictory after the repository-wide redesign.

In particular, these former rules are explicitly superseded:

- Image generation is optional design input, not a gate for every screenshot or code change.
- Chrome/ChatGPT UI automation is not a required engineering workflow.
- Old unchecked boxes and `/Users/gaozexuan/...` screenshot paths are not current work.
- Historical screenshot/build results do not prove the present worktree.
- Settings exports JSON only; the app has no importer and does not promise a restorable backup.
- The old card-heavy Today, phone inspector, inline-first Task Detail editor, and six-destination assumptions are no longer product contracts.

## Historical Product Intent Worth Keeping

The earlier pass established several durable ideas that remain valid through current documents:

1. Today is a live capture surface, not historical date navigation.
2. Time evidence is more important than decorative dashboard content.
3. Task-row tap opens one canonical read-first detail surface; editing is explicit.
4. Native navigation, lists, forms, menus, toolbars, typography, and SF Symbols are preferred.
5. Demo data used for screenshots must be explicitly enabled and isolated from the user/CloudKit store.
6. Layout review includes compact iPhone, iPad split view, macOS windows, long localization, Dynamic Type, VoiceOver, and actual interaction states.
7. Simulator sessions started for screenshots or profiling must be shut down after the run.

These principles are now maintained in [UI Design Notes](UI-Design.md), [Native UI Plan](NativeUIPlan.md), [User Guide](UserGuide.md), and [Agent Decisions](AgentDecisions.md).

## Historical Outcome

The May pass recorded baseline and iteration screenshots for iPhone, iPad, and macOS; moved task browsing toward a read-first detail; improved Analytics readiness checks; isolated screenshot demo data; and documented layout concerns around dense rows, card-heavy hierarchy, oversized controls, and compact-width collisions.

Those observations were subsequently re-triaged and substantially replaced by the July repository-wide work: system five-tab iPhone navigation, native split navigation, one shared-store macOS main window plus Settings scene, priority-ordered Today, completed-task visibility/reopen semantics, explicit-estimate forecasting, and broad accessibility restructuring.

No May screenshot, generated concept, build command, or test count should be cited as final evidence for the current tree. Current/final evidence belongs only in [Audit-2026-07-14](Audit-2026-07-14.md).

## Current Sources Of Truth

| Question | Current document |
| --- | --- |
| How does a user operate the app now? | [User Guide](UserGuide.md) |
| What UI principles and responsive behavior apply? | [UI Design Notes](UI-Design.md) and [Native UI Plan](NativeUIPlan.md) |
| Where does code belong? | [Code Guide](CodeGuide.md), [Architecture](Architecture.md), and [Project Map](ProjectMap.md) |
| Which decisions are binding? | [Agent Decisions](AgentDecisions.md) |
| What remains future work? | [Next Development Plan](NextDevelopmentPlan.md) |
| What was changed and what still needs proof? | [Audit-2026-07-14](Audit-2026-07-14.md) and [Testing](Testing.md) |

If a historical idea becomes relevant again, create a focused current proposal with user behavior, data/command ownership, accessibility acceptance, and a fresh verification plan. Do not reopen the old checkbox sequence.
