# 02：Today 本周累计时间柱状图

Status: Complete

> 本文件只保存历史实现与验证记忆，不是任务来源。任务内容和状态只允许从
> [`Docs/userfeedback.md`](../../../../userfeedback.md) 读取。

## 历史反馈摘录（非任务来源）

> Today 界面可以放一个本周累计时间的柱状图。

## 当前实现

- `97021b1` 已加入 `HomeWeeklyGrossTimeSection`、`WeeklyGrossTimeSnapshot` 与共享的 `DailyTimeSeriesChart`。
- iPhone 的 Today List 与 iPad/macOS 的 Today 内容都接入了同一周视图。
- 本任务先重新验证，不以已有提交标题或历史测试记录代替本轮验收。

## 产品与 HIG 语义

- 使用 Apple 原生 Swift Charts；柱状图适合比较一周内各日的累计时长。
- 周区间必须尊重当前 Calendar/Locale，X 轴域始终覆盖完整七日；数据点只生成到当前日，不能把尚未开始的未来日伪装成零值。跨周段只计入当前周交集。
- 柱状图以 0 为纵轴基线，数据本身最突出，轴、网格和说明提供上下文但不与数据竞争。
- 标题先说明“本周累计”，总时长无需依赖图表交互即可读取；日期和时长使用真实语义标签，保留 Swift Charts 的 VoiceOver 与 Audio Graph 基线。
- 活动计时应随时间刷新；没有本周记录时提供清晰空状态，不渲染误导性的零值图。
- 普通字号下，iPhone 紧凑宽度最大化绘图区；iPad 宽布局与周围区块保持同一 leading edge，不无意义拉伸。

## 代码审查范围

- `timetracker/Features/Home/HomeReadModels.swift`
- `timetracker/Features/Home/Sections/HomeWeeklyGrossTime*.swift`
- `timetracker/SharedUI/Components/DailyTimeSeriesChart.swift`
- Today 的 iPhone、iPad/macOS 组合入口与本地化字符串
- 对应领域测试、UI contract 与 UI test

## 验收证据

- [x] 审计 Calendar 周边界、跨日/跨周裁切、并行段 gross time、活动段刷新与空状态
- [x] 审计 Swift Charts API、稳定数据身份、0 基线、轴标签、本地化与普通无障碍语义
- [x] 领域测试、UI contract 与构建通过
- [x] 使用主代理明确拥有的 iPhone 与 iPad Simulator，在普通字号完成常规路径截图验收
- [x] `CONFIGURATION=Release scripts/build_install_all.sh` 全部当前可用设备安装通过
- [x] 终止测试 App，关闭并删除本任务拥有的 Simulator，确认无遗留构建/测试/扩展/trace 进程
- [x] 回写 `Docs/userfeedback.md`，将总账改为 `[x]` 并移除 `~active` 链接

## 本轮完成范围

- 复核既有生产提交 `97021b1`：Today 的 iPhone List 与 iPad/macOS 宽布局复用 `HomeWeeklyGrossTimeSection`，图表复用 `DailyTimeSeriesChart`。
- 确认周域使用注入的 `Calendar`，按当前周裁切 segment；gross time 分别累计重叠计时，wall time 只作为共享数据结构的辅助语义。
- 确认活动计时按分钟刷新，并响应 analytics revision、系统时钟、时区、跨日与 scene phase；空周显示明确空状态。
- 确认 Swift Charts 使用稳定的日期身份、`BarMark`、0 基线、约三档 Y 轴、逐日 X 轴与每个 mark 的日期/完整时长语义标签。
- 新增测试覆盖真实 `endedAt == nil` 计时增长、空快照不刷新、Sunday-first + 洛杉矶 DST 日边界，以及系统时钟回拨后的重新求值。

## 验证记录

- `git diff --check`：通过。
- 周图领域精确切片：6/6 通过，包含 Calendar/gross overlap、open timer、空快照、DST、未来结束与时钟回拨。
- 既有 task-relevant contract/utility/layout 切片：19 个通过。
- 较宽的 `HomeUIContractTests + TimeTrackerUtilityTests + CoreSourceLayoutTests` 尝试中有 66 个通过、4 个既有且与本任务无关的失败：
  - `AnalyticsStore+Breakdowns.swift` 246 行，超过 220 行契约；
  - `TaskDetailAnalyticsViews.swift` 189 行，超过 180 行契约；
  - `TaskTreeService.swift` 195 行，超过 160 行契约；
  - `trackingEntrypointsShareAvailabilityAndRunningStateSemantics` 期望 8 次引用，当前为 7 次。
- iPhone 17 Pro Simulator（iOS 27.0）常规 Today UI test：预热后的正式重试 1/1 通过。首次冷启动在 App 最终启动前触发 XCTest launch timeout，结果包明确没有进入图表断言；没有把该次失败计为通过。
- iPad Pro 11-inch (M4) Simulator（iOS 27.0）常规 Today UI test：1/1 通过。
- iPhone 截图：[`133D27ED-9D65-4456-87E9-234CA1ABA1DA.png`](/Users/aac6fef/.codex/visualizations/2026/07/20/019f7f11-0117-7af0-8655-754ef00481ea/task02-weekly-chart/iphone/133D27ED-9D65-4456-87E9-234CA1ABA1DA.png)，1206×2622。
- iPad 截图：[`0BABDB31-7DBF-4E42-8828-F7C7602E38BF.png`](/Users/aac6fef/.codex/visualizations/2026/07/20/019f7f11-0117-7af0-8655-754ef00481ea/task02-weekly-chart/ipad/0BABDB31-7DBF-4E42-8828-F7C7602E38BF.png)，1668×2420。
- `CONFIGURATION=Release scripts/build_install_all.sh`：成功；iOS App、内嵌 Watch companion 与 macOS universal App 均完成付费团队签名。
- 将同一 Release iOS 产物显式安装至 iPhone Air 与 iPad Pro M4，二者均回读 `1.1.52 (107)`；`/Applications/timetracker.app` 回读 build 107 且 codesign 通过。当前没有可见物理 Watch，仅确认内嵌 Watch App 签名有效，未宣称在手表端启动。

## 资源清理

- 本批创建并独占：
  - iPhone `E445A10F-C6D9-4E57-AB40-A39A7A5E1157`
  - iPad `7B19FB1D-BB9B-4921-8304-D71BD44C0DB4`
- 两台设备均已终止测试 App/runner、Shutdown 并删除。
- 未触碰来源不明的 `AnalyticsReview-iPhone17Pro`（保持 Shutdown）。
- Debug DerivedData、`.xcresult` 与卡住的本批诊断 helper 已释放；最终 PNG/manifest 保留。
- 清理后确认无本批 Booted device、`xcodebuild`、`xctest`、UI runner、App extension、Instruments/trace、Simulator 或 Problem Reporter 进程。

## 状态

完成。反馈原文与总账均已标记 `[x]`，活动链接已移除。

## 依赖

- 现有 Apple Swift Charts（系统框架），不新增第三方依赖。
- 本任务是七个固定日数据点的原生图表；引入外部 chart library 会增加样式、可访问性和平台适配成本，没有收益。

## 技能约束

- Apple HIG：bar chart 用于跨类别/时间累计比较；数据优先、从 0 起始、简洁网格、上下文标题、不能只靠交互揭示关键信息。
- SwiftUI：使用现代 Charts API、描述性 `.value` 标签、稳定身份、窄输入子视图；所有 `@State` 保持 `private`，避免高频无效刷新和在 `body` 中做重计算。
