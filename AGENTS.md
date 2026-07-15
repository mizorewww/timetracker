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
- Preserve paid Apple Developer signing and entitlements in build and test commands. Never disable code signing merely to make a checkpoint pass.
