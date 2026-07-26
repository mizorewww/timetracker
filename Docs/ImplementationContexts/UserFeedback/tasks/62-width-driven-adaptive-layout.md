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

- [~] A：认领反馈、建立本实现记忆、完成全量平台相关代码普查。
- [ ] B：确立唯一的宽度判据（统一的 layout-width 环境值 + 断点），替换所有 idiom
  判断。
- [ ] C：合并按平台拆分的视图与条件化修饰符。
- [ ] D：文字标签可见性等产品决策项按宽度重述（保留原意图，换判据）。
- [ ] E：多宽度截图验收（iPhone / iPad 全屏 / iPad 分屏 / Mac 窄窗）、
  `make test` 门禁、Release 全设备安装、反馈收口。

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

## 进度记录

- 2026-07-26 Checkpoint A：认领第 107 条，建立本文件与 active 链接。
