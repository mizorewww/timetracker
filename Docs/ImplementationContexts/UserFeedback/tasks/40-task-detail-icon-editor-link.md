# 40：任务详情图标跳转图标编辑实现记忆

> 本文件只用于主代理与子代理的实现、验证和编排记忆，不是任务来源。唯一范围与状态必须重新读取
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 条目。

## 当前阶段

- [x] 领取“任务详情页面，点击图标应该跳转到图标编辑页面”反馈。
- [~] 审计任务详情页图标展示与现有图标/颜色编辑器(color&icon 选择器)的呈现方式与入口。
- [ ] 确定最小跳转方案(复用现有编辑器,平台一致)。
- [ ] 实现并运行聚焦契约/UI 测试与 iPhone/iPad/macOS 模拟器截图验收。
- [ ] 执行 `CONFIGURATION=Release scripts/build_install_all.sh`(实体机安装失败不阻塞),标记完成并移除活动链接。

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
- [ ] Checkpoint B：审计详情页图标与编辑器入口。
- [ ] Checkpoint C：实现跳转并补齐聚焦测试。
- [ ] Checkpoint D：三平台模拟器脚本化视觉验收与资源清理。
- [ ] Checkpoint E：Release 构建安装、核验与收口。

## 资源所有权

- [~] 主代理：任务状态、编排、集成、所有 build/simulator/XCUITest/screenshot/Release 批次与清理。
- [ ] 待分配：任务详情页与图标编辑器代码审计。

## 已提交 checkpoint

- [~] 待提交：领取任务、实现记忆与 active link。
