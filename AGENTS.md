# Agent instructions

Operating manual for AI agents in this repository. Hard guardrails are marked **must**. Everything else is a pointer to the doc that owns the rule — follow the link instead of duplicating rules here.

## Resources

Consult these when the task touches their area; none are mandatory up-front reading.

- Skills: `.agents/skills/apple-hig/SKILL.md` and `.agents/skills/swiftui-expert-skill/SKILL.md` for Apple-platform UI/SwiftUI work; the `axiom-testing` skill for test design. The `axiom-*` skills come from the Axiom pi package declared in `.pi/settings.json`; that file's `npmCommand` (`npm --legacy-peer-deps`) workaround must survive any package reinstall (`pi update --extensions`).
- `Docs/ProjectMap.md` — where code lives, placement rules, which file to open first.
- `Docs/Architecture.md` — data model, sync, schema rules. `Docs/CodeGuide.md` — code conventions and the SharedUI rule.
- `Docs/Testing.md` — test philosophy, verification gates, signing, performance evidence.
- `Docs/UI-Design.md` — interaction patterns. `Docs/Localization.md` — user-facing copy. `Docs/PrivacyAndSecurity.md` — sync, AI, data safety.
- `Docs/Versioning.md` — version and hook rules. `Docs/DevelopmentTools.md` + `Docs/Scripts.md` — toolchain details.
- `Docs/AgentDecisions.md` — binding engineering decisions (AD-xxx). Accepted decisions **must** be followed; superseded ones are history.
- `Docs/userfeedback.md` — task source for user-feedback work. Only the user adds items; the agent checks off its own completed items.

By change type: behavior → Architecture + CodeGuide; UI/interaction → UI-Design + the two UI skills; tests/release → Testing; copy → Localization; sync/AI/data → PrivacyAndSecurity; schema → Architecture schema rules + Testing compatibility; refactoring → `Docs/CodeRefactorPlan.md`; versioning/hooks → Versioning + DevelopmentTools + Scripts.

## Toolchain

- All build, test, release, and hook commands enter through the **Makefile** (`make help`). `scripts/*.sh` are thin `uv run` wrappers around `tools/timetracker_tools/`; put business logic in the Python modules, entry points in the Makefile, almost never in the wrappers.
- Env vars pass through to the underlying module: `CONFIGURATION=Release make export-artifacts` and `make CONFIGURATION=Release export-artifacts` are equivalent. The inline build/test targets take `DEVELOPMENT_TEAM=<team>` to override the default.
- `make build-info` is not a manual gate — the `Write Build Info` Xcode build phase invokes it; see `Docs/DevelopmentTools.md` for the `uv` PATH fallback.
- **Must** keep `CODE_SIGN_STYLE=Automatic` and team `LT98S43NKA`; never disable signing to make a build or check pass.
- Install the pre-commit hook once per clone with `make install-hooks`. The hook runs only the localization parity gate: new `.strings` keys **must** be added to `en`, `zh-Hans`, and `zh-Hant` in the same change.
- Versions are bumped manually before a release with `make bump-version` (`Docs/Versioning.md`). Do not reintroduce automatic version changes into the commit flow.
- Keep Swift sources formatted with `make format` before committing; `make format-check` is the read-only gate. Formatting is deliberately not chained into the hook.
- Keep `AGENTS.md` and `.agents/` under version control; commit agent-instruction changes with the task that uses them.

## Workflow

- Get explicit, bounded scope before starting. One active feature or refactor at a time. Only tasks spanning multiple sessions get a record under `Docs/ImplementationContexts/`; small tasks are described by their commit message. One-time verification evidence lives in the shipping commit/PR, not in dated report files.
- For larger features, write the expected behavior in `Docs/Architecture.md` or a focused note under `Docs/ImplementationContexts/` before implementing.
- SwiftData schema changes follow the `VersionedSchema` + migration stage + frozen legacy snapshot process in `Docs/Architecture.md`, plus the old-store compatibility test required by `Docs/Testing.md`.
- Write or update failing behavior tests at the service/command/store boundary before wiring UI. Test philosophy: `Docs/Testing.md`.
  - **Must not** write source-string scan tests; use behavior tests, accessibility identifiers, and screenshot/manual checklists.
  - Every durable write gets a command-boundary test; every schema change gets an old-store compatibility test.
  - Temporary exploration or fault-injection tests are fine during development; delete them before closeout. This is judged at code review — there is no marker system.
- Layer placement (`Commands` / `Repositories` / `Services` / `Features` / `SharedUI`) follows `Docs/ProjectMap.md`; shared controls need a second caller (`Docs/CodeGuide.md`). `TimeTrackerStore` stays a facade.
- **Must** treat user data as safety-critical: every durable write goes through a command boundary, sync and AI behavior follow `Docs/PrivacyAndSecurity.md`, and schema changes follow the process above. Never delete or mutate user data outside an explicit, user-approved command path.
- Default gate: `make test` green. UI changes add scripted XCTest/XCUITest runs with screenshots at normal text size on the affected platforms. System surfaces (Widget, Watch, Live Activity, CloudKit, App Group): simulator evidence is diagnostic only; real-device verification uses `make build-install-all` / `make export-artifacts` and does not block the commit checkpoint.
- Performance-sensitive changes keep a deterministic correctness test for observable query/result shape, then capture a seeded Release trace before/after as described in `Docs/Testing.md`.
- Commit small, coherent, verified steps. Update affected docs in the same commit as the behavior change. Report failed or inconclusive verification honestly.

## Resource cleanup

- **Must** release every owned resource after a verification batch: terminate the tested app and runners, shut down and delete simulators you created, remove temporary DerivedData/result/trace artifacts, and confirm no owned `xcodebuild`, `xctest`, UI runner, app extension, or Booted device remains. Never shut down a simulator or kill a process another active agent owns.
- Parallel sub-agents and simulators are welcome. The primary agent coordinates so every run has a clear owner; each owner cleans up its own batch.

## UI review priority

This is a self-use app. Prioritize normal text sizes, ordinary interaction paths, platform conventions, and Apple HIG quality. Do not spend implementation or review budget on specialized Accessibility or extreme Dynamic Type work unless the user explicitly requests it, and do not block a verified UI refactor on an out-of-scope Accessibility-only audit.
