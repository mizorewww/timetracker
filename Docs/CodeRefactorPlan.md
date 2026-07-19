# Code Refactor Status And Guardrails

Status: current source-structure record after the 2026-07-14 repository-wide split and the 2026-07-17 scene/sync refinements. This document records what was split, what is still concentrated, and the engineering rules that keep the project maintainable. It is not a product feature backlog and it does not substitute for the final risk-proportionate build, test, simulator, and Instruments evidence in [Audit-2026-07-14](Audit-2026-07-14.md).

## 2026-07-17 收口计划：只推进一个主动重构项目

全面审查和本轮收口均已完成。writer 事务修复已在 `e30fd6a` 提交，唯一主动重构 R1 已在 `55f19ae` 提交并通过最终验证。当前没有允许 Agent 自行继续推进的主动重构项目；R2、R3 和新发现只能作为记录，必须由用户另行授权为边界明确的新任务。

| 顺序 | 项目 | 当前决定与价值 | 完成/停止条件 |
| --- | --- | --- | --- |
| W0（已完成） | Store writer 收口：同步偏好、LLM 凭据配置、Countdown 新建 | 修复跨 scene/进程 writer 与 timer admission 读写同一事实时使用旧 `ModelContext` 的竞态；LLM Keychain 补偿也不再读取锁外旧值。 | `e30fd6a`；coordinator、命令和回归测试通过，签名 macOS XCTest 成功，DerivedData/result 已删除且无 owned runner/simulator。 |
| **R1（已完成，停止主动重构）** | **Analytics 读模型的交互性能边界** | Analytics 是持续使用的复盘入口。虽然缓存和同周期刷新已避免空白屏，Today 的小时活动、时间线布局和 overlap sweep 仍曾随 snapshot 在 `@MainActor` 运行；大账本或频繁 live bucket 更新可能抢占导航、滚动和 period 切换。这个项目直接改善最常见的等待和卡顿风险，同时不触碰 iCloud schema 或不必要地重画 UI。 | `55f19ae`；主 actor 把 SwiftData 模型投影成 `Sendable` value input，后台只计算 Today visual read models；主 actor 仍拥有 SwiftData 可见性、core summary、cache/request identity、取消和发布。139/139 定向签名 macOS 测试与 9/9 性能预算回归已通过。 |
| R2（记录，不实施） | Inbox 的重排与建议“应用/丢弃”动作层级 | UI 审查发现重复入口会增加误操作和学习成本；有价值，但不高于已完成 R1 的日常流畅性和 writer 正确性。 | 只有用户以独立任务再次授权才排入实现。 |
| R3（记录，不实施） | Facade 余下的生命周期/同步观察者职责拆分 | 可降低维护成本，但没有用户可观察故障或量测瓶颈；单纯按行数拆文件是低价值工作。 | 只有用户以独立任务授权，或新的可复现故障/量测证据成立时才实施。 |
| Release gate（已完成） | 风险相称的签名测试、性能回归与 Release archive | 发布证据不用于扩大重构范围；Agent 不修改真实账户的生产 iCloud 数据来制造验收。 | 签名测试 139/139、性能预算 9/9、universal macOS Release archive 成功；签名与资源清理均已核验。 |

### R1 的工作契约（已归档）

1. **先测量，后改变。** 使用具有确定数量的 ledger fixture 和同一输入区间；记录 snapshot 总耗时、主线程繁忙区间、刷新/切换期间的可交互性。不得仅因文件大或猜测而引入 `Task.detached`、新缓存层或 schema。
2. **一次边界，而非重写。** 如果量测证明需要优化，SwiftData 获取、request identity、取消、cache 和 `@Observable` 发布继续留在既有 owner；只把已量测的 Today visual submodels（小时活动、timeline、overlap）连同 Sendable 输入搬到后台。不得让后台持有 `ModelContext`、`PersistentModel` 或 SwiftUI state；其它 core summary 只能在显式 residual budget 内留在主 actor。
3. **正确性优先。** 同一 request identity 的结果才可发布；period/calendar/revision/live bucket 变化取消旧任务；分类、deleted task、gross/wall、comparison、overlap 和 task-detail 结果必须和优化前一致。没有可信的行为/性能证据就回退该实现，而不是追加补丁。
4. **资源与签名。** 不用 Device Hub 代替自动化测试。每个 profiling 或 test batch 都记录 owner，并在结束时终止本批 app/process、删除 DerivedData/result/trace；只有为该批显式创建的 simulator 才可关闭和删除。构建与测试保留 Automatic Signing、团队和 paid Developer capabilities。
5. **停止条件。** R1 的基线证明无需优化，或一次经过验证的优化达到预算且没有回归时，立刻停止主动重构；剩余表项保持记录状态。任何新 P0/P1 都必须先写成独立、有限的任务并由用户确认范围。

