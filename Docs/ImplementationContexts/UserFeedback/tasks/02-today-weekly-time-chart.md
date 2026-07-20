# 02：Today 本周累计时间柱状图

## 反馈

> Today 界面可以放一个本周累计时间的柱状图。

## 当前实现

- `97021b1` 已加入 `HomeWeeklyGrossTimeSection`、`WeeklyGrossTimeSnapshot` 与共享的 `DailyTimeSeriesChart`。
- iPhone 的 Today List 与 iPad/macOS 的 Today 内容都接入了同一周视图。
- 本任务先重新验证，不以已有提交标题或历史测试记录代替本轮验收。

## 产品与 HIG 语义

- 使用 Apple 原生 Swift Charts；柱状图适合比较一周内各日的累计时长。
- 周区间必须尊重当前 Calendar/Locale，并始终展示完整七日；跨周段只计入当前周交集。
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

- [ ] 审计 Calendar 周边界、跨日/跨周裁切、并行段 gross time、活动段刷新与空状态
- [ ] 审计 Swift Charts API、稳定数据身份、0 基线、轴标签、本地化与普通无障碍语义
- [ ] 领域测试、UI contract 与构建通过
- [ ] 使用主代理明确拥有的 iPhone 与 iPad Simulator，在普通字号完成常规路径截图验收
- [ ] `CONFIGURATION=Release scripts/build_install_all.sh` 全部当前可用设备安装通过
- [ ] 终止测试 App，关闭并删除本任务拥有的 Simulator，确认无遗留构建/测试/扩展/trace 进程
- [ ] 回写 `Docs/userfeedback.md`，将总账改为 `[x]` 并移除 `~active` 链接

## 依赖

- 现有 Apple Swift Charts（系统框架），不新增第三方依赖。
- 本任务是七个固定日数据点的原生图表；引入外部 chart library 会增加样式、可访问性和平台适配成本，没有收益。

## 技能约束

- Apple HIG：bar chart 用于跨类别/时间累计比较；数据优先、从 0 起始、简洁网格、上下文标题、不能只靠交互揭示关键信息。
- SwiftUI：使用现代 Charts API、描述性 `.value` 标签、稳定身份、窄输入子视图；所有 `@State` 保持 `private`，避免高频无效刷新和在 `body` 中做重计算。
