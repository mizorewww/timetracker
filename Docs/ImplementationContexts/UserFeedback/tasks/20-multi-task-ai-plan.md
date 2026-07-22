# 20：AI 一次生成多个任务实现记忆

> 本文件只用于主代理与子代理的实现、验证和编排记忆，不是任务来源。唯一范围与状态必须重新读取
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 条目及其嵌套项。

## 当前阶段

- [x] 读取唯一反馈并领取任务。
- [~] 审计现有 Task Plan request、响应 schema、draft/editor、category 与批量落库能力。
- [ ] 研究成熟库与 Apple HIG / SwiftUI 约束，完成独立产品与技术设计文档。
- [ ] 实现一次生成多个、类型完整且可验证的任务计划，并安全预览/编辑/落库到 category。
- [ ] 使用现有 MarkdownView 呈现或编辑本任务的提示词体验，并完成定向测试。
- [ ] 完成 owned iPhone/iPad simulator 普通路径与截图验收，清理全部资源。
- [ ] 执行 `CONFIGURATION=Release scripts/build_install_all.sh`，标记反馈完成并移除活动链接。

## 唯一反馈边界

- Tasks / Generate Task Plan 必须允许一次 AI 请求生成多个任务。
- AI 提示词必须详细介绍软件支持的各种任务类型，不能只生成扁平普通任务。
- 验收示例：输入“帮我生成一个读书任务，checklist 里有 1–10 章，每一章一个 checklist”，能够生成并归入某个 category。
- 嵌套要求一：这部分需要认真设计并单独写文档；计划路径为
  `Docs/ImplementationContexts/UserFeedback/designs/20-multi-task-ai-plan-design.md`。
- 嵌套要求二：编辑提示词采用仓库现有 `MarkdownView`。
- 不领取后续 Apple Health、Inbox、Timeline、Live Activity、首页统计或 category 排序等反馈。

## 强制约束

- 先盘点现有 task/category/checklist/quantity/recurrence/Health 等真实模型语义，不能向 AI 描述不存在或不允许创建的类型。
- AI 响应必须经过本地 schema、引用、数量、层级、字符和总预算验证；不得让模型输出直接写入持久化层。
- 多任务创建必须是原子、可预览、可编辑且失败可恢复；不得留下半批数据或悬空 parent/category 引用。
- 用户已有 Task Plan prompt 覆盖值必须兼容迁移；不得静默丢失第 19 项已实现的设置。
- `MarkdownView` 是用户明确指定且已存在于仓库的依赖，可以复用；其他新增 GitHub 依赖一般要求至少 1k stars 并先审查许可、维护与平台支持。
- UI 与截图仅使用明确 owned simulator；物理 iPhone/iPad 只做最终 Release 安装和只读核验，不启动、不操作、不截图。
- 每个小 checkpoint 验证后提交；只暂存本任务状态差异，保护 `Docs/userfeedback.md` 中用户新增内容。

## 待审计问题

- [ ] 当前 `LLMTaskPlanService` 的单任务/树形 schema、硬预算和错误语义。
- [ ] 当前 `AITaskPlanMutationModels`、coordinator 与 editor 能否表达批量根任务及原子落库。
- [ ] category 是生成内容、现有目标选择，还是两者；如何处理名称冲突和引用。
- [ ] 各真实任务类型可由用户创建的字段与禁止由 AI 创建的 Health-managed 语义。
- [ ] `MarkdownView` 当前仅渲染还是具备编辑桥接；本任务“编辑提示词”的正确交互边界。

## Checkpoint 编排

- [~] Checkpoint A：现状/风险/库审计，独立设计文档与可执行测试矩阵。
- [ ] Checkpoint B：多任务 response schema、解析/预算、draft 模型与原子 mutation。
- [ ] Checkpoint C：生成/预览/编辑/落库 UI、MarkdownView 提示词体验与本地化。
- [ ] Checkpoint D：全量相关回归、owned simulator UI/截图、精确 Release 安装、状态与资源收口。

## 资源所有权

- Checkpoint A 尚未创建 simulator 或启动设备流程。
