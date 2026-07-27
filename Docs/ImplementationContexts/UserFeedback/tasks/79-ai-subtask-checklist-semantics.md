# 79：AI 子任务与 Checklist 语义区分实现记忆

状态：2026-07-27 实现中

> 本文件是主代理与子代理的实现、验证和编排记忆；唯一任务来源仍是
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 条目。

## 认领的反馈条目

- Time Tracker 的 AI 提示词需要稳定区分任务树中的子任务与任务内部的 checklist，
  避免模型把两种不同的结构混用。

## 初始范围

- 审计 AI workspace schema、系统/用户提示词、示例、结构化输出解析、校验与现有真实
  DeepSeek harness，找出歧义来自语义定义、示例、字段命名还是缺少验证。
- 先用行为测试锁定清晰规则：可独立规划/追踪时间的工作使用子任务；当前任务内部的
  原子完成步骤使用 checklist；不得用 checklist 模拟多层任务树。
- 优先加强现有 schema、few-shot 示例与 validation/retry 反馈，不复制第二套任务计划
  pipeline，也不在 View 层补救模型输出。
- 本任务不顺带更换模型供应商、重做整个 AI 设置页或改变非 AI 的手动任务编辑行为。

## 测试优先清单

- [x] 复现当前提示词/示例对“子任务与 checklist”边界表达不足的失败用例。
- [x] 结构化 workspace 计划明确编码两种语义，并拒绝/纠正明显混淆的输出。
- [x] 现有 DeepSeek harness 覆盖同时需要子任务与 checklist 的代表性请求。
- [x] 三套 AI 提示词公开预览、用户自定义指令与本地化文案保持一致且不泄露密钥。
- [ ] 完整测试、格式/本地化门禁、适当截图与 Release 全设备安装通过。

## Checkpoint 编排

- [x] A：完成架构、提示词、schema、harness、依赖与官方参考审计。
- [x] B：先补失败的行为/harness 测试，锁定子任务与 checklist 的可观察契约。
- [x] C：实现最小 prompt/schema/validation 改动，并补必要 UI 文案。
- [~] D：完成定向、全量、截图、Release 全设备安装与收口。

## 库策略

- 优先复用现有 Codable schema、原子 workspace mutation 与模型 provider abstraction；
  评估当前依赖和成熟的结构化输出/JSON Schema 能力后再决定是否需要新库。
- 新增依赖必须有清晰维护、许可证与隐私边界，一般不少于 1k GitHub stars；若原生
  Codable 与现有 pipeline 已足够，则明确记录不新增库的理由。

## 子代理编排

- 主代理负责范围、活动记忆、行为契约、集成、真实 harness、构建与提交。
- 可把现有提示词/schema 审计、测试覆盖审计与模型最佳实践审计拆成只读子任务；结论
  回写本文件，子代理不同时修改主代理正在处理的源文件。

## 进度记录

- 2026-07-27：认领任务并建立 `~79` 活动实现记忆，进入 Checkpoint A。
- 2026-07-27：三路只读子代理分别完成生产链/schema、测试/harness、官方文档/依赖/UI
  审计。结论一致：根因是生产 workspace 的固定 system contract 与工具描述在迁移时
  丢失了旧链路已有的计时语义，唯一 few-shot 又只有 checklist；不能用标题关键词或
  通用 JSON Schema 判断工作是否值得独立计时。
- 2026-07-27：核对 DeepSeek 官方
  [Thinking Mode](https://api-docs.deepseek.com/guides/thinking_mode)、
  [Tool Calls](https://api-docs.deepseek.com/guides/tool_calls)、
  [JSON Output](https://api-docs.deepseek.com/guides/json_mode/) 与
  [Chat Completion](https://api-docs.deepseek.com/api/create-chat-completion)。
  function description 与示例是当前正确控制面；strict 仍要求 beta endpoint 且只保证
  schema 形状，无法解决语义选择，因此不启用 strict、不新增第三方库。
- 2026-07-27：真实出站请求测试先产生 7 个失败，再覆盖 Inbox 固定契约、Task/
  Checklist create/update 描述与 finalize 自检的 5 个失败；补齐固定规则、mixed
  few-shot 和 exact-default 迁移后全部转绿。
- 2026-07-27：首次真实 DeepSeek `semantics` 场景暴露第二个 Task 使用目录外 SF
  Symbol，生产服务以 `invalidToolArguments` 中断。新增零写入可恢复 tool-result
  行为测试后，让同一会话纠正参数；真实场景随后通过，生成两个可独立计时子任务、
  五个精确归属 checklist，并经生产 coordinator 原子 Apply 后从 fresh context 重读。
- 2026-07-27：未新增库；复用 Foundation Codable/JSONSerialization、
  `OpenAIJSONValue`、既有 tool-call DTO/overlay/原子 coordinator。定向结果：
  `CoreLLMCompleteRequestTests` 9/9、`LLMSettingsTests` 35/35、
  `CoreAITaskWorkspaceTests` 8/8、真实 DeepSeek semantics 1/1。
- 2026-07-27：SwiftFormat 842 个 Swift 文件零格式问题，本地化 9/9 resource family
  parity 通过；最终完整 `make test` 为 1442/1442（162 suites）。
- 2026-07-27：iPhone 正常字号 UI 验收 1/1 通过（130.214 秒），确认默认提示词预览
  清晰区分 independently timed Task/child Task 与 untimed Checklist，固定契约公开可见。
  一次 iOS 27 Beta AX daemon 启动超时发生在 App 测试代码前，专用模拟器清理后重试
  通过。最终截图保存在
  `build/UITestScreenshots/task79-iOS-20260727-231156/`。
