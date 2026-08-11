# Agent instructions

## Required reading, in order

1. This file.
2. Before any testing-related work—including planning, writing, changing, deleting, debugging, or reviewing tests—load and read the `axiom-testing` skill completely. Read the task-relevant references routed by that skill before changing tests. Treat this as mandatory even when tests are only one part of a feature task.
3. Before any Apple-platform UI or SwiftUI design, implementation, review, or refactoring, read both skill instruction files completely and follow them:
   - `.agents/skills/apple-hig/SKILL.md`
   - `.agents/skills/swiftui-expert-skill/SKILL.md`

   Also read any task-relevant files referenced by those skills before making changes. Treat these repository-local skill instructions as mandatory for iOS, iPadOS, macOS, watchOS, widgets, Live Activities, and other SwiftUI work.
4. `Docs/ProjectMap.md` — where code lives and which file to open first.
5. The docs matching the change type:

| Change type | Also read |
| --- | --- |
| Any behavior change | `Docs/Architecture.md`, `Docs/CodeGuide.md` |
| UI / interaction | `Docs/UI-Design.md` |
| Tests, verification, release | `Docs/Testing.md` |
| User-facing copy | `Docs/Localization.md` |
| Sync, AI, data safety | `Docs/PrivacyAndSecurity.md` |
| SwiftData schema | `Docs/Architecture.md` schema rules, `Docs/Testing.md` schema compatibility, then a new `VersionedSchema` + migration stage + frozen legacy snapshot |
| Refactoring | `Docs/CodeRefactorPlan.md` |
| Commit/release automation | `Docs/Versioning.md`, `Docs/DevelopmentTools.md`, `Docs/Scripts.md` |

`Docs/AgentDecisions.md` records binding engineering decisions (AD-xxx). Accepted decisions must be followed; superseded ones are history. Dated `Docs/Audit-*.md` snapshots were retired on 2026-07-25; one-time verification evidence now lives in the shipping commit/PR, not in a separate dated file.

The `axiom-*` skills (including `axiom-testing` in item 2) come from the Axiom pi package declared in `.pi/settings.json` (cloned to `.pi/git/github.com/CharlesWiltgen/Axiom`, gitignored). That file also sets `npmCommand` to `["npm", "--legacy-peer-deps"]` because the upstream repo's docs devDependencies conflict under npm 11; keep that workaround if the package is reinstalled or updated (`pi update --extensions`).

## Makefile usage

Build, release, versioning, and hook commands enter through the Makefile. `scripts/*.sh` are thin `uv run` wrappers around the Python modules in `tools/timetracker_tools/`; do not call xcodebuild or edit the pbxproj version fields ad hoc — use the targets. Full layout, wrapper mechanism, and troubleshooting are in `Docs/DevelopmentTools.md`; per-script behavior and env vars are in `Docs/Scripts.md`.

Run `make help` for the authoritative target list. Keep target descriptions and variables in `Docs/DevelopmentTools.md` and `Docs/Scripts.md`; do not duplicate that table here.

Conventions:

- Env vars pass through to the underlying module, so `CONFIGURATION=Release make export-artifacts` and `make CONFIGURATION=Release export-artifacts` are equivalent. The inline build/test targets take `DEVELOPMENT_TEAM=<team>` to override the default `LT98S43NKA`.
- Keep `CODE_SIGN_STYLE=Automatic` and team `LT98S43NKA`; never disable signing to make a build pass.
- `make build-info` is not a manual gate — the `Write Build Info` Xcode build phase invokes the wrapper, which calls `uv run` then the Python module. If Xcode's PATH lacks uv, the wrapper prepends common install locations; see `Docs/DevelopmentTools.md` for the `.venv/bin/python` fallback.
- Change business behavior in `tools/timetracker_tools/*.py`, entry points in the `Makefile`, and almost never in the `scripts/*.sh` wrappers.

## Development workflow

Follow this lifecycle for every task. Do not skip steps to move faster; narrow the task instead.

### 1. Establish scope and task source

- User-feedback work: `Docs/userfeedback.md` is the single source of task content and status. Claim an item by marking it `[~]`, create an implementation memory at `Docs/ImplementationContexts/UserFeedback/tasks/NN-slug.md`, and link it from `Docs/ImplementationContexts/UserFeedback/active/~NN-slug.md` (symlink to the task memory). When the task is accepted, mark the item `[x]` and remove the active link. Only the user adds new items; the agent checks off its own completed items.
- Other work: get the user's explicit, bounded scope before starting. One active refactor or feature project at a time.
- Larger features: write expected behavior in `Docs/Architecture.md` or a focused note under `Docs/ImplementationContexts/` before implementation.

### 2. Tests before wiring

