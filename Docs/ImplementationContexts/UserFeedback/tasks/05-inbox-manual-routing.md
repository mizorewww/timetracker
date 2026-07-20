# 05：Inbox 人工归类实现记忆

> 本文件只保存实现、验证和子代理编排记忆，不是任务来源。范围与完成状态必须重新读取
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中唯一的 `[~]` 项。

## 当前阶段

- 审计 Inbox 条目、category、task、checklist 的数据模型和现有 LLM 建议落地路径。
- 优先复用同一个归类 command，确保人工选择与建议操作拥有一致的验证、持久化和错误行为。
- 在审计前不预设具体呈现形式；根据现有界面层级选择符合各平台惯例的短流程。

## 实现边界

- 人工入口必须覆盖归入 category、归入 task、作为 task checklist 三种目标。
- 选择目标前不修改数据；成功后 Inbox 条目只能被消费一次，失败时保留原条目。
- 排除不可用或会形成非法层级的目标，并处理目标在确认前被删除或归档的情况。
- iPhone 使用适合紧凑宽度的单一模态流程；iPadOS/macOS 保留上下文并支持指针、键盘选择。
- 不处理 `Docs/userfeedback.md` 中后续的选择器视觉统一、归档语义或详情编辑任务。

## 验收清单

- [ ] 盘点模型关系、持久化约束、LLM 建议 command 与 Inbox UI
- [ ] 建立人工归类 command 的领域测试和失败回滚测试
- [ ] 实现三种人工归类入口并复用既有选择组件
- [ ] 验证 iPhone、iPad、macOS 普通交互路径并截图
- [ ] 运行 `CONFIGURATION=Release scripts/build_install_all.sh`
- [ ] 核验安装版本与签名，释放 owned 设备、进程和临时产物
- [ ] 只在 `Docs/userfeedback.md` 标记完成并移除活动软链接

## 依赖策略

- 优先使用 SwiftUI、SwiftData 与项目现有选择器/command。
- 如确需第三方库，先核对维护状态、许可证、平台兼容性和至少 1k GitHub stars；
  没有明确收益则不新增依赖。

## 子代理编排

- 待分派：Inbox/LLM 建议落地与持久化路径审计。
- 待分派：现有任务/category/checklist 选择器与跨平台 UI 审计。
- 待分派：测试覆盖、边界条件与回归风险审计。
