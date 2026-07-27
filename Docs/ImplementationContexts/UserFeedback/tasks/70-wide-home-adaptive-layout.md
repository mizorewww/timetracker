# 70：宽屏主页自适应排布 实现记忆

状态：2026-07-27 进行中

> 本文件是主代理与子代理的实现、验证和编排记忆；唯一任务来源仍是
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 条目。

## 认领的反馈条目

- 宽度较宽的设备主页排布浪费空间，建议根据可用宽度自动排布。

## 预期行为

- iPad 与 macOS 主页随实际可用宽度选择合适的列数与列宽，而不是只在固定双栏中拉伸或留下大片空白。
- 信息层级、阅读顺序和交互顺序保持稳定；单个卡片不会被压到不可读，也不会无限拉宽。
- iPhone 紧凑主页保持现有单列行为；正常字号下遵循 Apple HIG 的间距与点击目标。

## UI 验收清单

- 先用确定性 fixture 和几何断言记录宽屏现状及失败证据。
- macOS 至少验证窄窗口与宽窗口；iPad 至少验证横屏宽布局；iPhone 验证紧凑单列。
- 普通字号截图检查列宽、空白利用、阅读顺序与对齐。
- SwiftFormat、相关 XCUITest、默认 `make test` 和 Release 全设备安装通过。
- 释放所有 owned 模拟器、runner 与临时构建资源。

## Checkpoint 编排

- [x] A：领取反馈、建立活动实现记忆并审计当前宽屏主页结构。
- [x] B：确定自适应排布规则，补充失败的几何/行为测试。
- [x] C：实现最小布局变更，更新相关设计与测试文档。
- [~] D：完成格式、跨尺寸 XCUITest/截图、全量测试、Release 全设备安装与收口。

## 库策略

- 优先评估 SwiftUI 原生 adaptive `Grid`、`Layout` 与现有主页容器是否足够。
- 只有成熟库能提供原生方案不具备的关键能力时才引入依赖；单纯响应式栅格不额外造依赖。

## 进度记录

- 2026-07-27：认领任务并建立 `~70` 活动实现记忆。
- 2026-07-27：Apple HIG、SwiftUI、实现和测试审计一致建议使用最多两列的有界布局；保持 Now → Overview → 可视化 → Quick Start → Timeline → Forecast/Countdown 阅读顺序，不采用三列、masonry 或自定义 `Layout`。
- 2026-07-27：库审计检查了 SwiftUI 原生 Grid/Layout、WaterfallGrid 与 Exyte Grid。原生 `HStack`/`VStack` 配合现有 `HomeLayoutPolicy` 已完整覆盖需求；候选库的维护与确定性风险没有带来关键能力，且 AD-039 禁止仅为原生层级引入第三方布局库，因此本任务不新增依赖。
- 2026-07-27：先写行为与 UI 几何测试。策略测试首次编译在缺少 `wideVisualizationColumnWidth` / `wideQuickStartColumnWidth` 时失败；修正 fixture 后 4/4 通过，结果为 `Test-timetracker-2026.07.27_16-28-54-+0800.xcresult`。实现前 macOS UI 测试在 `macOS-20260727-162910.xcresult` 记录真实失败：Weekly Gross Time 的尾缘 1237 pt，Quick Start 的首缘 521 pt，仍为纵向堆叠。
- 2026-07-27：`HomeLayoutPolicy` 现在从实际内容宽度派生 678...748 pt 可视化列和 300...410 pt Quick Start 列；`DesktopTodayContent` 在 1000 pt 断点以上先排“可视化 + Quick Start”，再排“Timeline + 可选 360 pt 辅助列”，较窄 proposal 保持原单列顺序。
- 2026-07-27：macOS 1500×1000 确定性窗口测试通过（`macOS-20260727-163153.xcresult`）；iPad Pro 13 英寸横屏收起 sidebar 后同一测试通过（`iOS-20260727-163331.xcresult`）。已人工检查 `mac-home-adaptive-packed-columns` 与 `ipad-home-adaptive-packed-columns` 截图，列宽、空白利用、阅读顺序和按钮尺寸正常。
- 2026-07-27：格式化后 macOS 宽屏回归再次通过（`macOS-20260727-164013.xcresult`），iPhone 紧凑主页回归通过（`iOS-20260727-164039.xcresult`）。`make format-check`、`make localization-check`、`make check-hooks` 均通过；默认 `make test` 在 `Test-timetracker-2026.07.27_16-42-24-+0800.xcresult` 中通过 1419 项测试。
