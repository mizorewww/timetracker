# 16：macOS 设置侧边栏固定展开实现记忆

Status: Complete

> 本文件仅作为主代理与子代理的实现、验证和编排记忆，不是任务来源。唯一范围与状态必须重新读取
> [`Docs/userfeedback.md`](../../../../userfeedback.md) 中对应的 `[~]` 条目。

## 当前阶段

- [x] 读取唯一反馈、Apple HIG 与 SwiftUI 强制技能并建立 active link。
- [x] 审计 macOS Settings 的 scene、导航容器、column visibility 与 toolbar/sidebar toggle 来源。
- [x] 确认并保留仓库既有原生 SwiftUI 产品修复，无需制造重复产品 diff。
- [x] 完成定向测试、owned macOS 普通路径窗口截图验收与资源清理。
- [x] 执行 `CONFIGURATION=Release scripts/build_install_all.sh` 并由 Codex 标记完成。

## 唯一反馈边界

- 仅在 macOS 设置界面让侧边栏固定保持展开。
- 删除该设置界面的侧边栏展开/收起状态切换按钮。
- 不领取或实现本条之后的睡眠合并等反馈。

## 强制设计与实现约束

- Apple HIG：macOS Settings 导航应稳定、可预测；当前仓库使用侧边栏的前提下，本任务按用户明确要求
  固定展开，不提供一个不会再有有效状态变化的伪切换按钮。
- SwiftUI：优先使用 `NavigationSplitView` / scene 原生 column-visibility 与 toolbar API，避免 AppKit
  window 遍历、视图坐标 hack 或重复导航容器；不顺手迁移无关软弃用 API。
- 保留 Command-Comma、最后选择的设置 pane、键盘导航、窗口尺寸与非 macOS 平台行为。
- UI 操作与截图仅使用 owned macOS App/测试会话或 owned 模拟器；物理 iPhone/iPad 只用于最终 Release
  安装，不启动、不操作、不截图。
- 每个小 checkpoint 完成验证并提交；只暂存本任务状态差异，保护 `Docs/userfeedback.md` 中用户新增内容。

## 初始审计问题

- 当前设置入口是否为 SwiftUI `Settings` scene，侧边栏是否由 `NavigationSplitView`、`List` selection 或
  自定义 split view 提供。
- 展开状态切换按钮来自系统自动 toolbar item、显式 `toggleSidebar:`、自定义 Button，还是 window toolbar。
- macOS 窗口变窄/重开 Settings 时，如何在不产生状态反复写入的前提下维持 sidebar 可见。
- iOS/iPadOS 是否复用同一 Settings view；修复必须用条件编译或平台封装避免改变移动端导航。

## 依赖与互联网库审计

- Apple 官方 `NavigationSplitViewVisibility` 文档确认 `.all` 显示全部列：
  https://developer.apple.com/documentation/swiftui/navigationsplitviewvisibility
- Apple 官方 `ToolbarDefaultItemKind` 文档明确 `sidebarToggle` 是 `NavigationSplitView` 自动添加、可传给
  `toolbar(removing:)` 删除的默认项：
  https://developer.apple.com/documentation/swiftui/toolbardefaultitemkind
- Apple 官方 `Settings` 文档确认 SwiftUI Settings scene 管理标准 macOS Settings 菜单、快捷键与窗口生命周期：
  https://developer.apple.com/documentation/swiftui/settings
- 审计成熟候选 SwiftUI Introspect（Swift Package Index：6,523 stars、持续维护、无包依赖）。本任务已经
  有完整原生 API；引入它会把稳定声明式行为变成 AppKit 视图层级 introspection，扩大 OS 版本耦合，故拒绝。
- 本任务使用的库：Apple SwiftUI、XCTest、Swift Testing；项目依赖图不变。

## 产品与平台审计

- 产品修复已由既有 checkpoint `7fc736a`（`fix: keep mac settings sidebar visible`）实现并完整保留：
  `NavigationSplitView(columnVisibility: fixedSettingsColumnVisibility)` 始终读取 `.all`，忽略系统隐藏写回；
  `.toolbar(removing: .sidebarToggle)` 精确删除系统自动切换按钮。
