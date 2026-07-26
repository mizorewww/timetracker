# 62：以宽度驱动的自适应布局（去平台专属 UI）实现记忆

状态：2026-07-26 进行中

> 本文件是主代理与子代理的实现、验证和编排记忆；唯一任务来源仍是
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 条目。

## 认领的反馈条目

- 反馈第 107 条：尽量少搞 platform specific 的 UI；是否渲染 iPhone 界面由**宽度**
  决定；建议全量审查一次代码，平台相关的代码能删就删。

## 设计依据（apple-hig / swiftui-expert 技能）

`.agents/skills/apple-hig/distilled/layout.md`：

- iPadOS：「Support the full range of window sizes (people resize freely, similar
  to macOS)」「Defer switching to compact view as long as possible — design
  full-screen first」「Test at common sizes: half, third, and quadrant of screen」。
- 通用：「Use SwiftUI or Auto Layout for automatic trait adaptation」。

结论：按 idiom（`UIDevice.current.userInterfaceIdiom == .pad`）分支在 HIG 下就是
错的——iPad 在 Split View / Slide Over 下宽度是 compact，Mac 窗口可以被拖到很窄，
两者都应该走「iPhone 版式」。**判据必须是当前可用宽度，不是设备型号。**

## 分类原则

审查结果分成三类，只有前两类要改：

- **A/B/D/E/F 类（要改）**：idiom/设备判断、控制版式的编译期平台分支、按平台拆分的
  视图类型、按平台条件化的布局修饰符、按平台决定的文字标签可见性 —— 一律改为由
  宽度/size class 驱动。
- **C 类（必须保留）**：真正 API 绑定的分支（UIKit vs AppKit 类型、`NSApplication`
  / `UIApplication`、haptics、`ActivityKit`、`WatchConnectivity`、
  `.navigationBarTitleDisplayMode`、跨平台不编译的 `listStyle` 等）。这类不是
  "platform specific UI"，删掉会编译失败。
- Watch / Widget / Live Activity target 的平台绑定代码不在本次范围内。

## Checkpoint 编排

- [x] A：认领反馈、建立本实现记忆、完成全量平台相关代码普查。
- [x] B：根 shell 判据改为宽度驱动；合并 iPad/Mac 两份 split view；
  `CompactHome*` 去平台化。（commit `46c5d45d`）
- [x] C：剩余的 idiom / 平台条件化布局项改为宽度驱动。
  （commits `4946bc65`、`fd34377a`）
- [~] D：多宽度 UI 截图验收（iPhone / iPad）。
- [ ] E：`make test` 门禁、Release 全设备安装、反馈收口。

## 约束与边界

- 不改 SwiftData `@Model` ⇒ 不需要新增 `VersionedSchema`。
- 保留既有的产品意图（例如「iPhone 上开始/暂停只显示图标，iPad 上显示文字」），
  只把判据从平台换成宽度。
- 已知既有失败（与本任务无关，不伪造绿色）：
  `TaskPersistencePolicyTests.archiveCommandPreservesTheOriginalArchiveTimestamp`、
  `PreferenceSyncBehaviorTests.checklistCompletionMovesOnlyTheTargetToTheDestinationGroupEnd`、
  `CoreLLMResponseTransportTests.nonSuccessStatusTakesPriorityOverDeclaredBodySize`。

## 使用的库

- 待定，见各 checkpoint 记录。

## 全量普查结果（子代理 Explore，`timetracker/` 主 target）

总计 184 处 `#if os(...)`/`canImport(...)`，分布在 91 个文件；3 处直接读
`UIDevice.current.userInterfaceIdiom`；5 处 `@Environment(\.horizontalSizeClass)`；
0 处 `UIScreen`；0 处 `verticalSizeClass`；0 处 `macCatalyst`。

| 类别 | 数量 | 处理 |
| --- | --- | --- |
| A идiom/设备/size-class | 34 | 改为宽度驱动 |
| B 控制布局的编译期平台分支 | 31 | 逐条判断，多数改宽度 |
| C 真正 API 绑定 | ~112 | **保留**（改了会编译失败） |
| D 按平台拆分的视图 | 5 对 | 能合的合 |
| E 平台条件化修饰符 | 28 | 与 B/C 重叠 |
| F 文字标签可见性 | 11 | 保留产品意图，换判据 |

关键发现：仓库**早就有**正确的宽度驱动范式——`HomeViews.swift` 用
`.onGeometryChange` + `HomeLayoutPolicy(width:)` 完全不看 idiom，`LayoutPolicies.swift`
是这些策略的既有归属地。本任务是把根 shell 和其余散落判断收敛到同一范式，
而不是发明新机制。

**明确不改的项（有理由的平台差异）**：

- B.1 触控目标常量（iOS 44pt / macOS 24–28pt，12 处）：这编码的是**输入方式**
  （手指 vs 指针），不是宽度。HIG 要求触控目标 44pt；Mac 用指针时 28pt 是对的。
  改成按宽度会让接了鼠标的窄窗口出现 44pt 巨型控件，属于劣化。
