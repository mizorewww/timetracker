# 59：Inbox AI 完整上下文与任务增删改查实现记忆

状态：进行中
反馈来源：`Docs/userfeedback.md` 中 Inbox AI 无法复用已有 Category、需要完整上下文并把增删改查作为工具调用的子项。

## 当前阶段

- [x] 按文档顺序领取反馈并建立可恢复的活动记忆。
- [x] 审计现有 Inbox AI 输入、提示词、流式协议、计划预览、命令边界和持久化测试。
- [~] 先定义完整任务树上下文、稳定身份和 CRUD 工具调用的行为契约与失败测试。
- [ ] 实现最小安全变更，复用既有 Commands / Repositories / SwiftData 分层。
- [ ] 验证 AI harness、持久化命令、普通字号 UI 预览及三平台行为。
- [ ] 提交小 checkpoint，执行 Release 全设备安装，标记反馈完成并移除活动链接。

## 唯一范围

- Inbox 的 AI 生成功能必须看到足以无歧义引用现有 Category、Task 与 Checklist 的完整当前上下文。
- 模型必须通过有稳定身份的结构化操作表达创建、读取、更新和删除意图，而不是仅返回一棵待新增的任务树。
- 将模型操作安全地映射到现有命令边界；预览、确认、冲突和失败不得绕过 durable-write 规则。
- 修复“已有 `a` Category 却新建重复 `a` Category”的回归，并覆盖同名、层级、删除和更新边界。

不在本任务内：

- 替换用户选择的模型供应商或密钥存储方案。
- 无关 Inbox 列表、Analytics、同步或任务详情视觉重构。
- 用 UI 自动化直接依赖真实付费 API 作为唯一回归门禁。

## 强制约束

- 测试先于持久化 wiring；每个 durable write 都必须有 command-boundary 行为测试。
- AI 输出视为不可信输入：稳定 ID、目标存在性、层级合法性、删除范围和并发变化都要验证。
- 不限制任务树上下文为任意小的固定条数；若供应商有实际窗口约束，必须显式报告并采用可验证的降级，而不是静默截断。
- Apple HIG 与 SwiftUI 专项规范约束预览、确认、进度、错误和破坏性操作。
- 优先复用现有成熟依赖与 Apple API；新增依赖需证明必要性、维护质量和许可。
- 只暂存本任务自己的反馈状态，保留用户尚未暂存的其他反馈编辑。

## Checkpoint 编排

- [x] Checkpoint A：领取、现状/历史/测试/库审计、行为契约。
- [~] Checkpoint B：失败测试、结构化工具协议和安全命令执行。
- [ ] Checkpoint C：UI 预览/确认、回归验证、文档与小提交。
- [ ] Checkpoint D：跨平台验收、Release 全设备安装和反馈收口。

## 子代理编排

- [x] AI 协议与安全审计：上下文序列化、模型响应、tool-call/streaming 与注入边界。
- [x] 命令/持久化审计：现有 task/category/checklist 命令、事务与测试缺口。
- [x] UI/历史/库审计：Inbox 生成流程、回归历史、Apple 原生与成熟库适用性。

## 资源所有权

- 主代理统一拥有后续 Xcode build/test、设备和模拟器批次。
- 子代理当前只做只读审计，不创建模拟器、不运行 Xcode、不修改共享文件。

## 审计结论

### 实际入口与直接根因

- 反馈描述为 Inbox，但当前 Inbox suggestion 只能生成建议文本，不能创建 Category。能够产生重复 Category 的实际入口是 Tasks 页 `AI Task Plan`；实现与 UI 验收覆盖用户真正触发的 Task Plan 流程，同时保留反馈原文。
- `tasks.generatePlan` 自提交 `2918530f`（2026-07-19）起就是独立、仅创建的草稿流；这不是近期回归，而是旧架构缺少编辑语义。
- `LLMTaskPlanService` 的请求只包含用户输入、说明和图标/颜色白名单，没有现有 Category、Task 或 Checklist 上下文。
- 旧响应是只新增的扁平 `categories/tasks/checklistItems`；每个 Category/Task 引用都会映射到新的本地 UUID，Coordinator 随后无条件调用 `createCategory`。所以现有 `a` 必然不会被复用。
- Checklist 响应中的引用会被丢弃并重新生成 UUID；旧流程无法稳定引用已有 Checklist。
- 现有“幂等”只检查提议的 Category/Task UUID 是否都存在，不校验内容、tombstone、assignment、Checklist、progress 或最终关系，可能把无关或残缺数据误判为成功。

### 协议与传输

