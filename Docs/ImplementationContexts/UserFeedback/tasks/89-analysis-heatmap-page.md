# 89：Analysis Heatmap 独立页面 实现记忆

状态：2026-07-28 已完成

> 本文件是主代理与子代理的实现、验证和编排记忆；唯一任务来源仍是
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 条目。

## 认领范围

- 把 Analysis 首页中现有 Heatmap 从内嵌内容改为独立、可导航的分析页面。
- 复用现有 Heatmap 数据投影、时间段选择和共享视图，不重建统计或绘图实现。
- 在紧凑和宽布局中都保留当前 Analysis 导航状态与平台原生返回行为。

## 验收条件

- [x] Analysis 首页只保留可发现的 Heatmap 入口，不再直接展开完整 Heatmap。
- [x] 独立页面显示完整 Heatmap、现有时间范围和空/加载/错误状态。
- [x] 返回后 Analysis 的选择和滚动语义符合原生导航。
- [x] 行为测试、普通字号 iPhone/iPad/macOS 截图、`make test`、格式与本地化门禁通过。
- [x] 最终提交完成 `make build-install-all`。

## 子代理编排

- 子代理 A：只读审计现有 Analysis Heatmap 组合、路由和测试缺口。
- 子代理 B：只读审计现有 UI test route、截图资产与全平台验收入口。
- 主代理：验收清单、测试、实现、集成、截图、提交和资源清理。

## 设计与库策略

- 遵循 Apple HIG：顶层 Analysis 保持概览层级，完整可视化通过类型安全导航渐进披露；
  宽度自适应，不按平台复制页面。
- 遵循 SwiftUI skill：路由值稳定、状态归属明确、图表数据身份稳定、共享 Heatmap 视图
  保持 context-agnostic。
- 继续使用项目现有 SwiftUI / Swift Charts / SwiftData 投影；不新增重复第三方库。

## 进度记录

- 2026-07-28：认领任务，已完成 Charts、导航、状态、自适应布局相关 skill 规则核对。
- 2026-07-28：先补独立 typed destination 行为测试并确认失败；实现首页入口、
  `AnalyticsHeatmapView`、配置空态与三语文案。路由单测 5/5、SwiftFormat、本地化 9/9
  通过。
- 2026-07-28：iPhone 普通字号真实入口、独立页、无重复日期筛选和系统返回验收通过；
  空态夹具确认正确，并修复外层页面标识覆盖空态标识的问题。
- 2026-07-28：截图验收发现逐 `RectangleMark` 的 `.accessibilityHidden(true)` 在当前系统上
  同时抑制了视觉 mark；改为 Chart 级 `.accessibilityElement(children: .ignore)`，仍只生成
  单个图表 AX 节点，同时恢复全部 Heatmap tile。
- 2026-07-28：普通字号 iPhone、13 英寸 iPad Pro、macOS 独立入口、完整页面与系统返回
  XCUITest 均通过，截图人工检查通过；配置空态 iPhone XCUITest 通过。`make test`
  1564/1564、SwiftFormat 875/875、本地化 9/9、hook 与 diff 门禁全部通过。
- 2026-07-28：实现 checkpoint `70280a84` 已提交；Release 全设备构建安装通过，应用已安装
  到 iPad Pro M4、iPhone Air 和 `/Applications/timetracker.app`，iOS 包内包含 Watch
  companion。
