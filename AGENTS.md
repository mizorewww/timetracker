# Agent instructions

## Required reading, in order

1. This file.
2. Before any Apple-platform UI or SwiftUI design, implementation, review, or refactoring, read both skill instruction files completely and follow them:
   - `.agents/skills/apple-hig/SKILL.md`
   - `.agents/skills/swiftui-expert-skill/SKILL.md`

   Also read any task-relevant files referenced by those skills before making changes. Treat these repository-local skill instructions as mandatory for iOS, iPadOS, macOS, watchOS, widgets, Live Activities, and other SwiftUI work.
3. `Docs/ProjectMap.md` — where code lives and which file to open first.
4. The docs matching the change type:

| Change type | Also read |
| --- | --- |
| Any behavior change | `Docs/Architecture.md`, `Docs/CodeGuide.md` |
| UI / interaction | `Docs/UI-Design.md` |
| Tests, verification, release | `Docs/Testing.md` |
| User-facing copy | `Docs/Localization.md` |
| Sync, AI, data safety | `Docs/PrivacyAndSecurity.md` |
| SwiftData schema | `Docs/Architecture.md` schema rules, `Docs/Testing.md` schema compatibility, then a new `VersionedSchema` + migration stage + frozen legacy snapshot |
| Refactoring | `Docs/CodeRefactorPlan.md` |
| Commit/release automation | `Docs/Versioning.md`, `Docs/Scripts.md` |

`Docs/AgentDecisions.md` records binding engineering decisions (AD-xxx). Accepted decisions must be followed; superseded ones are history. Dated `Docs/Audit-*.md` files are frozen evidence, not current specs.

## Development workflow

Follow this lifecycle for every task. Do not skip steps to move faster; narrow the task instead.

### 1. Establish scope and task source

- User-feedback work: `Docs/userfeedback.md` is the single source of task content and status. Claim an item by marking it `[~]`, create an implementation memory at `Docs/ImplementationContexts/UserFeedback/tasks/NN-slug.md`, and link it from `Docs/ImplementationContexts/UserFeedback/active/~NN-slug.md` (symlink to the task memory). When the task is accepted, mark the item `[x]` and remove the active link. Only the user adds new items; the agent checks off its own completed items.
- Other work: get the user's explicit, bounded scope before starting. One active refactor or feature project at a time.
- Larger features: write expected behavior in `Docs/Architecture.md` or a focused note under `Docs/ImplementationContexts/` before implementation.

### 2. Tests before wiring

- Write or update failing behavior tests at the service/command/store boundary before wiring UI. UI-only changes get an acceptance checklist first.
- No source-string scan tests: they were removed on 2026-07-25 for false-positiving on equivalent refactors. Use behavior tests, accessibility identifiers, and screenshot/manual checklists.
- Every durable write has a command-boundary test; every schema change has an old-store compatibility test.

### 3. Implement in layers

- Durable writes in `Commands`, SwiftData in `Repositories`, calculations in `Services`, composition in `Features/<Feature>`, shared controls in `SharedUI` only with a second caller. `TimeTrackerStore` stays a facade. Details: `Docs/ProjectMap.md` placement rules.

### 4. Verify at the level the risk requires

- Default gate: signed macOS unit tests (`Docs/Testing.md` baseline command) green.
- UI changes: simulator runs with scripted XCTest/XCUITest assertions and screenshots at normal text size, on the affected platforms. Release the simulator and every owned process afterward.
- Performance-sensitive changes: `CorePerformanceBudgetTests` plus a Release trace before/after.
- System surfaces (Widget, Watch, Live Activity, CloudKit, App Group): simulator evidence is diagnostic only; real-device verification is a separate gate and does not block the commit checkpoint.
- Keep `CODE_SIGN_STYLE=Automatic` and team `LT98S43NKA`; never disable signing to make a check pass.

### 5. Commit small and complete

- Commit after every small, coherent, verified step — do not wait for the whole repository-wide goal.
- Before the first commit in a clone, run `scripts/install_git_hooks.sh`; use `scripts/install_git_hooks.sh --check` to verify later checkpoints. The tracked hook must remain active so every normal commit advances the app marketing version and build number.
- Keep each commit focused, reviewable, and safe to revert. Stage only completed work; do not capture another active agent's half-finished edit.
- Update the affected current docs (UserGuide, CodeGuide, Architecture, ProjectMap, privacy, versioning) in the same commit as the behavior change.
- Keep repository agent resources, including `AGENTS.md` and `.agents/`, under version control. Do not add them to `.gitignore`; commit new or updated agent instructions and supporting files with the small task that uses them.
- Run the tests or checks appropriate to that task before committing. Report failed or inconclusive verification honestly.

### 6. Close out

- Release every owned resource: terminate the tested app and runners, shut down and delete simulators created for the batch, remove temporary DerivedData/result/trace artifacts, and audit that no owned `xcodebuild`, `xctest`, UI runner, or Booted device remains. Never shut down a simulator or terminate a process another active agent explicitly owns.
- Update the implementation memory and remove the active link for finished feedback tasks.
- Report: completed scope, validation performed, resource cleanup, cumulative progress, and remaining expected checkpoints.

## Parallel work and simulator ownership

Proactively use sub-agents and simulators when they improve review coverage or verification speed. Resource cleanup is not a request for single-agent execution or artificially low load.

- The primary agent coordinates build, TestManager, simulator, and Instruments batches so every run has a clear owner. Static audits and independent worktrees may continue in parallel.
- Record every simulator UDID created for a run. Avoid implicit UI-test runner clones; use explicitly owned destinations for a parallel device matrix.
- After each simulator batch, terminate the tested app, shut down and delete devices owned by that batch, quit Simulator and Problem Reporter when opened by the batch, and verify that no owned `xcodebuild`, `xctest`, UI runner, app extension, trace process, or Booted device remains.

## UI review priority

This is a self-use app. Prioritize normal text sizes, ordinary interaction paths, platform conventions, and Apple HIG visual/behavioral quality.

- Preserve inexpensive baseline semantics already present, but do not spend implementation, simulator, screenshot, trace, or review budget on specialized Accessibility or extreme Dynamic Type work unless the user explicitly requests it.
- Do not block an otherwise verified UI refactor on an Accessibility-only audit that is outside the requested scope.
