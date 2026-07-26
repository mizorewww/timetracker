# 63：停止计时后主页 timeline 仍显示为进行中 实现记忆

状态：2026-07-27 已完成

> 本文件是主代理与子代理的实现、验证和编排记忆；唯一任务来源仍是
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 条目。

## 认领的反馈条目

- 反馈第 108 条：停止一个任务时确实停止了，但主页 timeline 显示没有正确停止。

## 关键背景：timeline 需要同时携带区间和“Now”展示语义

修复前 `AnalyticsTimelineEntry` 只有非可选 `startedAt`/`endedAt`，活动区间被
`TrackedTimePolicy.boundedEnd` 裁到 `now` 后，图表能画出终点，但 legend 行无法再
区分“原记录仍开放”和“原记录已在这一刻闭合”。现在展示快照额外携带
`usesCurrentEndLabel`，图表和 legend 共用同一份值语义 snapshot。

`TrackedTimePolicy` 仍会把时钟偏差导致的未来结束时间裁到 `now`。因此视图重算时的
参考时间不得早于刚写入的停止时间；分钟时钟只负责定时触发，账本变更触发的任意
重算都使用 `max(clockDate, liveDate)`。

## 为什么 Now 区好了、timeline 没好

停止写入发生在**另一个 sibling `ModelContext`** 里：
`StoreScopedTimerMutationTransaction.withFreshReadContext`
（`Services/TimeTracking/StoreScopedTimerMutationTransaction.swift:70-74`）用
`TimerModelContextFactory.makeContext` 新建 context，整个 stop 在那里计划并写入，
不在 `store.modelContext`。

两个读模型因此分叉：

- **Now 区** 走 `activeSegments()`
  （`Repositories/SwiftDataTimeTrackingRepository+Queries.swift:6-8`），
  谓词是 `$0.endedAt == nil`。持久化行已经关闭，所以无论内存对象是什么状态，
  它都不会被选中 ⇒ Now 正确清空。
- **timeline** 走 `segments(from:to:now:)`（同文件 `:52-74`），谓词仍然命中
  （这条记录还是"今天"的），随后**读取返回对象的内存 `endedAt`**
  （`AnalyticsTimelineSnapshotService.swift:45`）。若该值仍为 `nil`，
  `boundedEnd` 返回 now ⇒ 条形继续生长。

SwiftData 会把 sibling context 的字段更新合并到同一个持久模型引用，因此
`segments` 数组的引用身份可以完全不变。`timelineSnapshot` 现在显式读取 store
持有的 `analyticsRevision`，确保 Observation 在可见账本刷新后重算值快照。

## 待验证的假设

- H1（已证伪）：main context 里的 `TimeSegment` 对象在 stop 之后仍持有
  `endedAt == nil`。
- H2（已证实并修复）：`TodayTimelineChart` 只持有
  `store`、`segments: [TimeSegment]`、`compactHeight`，全是引用/值相同，
  Observation 缺少值语义失效信号。
- H3（已证实并修复）：图表和 legend 各自独立算一份 snapshot，`now` 也不同。
- H4（UI 测试发现并修复）：停止动作可能落在分钟时钟两次 tick 之间；若重算仍沿用
  旧 tick，刚写入的 `endedAt` 会被时钟偏差保护逻辑误判为未来值并显示 `Now`。

区分方法：H1 在 store 层就会失败；H2/H3 在 store 层通过、只在视图层失败。

## Checkpoint 编排

- [x] A：认领反馈、建立实现记忆、写出能区分 H1/H2/H3 的测试。
- [x] B：按测试结果修根因。
- [x] C：消除图表与 legend 各算一份 snapshot 的重复，并修复分钟时钟竞争。
- [x] D：macOS UI 验收、Release 全设备安装、反馈收口。

## 约束与边界

- 不改 SwiftData `@Model` ⇒ 不需要新增 `VersionedSchema`。
- 已知既有失败（与本任务无关，不伪造绿色）：
  `TaskPersistencePolicyTests.archiveCommandPreservesTheOriginalArchiveTimestamp`、
  `PreferenceSyncBehaviorTests.checklistCompletionMovesOnlyTheTargetToTheDestinationGroupEnd`、
  `CoreLLMResponseTransportTests.nonSuccessStatusTakesPriorityOverDeclaredBodySize`。