- 修复严格位于 `#if os(macOS)` 的 Settings 分支。iOS Settings 继续使用列表导航；iPad 主导航保持自适应；
  macOS 主窗口仍使用可变 sidebar visibility 与 `SidebarCommands()`，只有 Settings 被用户要求固定。
- Settings scene 仍由 SwiftUI `Settings` 托管，Command-Comma 与标准菜单入口不变。Settings 窗口最小宽度
  640 pt，分类栏宽度为 180...240 pt，固定双列不会把 detail 压到不可用尺寸。
- 自定义 `SidebarRevealButton` 没有被 Settings 引用；本问题来源是 `NavigationSplitView` 默认 toolbar item，
  不需要删除或改变共享组件。

## 验证与资源所有权

- 精确执行 Swift Testing 源码契约
  `PlatformShellContractTests/macSettingsKeepsItsCategorySidebarVisibleWithoutAToggle()`：1 test / 1 suite
  passed，结果包 `build/Task16MacSettingsValidation/Contract.xcresult`；付费 Apple Development 签名保持开启。
- UI 普通路径从 macOS App 菜单打开 Settings，在目标 Settings 窗口内验证
  `settings.category.general` 同时存在且可交互，并断言 `Show Sidebar` / `Hide Sidebar` 按钮均不存在。
- 首轮 UI 运行 1/1 通过，但 `app.screenshot()` 包含无关桌面；未将其作为最终视觉证据。回归改用
  `XCTUnwrap` 锁定 Settings window 并调用 `settingsWindow.screenshot()`，避免捕获其他 App 或桌面内容。
- 增加可交互断言后的首轮编译暴露了错误的 query 链式写法，测试没有启动；已改用 XCTest 明确的
  `matching(identifier:)` 查询并以全新 result bundle 重跑，不把该失败运行计作验收。
- 最终 `build/Task16MacSettingsValidation/MacUI4.xcresult`：1 passed、0 failed、0 skipped；窗口级附件位于
  `build/Task16MacSettingsValidation/ExportedAttachments4/C1D3AC32-2DCA-4D56-B367-AFB56F8F4E87.png`，人工核验
  分类栏完整固定展开、General 可交互，标题栏没有侧边栏切换按钮。
- 测试 teardown 已终止目标 App；复核无 owned `xcodebuild`、`xctest`、UI runner、App/extension 或
  Instruments 进程，且没有 Booted 模拟器。既有 `AnalyticsReview-iPhone17Pro` 保持 Shutdown 且未触碰。
- 根目录 `README.md` 仍不存在；用户在 `Docs/userfeedback.md` 的未暂存新增内容未进入本 checkpoint。

## Release 全设备安装

- 精确执行 `CONFIGURATION=Release scripts/build_install_all.sh`，iOS/iPadOS（含 embedded Watch）与 macOS
  Release 构建均成功，保留付费 Apple Development team `LT98S43NKA` 的签名与 provisioning 更新能力。
- 脚本将移动端包安装到两台连接设备，将 macOS 包复制到 `/Applications/timetracker.app`；没有设置
  `LAUNCH_AFTER_INSTALL=1`，因此没有在物理 iPhone/iPad 上启动、操作或截图。
- 只读 `devicectl` 核验：iPad Pro M4（`748D0137-ADC3-58AF-855C-1E98B3125F93`）与 iPhone Air
  （`FBA36694-D841-56D4-8ED6-21942873B21B`）均安装 `me.mezorewww.timetracker` `1.1.52 (107)`。
- embedded Watch 包 `me.mezorewww.timetracker.watchkitapp` 为 `1.1.52 (107)`；iOS 主包、Watch 包及
  `/Applications/timetracker.app` 均通过 `codesign --verify --deep --strict`。
- 安装后确认无 owned `xcodebuild`、`xctest`、UI runner、timetracker App 或 extension 进程，无 Booted
  模拟器；既有 `AnalyticsReview-iPhone17Pro` 保持 Shutdown 且未触碰。
