# Agent instructions

## Required skills

Before designing, implementing, reviewing, or refactoring any Apple-platform UI or SwiftUI code in this repository, read both skill instruction files completely and follow them:

- `.agents/skills/apple-hig/SKILL.md`
- `.agents/skills/swiftui-expert-skill/SKILL.md`

Also read any task-relevant files referenced by those skills before making changes. Treat these repository-local skill instructions as mandatory for iOS, iPadOS, macOS, watchOS, widgets, Live Activities, and other SwiftUI work.

## Git checkpoints

The primary agent must commit its completed work after every small, coherent task has been implemented and verified. Do not wait until the entire repository-wide goal is finished before creating commits.

- Keep each commit focused, reviewable, and safe to revert.
- Run the tests or checks appropriate to that task before committing.
- Stage only completed work; do not capture another active agent's half-finished edit.
- Keep repository agent resources, including `AGENTS.md` and `.agents/`, under version control. Do not add them to `.gitignore`; commit new or updated agent instructions and supporting files with the small task that uses them.
- Preserve paid Apple Developer signing and entitlements in build and test commands. Never disable code signing merely to make a checkpoint pass.

## Parallel work and simulator ownership

Proactively use sub-agents and simulators when they improve review coverage or verification speed. Resource cleanup is not a request for single-agent execution or artificially low load.

- The primary agent coordinates build, TestManager, simulator, and Instruments batches so every run has a clear owner. Static audits and independent worktrees may continue in parallel.
- Record every simulator UDID created for a run. Avoid implicit UI-test runner clones; use explicitly owned destinations for a parallel device matrix.
- After each simulator batch, terminate the tested app, shut down and delete devices owned by that batch, quit Simulator and Problem Reporter when opened by the batch, and verify that no owned `xcodebuild`, `xctest`, UI runner, app extension, trace process, or Booted device remains.
- Never shut down a simulator or terminate a process that another active agent explicitly owns.