- 当前 OpenAI-compatible DTO 不能表达 assistant `tool_calls`、`role=tool`、`tool_call_id` 或 `finish_reason=tool_calls`。
- 流式 DTO 只读取 content/reasoning/usage；SSE 解码使用可失败忽略，会静默丢弃未知或损坏的 tool-call delta。
- OpenAI 与 DeepSeek 的官方协议都要求应用执行工具，再用对应 `tool_call_id` 返回工具结果。严格 schema 应为所有属性声明 required，并设置 `additionalProperties: false`。
- DeepSeek thinking-mode 多轮工具调用还要求把上一轮 assistant `reasoning_content` 原样带回下一轮；它只保存在单次生成会话内，不持久化、不记录日志。
- 流式 tool call 必须按 choice index 与 tool-call index 累积碎片；在完整结束后才解码参数。未知工具、重复/缺失 call ID、缺失名称、畸形参数、额外字段以及不支持的结束原因都显式失败。
- 工具回合数与调用数需要有防循环上限；该上限不得变成任务树实体数量限制。

### 命令与持久化

- 新批次不能嵌套现有各自开锁、fresh context、transaction 的 Coordinator。确认必须在一次共享锁、一个 fresh context、一次 atomic mutation 内完成完整 preflight 与写入。
- 可复用的安全边界包括 `StoreScopedTimerMutationTransaction.withFreshContext`、`ModelContext.performAtomicMutation`、Category/Task/Checklist baseline、Task lifecycle 校验、层级校验、Health 保留 ID 校验和 active-work revalidation。
- Task 产品语义只有 Archive/Restore，没有普通 Delete；AI 的 task delete 必须编译为 Archive，不能写 `deletedAt` 或恢复硬删除路径。
- Category 同名目前合法。已有实体一律用稳定 UUID 引用，绝不按 Task/Checklist 名称猜目标。仅当“新建 Category”的规范化名称唯一匹配一个现有 Category 时可确定性复用；匹配多个时返回歧义。
- Checklist 现有命令没有精确 rename/delete。复用完整 `TaskEditorDraft` 会旋转无关 Checklist/visual revision，且可能复活 tombstone；需要带 baseline 的精确 in-context add/update/delete 原语。
- Task 元数据更新同样应精确修改目标；确认前必须要求目标仍是可见且 baseline 一致。
- 预览期没有 store revision/baseline，无法发现生成后到确认前的并发变化。第一版采用保守的完整工作区 CAS：确认时所有可见 Category/Task/assignment/checklist/visual/goal/rule mutation revision 必须仍一致，否则整批拒绝并保留预览。

## 确认的实现架构

1. 构造纯值、确定性排序的完整 `AITaskWorkspaceSnapshot`，包含当前规范可见的 Category、Task、Checklist、稳定 UUID、关系、可编辑字段、完整 Task path、归档状态以及计划所需的 progress/recurrence 元数据。网络快照携带可显示的 `contextFingerprint`；本地保存完整 revision baseline。
2. 快照不包含 API key、Keychain、time ledger/history、Health samples 或其他无关隐私数据；本地 CAS baseline/revision map 不进入网络 DTO。
3. 不按任意实体数量静默截断，也不沿用过小的固定 request body 限额。供应商或传输若拒绝完整请求，返回包含实际大小/供应商原因的显式 typed error。
4. 模型通过纯内存 overlay 工具读取和修改快照：list/get；Category create/update/delete；Task create/update/archive；Checklist create/update/delete。工具绝不直接写 SwiftData。
5. 新实体 ID 由 App 生成并在 tool result 中返回；后续回合可读到同一 overlay，支持 read-after-write。
6. 模型 finalize 后，由 baseline→overlay 的确定性 diff 生成可审阅 draft 与影响摘要。
7. UI 展示 create/update/archive/delete/merge 数量及 before→after；破坏性影响使用原生 destructive confirmation。
8. 用户确认后，单一 store-scoped Coordinator 重新读取 fresh context，验证完整 CAS、身份、可见性、层级/循环/深度、root Category、Health、active work 与删除影响，再按确定顺序原子应用。任一条件失败则 0 写入、0 事件，保留预览并要求重新生成或复核。

## 验收契约

- 完整上下文保留所有可见 Category、Task、Checklist 和稳定 ID，不静默截断；同名 Task/Checklist 可通过稳定 ID 与完整路径无歧义引用。
- 已有 Category 被稳定 ID 命中时复用；新建 Category 的规范化名称唯一匹配现有项时复用，多个同名匹配返回歧义，不猜测也不重复创建 `a`。
- 所有 Create/Read/Update/Delete 都是结构化、严格校验、可预览的操作；Task Delete 仅归档。
- overlay 内 CRUD 支持 read-after-write；prompt-injection 形式的标题只能作为数据，不能成为工具指令。
- 更新、归档或删除在确认前展示明确影响；目标已变化、已删除、已归档或不存在时整批安全失败。
- 生成后任意被读取的工作区事实发生变化，确认必须以 stale error 拒绝整批，保留预览且不 dismiss。
- Category 层级循环、孤儿、本不允许的子 Category、跨类型 ID、保留 ID、重复 operation ID、冲突操作和 orphan local reference 都拒绝整批。
- Checklist rename/delete 只改变目标 item/visual revision；Task 元数据更新不旋转无关 Checklist revision。
- UI 在普通字号下清楚展示创建、更新、归档、删除/合并影响与 before→after；同名 Task 显示完整路径，Checklist 显示所属 Task。
- Request 页明确披露完整当前 Category/Task/Checklist 及必要文本会发送到已配置 endpoint，显示实体数，并说明密钥和时间历史不会发送。完整上下文无法序列化或超过供应商限制时，零请求、零写入并给出 counts/bytes 的可操作错误。
- Generate 阶段立即显示活动状态与 Stop；取消保留原请求，旧请求结果不能覆盖新请求。
- Preview 主按钮使用 `Apply N Changes`，不再使用 `Create`；含破坏性操作时用原生 destructive confirmation，Cancel 默认可用，破坏性 action 标红。
- stale/provider-tool incompatibility/invalid arguments 都显示可操作错误，保留 preview；绝不静默回退为旧的 create-only JSON。
- 真实付费 API 仅作为附加 smoke test；确定性 fake transport/fixture 和 command-boundary 行为测试是默认回归门禁。

