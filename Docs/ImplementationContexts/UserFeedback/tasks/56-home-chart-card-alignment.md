# 56：主页图表卡片对齐与设计规范实现记忆

> 本文件是主代理与子代理的实现、验证和编排记忆。任务内容与状态的唯一来源仍是
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 条目。

## 当前阶段

- [x] 按文档顺序领取标题字体、卡片左右间距和主页设计规范反馈。
- [x] 审计主页现有标题、卡片容器、heatmap 与 Gross Time 图表实现和历史边界。
- [x] 先写可验证的 UI 验收清单，再做最小实现。
- [~] 为相对标题/卡片几何补充失败的 UI 验收，再统一实现 owner。
- [ ] 完成格式、单元测试和 iPhone/iPad/macOS 普通字号截图验收。
- [ ] 提交小 checkpoint，执行 Release 全设备安装，标记反馈完成并移除活动链接。

## 唯一范围

- 统一主页 heatmap、Gross Time 柱状图与主页其他区块的标题字体、层级和水平边界。
- 统一这些图表卡片与主页其余卡片的左右间距，不顺带重做图表数据语义或颜色。
- 在当前设计文档中写出可复用、能由测试和截图核对的主页设计规范。
- 不领取 Analytics 闪烁、Apple Health、timeline、侧边栏或后续反馈。

## 强制约束

- 主代理完整遵循仓库本地 `apple-hig` 和 `swiftui-expert-skill`。
- 先复用现有 SwiftUI、Swift Charts、系统文字样式和已有卡片容器；系统 API 能覆盖时不新增第三方依赖。
- 若确需第三方库，先核查维护状态、许可证、近期发布和至少 1k GitHub stars。
- UI 变更先建立验收清单；完成后在普通字号对 iPhone、iPad、macOS 做脚本化截图。
- 每个模拟器登记名称和 UDID；结束后终止 App/Runner、关机并删除。
- `Docs/userfeedback.md` 中用户并行新增或重新打开的其他条目不纳入本任务提交。

## Checkpoint 编排

- [x] Checkpoint A：领取、现状/历史/测试审计、设计契约。
- [~] Checkpoint B：测试先行、统一容器与标题、更新主页设计规范。
- [ ] Checkpoint C：跨平台截图、完整门禁、Release 全设备安装和反馈收口。

## 子代理编排

- [x] `history_audit`：只读定位主页各卡片容器、标题来源和导致差异的提交。
- [x] `test_audit`：只读检查现有 UI contract、截图入口和可复用共享组件。

## 资源所有权

- 当前没有本任务拥有的模拟器、XCTest、Instruments、物理设备或构建进程。

## 待形成的 UI 验收清单

- [x] 主页 Overview、Gross Time 和 Heatmaps 标题复用同一个 Home owner：卡片模式统一
  `headline`，List 模式统一继承系统 `Section` header 语义，不为图表单独硬编码字号。
- [x] Gross Time 与每张 Heatmap 卡片在同一平台的 `minX/maxX` 误差不超过 2 pt，
  左右留白近似对称；标题继续位于卡片外且与卡片同列。
- [x] iPhone 纵向布局保留每个 Heatmap 独立卡片及至少 8 pt 可见分隔，同时与
  Today 其它 inset-grouped 内容使用同一水平边界；iPad/macOS 卡片模式不增加
  iPhone 专属 inset 或双重 padding。
- [x] 保留旧 header/card/grid/range identifier、标题 header trait、总数/总时长、
  独立 Info 按钮与完整图表可访问语义。
- [x] 不改变 Gross/Wall、日历周/DST、Heatmap period/metric/颜色/任务选择、异步刷新
  与重算期间保留旧快照的行为。

## 审计与设计结论

- iPhone `PhoneHomeView` 是 `.insetGrouped` List；Gross Time 和 Heatmap 进入
  `.listSection`，共同使用 `homeVisualizationListCard`。该 modifier 为保证 iOS 26+
  连续 `Section` 不把多张 Heatmap 合并，必须继续拥有独立背景、圆角、透明 row 和
  separator 规则；不能恢复任务 39 中被真实截图否决的纯原生 row 方案。
- 当前共享 modifier 同时设置 16 pt 内容 padding 与
  `.listRowInsets(EdgeInsets())`。后者清除了 List 的水平 row inset，是图表卡片
  左右边界相对原生 Today 卡片漂移的唯一集中 owner；修复应只改这里，不能给 Weekly
  与每张 Heatmap 各写一套 magic number。
- `HomeOverviewHeader`、`HomeWeeklyGrossTimeHeader` 和
  `HomeActivityHeatmapHeader` 各复制了一套“标题 + 可选统计 + Info”结构。源码没有
  单独的图表字号常量；真正风险是三套 composition、frame 和 identifier owner 漂移。
  最小实现是在 `Features/Home` 内抽取 Home 专属共享 header，保留现有 identifier
  归属和 accessory 语义，不扩大到全局 Settings/Analytics header。
- `HomeActivityHeatmapSection(.listSection)` 也被 Analytics 首页复用。共享卡片修改后
  必须运行 `testAnalyticsHomeShowsTrackedTaskHeatmaps`，确认没有引入页面外回归。
- Apple HIG 要求图表与页面其它元素对齐、用一致视觉层级让数据本身最突出；
  Swift Charts 已提供跨平台布局、本地化和可访问性。本任务继续复用 SwiftUI、
  Swift Charts 与现有 DesignSystem，不新增第三方依赖。
  参考：
  [Charts](https://developer.apple.com/design/human-interface-guidelines/charts)、
  [Layout](https://developer.apple.com/design/human-interface-guidelines/layout)、
  [Swift Charts](https://developer.apple.com/documentation/Charts)。

## 历史边界

- `0b0e2ae3` 把图表标题从共享 `SectionTitle` 拆成各自 header，形成三套 Home 标题。
- `bd7198f3` 首次用自绘卡片保证多张 Heatmap 独立。
- `3f5168b1` 曾回归纯原生 grouped row，但被 iOS 26+ 连续 Section 合并行为否决。
- `e6d402d6` 恢复独立卡片并加入当前 zero row inset；本次只能修几何，不能破坏
  任务 39 已冻结的独立卡片、26 pt 连续圆角、无描边和 grouped background。

## 计划验证

- 先扩充 `testTodayVisualizationCardsAreVisuallyIndependent`：新增可观察的 title leaf
  identifier；比较 Overview/Gross/Heatmap 标题高度和 Gross/Heatmap 卡片左右边界，
  先在当前布局得到失败证据。
- 复跑 Gross/Heatmap 领域行为套件，以及 Weekly、视觉独立、三 metric、Analytics
  共享 Heatmap 的 XCUITest。
- 普通字号截图：iPhone 竖屏；iPad 横屏；macOS 常规宽度与窄窗口。颜色/material
  不变，因此本任务不单独增加 dark-mode 批次。
