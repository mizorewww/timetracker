# Review remediation — 2026-10-14

Source: full-app review of 2026-10-14 (abstraction, hacks, performance, smells,
over-defense/over-testing/over-documentation). Owner instruction: fix all
findings, delete stale documentation, slim the test suite. Work lands on `main`
as small verified commits, one goal at a time; `make test` green per commit.
Delete this file at closeout.

## Goals

### G1 — Correctness and user-visible defects
- [x] Remove locale-dependent `localizedDescription.contains("conflict")` match (`SyncConflictService+CloudImport`).
- [x] Auto-merge only degrades validation failures to a prompt; I/O and lock errors propagate.
- [x] Bound the AI workspace tool loop (`maxRounds`) with a typed error.
- [x] Manual time no longer persists a hard-coded English `"Manual"` note (source already localizes).
- [x] Task/category restore tombstones use the same dominating LWW timestamp as ledger rows.
- [-] ~~Restore keeps `updatedAt` for unchanged rows~~ — dropped: an explicit local-winner restore must dominate not-yet-imported cloud rows; the whole-store re-upload is addressed by removing auto-merge in G5.
- [x] Inbox coordinator user-facing errors are localized.

### G2 — SwiftUI state written during `body`
- [ ] Task-detail analytics snapshot no longer mutates observed store state from `body`.
- [ ] `TimelineChart` computes bar layout once per input (Layout cache / parent), no `@State` write in `body`.
- [ ] Pomodoro countdown stops writing `@State` inside `TimelineView`.
- [ ] Analytics period titles stop allocating `DateFormatter` per evaluation.
- [ ] TaskDetail: one `.id(taskID)` owner; session/controller created once; recovery load in loader.
- [ ] Inbox list stops being rebuilt with `.id(completionPresentationRevision)`.

### G3 — Abstraction cleanup
- [ ] `ModelContext?` command parameters become non-optional; dead else-branches removed.
- [ ] One Pomodoro settle/discard implementation (repository-owned); private `segments(in:)` copies use canonical re-fetch.
- [ ] One `markMutated` on synced models; one LWW comparator.
- [ ] Remove dead snapshot-level lane allocation (`lane`, `labelIndex`, `laneCount`).
- [ ] Remove `TimerModelContextFactory`, pass-through command handlers, unused `AITaskWorkspaceSnapshot` decoding.
- [ ] Coordinators share one mutation environment instead of repeating init/session boilerplate.
- [ ] Named constants for sort-order step, Pomodoro discard ratio, maximum task depth.
- [ ] Live-clock refresh modifier shared by Analytics and Task detail.
- [ ] AI plan generator state collapsed into one phase enum.
- [ ] Startup configuration is an explicit state enum; test-launch arguments centralized.
- [ ] Container factory fallback chain de-duplicated.

### G4 — Performance on every-write paths
- [ ] Ledger relationship visibility maintained incrementally (no full task fetch + full segment filter per refresh).
- [ ] Domain store internals that drive no view are `@ObservationIgnored`; revision counters drive invalidation.
- [ ] Repository `children(of:)` uses a predicate; hierarchy writes reuse caller nodes; no redundant dedupe/sort.
- [ ] Cached trackable-task read model replaces repeated `tasks.filter` in views.
- [ ] Redundant first `refreshInboxDomain` pass removed; editor lookups use `segmentByID`.
- [ ] Sync conflict `prompt()` read path served from memory, no disk decode on the main actor per refresh batch.

### G5 — Structural simplification
- [ ] Sync conflict layer: snapshot only at mode-switch/recovery gates; drop per-commit capture and auto-merge (supersede the affected AD text).
- [ ] Watch: command age window consistent with durable delivery; receipt written in the same commit.
- [ ] LiveActivityCoordinator: protocol client seam, single dismissed checkpoint, tests.

### G6 — Tests
- [ ] Oracle tests for ledger math: gross/wall/overlap, cross-midnight, DST, soft-deleted segments, rapid restart.
- [ ] Remove redundant/duplicated tests and tests for deleted code; shared UI-test launch helper.

### G7 — Documentation
- [ ] Delete stale identifiers, deleted-name lists, hard-coded counts; ADs state invariants, numbers live in code.
- [ ] Remove finished implementation contexts; drop process overhead that does not fit a self-use app.

## Log
