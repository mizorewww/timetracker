# Agent instructions

构建与命令见 [README.md](README.md)，结构与不变量见 [Docs/Architecture.md](Docs/Architecture.md)，必须遵守的长期决策见 [Docs/AgentDecisions.md](Docs/AgentDecisions.md)。`Docs/userfeedback.md` 是用户反馈任务来源：只有用户添加条目，agent 只勾选自己完成的条目。

UI/SwiftUI 工作可参考 `.agents/skills/apple-hig/SKILL.md` 与 `.agents/skills/swiftui-expert-skill/SKILL.md`；测试设计可用 `axiom-testing` skill（来自 `.pi/settings.json` 声明的 Axiom pi 包，其 `npmCommand` 的 `--legacy-peer-deps` 在重装时必须保留）。

## Hard guardrails

- **Must** keep `CODE_SIGN_STYLE=Automatic` and team `LT98S43NKA`; never disable signing (`CODE_SIGNING_ALLOWED=NO`, empty team, ad-hoc) to make a build or check pass. The APS entitlement key is `aps-environment`.
- **Must** treat user data as safety-critical: durable writes go through the store-scoped command boundary; schema changes follow the rules in Architecture plus an old-store compatibility test. Never delete or mutate user data outside an explicit, user-approved command path.
- **Must** add every new `.strings` key to `en`, `zh-Hans`, and `zh-Hant` in the same change (`make localization-check`, also the pre-commit hook).
- **Must not** write source-string scan tests (reading Swift/project source to assert symbols, strings, or file layout).
- **Must** release resources you started (tested app, runners, simulators you created, temporary result bundles) and never stop another agent's.

## Workflow

- Get explicit, bounded scope before starting; one feature or refactor at a time.
- Write behavior tests at the command/store boundary for durable writes; avoid tests that pin implementation details, prompt prose, copy, or layout constants. Async tests wait on conditions, never fixed sleeps; never call a live model in the default suite.
- Default gate: `make test` green. UI changes add a focused XCUITest run with a normal-text-size screenshot. Widget/Watch/Live Activity/CloudKit/App Group need real-device checks (`make build-install-all`), which do not block a commit.
- Run `make format` before committing; commit small, verified steps.
- This is a self-use app: prefer simple code, native controls, and Apple HIG; don't add abstractions, limits, or tests for hypothetical cases.