- Every feature or behavior task that adds or changes tests must maintain a test record in its implementation memory under `Docs/ImplementationContexts/`. Before implementation, record the behavior/risk each planned test protects, its independent oracle, its boundary, and whether it is permanent regression coverage or temporary scaffolding. At closeout, update the record with the retained tests, deleted scaffolding, and verification evidence.
- Write or update failing behavior tests at the service/command/store boundary before wiring UI. UI-only changes get an acceptance checklist first.
- Temporary characterization, exploration, fault-injection, or implementation-driving tests must be marked `TEST-SCAFFOLD` both in the test source and in the implementation memory, with a concrete removal condition. They may exist during development but must be deleted when the feature is complete; they must not become permanent regression contracts merely because they pass.
- Permanent tests must be documented as product, durable-data, compatibility, security, or integration contracts. Do not label a test as scaffolding to bypass verification, and do not delete a permanent regression test merely because implementation is complete.
- No source-string scan tests: they were removed on 2026-07-25 for false-positiving on equivalent refactors. Use behavior tests, accessibility identifiers, and screenshot/manual checklists.
- Every durable write has a command-boundary test; every schema change has an old-store compatibility test.

### 3. Implement in layers

- Durable writes in `Commands`, SwiftData in `Repositories`, calculations in `Services`, composition in `Features/<Feature>`, shared controls in `SharedUI` only with a second caller. `TimeTrackerStore` stays a facade. Details: `Docs/ProjectMap.md` placement rules.

### 4. Verify at the level the risk requires

- Default gate: `make test` (signed macOS unit tests; see `Docs/Testing.md`) green.
- UI changes: simulator runs with scripted XCTest/XCUITest assertions and screenshots at normal text size, on the affected platforms. Release the simulator and every owned process afterward. A build-only sanity check uses `make build-ios` / `make build-macos`.
- Performance-sensitive changes: retain a deterministic correctness test for observable query/result shape when applicable, then capture a seeded Release trace before/after as described in `Docs/Testing.md`.
- System surfaces (Widget, Watch, Live Activity, CloudKit, App Group): simulator evidence is diagnostic only; real-device verification is a separate gate and does not block the commit checkpoint. For that gate, `make build-install-all` builds and installs the iOS+Watch and macOS apps to physical devices and `/Applications`; `make export-artifacts` produces the signed IPA and macOS zip.
- Keep `CODE_SIGN_STYLE=Automatic` and team `LT98S43NKA`; never disable signing to make a check pass.

### 5. Commit small and complete

- Commit after every small, coherent, verified step — do not wait for the whole repository-wide goal.
- Before the first commit in a clone, run `make install-hooks`; use `make check-hooks` to verify later checkpoints. The tracked hook must remain active so every normal commit advances the app marketing version and build number. The hook also runs the localization parity gate (`.strings` keys must match across all three locales) before staging the version bump — add new keys to `en`, `zh-Hans`, and `zh-Hant` in the same change.
- Keep each commit focused, reviewable, and safe to revert. Stage only completed work; do not capture another active agent's half-finished edit.
- Update the affected current docs (UserGuide, CodeGuide, Architecture, ProjectMap, privacy, versioning) in the same commit as the behavior change.
- Keep repository agent resources, including `AGENTS.md` and `.agents/`, under version control. Do not add them to `.gitignore`; commit new or updated agent instructions and supporting files with the small task that uses them.
- Run the task's verification gate before committing — `make test` for the default macOS unit suite, `make test-versioning` for any hook/versioning change, plus the UI/device checks the risk requires. Report failed or inconclusive verification honestly.
- Keep Swift sources formatted with `make format` (SwiftFormat, config in `.swiftformat`); `make format-check` is the read-only gate. Formatting is not chained into the pre-commit hook — run it manually before committing Swift changes.
- Do not run `make bump-version` in the normal commit flow; the pre-commit hook advances the version automatically. `make bump-version` is only for explicit manual bumps or temp-copy verification.

### 6. Close out

- Reconcile the implementation memory's test record: remove every `TEST-SCAFFOLD` test whose removal condition has been met, promote only tests that now protect a documented durable contract, and confirm no unaccounted scaffolding marker remains in the changed scope.
- Release every owned resource: terminate the tested app and runners, shut down and delete simulators created for the batch, remove temporary DerivedData/result/trace artifacts, and audit that no owned `xcodebuild`, `xctest`, UI runner, or Booted device remains. Never shut down a simulator or terminate a process another active agent explicitly owns. Drop ephemeral build outputs with `make clean` only once `build/Archives`/`build/Exports` are no longer needed as evidence.
- Update the implementation memory and remove the active link for finished feedback tasks.
- Move completed implementation memories to `Docs/ImplementationContexts/Archive/`; keep only active work and workflow indexes in the live tree.
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