- C 类全部：`.navigationBarTitleDisplayMode`、`.insetGrouped`、`EditMode`、
  `.presentationDetents`、UIKit/AppKit 类型桥接、ActivityKit/HealthKit/
  WatchConnectivity 可用性。
- F.8 Quick Start 编辑按钮：桌面是图标按钮、手机是整行 `Label`，与通用规则相反，
  是刻意的 list-row 习惯，机械按宽度翻转会造成回归。
- `SidebarViews.swift` mac 过滤掉 `.settings`：绑定 macOS Settings scene。

## 进度记录

- 2026-07-26 Checkpoint A：认领第 107 条，建立本文件与 active 链接，完成全量普查。

- 2026-07-26 Checkpoint B（commit `46c5d45d`）：
  - `RootLayoutPolicy` 改为 `(measuredWidth: CGFloat?, horizontalSizeClass:)`。
    判据：compact size class 一律 compact（保住 iPhone 横屏走标签页 shell）；
    否则按 720pt 断点比宽度；首帧未测量前退回 size class，避免闪一帧错误 shell。
    macOS 任何宽度都报 `.regular`，所以那里宽度是唯一信号——这正是窄 Mac 窗口
    能落到 compact shell 的原因。
  - 新增 `AppRootView`（`.onGeometryChange` 测宽 + 选 shell），替换
    `ContentView` 里的 `#if os(macOS)`；sync-conflict 横幅由选中的 shell 安装，
    不再装两遍。
  - `iPadRootView` 与 `DesktopRootView` ~80% 重复，合并为 `RegularShellRootView`；
    剩下的 `#if os(macOS)` 是 Settings scene 与 `focusedSceneValue`，不是布局。
  - `SplitColumnLayoutPolicy.iPad`/`.mac` 合并为 `.standard`，并加测试断言
    其 min 之和 ≤ shell 断点（否则会出现 split view 满足不了、compact shell
    又还没接管的宽度带）。
  - `PhoneHomeView/Sections/Rows` 去掉 `#if os(iOS)` 并更名 `CompactHome*`；
    只保留 `.insetGrouped`、键盘关闭、`navigationBarTitleDisplayMode` 与
    HealthKit 行的门；设置按钮改用 `.primaryAction`（两端都正确解析），
    又消掉一处平台分支。
  - 删除无生产调用点的 `AnalyticsLayoutPolicy` 与
    `PomodoroLayoutPolicy.showsInlineHeader`。
  - accessibility identifier 全部保持原样（`phone.tabView` / `ipad.splitNavigation`），
    它们是既有 XCUITest 契约；重命名推迟到用户的 UI test 改动落地之后。

- 2026-07-26 Checkpoint C（commits `4946bc65`、`fd34377a`）：
  - 新增环境值 `\.layoutShell`，由 `AppRootView` 发布一次；嵌套视图从"我在多大的
    空间里"取值，而不是"我在什么设备上"。默认 `.regular`，让脱离 shell 渲染的
    预览/独立 sheet 拿到宽松版式。
  - 三处直接 `UIDevice.current.userInterfaceIdiom` 全部消除：
    `appNativeCard`（iPhone 分组卡 vs 桌面描边卡）、任务详情开始/暂停按钮标签
    （`.iconOnly` vs `.titleAndIcon`）、根 shell（Checkpoint B 已做）。
    产品意图不变，判据从设备换成 shell。
  - `SizeClassLayoutPolicy` 增加 `shell` 参数。macOS 任何 size class 都报
    `.regular`，单靠 size class 会告诉窄 Mac 窗口"你很宽"。
  - `TimelineChart.usesVerticalLayout` 原本是 `#if os(iOS)` + size class，
    所以 macOS 永远画横向轴；现在窄 Mac 窗口和 iPad 分屏与 iPhone 一样走竖向轴。
  - Inbox 的 `isCompact` 原本在非 iOS 硬编码 false，窄 Mac 窗口会试图塞下完整的
    接受/忽略文字标签；现在同样按 shell 判定。
  - `PomodoroSetupViews` 因此可以整块删掉 `effectiveHorizontalSizeClass` 垫片。

## 验证记录

- macOS 与 iOS 两个平台 `xcodebuild build` 均通过。
- 在隔离的 git worktree（`build/verify-wt`，检出 `46c5d45d`）中跑
  `timetrackerTests`：1,418 条测试，3 条失败，全部为既有失败，且都不在本次
  改动半径内。用 worktree 是因为用户当时有一份未提交的
  `LLMSettingsTests.swift` 引用了尚不存在的 `LLMPromptKind.effectiveRequestDisclosure`，
  会让整个测试 bundle 编译失败；worktree 既不碰用户的工作副本，也不影响验证。
