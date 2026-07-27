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

- [~] 复现当前提示词/示例对“子任务与 checklist”边界表达不足的失败用例。
- [ ] 结构化 workspace 计划明确编码两种语义，并拒绝/纠正明显混淆的输出。
- [ ] 现有 DeepSeek harness 覆盖同时需要子任务与 checklist 的代表性请求。
- [ ] 三套 AI 提示词公开预览、用户自定义指令与本地化文案保持一致且不泄露密钥。
- [ ] 完整测试、格式/本地化门禁、适当截图与 Release 全设备安装通过。

## Checkpoint 编排

- [~] A：完成架构、提示词、schema、harness、依赖与官方参考审计。
- [ ] B：先补失败的行为/harness 测试，锁定子任务与 checklist 的可观察契约。
- [ ] C：实现最小 prompt/schema/validation 改动，并补必要 UI 文案。
- [ ] D：完成定向、全量、截图、Release 全设备安装与收口。

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