## 测试先行清单

### 快照、协议与纯运行时

- `fullWorkspaceContextPreservesStableIDsAndDoesNotSilentlyTruncate`
- `stableIDsDisambiguateSameNamedTasksAndChecklistItems`
- `duplicateSameNamedCategoriesReturnAmbiguousInsteadOfChoosingOne`
- `uniqueNormalizedExistingCategoryIsReusedWithoutCreate`
- `unknownTombstonedCrossKindAndReservedIDsRejectWholePlan`
- `duplicateOperationIDsConflictingOperationsAndOrphanLocalRefsReject`
- `taskDeleteCompilesToArchiveAndNeverWritesDeletedAt`
- buffered 与 SSE fragmented multi-tool、choice index、reasoning passback、usage、畸形/未知/重复/结束原因测试
- overlay CRUD read-after-write、循环、孤儿与不允许的 child Category 测试

### 命令边界

- 混合 Category/Task/Checklist CRUD 在一次 atomic mutation 成功。
- 每个 CRUD checkpoint 注入失败都完整回滚。
- preview 后 Task/Category/assignment/checklist/visual/archive subtree/active work 任一变化都拒绝整批。
- preview 后新增同名 Category 必须重新预览，不能新建重复项。
- Checklist rename/delete 只触碰目标；Task metadata update 不旋转无关 Checklist revision。
- stale/invalid 批次不发布任何 mutation event。
- tombstone、内容冲突与 partial graph 不再触发旧的错误幂等成功。

### UI

- 预览显示 create/update/archive/delete/merge 数量和 before→after。
- 破坏性操作显示影响范围并要求原生 destructive confirm。
- stale error 保留预览，不自动 dismiss。
- 同名 Task 显示完整路径，Checklist 显示 Task 上下文。
- iPhone 普通字号：混合预览含复用 `a`、create/update/archive/delete 影响及 destructive confirmation；长路径可换行，交互目标至少 44pt。
- iPad 横屏普通字号：相同混合计划与长标题/路径，利用 regular width 展示差异且 split/collapse 状态一致。
- macOS 普通字号：可缩放 sheet/window、至少 28pt 控件、Esc cancel、仅安全时提供默认 Apply 快捷键；覆盖混合预览、确认与 stale conflict。

## 库与官方协议策略

- 已审计 [OpenAI function calling 官方指南](https://developers.openai.com/api/docs/guides/function-calling)、[DeepSeek Tool Calls 官方指南](https://api-docs.deepseek.com/guides/tool_calls/) 与 [DeepSeek Chat Completion API](https://api-docs.deepseek.com/api/create-chat-completion/)；实现按官方 OpenAI-compatible 消息与 tool-call roundtrip 约定。
- `MacPaw/OpenAI` 是成熟候选：MIT、约 2.9k stars、活跃发布，支持 tools、streaming、DeepSeek 宽松解析与 reasoning passback。其公开 transport 尚不能证明保留当前 ephemeral session、无 cookie/cache、same-origin redirect hardening、2 MiB response ceiling、取消优先和 SSE 失败语义，因此不直接替换现有 `LLMSecureHTTPTransport`。
- 官方 `modelcontextprotocol/swift-sdk` 达到质量门槛，但用途是 App 与外部 MCP client/server 的通信，不适合进程内私有 proposal overlay。
- Apple Swift OpenAPI Generator 也达到成熟度门槛，但供应商协议缺少适合本任务的稳定完整 OpenAPI 输入，引入会增加生成代码与适配层而不能解决本地 overlay/事务问题。
- 专用 Swift JSON Schema/Agent 候选没有达到用户要求的 1k stars 或成熟度/许可门槛，因此不采用。
- Apple FoundationModels 的 Tool/Generable/Evaluations API 只借鉴工具形状与 stub-tool 测试思路；其当前上下文限制与 OS 可用性不满足现有多平台、完整大上下文要求，不替换供应商路径。
- 当前决定：保留已经验证的安全 transport，依据官方协议补齐最小 DTO、tool delta assembler 与 overlay runtime；不为“使用库”牺牲现有安全边界。如果后续 spike 能证明成熟库可注入并复用现有 transport，再重新评估。
