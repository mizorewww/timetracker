# 84：macOS Blossom Color Picker 位置实现记忆

Status: Complete

状态：2026-07-28 已完成

> 本文件是主代理与子代理的实现、验证和编排记忆；唯一任务来源仍是
> [`Docs/userfeedback.md`](../../../../userfeedback.md) 中对应的 `[~]` 条目。

## 认领的反馈条目

- macOS 上 Blossom Color Picker 应从用户触发它的颜色控件附近出现。
- 不应漂移到窗口角落、无关视图或屏幕上的意外位置。

## 初始范围

- 审计所有 BlossomColorPicker 调用点、macOS 展示容器、popover 锚点与窗口坐标行为。
- 对照项目当前锁定版本的官方源码与公开 API，优先修正调用契约。
- 保持 iPhone/iPad 现有颜色选择交互不变，不改变颜色持久化语义。

## UI 验收清单

- [x] macOS 普通窗口尺寸下，picker 以触发它的颜色控件中心展开。
- [x] picker 归属实际 source window，随 owner window 移动；screen edge 才允许夹紧。
- [x] 默认空间保持 Blossom 既定的“从 well 中心绽放”交互，不用 magic offset 避让触发控件。
- [x] iPhone/iPad 原有颜色选择路径无回退。
- [x] macOS 正常字号自动化断言与截图覆盖错误位置的回归。

## 测试优先清单

- [x] 先复现并补 macOS UI 自动化红测。
- [x] 实现后跑受影响定向测试、完整 `make test`、格式与本地化门禁。
- [x] macOS 截图验收。
- [x] 清理自有资源。
- [x] `make build-install-all` 安装最终任务版本。

## Checkpoint 编排

- [x] A：完成调用点、上游实现、HIG 与测试边界审计。
- [x] B：新增先失败的位置回归测试。
- [x] C：实现正确锚定并验证跨平台无回退。
- [x] D：完成定向、全量、截图、Release 全设备安装与关闭。

## 库策略

- 继续使用项目已有的 BlossomColorPicker 固定 revision `9a1ee3d`，先核对其官方源码、
  维护状态和 macOS 展示契约。
- 若上游不提供可靠锚定能力，优先在应用侧做最薄的适配，不复制完整 picker，也不新增
  功能重叠依赖。
- 官方仓库当前仍是固定 revision，公开 main 无更新修复；该库约 74 stars，但它是用户明确
  指定且已由 AD-117 审查的例外。本任务没有新增依赖。

## 子代理编排

- 主代理负责范围、活动记忆、模拟器/设备所有权、集成、提交和收口。
- 子代理可并行进行只读 HIG/SwiftUI、上游源码和 UI 测试审计；不得并发运行构建或修改
  主代理正在编辑的文件。

## 进度记录

- 2026-07-28：按反馈顺序认领任务，建立 `~84` 活动实现记忆并进入 Checkpoint A。
- 2026-07-28：四类入口最终都汇入 `SymbolColorWell`。上游 macOS presenter 把
  `GeometryReader(.global)` 的 source frame 再交给 `NSApp.keyWindow` 转屏幕坐标；
  当 well 位于 SF Symbols popover 时两者不是同一窗口，红测记录中心偏差 75 pt。
- 2026-07-28：改为复用公开 `BlossomColorPickerCore`，用实际 anchor `NSView` 的所属
  window 完成 `convertToScreen`，并以 owner child window 管理层级、关闭和边缘夹紧；
  默认 `PetalLayout`、194 pt 总尺寸、动画、色板、亮度和颜色写回均未复制或改写。
- 2026-07-28：macOS 定向 UI 1/1 通过，Blossom frame 为
  `{{369, 90}, {194, 194}}`、中心距离不超过 4 pt，结果包 `runtimeWarnings` 为空；
  最终全屏截图目视确认花瓣从 SF Symbols popover 右上角色块中心展开。
- 2026-07-28：现有 iPhone 与 iPad `testTaskDetailIconOpensSymbolColorPicker` 各 1/1
  通过。
- 2026-07-28：`make format-check` 通过（843 个 Swift 文件 0 问题），
  `make localization-check` 通过（9/9 资源），`make check-hooks` 通过；
  付费签名 `make test` 以 1447 tests / 162 suites 全绿。
- 2026-07-28：首轮 `make build-install-all` 已完成 Release 签名构建；iOS+Watch
  companion 安装到 iPad Pro M4 与 iPhone Air，macOS app 已复制到
  `/Applications/timetracker.app`。当前没有可见的独立实体 Apple Watch，Watch app
  仍随配对 iPhone 的 companion 安装策略交付。
- 2026-07-28：Release 构建发现 presenter 的两个 block-based
  `NotificationCenter` observer 产生 Swift 6 actor isolation 告警；改用
  `NSObject` selector observer 后，Release macOS 构建只保留仓库既有告警。随后
  macOS 定向 UI 再次 1/1 通过且 `runtimeWarnings` 为空，格式、本地化和
  1447 tests / 162 suites 全量门禁再次通过。
- 2026-07-28：告警修复 checkpoint `3d73fc5f` 后再次执行
  `make build-install-all`；Release iOS+Watch companion 成功安装到 iPad Pro M4
  与 iPhone Air，Release macOS app 成功复制到 `/Applications/timetracker.app`。
  活跃链接和自有 UI 测试资源已收口，第 84 项完成。
