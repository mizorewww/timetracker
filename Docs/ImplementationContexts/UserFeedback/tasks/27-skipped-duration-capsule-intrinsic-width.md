# 27：省略时长胶囊自适应文字宽度实现记忆

> 本文件只用于主代理与子代理的实现、验证和编排记忆，不是任务来源。唯一范围与状态必须重新读取
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 子条目。

## 当前阶段

- [~] 领取反馈，定位 `xxx min elapsed/skipped` 胶囊的固定宽度来源及所有平台复用点。
- [ ] 对照 Apple HIG、SwiftUI intrinsic sizing 与现有成熟组件确定自适应宽度契约。
- [ ] 实现胶囊抱住完整文字并补充布局/契约回归。
- [ ] 使用 owned simulator 与 XCTest 自动化 macOS window 做跨平台截图验收并清理资源。
- [ ] 精确执行 `CONFIGURATION=Release scripts/build_install_all.sh`，标记反馈完成并移除活动链接。

## 唯一反馈边界

- Timeline 的省略时长文字胶囊不能使用无法容纳完整文案的固定宽度；背景必须随实际文字和内边距自适应。
- 修复覆盖该共享 Timeline 组件所支持的平台与布局方向。
- 不领取版本 hook、Live Activity、主页说明文字或任何后续反馈。

## 强制约束

- 先审计现有组件、局部化文案与布局算法；不能通过缩小字体、截断文字或为截图硬编码某个文案宽度掩盖问题。
- 优先使用 SwiftUI 原生 intrinsic sizing 与现有组件；如确需第三方依赖，先核验成熟度并一般拒绝 GitHub 少于 1k stars 的非用户指定库。
- UI 验收只使用 owned simulator 与 XCTest 自动化 macOS window；物理设备只做最终 Release 安装和只读核验，不启动、不操作、不截图。
- 每个小 checkpoint 验证后提交；只暂存本任务状态差异，保护 `Docs/userfeedback.md` 的其他用户新增内容。

## Checkpoint 编排

- [~] Checkpoint A：静态根因、复用点、局部化宽度与成熟方案审计。
- [ ] Checkpoint B：intrinsic capsule 实现与纯布局/契约回归。
- [ ] Checkpoint C：owned UI 设备矩阵与脚本截图验收。
- [ ] Checkpoint D：精确 Release 安装、状态标记与收口。
