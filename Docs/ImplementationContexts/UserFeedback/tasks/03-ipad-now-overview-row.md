# 03：iPad Now 与 Overview 自适应同行

> 本文件只保存实现与验证记忆，不是任务来源。每次继续前必须重新读取
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中唯一的 `[~]` 项。

## 当前候选实现

- `a0837a7` 引入 `DesktopTodayCurrentStateSections` 与 `HomeLayoutPolicy` 的 current-state 双栏宽度策略。
- 普通 iPad 宽度下，Now 与 Overview 应在同一条 top-aligned row；Now 不再独占整行拉伸。
- 本任务不根据已有提交或任务 02 的旁证截图直接勾选，仍需完成针对性的静态、行为、UI 与 Release 验收。

## 产品与 HIG 语义

- iPad 的额外空间用于并列关联内容，而不是把单张操作卡无边界拉长。
- Now 是主要操作区，Overview 是辅助信息区；两者同行时保持清楚的 leading/trailing 分区和一致顶部基线。
- 以实际可用内容宽度驱动布局，而不是假设所有 regular size class 都足够宽。
- Now 列保留可读的最小宽度并设置合理最大宽度；Overview 也保留最小宽度，二者之间使用统一内容间距。
- 宽度不足时自然回退为纵向排列；普通字号常规路径优先，保留已有低成本的大字号单列回退。
- 页面总体宽度继续受统一内容上限约束，避免在大 iPad 或 macOS 窗口中无限拉伸。

## 审查范围

- `timetracker/Features/Home/HomeViews.swift`
- `timetracker/SharedUI/Foundation/LayoutPolicies.swift`
- `timetracker/Features/Home/Sections/HomeTimelineViews.swift`
- `timetracker/Features/Home/Rows/HomeTimerRows.swift`
- `timetracker/Features/Home/Sections/HomeMetricsViews.swift`
- `timetrackerTests/Core/CoreArchitectureBehaviorTests.swift`
- `timetrackerTests/UIContracts/HomeUIContractTests.swift`
- `timetrackerUITests/timetrackerUITests.swift`

## 验收证据

- [x] 审计同行阈值、列宽总和、最大/最小宽度、窄宽与大字号回退
- [x] 审计 Now/Overview 只各组合一次、顶部对齐且没有强制等高拉伸
- [x] 相关 layout policy 与 UI contract 测试通过
- [x] 使用主代理明确拥有的 iPad Simulator，在普通字号常规路径完成 UI test 与截图验收
- [x] `CONFIGURATION=Release scripts/build_install_all.sh` 全部当前可用设备安装通过
- [x] 终止测试 App，关闭并删除本任务拥有的 Simulator，确认无遗留构建/测试/扩展/trace 进程
- [x] 只在 `Docs/userfeedback.md` 将状态改为 `[x]`，并移除 `~active` 链接

## 完成记录

- 2026-07-20 静态审计确认 `DesktopTodayCurrentStateSections` 以实际内容宽度选择
  `HStack(alignment: .top)` 或纵排回退；Now 列有界，Overview 保留最小宽度，
  两张卡片没有被强制等高。
- macOS 定向测试通过：
  `CoreArchitectureBehaviorTests/layoutPoliciesCentralizeResponsiveChoices()` 与
  `HomeUIContractTests/desktopTodayUsesSharedPriorityAndBoundedWideLayout()`，共
  `2 passed / 0 failed`。
- 主代理创建并独占 iOS 27.0 的 iPad Pro 11-inch (M4)
  `508C0F09-07E4-443E-8783-49086823B7F6`。首次 UI 测试暴露 Xcode 27 未向
  `XCUIApplication` 传递 launch arguments，导致 demo active timer 未生成；
  同次 UI hierarchy 已证明 Now 与 Overview 同为 `minY = 206` 且左右不重叠。
  将等价 demo mode 写入该临时 App domain 后，原测试
  `testIPadTodayPlacesNowAndOverviewInOneAdaptiveRow()` 重跑为
  `1 passed / 0 skipped`，Stop 与 Start Another Timer 均可见、可点击且保留文案。
- 最终截图：
  `/Users/aac6fef/.codex/visualizations/2026/07/20/019f7f11-0117-7af0-8655-754ef00481ea/task03-ipad-now-overview/ipad-today-now-overview-adaptive-row.png`
  （1668×2420）；Apple HIG 与 SwiftUI 目视验收通过。
- `CONFIGURATION=Release scripts/build_install_all.sh` 退出码为 0。付费开发签名
  Release `1.1.52 (107)` 已安装到 iPad Pro M4
  `748D0137-ADC3-58AF-855C-1E98B3125F93` 与 iPhone Air
  `FBA36694-D841-56D4-8ED6-21942873B21B`；设备内版本查询一致。
  `/Applications/timetracker.app` 已替换并通过严格签名校验；嵌入式 Watch
  companion 同版本且签名有效，当前没有可见物理 Apple Watch。
- 已终止本批 App/runner，删除 owned iPad Simulator，清除 UI 与 Release
  DerivedData、xcresult、失败附件和中间截图。没有遗留本批
  `xcodebuild`、`xctest`、runner、扩展、Instruments 或 Booted device；
  来源不明的 Shutdown iPhone Simulator 未被触碰。

## 依赖

- 使用 SwiftUI 原生 `HStack`、`VStack`、geometry observation 与项目现有布局策略，不新增第三方依赖。
- 此任务是有限的自适应组合问题；外部 layout library 不会提供额外价值。

## 技能约束

- Apple HIG：利用 iPad 空间展示相关内容，保持清晰层级、对齐和一致间距，并能适应窗口宽度变化。
- SwiftUI：由容器宽度和窄输入策略驱动组合；避免 `AnyView`、`GeometryReader` 滥用和强制等高；所有状态保持私有。
