# 60：真实 DeepSeek 任务计划 Harness 与大计划验收实现记忆

状态：2026-07-26 进行中

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

- [ ] 用生产 `LLMTaskWorkspacePlanningService` 和 hardened transport 调用官方
  DeepSeek endpoint；先记录真实失败，不预先假定协议兼容。
- [ ] 使用反馈中的指定模型与指定 1...28 提示词，断言真实返回包含正确 Category、
  Task 和 28 个 Checklist 操作。
- [ ] 使用真实模型请求一个 Task 下 150 个 Checklist，断言模型完成多轮 tool-call、
  Preview 完整到第 150 项并能够通过原子 Apply 写入隔离 store。
- [ ] 至少一条普通字号 XCUITest 从真实输入页点击 Generate，等待真实网络结果，
  检查 token/CoT/raw output/Preview，再 Apply；fixture 不得预造计划。
- [ ] 若真实 API 失败，以完整、脱敏的 provider 状态/错误/回合信息定位并修复，
  不能改回 mock 输出或把失败写成通过。

## Checkpoint 编排

- [x] A：重新领取反馈、建立活动记忆、停止错误的完成/安装流程。
- [~] B：删除伪造 provider/plan 的 AI 测试与 fixture；加入 live API harness，
  运行指定 1...28 提示词并记录真实失败。
- [ ] C：修复真实协议/提示词/模型兼容问题，以 live 1...28 + 150 计划为准。
- [ ] D：真实 API 的隔离 UI Preview/Apply、截图与安全清理。
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
- 下一步：提交 mock 删除，随后加入只接受真实凭据的 live harness。
