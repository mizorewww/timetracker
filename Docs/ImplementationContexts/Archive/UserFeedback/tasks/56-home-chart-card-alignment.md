# 56：主页图表卡片对齐与设计规范实现记忆

Status: Complete

> 本文件是主代理与子代理的实现、验证和编排记忆。任务内容与状态的唯一来源仍是
> [`Docs/userfeedback.md`](../../../../userfeedback.md) 中对应的 `[~]` 条目。

## 当前阶段

- [x] 按文档顺序领取标题字体、卡片左右间距和主页设计规范反馈。
- [x] 审计主页现有标题、卡片容器、heatmap 与 Gross Time 图表实现和历史边界。
- [x] 先写可验证的 UI 验收清单，再做最小实现。
- [x] 为相对标题/卡片几何补充 UI 验收，并统一实现 owner。
- [x] 完成针对性回归与实现后截图核对。
- [x] 完成格式、单元测试和 iPhone/iPad/macOS 普通字号截图验收。
- [x] 提交小 checkpoint，执行 Release 全设备安装，标记反馈完成并移除活动链接。

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
- [x] Checkpoint B：测试先行、统一容器与标题、更新主页设计规范。
- [x] Checkpoint C：跨平台截图、完整门禁、Release 全设备安装和反馈收口。

## 子代理编排

- [x] `history_audit`：只读定位主页各卡片容器、标题来源和导致差异的提交。
- [x] `test_audit`：只读检查现有 UI contract、截图入口和可复用共享组件。

## 资源所有权

- iPhone 红灯/首轮实现批次：`codex-task56-red-iPhone17Pro`，
  UDID `1F22694D-8D21-43C6-8F8A-37C3FDFB3662`；已终止 App，关机并删除。
- iPad 普通字号批次：`codex-task56-iPadPro13`，
  UDID `46C294A9-6AA9-43E4-872E-C6128FC56813`；已终止 App，关机并删除。
- macOS 批次使用当前 Mac destination；测试已终止 App，没有仍在运行的 owned
  XCTest/xcodebuild。
- 三个平台的临时 DerivedData、xcresult 和导出截图目录均已删除；进程与设备审计
  没有发现 owned xcodebuild、XCTest Runner 或同名模拟器残留。

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
- 当前共享 modifier 同时设置 16 pt 内容 padding、内层自绘 background 与
  `.listRowInsets(EdgeInsets())`。XCU 行几何显示原生 row 边界均为 16 pt，但实现前
  普通字号截图显示自绘 background 实际从 32 pt 开始；差异来自 background 跟随
  已 inset 的内容 view，而不是系统 row 本身。直接交给 `listRowBackground` 会被
  外层透明规则覆盖；去掉透明规则又会让 iOS 27 把所有 Section 合成一张白卡。最终
  保留透明 row 和独立自绘背景，只保留 vertical `cardPadding`，并让背景从系统
  content column 向两侧各扩展一个 `cardPadding`：背景回到 16 pt，内容回到 32 pt。
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

- 已扩充 `testTodayVisualizationCardsAreVisuallyIndependent`，比较 Overview、
  Gross 与每张 Heatmap 所属原生 cell 的左右边界和对称性；标题因 SwiftUI header
  的 combine 语义不能稳定暴露 leaf frame，改由单一 `HomeSectionHeader` owner 和
  普通字号截图验收。
- 实现前截图
  `iphone-home-visualization-card-separation` 明确显示 Heatmap background 为 32 pt
  外边距，而 inset-grouped row 合同为 16 pt；这份视觉证据是本次 UI-only 变更的
  红灯基线。
- 中间截图先暴露 row background 被透明 Section 覆盖、再暴露去掉透明规则会合并
  所有卡片；两种方案均已否决。最终 `FinalLayout.xcresult` 截图显示卡片各自独立，
  左右背景边界约 16 pt，标题/内容列约 32 pt，Weekly 与 Heatmap 使用同一层级。
- 复跑 Gross/Heatmap 领域行为套件，以及 Weekly、视觉独立、三 metric、Analytics
  共享 Heatmap 的 XCUITest。
- 普通字号截图：iPhone 竖屏；iPad 横屏；macOS 常规宽度与窄窗口。颜色/material
  不变，因此本任务不单独增加 dark-mode 批次。

## 已完成验证

- `make format-check localization-check`：通过；817 个 Swift 文件无需格式调整，
  9/9 本地化资源键一致。
- iPhone `testTodayVisualizationCardsAreVisuallyIndependent`：
  `FinalLayout.xcresult` 与最新可访问性 owner 修改后的
  `FinalCompatibility.xcresult` 均通过；截图确认背景 16 pt、内容/标题列 32 pt、
  卡片独立。
- 同一测试此前有一次 fixture 未装载 Heatmap 选择而失败；保留失败结果后独立重跑
  通过。该间歇现象在实现前基线也出现，失败点在 Heatmap header 不存在，不是布局断言。
- iPad `testTodayVisualizationCardsAreVisuallyIndependent`：
  `iPadVisualizationRetry.xcresult` 与最新修改后的 `iPadCompatibilityRetry.xcresult`
  通过；普通字号竖屏、横屏截图均确认图表卡片独立且标题/内容列一致。首个 iPad
  几何版测试错误地假定宽屏也暴露 iPhone 原生 List cell，已把这组 cell 几何断言
  收窄到 compact-width；最终一次运行同样遇到 Heatmap 夹具未载入，独立重跑通过。
- macOS `testTodayWeeklyGrossTimeChartIsVisible`：
  `macWeeklyRetry.xcresult` 通过；普通字号常规窗口截图确认 Overview、Weekly 标题、
  摘要、Info 和卡片边界一致。首次运行发现共享 header identifier 落在合并后的
  leaf 会改变旧 XCU descendant 查询，已把 identifier owner 移到保留 children
  的外层容器；macOS、iPhone 和 iPad 最新回归均验证兼容。
- iPhone 共享页面/行为回归：
  `testAnalyticsHomeShowsTrackedTaskHeatmaps` 与
  `testTodayConfiguredHeatmapsStayIndependentByTaskAndMetric` 同批通过，确认 Analytics
  复用 Heatmap、三种指标、三张独立卡片、Info 内容和旧 identifier 语义均未回归。
- `CONFIGURATION=Release make build-install-all`：通过。iOS App 与依赖型 Watch
  companion、macOS App 均签名构建成功；版本 `1.1.170 (225)` 已安装并由
  `devicectl` 复核在物理 iPad Pro M4 与 iPhone Air 上，macOS 同版本已复制到
  `/Applications/timetracker.app` 并通过签名校验。Watch companion 已嵌入 iOS App，
  由配对 iPhone 的 Automatic App Install 管理。
- `make test`：1433 个测试中 1431 通过；本任务相关的
  `TodayActivityHeatmapRefreshTests`、`TodayActivityHeatmapTests` 与
  `TodayHeatmapRecurrenceProjectionTests` 全部通过。默认门禁仍有两个开始本任务前已知、
  与本改动无关的失败：
  `PreferenceSyncBehaviorTests.checklistCompletionMovesOnlyTheTargetToTheDestinationGroupEnd`
  和
  `TaskPersistencePolicyTests.archiveCommandPreservesTheOriginalArchiveTimestamp`。

## 采用的库与框架

- 没有新增第三方依赖。
- 实现继续复用 Apple SwiftUI、Swift Charts 和项目现有 DesignSystem/AppLayout。
  这是布局 owner 与系统 List/card 语义修正，引入额外图表或布局库会增加跨平台
  行为漂移，不能提升本任务质量。