### R1 基线证据（2026-07-17）

已在保留自动签名的 macOS runner 上运行 `CorePerformanceBudgetTests`：8/8 通过，无 warning、无 simulator。`analyticsSnapshotStaysWithinPerformanceBudget()`（720 个 session/segment 的月度输入）测试总时长为 **98 ms**；`denseOverlapAnalyticsSnapshotStaysWithinPerformanceBudget()`（2,000 个高重叠 segment 的 Today 输入）为 **284 ms**。这两个数字包含 fixture 构造，因而不能伪装成纯 `AnalyticsStore` 调用的精确 microbenchmark；但两者均在 `@MainActor` 测试中执行，284 ms 已超过正常 range 切换或 live refresh 的交互预算。

R1 的一次实现把 Today visual read models 提取成 `AnalyticsVisualSnapshotInput`/`AnalyticsVisualSnapshotService`：投影发生在 main actor，worker 不持有持久模型，`withTaskCancellationHandler` 会取消 owned detached task；task id 变化后 facade 不会缓存/发布过期结果。2,000 条输入的首轮拆分测量中，投影低于 **50 ms**，visual 之后的 main-actor core assembly 为 **145.17 ms**；因此保留一个 **175 ms** 的 high-density residual budget，而不是声称整个 snapshot 已完全后台化。该预算是新建的受控测试，不是放宽旧的 4 秒端到端保护；后者仍保留。语义回归同时比较 legacy hourly/timeline/overlap 与 Sendable worker，并覆盖空 Today 保持 24 个小时桶。

尝试直接运行 Release XCTest 未产生有效数据：Release module 默认没有为 `@testable import` 构建；一次性 `ENABLE_TESTABILITY=YES` 重试在 test worker materialization 无进展时被主动中止并清理。它没有改变工程 signing 或发行设置。最终改用与测试职责分离的 universal macOS Release archive 完成发行配置验证，archive 成功并保留付费开发者签名。

### 收口状态与非主动记录

- W0 已由 `e30fd6a` 提交；R1 已由 `55f19ae` 提交。当前工作树在提交后保持干净，本轮没有未提交代码或文档。
- R1 的 Sendable visual boundary、139/139 定向签名测试、9/9 性能预算回归和一次 universal macOS Release archive 均已完成；主动重构已经停止。
- Release archive 保留 `Apple Development: ZEXUAN GAO (PX46M259V3)` / team `LT98S43NKA` 签名，未禁用 signing。archive 仅报告既有 `timetrackerWatchApp` 缺少 App Category 的 metadata warning；记录在 audit，不在 R1 中扩展修复。发现新问题必须由用户决定是否开启新的有限项目。
- R1 增加异步加载后，`AnalyticsCategoryDetailView` 与 `TimeTrackerStore+Analytics` 超出既有职责预算；已按真实 owner 将 category 的内容组合移到 `AnalyticsCategoryDetailContent.swift`、将异步 cache-miss 加载移到 `TimeTrackerStore+AnalyticsLoading.swift`。预算保持不变，不以放宽 source-layout contract 掩盖新增职责。
- 所有本批 DerivedData、result bundle、archive 和临时目录均已删除；最终没有 owned `xcodebuild`、`xctest` 或 Booted simulator。

## Review Summary

The current pass established semantic folders, split domain stores and repositories, and then removed the largest mixed-responsibility production files:

