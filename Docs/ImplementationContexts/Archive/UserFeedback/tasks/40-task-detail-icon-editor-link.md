# 40：任务详情图标跳转图标编辑实现记忆

Status: Complete

> 本文件只用于主代理与子代理的实现、验证和编排记忆，不是任务来源。唯一范围与状态必须重新读取
> [`Docs/userfeedback.md`](../../../../userfeedback.md) 中对应的 `[~]` 条目。

## 当前阶段

- [x] 领取“任务详情页面，点击图标应该跳转到图标编辑页面”反馈。
- [x] 审计任务详情页图标展示与现有图标/颜色编辑器(color&icon 选择器)的呈现方式与入口。
- [x] 确定最小跳转方案(复用现有编辑器,平台一致)。
- [x] 实现并运行聚焦契约/UI 测试与 iPhone/iPad/macOS 模拟器截图验收。
- [x] 执行 `CONFIGURATION=Release scripts/build_install_all.sh`(实体机安装失败不阻塞),标记完成并移除活动链接。

## 唯一反馈边界

- 只让任务详情页的图标可点击并跳转到该任务的图标编辑页面。
- 不领取 Analytics 闪烁、番茄钟卡片或其他反馈。
- 以普通文字大小、正常交互路径、三平台系统约定为优先。

## 强制约束

- 完整遵循仓库本地 `apple-hig` 与 `swiftui-expert-skill`;所有 UI 导航、断言与截图只用 XCTest/XCUITest 脚本。
- 实体机器不做测试;模拟器验收后 shutdown+delete 并清理 /tmp 产物。
- 优先复用 SwiftUI 与现有编辑器组件;除用户建议外不引入 GitHub 少于 1k stars 的库。
- 每个 checkpoint 只暂存本任务的已完成变更;保留用户在反馈文件中的其他内容。

## Checkpoint 编排

- [x] Checkpoint A：领取任务、创建实现记忆与 active link。
- [x] Checkpoint B：审计详情页图标与编辑器入口。
- [x] Checkpoint C：实现跳转并补齐聚焦测试。
- [x] Checkpoint D：三平台模拟器脚本化视觉验收与资源清理。
- [x] Checkpoint E：Release 构建安装、核验与收口。

## 资源所有权

- [x] 主代理：任务状态、编排、集成、所有 build/simulator/XCUITest/screenshot/Release 批次与清理。
- [x] 主代理(直接审计,无需子代理)：任务详情页与图标编辑器代码审计。

## 已提交 checkpoint

- [x] `36d697b6`:实现 + 契约/UI 测试 + 三平台截图验收(1.1.107 (162))。
- [x] `dfd1d229`：领取任务、实现记忆与 active link。


## 实现与验收记录

- 方案:抽出 `SymbolColorPickerPresentation<Label>`(iOS 推送 / macOS popover,与既有 `SymbolColorPickerButton` 同一呈现语义并复用之),把任务详情 identity 行的 44pt `TaskIcon` 包进该链接,绑定 `$draft.iconName`/`$draft.colorHex`,打开时收起键盘;标识符 `task.detail.icon.edit`。
- 契约测试 `taskDetailIconOpensTheSharedSymbolColorPicker` 锁定链接、绑定与焦点清理。
- XCUITest `testTaskDetailIconOpensSymbolColorPicker`:经 `route: "task-detail"` 直接启动(手写 Tasks 导航在 macOS 上不稳定,改用既有 route 机制),断言推出/弹出 `symbol.picker.view` 与搜索框;iPhone 需 15s 等待(route 在健康刷新后应用)。
- [x] iPhone(owned `codex-task40-iPhone17Pro`)、iPad(`codex-task40-iPadPro11`)、macOS 均通过;截图确认 iOS 推送整页编辑器、macOS popover 锚定图标。
- [x] `CONFIGURATION=Release scripts/build_install_all.sh` 成功;iPhone Air 已装 `1.1.107 (162)`;实体机安装状态不阻塞收口。
- [x] 反馈已由主代理标记完成,active link 已移除;owned 模拟器与 /tmp 产物已清理。