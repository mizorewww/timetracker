# 81：Checklist 删除二级菜单与滑动操作实现记忆

状态：2026-07-28 实现中

> 本文件是主代理与子代理的实现、验证和编排记忆；唯一任务来源仍是
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 条目。

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

- [ ] iPhone/iPad 正常字号：Checklist 行不显示常驻垃圾桶；从一侧滑动可看到明确的
  destructive Delete 操作，另一侧不会出现重复或含义不清的删除入口。
- [ ] macOS 正常字号：Checklist 行不显示常驻垃圾桶；右键/Control-click 的二级菜单
  包含 destructive Delete，并保留键盘、拖拽及上下移动等既有操作。
- [ ] 菜单与滑动删除都走相同 session/command 边界；删除保存后 fresh reload 不复现。
- [ ] 已存在内容、空白新行、未完成/已完成分组，以及创建任务/编辑任务路径行为一致。
- [ ] 三语文案、accessibility identifier、行为/UI 测试与产品文档同步。

## 测试优先清单

- [ ] 先补或扩展删除后 save → fresh reload 的行为回归。
- [ ] 先补 UI 自动化，证明改动前常驻垃圾桶仍存在或新入口缺失。
- [ ] 实现后复跑 iPhone/macOS UI 自动化并保留正常字号截图。
- [ ] 完整测试、格式/本地化门禁与 Release 全设备安装通过。

## Checkpoint 编排

- [~] A：完成删除入口、共用 row、command/session、平台能力、测试与依赖审计。
- [ ] B：补充失败的行为/交互测试。
- [ ] C：实现原生二级菜单与滑动操作，收口冗余按钮。
- [ ] D：完成定向、全量、截图、Release 全设备安装与关闭。

## 库策略

- 原生 SwiftUI 已提供平台一致的菜单、destructive role 与 List swipe action；仅当原生
  API 无法满足现有部署目标和交互契约时才评估成熟依赖。

## 子代理编排

- 主代理负责范围、活动记忆、测试优先、集成、模拟器/设备批次、提交与收口。
- 子代理可并行进行 UI/共用组件审计、删除持久化测试审计及 Apple HIG/平台交互审计；
  结论回写本文件，避免同时修改主代理正在处理的文件。

## 进度记录

- 2026-07-28：按反馈顺序认领任务并建立 `~81` 活动实现记忆，进入 Checkpoint A。
