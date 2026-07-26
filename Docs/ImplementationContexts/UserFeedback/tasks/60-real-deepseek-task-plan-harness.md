# 60：真实 DeepSeek 任务计划 Harness 与大计划验收实现记忆

状态：2026-07-26 进行中

用户已明确要求继续完成任务 60 后再停，不处理下一条反馈；Checkpoint D 已完成，
Checkpoint E 与提示词透明度/完整上下文收口尚未完成，反馈条目保持 `[~]`。

> 本文件是主代理与子代理的实现、验证和编排记忆；唯一任务来源仍是
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 条目。

## 用户纠正

- 先前把 fake transport 和直接构造 UI fixture 当成了 AI 自动生成任务的核心验收；
  这些只能证明客户端分支，不能证明真实模型、真实 tool-call 多轮、生产传输与 UI
  接线可用。
- 用户已在反馈源中明确提供真实 DeepSeek 凭据、`deepseek-v4-flash` 模型与指定提示词；
  未运行真实 API 就把相关条目标成 `[x]` 是错误的。
- 用户明确要求删除伪造 provider 响应和直接预造 plan 的测试，因为这些错误契约会把
  对真实模型行为的猜测固化成“绿色”；先前任务 43、51、54、59 的这类证据全部撤销。

## 当前唯一范围

- 重新领取以下相互依赖的反馈：
  1. 三条 AI 提示词与自动任务生成必须用反馈中指定的真实 DeepSeek API/模型测试；
  2. 指定提示词必须通过真实生产计划服务生成 `阅读 → 人工智能：现代方法 →
     Checklist 1...28`；
  3. 一个任务下 150 个 Checklist 必须通过真实模型调用、真实预览和真实 Apply，
     不得用本地构造 plan 代替。
- API key 只允许在本机进程内读取和使用；不得写入新增源码、测试产物、提交信息、
  截图或日志。
- 真实 API 验收必须使用隔离工作区，避免修改用户现有 iCloud/SwiftData 数据。
- 删除 fake transport、伪造 tool-call 响应、直接构造 plan 的 UI tests 与 App
  fixture；不再把这些内容作为默认回归门禁。
- 保留不伪造模型行为的持久化事务、原子回滚、安全 transport 与纯 UI 组件测试。

## 真实验收契约

- [x] 将 `inboxRouting`、`checklistVisual` 与 `taskPlan` 三条 catalog prompt
  分别送入对应的生产 service 和真实 DeepSeek；不以 request 编码或 provider
  fixture 代替模型结果。
- [x] 用生产 `LLMTaskWorkspacePlanningService` 和 hardened transport 调用官方
  DeepSeek endpoint；先记录真实失败，不预先假定协议兼容。
- [x] 使用反馈中的指定模型与指定 1...28 提示词，断言真实返回包含正确 Category、
  Task 和 28 个 Checklist 操作。
- [x] 使用真实模型请求一个 Task 下 150 个 Checklist，断言模型完成多轮 tool-call、
  Preview 完整到第 150 项并能够通过原子 Apply 写入隔离 store。
- [x] 至少一条普通字号 XCUITest 从真实输入页点击 Generate，等待真实网络结果，
  检查 token/CoT/raw output/Preview，再 Apply；fixture 不得预造计划。
- [ ] 若真实 API 失败，以完整、脱敏的 provider 状态/错误/回合信息定位并修复，
  不能改回 mock 输出或把失败写成通过。

## Checkpoint 编排

- [x] A：重新领取反馈、建立活动记忆、停止错误的完成/安装流程。
- [x] B：删除伪造 provider/plan 的 AI 测试与 fixture；加入 live API harness，
  运行指定 1...28 提示词并记录真实失败。
- [x] C：修复真实协议/提示词/模型兼容问题，以 live 1...28 + 150 计划为准。
- [x] D：真实 API 的隔离 UI Preview/Apply、截图与安全清理。
- [ ] E：默认回归门禁、Release 全设备安装、反馈收口与逐 checkpoint 提交。

## 已知安全边界

- 真实网络测试不得打印 Authorization header 或 API key。
- 真实响应可以保存在临时测试结果中，但不得包含用户真实 workspace；只用隔离的
  合成 Category/Task/Checklist 上下文。
- 供应商费用与延迟是本任务验收的正常成本；不得再用伪造 provider 响应来替代。

## Checkpoint B 进度

- 已删除基于伪造 provider/tool-call 返回的计划服务测试、流式测试与 workspace
  planning 测试。
- 已删除四条直接注入预制 plan 的 XCUITest、对应 App 启动参数、预制 plan
  生成器和旧版未接线的 flat-JSON 计划 UI。
- 已删除旧版 `AITaskPlanDraft` Apply 流水线的预制 plan 测试；仍保留 workspace
  command 的原子事务/回滚测试和 transport 安全边界测试，因为它们不伪造模型
  结果，也不作为真实 API 验收。