## 新增覆盖

- `TodayTimelineStopTests`：持久化结果、store 可见读模型、Observation 投影失效，
  并断言活动/停止快照的 `usesCurrentEndLabel`。
- `testStoppingTodayTimerImmediatelyClosesMatchingTimelineRow`：隔离 demo 数据，
  按真实 UI 停止一条计时，按 segment identity 找到同一 Timeline 行并断言其
  accessibility value 不再包含 `Now`，同时保存正常字号截图。

## 使用的库

- 未新增第三方库。该问题属于 SwiftUI Observation、SwiftData sibling context
  合并和本地展示时钟协作；采用系统框架比引入外部状态库更小、更符合现有架构。
- 参考 Apple 官方 ModelContext 与 SwiftData history 文档核对跨 context 语义。

## 进度记录

- 2026-07-26 Checkpoint A：认领第 108 条，完成数据通路溯源，建立本文件。
- 2026-07-27 Checkpoint A 复验：`make test` 中两个账本值测试均通过，
  H1 被证伪；全套只有 4 个已知无关基线失败。根因收敛到 H2：
  sibling context 合并后的 `TimeSegment` 字段已更新，但数组保持持久模型身份相等，
  Today timeline 没有值语义 revision 可供 Observation 发布。追加投影失效测试，
  要求 Stop 必须触发 SwiftUI 所依赖的观察失效。
- 2026-07-27 Checkpoint B：确认投影失效测试在修复前失败；让
  `timelineSnapshot` 显式读取现有 `analyticsRevision`，沿用 AD-013/AD-054
  的事件驱动、store-owned semantic revision 模式。修复后 Today timeline
  三项回归测试全部通过；完整 `make test` 共 1417 项，只剩 4 个无关基线失败：
  `CoreLLMResponseTransportTests.nonSuccessStatusTakesPriorityOverDeclaredBodySize`、
  `DemoDataLifecycleTests.demoDataContainsMultiDayAnalyticsAndActiveTimers`、
  `PreferenceSyncBehaviorTests.checklistCompletionMovesOnlyTheTargetToTheDestinationGroupEnd`
  和 `TaskPersistencePolicyTests.archiveCommandPreservesTheOriginalArchiveTimestamp`。
  本 checkpoint 未引入第三方库。
- 2026-07-27 Checkpoint C：图表和 legend 改为消费同一份
  `AnalyticsTimelineSnapshot`，值快照保存 `usesCurrentEndLabel`。初版用隐藏的
  `TimelineView` 驱动本地时钟，在 macOS 首帧约束更新时触发 AppKit 崩溃，已撤回并
  改为可取消的 Swift Concurrency 分钟任务。iPhone 端到端测试随后复现第二层竞争：
  Stop 写入发生在上一次 minute tick 之后，旧参考时间把新结束时间当成未来值。
  `homeTimelineSnapshotReferenceDate` 现在保证普通运行时取
  `max(clockDate, liveDate)`。定向 iPhone UI 测试通过，截图确认
  `00:17 - 00:50`；完整 `make test` 仍为 1417 项、仅同一组 4 个基线失败。
- 2026-07-27 Checkpoint D：定向 iPhone UI 测试通过，结果包为
  `/tmp/timetracker-63-iphone-run3-20260727.xcresult`，正常字号截图确认对应
  Timeline 行已显示闭合区间 `00:17 - 00:50`；定向 macOS UI 测试通过，结果包为
  `/tmp/timetracker-63-macos-run4-20260727.xcresult`，截图确认图表色块在停止时刻
  闭合。`make format-check`、`make localization-check`、`make check-hooks` 和
  `git diff --check` 均通过。Checkpoint B、C 和跨平台 UI 验收分别提交为
  `2e3fe481`、`da3c78a9`、`b6a14540`。
- 2026-07-27 Release 安装：`make build-install-all` 使用 Release 和自动签名成功，
  已安装到实体 `iPad Pro M4`、实体 `iPhone Air`，并把通用 macOS App 复制到
  `/Applications/timetracker.app`。当前未检测到实体 Apple Watch；嵌入的 Watch
  伴侣 App 已完成签名/描述文件校验，会在配对设备启用自动安装后随 iPhone App
  安装。
