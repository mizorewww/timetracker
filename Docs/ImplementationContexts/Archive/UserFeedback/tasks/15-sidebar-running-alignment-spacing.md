# 15：侧边栏计时状态对齐与任务间距实现记忆

Status: Complete

> 本文件只保存实现、验证与子代理编排记忆，不是任务来源。范围与状态必须重新读取
> [`Docs/userfeedback.md`](../../../../userfeedback.md) 中对应的唯一 `[~]` 项。

## 当前阶段

- [x] 领取反馈、读取 Apple HIG / SwiftUI 强制技能并建立活动链接。
- [x] 审计侧边栏任务行的视图层级、对齐轴、默认行 inset 与自定义 spacing。
- [x] 确认并定向验证仓库既有最小修复与稳定布局契约，无需重复修改产品代码。
- [x] 使用 owned iPad 模拟器完成普通路径、真实行几何断言与截图验收。
- [x] 执行 `CONFIGURATION=Release scripts/build_install_all.sh`，清理资源并由 Codex 标记完成。

## 唯一反馈边界

- 侧边栏中“正在计时”状态图标与任务图标应处于同一水平中心线。
- 相邻任务行的垂直节奏应一致，消除当前异常的额外间距。
- 不领取或实现本条之后的任何反馈。

## 强制设计与实现约束

- Apple HIG：侧边栏使用熟悉的 SF Symbols 与系统选择/列表行为；状态图标颜色只在表达运行状态时使用；
  保持适合 iPadOS/macOS 的紧凑但可读信息密度，并适应可调整窗口宽度。
- SwiftUI：一个任务对应一个稳定 identity 的单根 row；优先在同一 `HStack` 中用 `.center` 对齐，避免
  用独立 overlay/offset 修补；明确区分 `List` 的 row inset/spacing 与 row 内 padding，防止垂直间距叠加。
- 先复用仓库现有侧边栏、任务图标和计时状态组件，不创建第二套计时状态或自定义列表系统。
- 原生 SwiftUI `List`、布局容器与 SF Symbols 足以覆盖时不新增依赖；第三方库必须有清晰边界并通过成熟度审计。
- 所有 UI 操作和截图只使用 owned 模拟器；物理设备仅用于最终 Release 安装，不启动、不操作、不截图。
- 每个小 checkpoint 验证并提交；只暂存本任务差异，保护 `Docs/userfeedback.md` 末尾 8 条用户新增反馈。

## 初始验收问题

- 正在计时图标是否由 overlay、独立 frame、baseline alignment 或条件分支导致垂直偏移。
- 异常间距来自 `List` section/row 默认值、`listRowInsets`、row 内 padding，还是条件状态视图改变行高。
- iPadOS 与 macOS 是否共用 row；普通任务与正在计时任务的测量高度是否一致。
- 修复后选择态、点击目标、截断、计时刷新与列表 identity 是否保持稳定。

## Checkpoint 记录

- [x] 初始 checkpoint `2861b21`：领取反馈、完成强制参考读取、建立实现记忆与 active link。
- [x] 现状与定向回归审计：
  - 反馈的产品修复已由既有 checkpoint `d9a2117`（`fix: align sidebar task status`）实现，当前 HEAD
    仍完整保留，因而不制造第二套实现或无意义产品 diff。
  - `SidebarTaskTreeRow` 复用 `TaskSummaryRow(layout: .inline)`；任务图标、文字和尾部状态都在同一个
    `HStack(alignment: .center, spacing: 12)` 中，计时状态不再进入第二条 metadata line。
  - running 与 idle 行共享外层行高策略：iPadOS 由 disclosure slot 和外层 row 保持 44 pt 最小触控高度，
    macOS 继续采用系统紧凑行高；条件出现的 running indicator 不改变行高或相邻任务的垂直节奏。
  - 状态复用 `TaskRunningIndicator` 与 SF Symbol `timer.circle.fill`，没有侧边栏专用重复状态组件；绿色只
    表达正在运行这一有意义状态，任务图标继续使用任务自身配色。
  - 既有源码契约锁定 `.inline`、中心对齐、单行文本、无状态驱动行高和不创建侧边栏专用 timer image；
    既有 UI E2E 直接比较 running/idle sibling 的 `minX` 与 `height`（容差 1 pt）并保存截图。
  - 首次把不存在的另外两条测试名连同正确 suite 过滤器执行时，Xcode 明确报告 0 tests；该次不计验证。
    随后使用包含 `()` 的完整 Swift Testing 标识精确执行
    `sidebarUsesTheSharedInlineTaskSummaryWithoutStatusDrivenRowHeight()`：1 test passed、0 failure。
  - 定向测试保持 Apple Development `ZEXUAN GAO (PX46M259V3)` 与付费团队 provisioning，未关闭签名。

