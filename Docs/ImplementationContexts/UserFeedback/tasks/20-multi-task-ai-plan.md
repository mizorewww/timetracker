# 20：AI 一次生成多个任务实现记忆

> 本文件只用于主代理与子代理的实现、验证和编排记忆，不是任务来源。唯一范围与状态必须重新读取
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 条目及其嵌套项。

## 当前阶段

- [x] 读取唯一反馈并领取任务。
- [x] 审计现有 Task Plan request、响应 schema、draft/editor、category 与批量落库能力。
- [x] 研究成熟库与 Apple HIG / SwiftUI 约束，完成独立产品与技术设计文档。
- [x] 实现一次生成多个、类型完整且可验证的任务计划，并安全落库到 category。
- [~] 使用现有 MarkdownView 呈现本任务的提示词预览，补齐计划草稿类型编辑并完成定向测试。
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

- [x] 当前 service 已支持多个根 task 与扁平树形引用；维持 4 KiB request/instructions、128 KiB response、8/64/32/256 数量和 6 层深度预算。
- [x] 当前 coordinator 已原子创建多个根 task，但尚未把 quantity/daily recurrence 送入真实 progress mutation service。
- [x] 本任务只生成同份草稿内的新 category；不向 AI 暴露现有 store graph，也不伪造或按名称合并现有 category。
- [x] AI 可创建普通/父子/checklist/quantity/daily recurrence（quantity 可与 daily 组合）；Health-managed task 明确禁止生成。
- [x] `MarkdownView 4.1.7` 只有渲染/选择能力；采用系统 `TextEditor` 编辑 + `MarkdownView` 实时预览。

## Checkpoint 编排

- [x] Checkpoint A：现状/风险/库审计，独立设计文档与可执行测试矩阵。
  - 三个只读子审计与主代理结论一致：保留现有多根/扁平图；quantity 与 daily recurrence 是正交能力；Health-managed 不可生成；MarkdownView 只做渲染。
  - 上游核验：仓库已锁定用户指定的 `MarkdownView 4.1.7`（MIT、138 stars、2026-07-16 release）；因用户明确指定而作为低于默认 1k-star 门槛的例外，不新增其他依赖。
  - macOS 基线：`CoreLLMTaskPlanServiceTests` 7/7、`StoreScopedAITaskPlanCommandCoordinatorTests` 6/6、`AITaskPlanUIContractTests` 3/3，共 16/16 通过；xcresult/DerivedData 已删除。
- [x] Checkpoint B：多任务 response schema、解析/预算、draft 模型与原子 mutation。
  - task payload 新增可选 quantity goal 与 daily recurrence，旧 payload 缺字段仍兼容；固定 contract 要求完整多任务/章节清单并禁止 Health-managed 内容。
  - 默认 Task Plan instructions 升级为 Markdown；只把精确旧默认值迁移为新默认，自定义内容保持不变。
  - quantity、daily rule、当天 occurrence 与生成 task 在同一 fresh-context transaction 落库；五个 progress checkpoint 注入失败均整批回滚，重放仍幂等。
  - 主代理 macOS 集成定向测试 `50/50` 通过（service、coordinator、settings、UI contract）；独立 DerivedData/xcresult 已删除，无 `xcodebuild`/`xctest`、Booted simulator 或设备流程残留。
  - 未新增依赖；复用现有 `TaskProgressDraftPersistencePolicy`、`TaskDraftProgressMutationService` 与事务基础设施。
- [~] Checkpoint C：生成/预览/编辑/落库 UI、MarkdownView 提示词体验与本地化。
- [ ] Checkpoint D：全量相关回归、owned simulator UI/截图、精确 Release 安装、状态与资源收口。

## 资源所有权

- Checkpoint A 尚未创建 simulator 或启动设备流程。
