# Code Refactor Status And Guardrails

Status: current source-structure record after the 2026-07-14 repository-wide split and the 2026-07-17 scene/sync refinements. This document records what was split, what is still concentrated, and the engineering rules that keep the project maintainable. It is not a product feature backlog and it does not substitute for the final risk-proportionate build, test, simulator, and Instruments evidence in [Audit-2026-07-14](Audit-2026-07-14.md).

## 2026-07-17 收口计划：只推进一个主动重构项目

全面审查已经完成了横向的正确性、信息架构和源码职责检查。它留下的事项不能成为无限期、机会主义的“顺手重构”列表：每一项都必须有用户价值、可观察证据和明确停止条件。当前未提交的 writer 事务修复是既有审查的最后一个正确性检查点；它完成、通过定向签名测试并提交后，**唯一允许主动实施的重构项目是 R1**。R2 以后只记录为将来输入，不得与 R1 并行编码。

| 顺序 | 项目 | 当前决定与价值 | 完成/停止条件 |
| --- | --- | --- | --- |
| W0（进行中） | Store writer 收口：同步偏好、LLM 凭据配置、Countdown 新建 | 修复跨 scene/进程 writer 与 timer admission 读写同一事实时使用旧 `ModelContext` 的竞态；LLM Keychain 补偿也不再读取锁外旧值。它是 R1 开始前必须提交的正确性前提，不是新的长期项目。 | coordinator、命令和回归测试通过；付费签名 macOS XCTest 成功；删除该批 DerivedData/result bundle，确认没有本批 `xcodebuild`/`xctest`/booted simulator 后提交。 |
| **R1（唯一主动项目）** | **Analytics 读模型的交互性能边界** | Analytics 是持续使用的复盘入口。虽然缓存和同周期刷新已避免空白屏，snapshot 构建仍由 `@MainActor` store 触发；大账本或频繁 live bucket 更新可能抢占导航、滚动和 period 切换。这个项目直接改善最常见的等待和卡顿风险，同时不触碰 iCloud schema 或不必要地重画 UI。 | 先以签名 Release/macOS 以及一个明确、受控的大账本 fixture 取得主线程与 snapshot 时长基线；若没有实际预算违例，记录证据并**不改架构**。若有违例，只实现一次：把可发送的纯输入/计算移到后台边界，主 actor 只负责快照发布、请求 identity、取消和缓存。以相同 fixture 复测，保证结果、取消、周期切换和缓存命中不退化；完成后停止主动重构。 |
| R2（记录，不实施） | Inbox 的重排与建议“应用/丢弃”动作层级 | UI 审查发现重复入口会增加误操作和学习成本；有价值，但不高于 R1 的日常流畅性和已确认的 writer 正确性。 | R1 已明确完成或取消后，只有用户再次授权才排入实现。 |
| R3（记录，不实施） | Facade 余下的生命周期/同步观察者职责拆分 | 可降低维护成本，但没有用户可观察故障或量测瓶颈；单纯按行数拆文件是低价值工作。 | 除非 R1 的 profiling 指向它，或用户以独立任务授权，否则不做。 |
| Release gate（非重构） | 全量签名 build/test、真实账户/iCloud 路径与一次正常操作路径验收 | 这是发布证据，不是无限重构的理由。仅在 R1 结束时执行风险相称的最终验证。 | 记录成功/失败证据与资源清理；发现新问题必须由用户决定是否开启新的有限项目。 |

### R1 的工作契约

1. **先测量，后改变。** 使用具有确定数量的 ledger fixture 和同一输入区间；记录 snapshot 总耗时、主线程繁忙区间、刷新/切换期间的可交互性。不得仅因文件大或猜测而引入 `Task.detached`、新缓存层或 schema。
2. **一次边界，而非重写。** 如果量测证明需要优化，SwiftData 获取、请求 identity、取消、缓存和 `@Observable` 发布继续留在既有 owner；仅把 Sendable 的纯 Analytics 输入和计算搬到后台。不得让后台持有 `ModelContext`、`PersistentModel` 或 SwiftUI state。
3. **正确性优先。** 同一 request identity 的结果才可发布；period/calendar/revision/live bucket 变化取消旧任务；分类、deleted task、gross/wall、comparison、overlap 和 task-detail 结果必须和优化前一致。没有可信的行为/性能证据就回退该实现，而不是追加补丁。
4. **资源与签名。** 不用 Device Hub 代替自动化测试。每个 profiling 或 test batch 都记录 owner，并在结束时终止本批 app/process、删除 DerivedData/result/trace；只有为该批显式创建的 simulator 才可关闭和删除。构建与测试保留 Automatic Signing、团队和 paid Developer capabilities。
5. **停止条件。** R1 的基线证明无需优化，或一次经过验证的优化达到预算且没有回归时，立刻停止主动重构；剩余表项保持记录状态。任何新 P0/P1 都必须先写成独立、有限的任务并由用户确认范围。

### 本轮仍未完成的事项

- W0 的定向签名 XCTest、源码合同和提交尚未完成；除它以外没有正在实施的横向重构。
- R1 的量测基线、是否需要代码移动的决策，以及（仅在基线证明必要时）一次受限实现尚未完成。
- 最终 release gate 尚未执行，且应在 R1 停止后而不是现在扩大为长期测试/重构循环。
- 已知基线测试债务：当前 `HEAD` 的 `AnalyticsCategoryDetailView.swift` 已有 183 个物理行，而既有 `CoreSourceLayoutTests` 仍限制 180（由 `4f81577` 之前后遗留，非 W0 改动）。全套 source-layout suite 因此失败；它必须在最终 release gate 以一次明确的责任边界调整处理，不能为了当前 writer checkpoint 机械拆 UI 或悄悄放宽预算。

## Review Summary

The current pass established semantic folders, split domain stores and repositories, and then removed the largest mixed-responsibility production files:

- `SyncConflictService.swift` was reduced to bootstrap/prompt ownership; local mutation, Cloud import/export, recovery/resolution, persisted state, file lock/locations, export encoding, snapshot capture/domain restores, snapshot state, and domain record DTOs now have focused files.
- Analytics landing-page composition and `AnalyticsCategoryDetailView` were split; category navigation is typed, while overview-row, metric-list, detail-list, period, group-breakdown, metrics, overlap, task-snapshot, and snapshot-cache responsibilities have focused owners.
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
- Analytics landing-page routing stays in `AnalyticsViews.swift`; typed category-detail composition lives in `AnalyticsCategoryDetailView.swift`, while overview rows, metric/detail lists, period controls, and decision-support builders are split by responsibility.
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
- Selection coordinator tests for task deletion, selection invalidation, and navigation preservation.

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