## 依赖与互联网库审计

- Apple 官方 SwiftUI 文档确认 `HStack` 的 alignment 控制子视图的垂直对齐且默认值为 center；
  `listRowSpacing(_:)` 专门控制相邻 List rows 的垂直间距。当前共享单根 row 已直接满足，无需自定义布局引擎。
- 审阅成熟候选 `SwiftUIX`（约 8.1k stars）、`SwiftUI Introspect`（约 6.5k stars）和仅测试使用的
  `ViewInspector`（约 2.6k stars）。前两者会把标准 SwiftUI 行布局变成额外框架/底层 UIKit-AppKit
  耦合，后者不能替代真实 List 几何验收；都没有带来值得新增依赖的任务边界。
- 本 checkpoint 使用的库：仅 Apple SwiftUI 与既有测试基础设施；项目依赖图不变。

## 模拟器验收与资源所有权

- Task 15 独占 fresh iPad Pro 13-inch (M5, 16GB) / iOS 27.0：
  `D17733BD-1FD3-4F5A-9C0D-55DA062B5855`。iPhone 紧凑布局不显示持久侧边栏，不做无关截图。
- 源码契约补强：锁定 inline metadata 至少与 24 pt 图标同高，防止计时状态重新引入第二行或改变行高。
- UI E2E 补强：使用平台模型识别 iPad（不依赖 iOS 27 未公开到 AX 树的 split-view identifier），并断言
  相邻 running / idle 叶子行之间没有额外 gap（`0 ± 2 pt`）；原有同 `minX`、同 row height 断言继续保留。
- 诊断历史：首轮因 `ipad.splitNavigation` 未暴露而 skip；第二轮证明实际侧边栏可达，但用 disclosure
  parent 的内容 AX frame 比较整行 gap 得到无效失败；移除该不成立的比较后，一轮因启动时侧边栏折叠而
  skip。最终改用真实平台模型判定，测试会通过系统 sidebar toggle 展开普通路径，不掩盖布局失败。
- 最终结果包 `build/Task15SimulatorValidation/iPad4.xcresult`：1 test passed、0 failed、0 skipped；
  截图附件 `ipad-sidebar-running-task-spacing` 同时包含 running 与 idle 相邻叶子任务。人工核验绿色计时
  状态与任务图标处于同一中心线，叶子行垂直节奏一致。
- 批次结束后终止了遗留的 owned `iPad2` xcodebuild/diagnostics，owned App 已由测试 teardown 终止；
  随后 shutdown + delete `D17733BD-1FD3-4F5A-9C0D-55DA062B5855`。复核无 Booted device，且无 owned
  `xcodebuild`、`xctest`、UI runner、App extension、Instruments/trace、Simulator 或 Problem Reporter
  进程残留；未触碰既有且保持 Shutdown 的 `AnalyticsReview-iPhone17Pro`。

## Release 全设备安装

- 精确执行 `CONFIGURATION=Release scripts/build_install_all.sh`，exit 0；没有设置
  `LAUNCH_AFTER_INSTALL=1`，因此未启动或操作物理设备 App。
- iOS/iPadOS Release 与 embedded Watch companion、macOS Release 均 build succeeded；iOS、Watch、
  `/Applications/timetracker.app` 均通过 `codesign --verify --deep --strict`。签名为 Apple Development
  `ZEXUAN GAO (PX46M259V3)`，Team ID `LT98S43NKA`，未禁用签名或付费 provisioning。
- Watch bundle `me.mezorewww.timetracker.watchkitapp` 已嵌入 iOS App，
  `WKCompanionAppBundleIdentifier = me.mezorewww.timetracker`，签名与依赖关系验证通过。
- 只读 `devicectl device info apps` 验证 iPad Pro M4 与 iPhone Air 都已安装
  `me.mezorewww.timetracker` 版本 `1.1.52 (107)`；没有对任一物理设备进行启动、UI 操作或截图。
- 安装后复核无 owned `xcodebuild`、`xctest`、UI runner、App/extension 或 Instruments 进程，且没有
  Booted 模拟器；根目录 `README.md` 仍不存在，用户未暂存的 8 条新增反馈保持不进入本任务提交。
