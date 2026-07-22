# 26：Timeline 任务条图标 footprint 与记录图标实现记忆

> 本文件只用于主代理与子代理的实现、验证和编排记忆，不是任务来源。唯一范围与状态必须重新读取
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 子条目。

## 当前阶段

- [x] 领取反馈，复现并审计彩色任务条无法包住图标、记录列表仍使用圆点的问题。
- [x] 对照 Apple HIG、SwiftUI 布局语义与成熟图表实现，确定图标最小 footprint 和密集时间段降级策略。
- [x] 实现共享跨平台布局与记录图标，并补充纯布局/契约测试。
- [~] 使用 owned iPhone/iPad simulator 与 XCTest 自动化 macOS window 做截图验收并清理资源。
- [ ] 精确执行 `CONFIGURATION=Release scripts/build_install_all.sh`，标记反馈完成并移除活动链接。

## 唯一反馈边界

- Timeline 中每条彩色任务条至少完整包住任务图标并保留可见 padding，不能让短任务条裁切或挤压图标。
- Timeline 下方记录列表当前的颜色圆点改为对应任务图标，同时保持任务颜色语义。
- 修复必须覆盖 iPhone、iPad 和 macOS 的共享 Timeline。
- 不领取下一条“省略时长胶囊自适应文字宽度”，也不处理版本 hook、Live Activity 或其他反馈。

## 强制约束

- 先确认现有 Timeline lane/axis compression 能否表达最小可视 footprint；不能通过伪造任务时长或截图专用硬编码掩盖真实数据。
- 优先复用系统 SF Symbols、现有 `SymbolCatalog`/任务 identity 组件和成熟库；一般拒绝非用户指定且 GitHub 少于 1k stars 的新依赖。
- UI 截图只来自 owned simulator 或 XCTest 自动化 macOS window；物理设备只做最终 Release 安装和只读核验，不启动、不操作、不截图。
- 每个小 checkpoint 验证后提交；只暂存本任务状态差异，保护 `Docs/userfeedback.md` 的其他用户新增内容。

## Checkpoint 编排

- [x] Checkpoint A：静态根因、现有组件/依赖与成熟方案审计。
- [x] Checkpoint B：任务条最小 icon footprint、记录图标与纯布局/契约回归。
- [~] Checkpoint C：owned UI 设备矩阵与脚本截图验收。
- [ ] Checkpoint D：精确 Release 安装、状态标记与收口。

## Checkpoint A 静态证据

### 根因

- `TimelineChartBars.swift` 把 SF Symbol 放在 `overlay` 中，但图标没有明确可缩放边界，彩色条也没有与图标 padding 共享尺寸契约。
- `TimelineChartLayout.swift` 的水平最短时间条为 `18pt`、垂直最短时间条为 `20pt`；这两个数字与图标尺寸无关，因此无法证明图标和内边距必然落在条内。
- compact iPhone 的 `verticalLanes` 在重叠 lane 较多时会把 `laneExtent` 持续压缩到接近 `1pt`，没有最小图标 footprint，这是“条的宽度不够容纳图标”的直接根因。
- `HomeTimelineRows.swift` 的 normal-size `regularContent` 和 `compactContent` 硬编码了 `Circle()` 颜色点；Analytics/Apple Health 的 `TimelineLegendRow` 已经显示任务 SF Symbol，不在该缺陷内。

### 复用与布局契约

- 记录行直接复用 canonical `TaskIcon` + `TaskVisualPresentation`；后者通过 `ChecklistVisualSanitizer` 保证 SF Symbol 和颜色有可用回退值。
- 彩色条图标使用可缩放的 `12pt × 12pt` SF Symbol，四边各保留 `4pt` 可见 padding，因此两个轴向的最小 footprint 统一为 `20pt`。
- horizontal 布局保持可增高的 lane 容器；compact vertical 布局对 lane 宽度设 `20pt` 下限并保留现有 `8pt` lane 间距。10 lanes 的最小内容宽度为 `96 + 12 + 10×20 + 9×8 = 380pt`；只在视口不足时由原生水平 `ScrollView` 滚动，不伪造时长、不缩小图标来掩盖问题。
- 量化回归：所有条的时间轴 extent 和 lane extent 都必须 `>= 20pt`；10 个同时重叠的 iPhone fixture 也必须满足该下限。

### 库与成熟方案审计

- Apple Swift Charts 原生支持 marks、axes 和 mark annotations，但本图的压缩时间轴、省略 gap 与重叠 lane 已是纯模型并有完整回归；为本次 footprint 缺陷整图换框架会扩大风险，不引入。
- `ChartsOrg/Charts` 约 28k stars，质量门槛通过，但需要 UIKit/AppKit bridge，也不直接提供当前压缩 lane 语义，所以不为这个局部修复新增重依赖。
- `willdale/SwiftUICharts` 当前约 963 stars，低于用户指定的 1k 门槛，明确拒绝引入。
- 保留 Apple `swift-collections 1.6.0` 的 `HeapModule`，继续用于现有 lane allocator；UI 使用 SwiftUI + SF Symbols，本 checkpoint 无新依赖。

### 全脚本验收契约

- 扩展现有 `--uitesting-overlap-timeline` fixture 和 `assertOverlappingTimelineMarks`，由 XCTest 对水平/垂直两种时间轴的条尺寸直接断言 `>= 20pt`，并比较实际 icon frame 与 bar frame，容许 `0.5pt` 像素舍入后四边仍至少保留 `3.5pt`。
- 记录按钮增加稳定的图标测试 identifier，XCTest 自动滚动到带指定 SF Symbol 的记录行后截图。
- macOS 流程在测试内调用 `placeMainWindowOnPrimaryScreen`，随后断言前台状态与 window/frame 包含关系；不再手工调窗口。
- 所有截图只由 owned iPhone/iPad simulator 或 macOS XCTest 生成；物理机仍只做 Release 安装和只读签名/版本核验。

## 资源所有权

- 当前未创建 simulator；任何 UI batch 开始前必须记录专属名称与 UDID，完成后 shutdown/delete。

## Checkpoint B 实现与验证

- `TimelineChartLayout` 以 `12pt` 图标 + 四边 `4pt` padding 推导统一 `20pt` 最小 footprint；水平/垂直的时间 extent 均使用该值。
- compact vertical 的 10-lane 最小内容宽度为 `380pt`，视口不足时由 SwiftUI 原生水平 `ScrollView` 承载；`verticalLanes` 在该宽度下每 lane 至少 `20pt`、间距保持 `8pt`。
- `TimelineChartBars` 明确约束实际 SF Symbol 为 `12×12pt`，外层 footprint 为 `20×20pt`；测试模式保留 bar 容器并暴露实际 icon 子元素 frame。
- Timeline 三种正常/大字布局均复用 `TaskIcon(visual:size: 24)`，按钮 identifier 同时编码 sanitizer 后的 SF Symbol，原有两个 `Circle()` 已移除。
- 精确回归通过：`AnalyticsTimelineTests` 全部 35 项以及本任务拥有的两项 `HomeUIContractTests`，合计 37 项；命令退出码 `0`、`** TEST SUCCEEDED **`。
- 首次运行完整 `HomeUIContractTests` 时另有三项与本任务无关的既有契约失败（timer button 源码形状断言两处、tracking entrypoint 计数一处）；本任务拥有的旧 `.ignore` 断言已同步为 `.contain` 并在精确回归中通过，未擅自修改无关失败。
- 本 checkpoint 未创建 simulator、未打开或手工移动窗口；无 owned UI 资源需要清理。