- `SyncConflictService.swift` was reduced to bootstrap/prompt ownership; local mutation, Cloud import/export, recovery/resolution, persisted state, file lock/locations, export encoding, snapshot capture/domain restores, snapshot state, and domain record DTOs now have focused files.
- Analytics landing-page composition, category-detail loading and category-detail content are split; category navigation is typed, while overview-row, metric-list, detail-list, period, group-breakdown, metrics, overlap, task-snapshot, and snapshot-cache responsibilities have focused owners.
- Pomodoro setup composition was split from its empty state, focus controls, Plan/Task selection controls, and timer face.
- The retired `SettingsSectionsViews.swift` was replaced by focused display/timing, Pomodoro, countdown, sync, data, action, binding, and support files.
- Shared Settings rows were split into foundation/value, action/destructive, input, platform-presentation, and sync-feedback files; each owner stays within the current production source-layout budget.
- Task Detail is now one focused orchestration view plus identity, checklist, overview, analytics, navigation, and record section files.
- The retired `TimeTrackerServices.swift` was replaced by `AppCloudSync`, persistence-write safety, timer command, aggregation, formatting, device identity, and ledger-summary files.
- Facade startup/configuration and post-commit system-surface attachment were split from refresh/mutation/recovery lifecycle. Configuration is focused; Lifecycle, PreferenceCommands, and SyncObservers still need one more responsibility split to satisfy the facade source-layout budget.
- Widget entry/provider/configuration, active-timer layouts, supplementary/error states, and deep-link/localization/color support are separate files.
- Watch dashboard orchestration, timer rows, status/error/empty states, and color support are separate files. `WatchAppStore.swift` owns observable state and safe restoration, `WatchAppStore+Commands.swift` owns command queue/timeout/persistence, `WatchAppStore+Connectivity.swift` owns activation/transport/payload/freshness, and `WatchAppStore+SessionDelegate.swift` owns WCSession callbacks.
- Ledger's ordered flat-array mutation/index maintenance is isolated in `LedgerStore+FlatSegmentIndex.swift`; day/change indexing remains in `LedgerStore+SegmentIndex.swift`.
- Incremental rollup state/full rebuild remains in `RollupIncrementalIndex.swift`, while scoped segment/checklist mutation and replacement-delta application lives in `RollupIncrementalIndex+Mutation.swift`.
- Today compact composition, wide composition, section content, row presentation, and centralized read models have separate owners; `HomeViews.swift` now contains only the wide wrapper/composition and header.

This structural work is real, but it does not make every production file small or single-purpose. The remaining concentrations below must not be hidden behind a blanket “refactor complete” claim.

Remaining risks are policy-level and should be handled when the related subsystem is touched:

- `TimeTrackerStore` remains a compatibility facade. New business logic should go into command handlers, domain stores, services, or repositories.
- A small number of source-contract tests still protect architecture boundaries. Replace them with behavior/UI tests opportunistically when editing the relevant feature.
- SwiftData schema changes are high-risk because iCloud users can have older stores.
- Custom layout remains allowed only when the behavior is covered by service tests or a manual screenshot/device acceptance checklist.
- Tests are allowed to be larger when they group one subsystem, but production Swift files should stay small enough to review quickly.

## Current Responsibility Concentrations

These are the highest-priority mixed-responsibility owners, not an exhaustive line-count report and not automatic failures. Split them along the named ownership boundaries when the subsystem is next changed, and protect behavior before moving code. Recompute the exact repository-wide line inventory at each review instead of treating this table as a frozen size snapshot:

| Area | Current concentration | Preferred boundary |
| --- | --- | --- |
| `Stores/Facade/TimeTrackerStore+Lifecycle.swift` | Generic refresh, mutation authorization/post-commit work, repository requirements, errors, and sync snapshot finishing share one owner | Split refresh/account/conflict lifecycle, mutation orchestration, and repository/error support without widening private helpers |
| `Stores/Facade/TimeTrackerStore+PreferenceCommands.swift` | Display/timing, Focus, cloud/Quick Start, and LLM preferences share one command facade | Split by preference family while retaining one validated `setPreference` support boundary |
| `Stores/Facade/TimeTrackerStore+SyncObservers.swift` | Observer installation, event decoding, batch drain, conflict processing, and recovery presentation share one owner | Separate observer/event intake from batch processing and recovery presentation; keep the fixed-deadline bounded coalescer semantics |
| `Features/Tasks/Management/TaskRowComponents.swift` | Row action policy, context menu, swipe actions, and destructive confirmation remain coupled | Extract one shared action context before separating menu and swipe presentation, so they cannot acquire divergent confirmation state |
| `Features/Analytics/AnalyticsPeriodSelectionViews.swift` | Period selector views, date text/policy, navigation bounds, and snapshot requests share one file | Separate pure period/navigation policy from SwiftUI presentation when this screen next changes |

