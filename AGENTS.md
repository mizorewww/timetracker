# Agent instructions

## Required skills

Before designing, implementing, reviewing, or refactoring any Apple-platform UI or SwiftUI code in this repository, read both skill instruction files completely and follow them:

- `.agents/skills/apple-hig/SKILL.md`
- `.agents/skills/swiftui-expert-skill/SKILL.md`

Also read any task-relevant files referenced by those skills before making changes. Treat these repository-local skill instructions as mandatory for iOS, iPadOS, macOS, watchOS, widgets, Live Activities, and other SwiftUI work.

## Git checkpoints

The primary agent must commit its completed work after every small, coherent task has been implemented and verified. Do not wait until the entire repository-wide goal is finished before creating commits.

Before the first commit in a clone, run `scripts/install_git_hooks.sh`; use `scripts/install_git_hooks.sh --check` to verify later checkpoints. The tracked hook must remain active so every normal commit advances the app marketing version and build number.

- Keep each commit focused, reviewable, and safe to revert.
- Run the tests or checks appropriate to that task before committing.
- Stage only completed work; do not capture another active agent's half-finished edit.
- Keep repository agent resources, including `AGENTS.md` and `.agents/`, under version control. Do not add them to `.gitignore`; commit new or updated agent instructions and supporting files with the small task that uses them.
- Preserve paid Apple Developer signing and entitlements in build and test commands. Never disable code signing merely to make a checkpoint pass.

## Task reports

After every small, coherent task reaches its commit checkpoint, the primary agent must report the completed scope, the validation and resource cleanup performed, cumulative progress toward the repository-wide goal, and the remaining expected checkpoints. Report failed or inconclusive verification honestly; do not present a checkpoint as complete before its owned simulator, build, test, trace, and temporary artifacts have been released.

## Parallel work and simulator ownership

Proactively use sub-agents and simulators when they improve review coverage or verification speed. Resource cleanup is not a request for single-agent execution or artificially low load.

- The primary agent coordinates build, TestManager, simulator, and Instruments batches so every run has a clear owner. Static audits and independent worktrees may continue in parallel.
- Record every simulator UDID created for a run. Avoid implicit UI-test runner clones; use explicitly owned destinations for a parallel device matrix.
- After each simulator batch, terminate the tested app, shut down and delete devices owned by that batch, quit Simulator and Problem Reporter when opened by the batch, and verify that no owned `xcodebuild`, `xctest`, UI runner, app extension, trace process, or Booted device remains.
- Never shut down a simulator or terminate a process that another active agent explicitly owns.

## UI review priority

This is a self-use app. Prioritize normal text sizes, ordinary interaction paths, platform conventions, and Apple HIG visual/behavioral quality.

- Preserve inexpensive baseline semantics already present, but do not spend implementation, simulator, screenshot, trace, or review budget on specialized Accessibility or extreme Dynamic Type work unless the user explicitly requests it.
- Do not block an otherwise verified UI refactor on an Accessibility-only audit that is outside the requested scope.
