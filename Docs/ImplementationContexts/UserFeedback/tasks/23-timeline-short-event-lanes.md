# 23：Timeline 短任务轨道布局实现记忆

> 本文件只用于主代理与子代理的实现、验证和编排记忆，不是任务来源。唯一范围与状态必须重新读取
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 条目。

## 当前阶段

- [~] 领取反馈，审计手机 Timeline 的事件几何、最小高度、图标和 elapsed 标签布局。
- [ ] 对照 Apple HIG、SwiftUI 布局语义与成熟日历/时间轴实现，确定轨道分配和间距规则。
- [ ] 实现短任务避让及回归测试，保持正常长度任务和跨平台行为稳定。
- [ ] 使用 owned iPhone simulator 验证普通交互路径并截图；按需要补充 iPad 回归，随后清理资源。
- [ ] 执行 `CONFIGURATION=Release scripts/build_install_all.sh`，标记反馈完成并移除活动链接。

## 唯一反馈边界

- 手机上的任务时间过短、无法容纳图标时，不得向上侵占相邻任务；应按屏幕几何阈值将冲突事件分配到不同轨道或向安全方向布局。
- 相邻短任务之间必须保持可辨识间距，不遮挡已有或可能出现的 `xxx min elapsed` 标签。
- 不领取后续 Live Activity、首页统计、Apple Health 历史或其他新增反馈。

## 强制约束

- 优先修正共享 Timeline layout/read model，不以某条测试数据或硬编码坐标伪造结果。
- 先审计现有依赖与成熟实现；只有质量、维护状态和收益足够时才引入库，一般拒绝非用户指定且 GitHub 少于 1k stars 的依赖。
- UI 与截图只使用明确登记的 owned simulator；物理设备只做最终 Release 安装和只读核验，不启动、不操作、不截图。
- 每个小 checkpoint 验证后提交；只暂存本任务状态差异，保护 `Docs/userfeedback.md` 中用户新增内容。

## Checkpoint 编排

- [~] Checkpoint A：静态审计与算法/依赖研究。
- [ ] Checkpoint B：实现轨道几何与单元/契约回归。
- [ ] Checkpoint C：owned simulator 截图验收与精确 Release 安装收口。

## 资源所有权

- 尚未创建 simulator、测试 runner、截图或 trace 资源。