Sync remains the highest semantic-risk subsystem because it combines security-, migration-, export-, and synchronization-sensitive behavior. Mechanical file movement alone is not completion: deterministic LWW/tombstone behavior, sensitive-key filtering, atomic restore behavior, recovery intent/session barriers, legacy-state checkpoint invalidation, and per-domain snapshot tests must remain green after every change. The current concentrations are the real files listed above; retired names must not remain in this table.

## Completed Structural Work

- App startup is split into container creation, commands, app delegate, settings scene, root views, and scene-owned typed presentation and FIFO feedback routing/hosting.
- Settings is split into actions, bindings, data sections, and presentation sections.
- Inbox commands are split between item mutations and LLM suggestion mutations.
- Checklist commands are split between item mutations and LLM visual suggestions.
- Ledger repository code is split into base, query, and mutation files.
- Forecast rollup recursion is isolated in `TaskRollupCalculationContext`.
- Timeline layout models and axis compression are split from the lane-placement engine.
- Today compact composition is in `PhoneHomeView.swift` and `PhoneHomeSections.swift`; wide priority composition remains in `HomeViews.swift`, while rows, actions, metrics, Quick Start, timeline, forecast, countdown, and shared read models have focused files.
- Analytics landing-page routing stays in `AnalyticsViews.swift`; typed category-detail loading lives in `AnalyticsCategoryDetailView.swift`, its category sections live in `AnalyticsCategoryDetailContent.swift`, while overview rows, metric/detail lists, period controls, and decision-support builders are split by responsibility.
- `AnalyticsStore.swift` now owns snapshot generation state, while `AnalyticsStore+Caching.swift` owns full/task evaluation-key lookup, bounded replacement, invalidation, and cache counts.
- Pomodoro setup is split into `PomodoroSetupViews.swift`, `PomodoroSetupEmptyState.swift`, `PomodoroFocusSetupControls.swift`, `PomodoroSetupSelectionViews.swift`, and `PomodoroTimerFace.swift`; the setup container remains the composition owner.
- Settings timing, Pomodoro, countdown, sync, data, action, binding, and support responsibilities are split; `SettingsSectionsViews.swift` is retired.
- Reusable Settings rows are split into `SettingsRows.swift`, `SettingsActionRows.swift`, `SettingsInputRows.swift`, `SettingsPresentationModifiers.swift`, and `SettingsSyncFeedbackRow.swift`; large Dynamic Type composition and VoiceOver title/value semantics remain part of those shared owners.
- Task Detail identity, checklist, overview, analytics, navigation, and record sections are split from the canonical detail router.
- Task symbol-picker presentation/search state is split from the system/bundled SF Symbols catalogue loader and AI-safe vocabulary.
- Ledger cloud mode, transaction diagnostics, timer DTO, aggregation, formatting, device identity, and summary responsibilities are split; `TimeTrackerServices.swift` is retired.
- Sync-conflict bootstrap/prompt, local mutation, Cloud import/export, recovery/resolution, state persistence, file lock/locations, export encoding, snapshot capture/domain restores, snapshot state, and organization/ledger/planning/checklist/Inbox record DTOs are split by responsibility.
- `TimeTrackerStore+Configuration.swift` owns first configuration, repository-only attachment, and committed-mutation surface refresh; `TimeTrackerStore+Lifecycle.swift` owns generic refresh, mutation, recovery, and error boundaries.
- Widget entry/provider/configuration, active-timer views, supplementary states, and support helpers are split into `TimeTrackerWidget.swift`, `ActiveTimerWidgetView.swift`, `WidgetSupplementaryViews.swift`, and `WidgetSupport.swift`.
- Watch UI composition is split into `WatchDashboardView.swift`, `WatchTimerRows.swift`, `WatchStatusViews.swift`, and `WatchColorSupport.swift`; the store family is split into observable state/restore (`WatchAppStore.swift`), commands/queue timeout/persistence (`WatchAppStore+Commands.swift`), activation/transport/payload/freshness (`WatchAppStore+Connectivity.swift`), and WCSession callbacks (`WatchAppStore+SessionDelegate.swift`).
- Ledger ordered-array mutation/index maintenance is split into `LedgerStore+FlatSegmentIndex.swift`; `LedgerStore+SegmentIndex.swift` retains day/change indexing and scoped replacement coordination.
- Rollup scoped mutation/replacement logic is split into `RollupIncrementalIndex+Mutation.swift`; the base type retains state and full rebuild, with pace, topology, and activity in their existing focused extensions.
- Source-layout tests guard the important boundaries so new work does not rebuild the earlier large-file problem; the current focused suite includes file-existence and per-family size contracts for all three splits.

