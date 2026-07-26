# 59：Inbox AI 完整上下文与任务增删改查实现记忆

状态：进行中  
反馈来源：`Docs/userfeedback.md` 中 Inbox AI 无法复用已有 Category、需要完整上下文并把增删改查作为工具调用的子项。

## 当前阶段

- [x] 按文档顺序领取反馈并建立可恢复的活动记忆。
- [~] 审计现有 Inbox AI 输入、提示词、流式协议、计划预览、命令边界和持久化测试。
- [ ] 先定义完整任务树上下文、稳定身份和 CRUD 工具调用的行为契约与失败测试。
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

- [~] Checkpoint A：领取、现状/历史/测试/库审计、行为契约。
- [ ] Checkpoint B：失败测试、结构化工具协议和安全命令执行。
- [ ] Checkpoint C：UI 预览/确认、回归验证、文档与小提交。
- [ ] Checkpoint D：跨平台验收、Release 全设备安装和反馈收口。

## 子代理编排

- [ ] AI 协议与安全审计：上下文序列化、模型响应、tool-call/streaming 与注入边界。
- [ ] 命令/持久化审计：现有 task/category/checklist 命令、事务与测试缺口。
- [ ] UI/历史/库审计：Inbox 生成流程、回归历史、Apple 原生与成熟库适用性。

## 资源所有权

- 主代理统一拥有后续 Xcode build/test、设备和模拟器批次。
- 子代理当前只做只读审计，不创建模拟器、不运行 Xcode、不修改共享文件。

## 待确认的验收契约

- 已有 Category 被名称或稳定引用命中时，生成结果复用其身份，不创建重复 Category。
- Create/Read/Update/Delete 都有结构化、可验证、可预览的目标和参数。
- 更新或删除必须在用户确认前展示明确影响；目标已变化或不存在时安全失败。
- 模型看到完整当前任务树、Checklist 与必要元数据，同时不暴露本地密钥或无关隐私数据。
- 真实 API 可做附加 smoke test；确定性 fake transport / fixture 才是默认回归门禁。

## 库策略

- 待审计。优先现有 Codable、Swift Concurrency、SwiftData 命令层和当前流式解析器。
