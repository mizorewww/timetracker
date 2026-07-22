# 22：Inbox 完成态可逆切换实现记忆

> 本文件只用于主代理与子代理的实现、验证和编排记忆，不是任务来源。唯一范围与状态必须重新读取
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 条目。

## 当前阶段

- [~] 领取反馈，审计 Inbox 完成态模型、命令、列表分组与行交互。
- [ ] 定位完成后无法恢复的根因，并确定与现有架构一致的最小修复。
- [ ] 实现完成/未完成双向切换及回归测试。
- [ ] 使用 owned iPhone/iPad simulator 验证普通交互路径并按需截图，随后清理资源。
- [ ] 执行 `CONFIGURATION=Release scripts/build_install_all.sh`，标记反馈完成并移除活动链接。

## 唯一反馈边界

- Inbox 中已勾选完成的任务必须能够切回未完成状态。
- 保持现有 Inbox 捕获、建议项、任务转换与删除语义不变。
- 不领取后续 Timeline、Live Activity、首页统计或 Apple Health 历史反馈。

## 强制约束

- 优先复用现有 Inbox command/state service，不建立平行完成态或仅在 View 中伪造状态。
- UI 与截图只使用明确登记的 owned simulator；物理设备只做最终 Release 安装和只读核验，不启动、不操作、不截图。
- 每个小 checkpoint 验证后提交；只暂存本任务状态差异，保护 `Docs/userfeedback.md` 中用户新增内容。

## Checkpoint 编排

- [~] Checkpoint A：静态审计模型、命令、列表分组、跨设备入口和现有测试。
- [ ] Checkpoint B：实现、单元/契约/UI 测试。
- [ ] Checkpoint C：owned simulator 验收、精确 Release 安装、状态与资源收口。

## 资源所有权

- 尚未创建 simulator、启动设备流程或生成 trace。