## Refactor Principles

1. Keep canonical `TimeSegment` as the editable/soft-deletable fact source; caches and summaries remain rebuildable projections.
2. Put durable writes in command handlers.
3. Put SwiftData reads/writes in repositories.
4. Put calculations in services.
5. Put observable feature state in domain stores and expose it through the `@Observable` facade.
6. Keep SwiftUI views mostly declarative: render state, do not derive heavy state.
7. Prefer behavior tests, service tests, command tests, and accessibility/UI tests over source-string tests.
8. Prefer new extension models over modifying core SwiftData models.

## Facade Rules

`TimeTrackerStore` should remain a compatibility facade for SwiftUI, but domain behavior should keep moving outward.

Rules:

- Facade methods longer than 30 lines require a documented reason.
- Read-model helpers that do not need observation move out of the facade.
- Domain commands return typed results/events.

Tests:

- Command handler tests for every durable write.
- Refresh planner tests for each emitted event.
- Selection coordinator tests for task archive/restore, historical-tombstone invalidation, and navigation preservation.

## Repository Rules

Repositories should provide domain-sized queries. Views and stores should not compensate for broad fetches with repeated in-memory filtering.

Rules:

- Domain stores do not call broad "all" queries during normal user actions unless the event is `fullSync` or a history invalidation has no usable range.
- Range query semantics include explicit `now`.
- Each repository query has a behavior test or integration test.
- Add a persisted ledger bucket cache only when profiling proves range fetches are the bottleneck.

## Test Rules

Source-string tests were useful while the UI was moving quickly, but they are now a maintenance cost.

Rules:

- Keep source-contract tests only for critical architecture boundaries:
  - no recursive task `DisclosureGroup`
  - no direct SwiftData writes in views
  - shared app scheme exists
- Prefer replacing UI source assertions with:
  - pure service tests
  - command tests
  - view model tests
  - accessibility identifier UI tests
  - screenshot/manual acceptance checklists where layout is visual

Acceptance:

- No test asserts exact font, padding, or layout string unless preventing a known regression.
- UI behavior is covered by state and action contracts.

## Schema And Migration Rules

Every schema change must be safe for local-first and iCloud-backed users.

Rules:

- Keep a registry test for cloud-synced user model names.
- For each new model:
  - document whether it syncs
  - add soft-delete rules
  - add cleanup behavior if needed
- Prefer additive relation models over changing existing fact models.

Acceptance:

- A schema PR cannot merge without a migration/compatibility test.
- Demo data can be cleared independently from user data.
- iCloud startup fallback never masks data loss.

## Observability And Performance Rules

Performance fixes should be evidence-driven.

Rules:

- A slow screen can be traced to a domain refresh, service calculation, or SwiftUI layout cause.
- Performance tests protect known high-cost algorithms.
- No timer label causes full-screen refresh every second.
- Profile Release builds on macOS and devices before changing UI architecture.

## File And Folder Rules

The folder structure is now semantic. Keep the family-specific guards in `CoreSourceLayoutTests` aligned with the current owners so new work does not rebuild the earlier large-file problem. A line limit is a review signal, not a substitute for cohesion or behavior coverage.

Rules:

- A new SwiftUI feature file over 250 lines requires a responsibility review; existing larger files require the same review even when they are not among the prioritized mixed-responsibility owners above.
- A facade extension over 250 lines should be split by command/read-model responsibility.
- A test file over 400 lines should be split by subsystem.
- New shared controls belong in `SharedUI` only after a second caller exists or is imminent.
- Do not create `timetracker+Something.swift` style files for unrelated helpers; place them under the semantic folder that owns the behavior.
