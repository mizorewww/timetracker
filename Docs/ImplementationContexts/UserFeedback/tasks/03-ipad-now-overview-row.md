# 03：iPad Now 与 Overview 自适应同行

## 反馈

> iPad 上，正在计时的卡片去拉长适应空间，相当诡异，建议将其和概览合并成一行。

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
- `timetracker/Features/Home/Sections/HomeActiveTimerViews.swift`
- `timetracker/Features/Home/Sections/HomeMetricsViews.swift`
- `timetrackerTests/Core/CoreArchitectureBehaviorTests.swift`
- `timetrackerTests/UIContracts/HomeUIContractTests.swift`
- `timetrackerUITests/timetrackerUITests.swift`

## 验收证据

- [ ] 审计同行阈值、列宽总和、最大/最小宽度、窄宽与大字号回退
- [ ] 审计 Now/Overview 只各组合一次、顶部对齐且没有强制等高拉伸
- [ ] 相关 layout policy 与 UI contract 测试通过
- [ ] 使用主代理明确拥有的 iPad Simulator，在普通字号常规路径完成 UI test 与截图验收
- [ ] `CONFIGURATION=Release scripts/build_install_all.sh` 全部当前可用设备安装通过
- [ ] 终止测试 App，关闭并删除本任务拥有的 Simulator，确认无遗留构建/测试/扩展/trace 进程
- [ ] 回写 `Docs/userfeedback.md`，将总账改为 `[x]` 并移除 `~active` 链接

## 依赖

- 使用 SwiftUI 原生 `HStack`、`VStack`、geometry observation 与项目现有布局策略，不新增第三方依赖。
- 此任务是有限的自适应组合问题；外部 layout library 不会提供额外价值。

## 技能约束

- Apple HIG：利用 iPad 空间展示相关内容，保持清晰层级、对齐和一致间距，并能适应窗口宽度变化。
- SwiftUI：由容器宽度和窄输入策略驱动组合；避免 `AnyView`、`GeometryReader` 滥用和强制等高；所有状态保持私有。
