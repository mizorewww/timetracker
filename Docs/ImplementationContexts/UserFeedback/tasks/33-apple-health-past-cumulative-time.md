# 33：Apple Health 过去累计时间与时间段实现记忆

> 本文件只用于主代理与子代理的实现、验证和编排记忆，不是任务来源。唯一范围与状态必须重新读取
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 条目。

## 当前阶段

- [x] 领取“Apple Health 任务似乎无法查看过去累积时间和过去时间段”的反馈。
- [x] 对照上一项历史分析实现，以脚本化测试设计复现真实剩余缺口。
- [x] 审计数据查询范围、累计口径、详情/统计入口与刷新生命周期。
- [~] 复用现有周期导航实现最小修复并补齐 Core/UI contract/XCUITest。
- [ ] 提交实现 checkpoint，执行 `CONFIGURATION=Release scripts/build_install_all.sh`，标记反馈完成并移除活动链接。

## 唯一反馈边界

- Apple Health 固定任务应能查看过去累计时间，以及用户选择的过去时间段。
- 不领取后续首页卡片、category 展开或其他反馈。

## 强制约束

- 完整遵循仓库本地 `apple-hig` 与 `swiftui-expert-skill`；UI 调试、导航、断言与截图全部使用 XCTest/XCUITest 脚本。
- 不手动操作调试窗口；物理设备只做最终 Release 安装和只读版本/签名核验，不启动、点击或截图。
- 优先复用现有历史分析服务和系统框架；若评估第三方库，必须核验维护质量与 GitHub stars，除用户建议外不采用少于 1k stars 的库。
- 每个 checkpoint 只暂存本任务变更，保护 `Docs/userfeedback.md` 中其余用户新增内容。

## Checkpoint 编排

- [x] Checkpoint A：范围领取、上一实现差距审计与自动化复现设计。
- [~] Checkpoint B：最小实现、聚焦测试与脚本截图验收。
- [ ] Checkpoint C：Release 全设备安装、签名/版本只读核验与收口。

## Checkpoint A 审计结论

- 根因可直接复现：详情页只有 `Today / Week / Month` 粒度选择，没有历史日期状态或周期导航；`taskAnalyticsSnapshotRequest` 又把同一个 `now` 同时作为 `referenceDate` 与 `liveNow`，所以三个粒度永远锚定当前周期。
- 底层 `AppleHealthTaskAnalyticsProjectionService` 已按 request 的 `evaluationKey.interval` 裁剪当前周期，并查询上一比较周期及睡眠上下文；只要请求能够表达历史日期，所选历史周期的累计时间、图表和记录无需另造投影服务。
- “过去累积时间”按应用既有术语指所选过去周期的 Gross Time，而不是 lifetime/all-time。当前反馈没有“自始至今/全部/生命周期”语义；不擅自增加无界 HealthKit 查询或新的累计口径。
- Task31 的 XCUITest 只从 Week 切到 Month，验证的是粒度而不是历史周期，因此在完全无法查看上周/上月时仍会通过。
- 最小修复：详情页复用现有 `AnalyticsPeriodNavigator`、`AnalyticsPeriodText`、`AnalyticsRange.evaluation(referenceDate:liveNow:)` 与 `AnalyticsRefreshPlan`；请求构造明确拆分 selected reference date 和 wall-clock now，并保持现有 cancellable/newest-wins 生命周期。
- 自动化验收必须真实点击“上一周期”，断言周期标题改变、下一周期按钮启用、历史累计非零、图表/历史记录属于已加载的过去周期，并从 XCUITest 的 xcresult 附件取图审阅。
- Apple 官方 SwiftUI `DatePicker` 文档确认原生控件支持绑定绝对日期并限制选择范围；现有 navigator 已使用 `...liveNow` 阻止未来日期，不需要新增第三方依赖。

## 非本项范围

- lifetime/all-time Health 总计需要独立 read model 与受控/增量 HealthKit 查询，不能把 sample query 起点粗暴改成 `distantPast`；当前反馈不授权扩项。
- 当前周期内永久前台时监听外部 Health 新样本、历史列表分页/“查看全部”都不是本次“无法选择过去周期”的根因，留给明确反馈处理。

## 资源所有权

- 尚未创建本任务 simulator；任何创建的 UDID 必须记录于此并在批次结束后 shutdown/delete。