- `make format-check` 通过；`make test` 连续两次均完成 1,407 条测试并仅有两个与
  本次 AI 删除无关的既有失败：
  `PreferenceSyncBehaviorTests.checklistCompletionMovesOnlyTheTargetToTheDestinationGroupEnd`
  与
  `TaskPersistencePolicyTests.archiveCommandPreservesTheOriginalArchiveTimestamp`。
  本 checkpoint 不修改它们来伪造绿色。
- 已加入 opt-in `make test-llm-live`：从
  `TIMETRACKER_LIVE_LLM_API_KEY` 或仓库根目录本地 `.env` 读取凭据，不再从反馈
  文档提取 key；Xcode 隔离测试进程使用完桥接文件后由 Makefile 清理。
- 2026-07-26 使用新 key 从 `.env` 运行真实 `prompt28`，请求实际到达 DeepSeek；
  供应商返回 HTTP 400：
  `invalid_request_error: Thinking mode does not support this tool_choice`。
  该结果是真实协议失败，不算业务验收通过。
- 用户已澄清“完成后停止”指完成整个任务 60；当前继续修复该 400，任务 60 完成后
  才停止，不处理下一条反馈。

## Checkpoint C 进度

- 对照 DeepSeek V4 官方 thinking-mode tool-call 契约，`deepseek-v4-flash/pro`
  请求现在显式发送 `thinking.enabled` 与 `reasoning_effort=high`，不再发送 thinking
  模式拒绝的 `tool_choice`，也不发送无效的 `temperature`。
- assistant 工具调用历史始终包含非空缺的 `content` 字段并完整回传
  `reasoning_content`；允许 DeepSeek 合法地同时返回可见 `content` 和
  `tool_calls`。
- 2026-07-26 真实 `prompt28` 首次通过：30.493 秒内生成唯一 `阅读` Category、
  唯一 `人工智能：现代方法` Task 与按序 1...28 的 28 个 Checklist；生产
  hardened transport、真实 DeepSeek、真实工具 overlay 与真实响应内容全部参与。
- 同一真实 `prompt28` 在加入 CoT 非空断言后再次通过（34.695 秒），确认不是只验证
  最终结构，还实际收到 reasoning 与 raw provider response。
- 2026-07-26 真实 `prompt150` 通过（127.055 秒）：模型通过至少 153 次工具调用
  生成唯一 Category、唯一 Task 与按序 1...150 的 Checklist；随后使用生产
  `StoreScopedAITaskAtomicMutationCoordinator` 将计划 Apply 到独立的内存
  SwiftData store，并重新读取确认 150 条全部持久化。测试同时确认 reasoning
  非空、raw provider response 存在，全程未注入 provider 或预造 plan。
- 2026-07-26 `prompts` 真实场景通过：`checklistVisual` 用生产 service 在
  2.220 秒返回目录内 SF Symbol、允许色和非空理由；`inboxRouting` 用生产
  service 在 3.317 秒把明确的“读第 3 章”路由到现有阅读任务的 Checklist，
  并返回目录内 symbol、允许色与模型 ID。两条调用都直接使用当前
  `LLMPromptKind` 默认可编辑说明和 fixed response contract，不检查本地构造的
  假响应。

## Checkpoint D 进度

- 加入普通字号、空内存 SwiftData workspace 的 iPhone live UI gate：测试进程只
  通过环境配置 endpoint/model/key，App 使用内存 credential store；生成器仍直接
  构造生产 `LLMTaskWorkspacePlanningService`，没有 provider/plan fixture。
- 首次真实 UI 运行完整进入生产 Generate，最终 accessibility hierarchy 已到真实
  Preview（可见 Change Request），但 XCTest 没捕捉到短暂的 token 行并按契约失败；
  这不是 API 失败。根因是同一 MainActor turn 内从最后一次真实 `onProgress` 立即
  切到 Preview，SwiftUI 可能来不及提交 token 状态。
- 正在修复为：首次真实 token progress 至少显示 2 秒再切换 Preview。显示值仍来自
  provider usage/真实响应字符数，不伪造 token，也不延迟网络调用。
- 真实 UI 门禁第五次运行通过（测试本体 223.504 秒）：从输入页键入反馈指定
  prompt28，点击生产 Generate，截图捕获约 437 个真实输出 token；随后进入含 30
  项 create 的 Preview，滚动确认第 28 章，展开并截图真实 reasoning 与 raw provider
  response，再点击 Apply 并进入标题为“人工智能：现代方法”的真实任务详情。
- 通过结果保存在
  `build/LiveLLMUIHarness/LiveLLMUI-20260726-212051.xcresult`，导出的 6 张普通字号
  iPhone 截图位于
  `build/LiveLLMUIHarness/exported-20260726-212051/`。截图未包含 API key。
