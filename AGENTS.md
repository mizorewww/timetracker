# Agent instructions

Operating manual for AI agents in this repository. Hard guardrails are marked **must**. Everything else is a pointer to the doc that owns the rule — follow the link instead of duplicating rules here. Setup and commands are in [README.md](README.md).

## Resources

Consult these when the task touches their area; none are mandatory up-front reading.

- Skills: `.agents/skills/apple-hig/SKILL.md` and `.agents/skills/swiftui-expert-skill/SKILL.md` for Apple-platform UI/SwiftUI work; the `axiom-testing` skill for test design. The `axiom-*` skills come from the Axiom pi package declared in `.pi/settings.json`; that file's `npmCommand` (`npm --legacy-peer-deps`) workaround must survive any package reinstall (`pi update --extensions`).
- `Docs/ProjectMap.md` — where code lives, placement rules, which file to open first.
- `Docs/Architecture.md` — data model, sync, schema rules. `Docs/CodeGuide.md` — code conventions and the SharedUI second-caller rule.
- `Docs/Testing.md` — test philosophy, verification gates, signing, performance evidence, resource cleanup.
- `Docs/UI-Design.md` — interaction patterns. `Docs/Localization.md` — user-facing copy. `Docs/PrivacyAndSecurity.md` — sync, AI, data safety.
- `Docs/Versioning.md` — version and hook rules. `README.md` — toolchain commands.
- `Docs/AgentDecisions.md` — binding engineering decisions (AD-xxx). Accepted decisions **must** be followed; superseded ones are history.
- `Docs/userfeedback.md` — task source for user-feedback work. Only the user adds items; the agent checks off its own completed items.

By change type: behavior → Architecture + CodeGuide; UI/interaction → UI-Design + the two UI skills; tests/release → Testing; copy → Localization; sync/AI/data → PrivacyAndSecurity; schema → Architecture schema rules + Testing compatibility; refactoring → ProjectMap placement rules; versioning/hooks → Versioning.

## Hard guardrails

- **Must** keep `CODE_SIGN_STYLE=Automatic` and team `LT98S43NKA`; never disable signing to make a build or check pass.
- **Must** treat user data as safety-critical: every durable write goes through a command boundary, sync/AI behavior follows `Docs/PrivacyAndSecurity.md`, and schema changes follow the `VersionedSchema` + migration-stage + frozen-legacy-snapshot process in `Docs/Architecture.md` plus the old-store compatibility test in `Docs/Testing.md`. Never delete or mutate user data outside an explicit, user-approved command path.
- **Must** add every new `.strings` key to `en`, `zh-Hans`, and `zh-Hant` in the same change (`make install-hooks` pre-commit gate).
- **Must not** write source-string scan tests; use behavior tests, accessibility identifiers, and screenshot/manual checklists.
- **Must** release every owned resource after a verification batch (terminate the tested app and runners, shut down and delete simulators you created, remove temp DerivedData/result/trace artifacts, confirm no owned `xcodebuild`/`xctest`/UI runner/Booted device remains). Never shut down a simulator or kill a process another active agent owns. Details in `Docs/Testing.md`.

## Workflow

- Get explicit, bounded scope before starting. One active feature or refactor at a time. Only tasks spanning multiple sessions get a record under `Docs/ImplementationContexts/`; small tasks are described by their commit message.
- Write or update failing behavior tests at the service/command/store boundary before wiring UI (`Docs/Testing.md`). Every durable write gets a command-boundary test; every schema change gets an old-store compatibility test.
- Commit small, coherent, verified steps; run `make format` before committing. Keep `AGENTS.md` and `.agents/` under version control.
- Default gate: `make test` green. UI changes add scripted XCTest/XCUITest runs with screenshots at normal text size. System surfaces (Widget, Watch, Live Activity, CloudKit, App Group): simulator evidence is diagnostic only; real-device verification uses `make build-install-all` / `make export-artifacts` and does not block the commit checkpoint.
- This is a self-use app: prioritize normal text sizes, ordinary interaction paths, platform conventions, and Apple HIG quality. Do not block a verified UI refactor on an out-of-scope Accessibility-only audit.
