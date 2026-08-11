# 81：Checklist 删除二级菜单与滑动操作实现记忆

Status: Complete

状态：2026-07-28 已完成

> 本文件是主代理与子代理的实现、验证和编排记忆；唯一任务来源仍是
> [`Docs/userfeedback.md`](../../../../userfeedback.md) 中对应的 `[~]` 条目。

## 认领的反馈条目

- 任务 Checklist 的删除图标不再作为常驻一级按钮；删除入口改为二级菜单，并在支持
  行滑动的平台提供左右滑动操作。

## 初始范围

- 审计 Task Editor、Task Detail、恢复草稿与其它 Checklist row 的删除入口，确认共用
  组件、平台差异、持久化 command/session 边界及现有测试。
- 删除仍沿用现有 command/session，不在 View 中新增 durable write。
- 优先使用 SwiftUI 原生 `contextMenu`、`swipeActions`、`Button(role: .destructive)`；
  不自造横向手势，不引入第三方 swipe/menu 库。

## UI 验收清单（改动前）

- [x] iPhone/iPad 正常字号：Checklist 行不显示常驻垃圾桶；从一侧滑动可看到明确的
  destructive Delete 操作，另一侧不会出现重复或含义不清的删除入口。
- [x] macOS 正常字号：Checklist 行不显示常驻垃圾桶；右键/Control-click 的二级菜单
  包含 destructive Delete，并保留键盘、拖拽及上下移动等既有操作。
- [x] 菜单与滑动删除都走相同 session/command 边界；删除保存后 fresh reload 不复现。
- [x] 已存在内容、空白新行、未完成/已完成分组，以及创建任务/编辑任务路径行为一致。
- [x] 三语文案、accessibility identifier、行为/UI 测试与产品文档同步。

## 测试优先清单

- [x] 先补或扩展删除后 save → fresh reload 的行为回归。
- [x] 先补 UI 自动化，证明改动前常驻垃圾桶仍存在或新入口缺失。
- [x] 实现后复跑 iPhone/macOS UI 自动化并保留正常字号截图。
- [x] 完整测试、格式/本地化门禁与 Release 全设备安装通过。

## Checkpoint 编排

- [x] A：完成删除入口、共用 row、command/session、平台能力、测试与依赖审计。
- [x] B：补充失败的行为/交互测试。
- [x] C：实现原生二级菜单与滑动操作，收口冗余按钮。
- [x] D：完成定向、全量、截图、Release 全设备安装与关闭。

## 库策略

- 原生 SwiftUI 已提供平台一致的菜单、destructive role 与 List swipe action；仅当原生
  API 无法满足现有部署目标和交互契约时才评估成熟依赖。

## 子代理编排

- 主代理负责范围、活动记忆、测试优先、集成、模拟器/设备批次、提交与收口。
- 子代理可并行进行 UI/共用组件审计、删除持久化测试审计及 Apple HIG/平台交互审计；
  结论回写本文件，避免同时修改主代理正在处理的文件。

## 进度记录

- 2026-07-28：按反馈顺序认领任务并建立 `~81` 活动实现记忆，进入 Checkpoint A。
- 2026-07-28：三个只读审计确认新建/编辑/详情/恢复路径复用
  `ChecklistEditorRow`；删除应按稳定 UUID 进入 `TaskEditorSession`，继续由现有
  editor save 与 `ChecklistDraftService` 产生 tombstone，不新增 repository 写路径。
- 2026-07-28：Apple 官方 `Menu`、`swipeActions`、`contextMenu` 已覆盖所需平台交互；
  采用 visible More menu、iOS/iPadOS trailing swipe（`allowsFullSwipe: false`）及
  macOS context menu，不引入第三方库，也不在左右两侧重复 destructive action。
- 2026-07-28：测试优先新增稳定 UUID 删除后 save → fresh `ModelContext` 回归，以及
  `testChecklistDeleteUsesSecondaryActions`。实现前 UI 测试真实失败于常驻 Delete
  按钮仍存在；实现后 `TaskEditorSessionTests` 定向通过。
- 2026-07-28：删除 View 内的常驻垃圾桶和数组下标删除，新增共享 More/menu、
  trailing swipe、macOS context menu；删除当前行先清 focus，并通过
  `TaskEditorSession.deleteChecklistItem(id:)` 修改草稿。
- 2026-07-28：iPhone UI 最终通过（1 test / 2 screenshots），结果
  `build/UITestResults/iOS-20260728-002142.xcresult`，目检截图在
  `build/UITestScreenshots/task81-ios-20260728-002142/`。macOS 最终通过
  （1 test / 2 screenshots），结果
  `build/UITestResults/macOS-20260728-003055.xcresult`，目检截图在
  `build/UITestScreenshots/task81-macos-20260728-003055/`；测试先关闭 Xcode 27
  beta 遗留的 WidgetRenderer 系统报告窗，最终截图无外部遮挡。
- 2026-07-28：同步更新 Architecture、CodeGuide、UI-Design、Testing 与 UserGuide；
  进入完整测试、格式/本地化与 Release 全设备安装 Checkpoint D。
- 2026-07-28：完整 `make test` 通过（1444 tests / 162 suites）；`make format-check`
  通过（0/842），`make localization-check` 通过（9/9、主资源 1282 keys），
  `git diff --check` 通过。等待实现 checkpoint 提交与 Release 全设备安装。
- 2026-07-28：实现 checkpoint 提交 `1840ca5a`（1.1.286 / 341）完成 Release
  `make build-install-all`：安装到 iPad Pro M4、iPhone Air，iOS 包包含 Watch
  companion，并将签名验证通过的 macOS App 复制到 `/Applications/timetracker.app`。
  任务完成；closeout 提交后再以最终 HEAD 复跑同一安装门禁。
