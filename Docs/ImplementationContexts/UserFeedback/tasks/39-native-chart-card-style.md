# 39：Heatmap 与柱状图原生卡片风格实现记忆

> 本文件只用于主代理与子代理的实现、验证和编排记忆，不是任务来源。唯一范围与状态必须重新读取
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 条目。

## 当前阶段

- [x] 领取“Heatmap 和柱状图风格与原生卡片不一致”反馈。
- [~] 审计 Heatmap、柱状图与同屏原生卡片的组件、平台差异和现有自动化证据。
- [ ] 确定复用 SwiftUI 原生容器/项目 DesignSystem 的最小统一方案。
- [ ] 分 checkpoint 实现并运行聚焦测试与 macOS/iPhone/iPad XCUITest 截图验收。
- [ ] 执行 `CONFIGURATION=Release scripts/build_install_all.sh`，由 Codex 标记完成并移除活动链接。

## 唯一反馈边界

- 只统一 Heatmap 与柱状图相对同屏原生卡片的视觉和容器行为。
- 不领取后续任务详情图标跳转、Analytics 闪烁、番茄钟卡片或其他反馈。
- 以普通文字大小、正常交互路径、三平台系统约定为优先；不手动操作调试窗口。

## 强制约束

- 完整遵循仓库本地 `apple-hig` 与 `swiftui-expert-skill`；所有 UI 导航、断言与截图只用 XCTest/XCUITest 脚本。
- 物理设备只做最终 Release 安装和只读签名/版本核验，不启动、不交互、不截图。
- 优先复用 SwiftUI、Swift Charts 与现有 DesignSystem；评估成熟库但不为原生容器造轮子，除用户建议外不引入 GitHub 少于 1k stars 的库。
- 每个 checkpoint 只暂存本任务的已完成变更；保留用户在反馈文件中的其他内容。

## Checkpoint 编排

- [x] Checkpoint A：领取任务、创建实现记忆与 active link。
- [~] Checkpoint B：并行审计现有卡片实现、HIG/库方案与自动化矩阵。
- [ ] Checkpoint C：实现共享原生卡片样式并补齐聚焦测试。
- [ ] Checkpoint D：三平台脚本化视觉验收。
- [ ] Checkpoint E：Release 全设备安装、签名/版本核验与收口。

## 资源所有权

- [~] 主代理：任务状态、编排、集成、所有 build/TestManager/simulator/XCUITest/screenshot/Release 批次与清理。
- [~] 待分配：Heatmap/柱状图/原生卡片代码审计。
- [~] 待分配：Apple HIG、SwiftUI 与成熟库方案审计。
- [~] 待分配：现有 UI contract/XCUITest 与截图矩阵审计。

## 已提交 checkpoint

- [~] 待提交：领取任务、实现记忆与 active link。
