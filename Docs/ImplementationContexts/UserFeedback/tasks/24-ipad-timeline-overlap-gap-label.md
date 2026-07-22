# 24：iPad Timeline 重叠与省略时长标注实现记忆

> 本文件只用于主代理与子代理的实现、验证和编排记忆，不是任务来源。唯一范围与状态必须重新读取
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 子条目。

## 当前阶段

- [~] 领取反馈，审计 iPad/macOS horizontal Timeline 的重叠轨道、短任务几何与 omitted-gap 标注层级。
- [ ] 对照 Apple HIG、SwiftUI 布局语义及成熟时间轴实现，确定跨平台修复与依赖策略。
- [ ] 构造大量重叠、短任务的隔离 fixture，完成纯布局、契约和性能回归。
- [ ] 使用明确登记的 owned iPhone/iPad simulator 与本机 macOS 测试窗口进行 UI 验收并截图，随后清理资源。
- [ ] 精确执行 `CONFIGURATION=Release scripts/build_install_all.sh`，标记反馈完成并移除活动链接。

## 唯一反馈边界

- iPad Timeline 中任务条不得遮挡 `xxx min elapsed` 省略时长标注。
- 用大量时间重叠且持续时间短的任务验证 iPhone、iPad 与 macOS Timeline 的轨道、间距、标注层级和可读性。
- 不领取后续 Live Activity、首页统计或其他反馈。

## 强制约束

- 优先修正共享 Timeline 纯布局，不以某张截图或单一 fixture 的硬编码坐标伪造结果。
- 先审计现有依赖与成熟实现；只有质量、维护状态和收益足够时才引入库，一般拒绝非用户指定且 GitHub 少于 1k stars 的依赖。
- UI 截图只来自 owned simulator 或本机 macOS 自动化窗口；物理设备只做最终 Release 安装和只读核验，不启动、不操作、不截图。
- 每个小 checkpoint 验证后提交；只暂存本任务状态差异，保护 `Docs/userfeedback.md` 中其余用户新增内容。

## Checkpoint 编排

- [~] Checkpoint A：静态审计、任务相关规范与依赖研究。
- [ ] Checkpoint B：跨平台布局修复、fixture、回归与性能测试。
- [ ] Checkpoint C：owned UI 设备矩阵截图验收、精确 Release 安装与收口。

## 资源所有权

- 尚未创建 simulator、启动 UI runner 或生成临时构建产物。
