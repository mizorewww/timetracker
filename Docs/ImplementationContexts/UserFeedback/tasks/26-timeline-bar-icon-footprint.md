# 26：Timeline 任务条图标 footprint 与记录图标实现记忆

> 本文件只用于主代理与子代理的实现、验证和编排记忆，不是任务来源。唯一范围与状态必须重新读取
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 子条目。

## 当前阶段

- [~] 领取反馈，复现并审计彩色任务条无法包住图标、记录列表仍使用圆点的问题。
- [ ] 对照 Apple HIG、SwiftUI 布局语义与成熟图表实现，确定图标最小 footprint 和密集时间段降级策略。
- [ ] 实现共享跨平台布局与记录图标，并补充纯布局/契约测试。
- [ ] 使用 owned iPhone/iPad simulator 与 XCTest 自动化 macOS window 做截图验收并清理资源。
- [ ] 精确执行 `CONFIGURATION=Release scripts/build_install_all.sh`，标记反馈完成并移除活动链接。

## 唯一反馈边界

- Timeline 中每条彩色任务条至少完整包住任务图标并保留可见 padding，不能让短任务条裁切或挤压图标。
- Timeline 下方记录列表当前的颜色圆点改为对应任务图标，同时保持任务颜色语义。
- 修复必须覆盖 iPhone、iPad 和 macOS 的共享 Timeline。
- 不领取下一条“省略时长胶囊自适应文字宽度”，也不处理版本 hook、Live Activity 或其他反馈。

## 强制约束

- 先确认现有 Timeline lane/axis compression 能否表达最小可视 footprint；不能通过伪造任务时长或截图专用硬编码掩盖真实数据。
- 优先复用系统 SF Symbols、现有 `SymbolCatalog`/任务 identity 组件和成熟库；一般拒绝非用户指定且 GitHub 少于 1k stars 的新依赖。
- UI 截图只来自 owned simulator 或 XCTest 自动化 macOS window；物理设备只做最终 Release 安装和只读核验，不启动、不操作、不截图。
- 每个小 checkpoint 验证后提交；只暂存本任务状态差异，保护 `Docs/userfeedback.md` 的其他用户新增内容。

## Checkpoint 编排

- [~] Checkpoint A：静态根因、现有组件/依赖与成熟方案审计。
- [ ] Checkpoint B：任务条最小 icon footprint、记录图标与自动化回归。
- [ ] Checkpoint C：owned UI 设备矩阵截图、精确 Release 安装与收口。

## 资源所有权

- 当前未创建 simulator；任何 UI batch 开始前必须记录专属名称与 UDID，完成后 shutdown/delete。
