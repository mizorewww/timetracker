# 63：停止计时后主页 timeline 仍显示为进行中 实现记忆

状态：2026-07-26 进行中

> 本文件是主代理与子代理的实现、验证和编排记忆；唯一任务来源仍是
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 条目。

## 认领的反馈条目

- 反馈第 108 条：停止一个任务时确实停止了，但主页 timeline 显示没有正确停止。

## 关键背景：timeline 里没有"进行中"这个标志

`AnalyticsTimelineEntry`（`Models/AnalyticsTimelineReadModels.swift:72-90`）只有
非可选的 `startedAt`/`endedAt`。"仍在进行"完全由**条形的结束时间等于 now** 表达：

- `AnalyticsTimelineSnapshotService.presentationSeeds`
  （`Services/Analytics/AnalyticsTimelineSnapshotService.swift:43-48`）
  调用 `TrackedTimePolicy.interval(startedAt:endedAt:now:clippedTo:)`。
- `TrackedTimePolicy.boundedEnd`（`Models/LedgerModels.swift:36-38`）：
  `min(endedAt ?? now, now)`。**这一行就是"未结束 ⇒ 画到 now"的唯一判据。**

所以只要 `TimeSegment.endedAt` 在读取方看来仍是 `nil`，条形就会一直长到 now，
并被 `TodayTimelineChart` 的 `TimelineView(.periodic(by: 60))`
（`Features/Home/Sections/HomeTimelineViews.swift:111`）每 60 秒重新确认一次。

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

`LedgerStore+FlatSegmentIndex.swift:17-24` 还显式假设了同一引用语义：
注释写着 "SwiftData returns the same reference after an in-context edit"，
并在 `allSegments[existingIndex] === model` 时**整段跳过写回**。对跨 context
的编辑，这条快速路径会把陈旧引用固化下来。

## 待验证的假设

- H1（首选）：main context 里的 `TimeSegment` 对象在 stop 之后仍持有
  `endedAt == nil`，`refreshVisible`（`Stores/Domains/LedgerStore.swift:36-73`）
  重新 fetch 也没有把它刷新。**先用 store 边界测试证伪或证实。**
- H2：`TodayTimelineChart`（`HomeTimelineViews.swift:105-123`）只持有
  `store`、`segments: [TimeSegment]`、`compactHeight`，全是引用/值相同，
  SwiftUI 可以判定"未变化"而跳过重建，于是 legend 行更新、图表不更新。
- H3：图表和 legend 各自独立算一份 snapshot（`:46` 与 `:114-118`，`now` 还不同），
  即使数据新鲜也可能在 60 秒内互相不一致。属于既有重复缺陷。

区分方法：H1 在 store 层就会失败；H2/H3 在 store 层通过、只在视图层失败。

## Checkpoint 编排

- [x] A：认领反馈、建立实现记忆、写出能区分 H1/H2/H3 的测试。
- [x] B：按测试结果修根因。
- [~] C：消除图表与 legend 各算一份 snapshot 的重复（H3），无论它是不是根因。
- [ ] D：`make test` 门禁 + 模拟器验收、Release 全设备安装、反馈收口。

## 约束与边界

- 不改 SwiftData `@Model` ⇒ 不需要新增 `VersionedSchema`。
- 已知既有失败（与本任务无关，不伪造绿色）：
  `TaskPersistencePolicyTests.archiveCommandPreservesTheOriginalArchiveTimestamp`、
  `PreferenceSyncBehaviorTests.checklistCompletionMovesOnlyTheTargetToTheDestinationGroupEnd`、
  `CoreLLMResponseTransportTests.nonSuccessStatusTakesPriorityOverDeclaredBodySize`。

## 现有覆盖

**没有任何测试覆盖"停止计时后的主页 timeline"。** 最接近的是
`CoreSystemActionCommandTests.swift:605 systemActionStopTimerClosesActiveSegment`，
但它只断言持久化，而且是用**持有该对象的同一个 context** 重新读取的，
正好绕开了本 bug。

## 使用的库

- 待定。

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