- 运行使用 `--uitesting` 的内存 SwiftData container 与内存 credential store，
  没有接触用户 iCloud/生产 store；Make trap 已终止 App、关闭并删除本轮明确拥有的
  simulator `B29AE3FF-78E2-4B83-B27D-29D52B7E85D9`，资源审计未发现残留 runner、
  xcodebuild 或 Booted device。
- 截图验收发现 confirmation toolbar 的 “Apply 30 Changes” 挤压了居中标题；按 HIG
  改成视觉上简洁的 “Apply”，完整变更数量保留在 accessibility label。生成区的
  identifier 也移到系统 `ProgressView`，让 token 文本保持独立可读。
- 本 checkpoint 没有新依赖；继续复用 SwiftUI 原生 Form/List/DisclosureGroup、
  Foundation URLSession/SwiftData/XCTest，以及项目现有 MarkdownView。

## 提示词透明度 Checkpoint 进度

- 三个默认可编辑提示词都加入了 typed worked example：Inbox routing 与 Checklist
  visual 给出实际输入/严格 JSON 输出；Task plan 给出使用现有 UUID 连续创建三条
  checklist tool call、再 `finalize_plan` 的完整顺序，不再只靠 zero-shot 规则。
- 精确等于上一版默认值的已同步偏好会迁移到新 few-shot 默认；只要用户曾增加或修改
  一个字符就保持原样，避免覆盖个人定制。
- 三个提示词编辑器新增“实际发送给服务商的请求”Markdown 披露，内容直接复用生产
  temperature/reasoning 常量、实际 SF Symbol/颜色计数与
  `AITaskWorkspaceToolName.allCases`，列出 HTTP envelope、runtime user JSON、
  response format、thinking/reasoning/tool_choice 分支、全部 15 个工具，并直接
  pretty-print 生产 `toolDefinitions` 的完整 JSON Schema；披露没有另写一份易漂移
  的 schema。
- 披露明确 API key 只从 Keychain 写入 Authorization header，不进入 prompt、
  workspace JSON、工具参数或工具结果；编辑器仍使用现有 MarkdownView，没有新依赖。
- scoped SwiftFormat 与三语 localization parity 通过。`make test` 完成编译并运行
  1,421 项：本 checkpoint 新增的三个提示词/迁移/披露行为测试全部通过；总计
  1,418 项通过，仍有三个不在本改动路径的失败：
  `CoreLLMResponseTransportTests.nonSuccessStatusTakesPriorityOverDeclaredBodySize`、
  `PreferenceSyncBehaviorTests.checklistCompletionMovesOnlyTheTargetToTheDestinationGroupEnd`
  与
  `TaskPersistencePolicyTests.archiveCommandPreservesTheOriginalArchiveTimestamp`。
  加入生产 tool schema 披露后第二次完整运行仍为相同三项失败，新增测试继续通过；
  本任务不修改这些断言来制造全绿。

## 完整请求上下文 Checkpoint 进度

- 删除两组以人工 48 候选、12 KiB candidate JSON、24 KiB prompt、64 KiB request body
  为正确答案的 budget 测试；没有再注入任何预制 provider response。
- 新的 request-serialization 行为测试通过 production service 与 capture transport
  检查实际 HTTP request：Inbox 完整序列化 120 个 Task、40 个 Category 和完整
  Unicode 字段；Inbox/checklist/task-plan 都发送与 picker 相同的完整规范
  SF Symbols 目录，并确认 request body 可以超过旧 64 KiB 而不丢最后一项。
- `TimeTrackerStore` 不再用本机 Quick Start/频率启发式替模型删除候选；
  Task/Category 只规范化、去重、确定性排序后全部发送。三条生产 service 和旧兼容
  service 都移除了人工字段/prompt/body 截断。
- model ID 继续使用真实 256-byte 同步 compact-field 边界，但作为 opaque ID 必须
  整体通过，不会截断为另一个服务端 ID；endpoint/API key、2 MiB response 和
  512-byte reason 持久化边界保留。API key 仍只在 Authorization header。
- 三个可编辑提示词改为按既有 `PreferenceJSON` 编码后的 256 KiB 同步偏好边界
  验证，不再额外套 4 KiB 请求限制。
- 继续复用 Foundation `JSONEncoder`、`URLRequest` 和项目已有 `SymbolCatalog`，
  没有引入新依赖。
- `make format-check` 通过（829 个文件、0 个格式问题），三语
  `make localization-check` 通过（每种语言 1,275 keys），`git diff --check`
  通过。
- `make test` 编译并运行 1,412 项；本 checkpoint 新增的完整请求测试全部通过，
  总结果仍只有三个不在本改动路径的既有失败：
  `CoreLLMResponseTransportTests.nonSuccessStatusTakesPriorityOverDeclaredBodySize`、
  `PreferenceSyncBehaviorTests.checklistCompletionMovesOnlyTheTargetToTheDestinationGroupEnd`
  与
  `TaskPersistencePolicyTests.archiveCommandPreservesTheOriginalArchiveTimestamp`。
  本任务不修改这些断言来制造全绿。
