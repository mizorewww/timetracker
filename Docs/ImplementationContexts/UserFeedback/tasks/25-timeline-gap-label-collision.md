# 25：跨平台 Timeline 省略时长标注碰撞实现记忆

> 本文件只用于主代理与子代理的实现、验证和编排记忆，不是任务来源。唯一范围与状态必须重新读取
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 子条目。

## 当前阶段

- [~] 领取反馈，复现并审计 iPhone 多个 `xxx min elapsed` 标注互相遮挡的根因。
- [ ] 对照 Apple HIG、SwiftUI 布局语义和成熟实现，确定跨平台标注避让策略。
- [ ] 实现纯布局修复与覆盖密集 gap 的单元/契约测试。
- [ ] 使用明确登记的 owned simulator 与本机 macOS 窗口做全平台 UI/截图验收并清理资源。
- [ ] 精确执行 `CONFIGURATION=Release scripts/build_install_all.sh`，标记反馈完成并移除活动链接。

## 唯一反馈边界

- 修复 iPhone Timeline 中多个 `xxx min elapsed` 标注彼此遮挡的问题。
- 同一修复必须覆盖 iPhone、iPad 与 macOS Timeline，并做视觉测试。
- 不领取紧随其后的彩色任务条宽度/图标反馈，也不处理版本 hook、Live Activity 或其他条目。

## 强制约束

- 优先修正共享纯布局与真实 fixture，不用截图专用硬编码坐标伪造结果。
- 先审计现有依赖与成熟实现；一般拒绝非用户指定且 GitHub 少于 1k stars 的依赖。
- UI 截图只来自 owned simulator 或本机 macOS 自动化窗口；物理设备只做最终 Release 安装和只读核验，不启动、不操作、不截图。
- 每个小 checkpoint 验证后提交；只暂存本任务状态差异，保护 `Docs/userfeedback.md` 中其余用户新增内容。

## Checkpoint 编排

- [~] Checkpoint A：静态根因审计、相关规范与依赖研究。
- [ ] Checkpoint B：共享标注布局、密集 gap fixture 与自动化回归。
- [ ] Checkpoint C：owned UI 设备矩阵截图、精确 Release 安装与收口。

## 资源所有权

- 当前未创建 simulator，未启动 app、测试宿主或 Instruments。
