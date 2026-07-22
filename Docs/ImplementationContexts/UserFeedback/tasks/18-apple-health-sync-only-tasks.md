# 18：Apple Health 任务仅同步实现记忆

> 本文件只用于主代理与子代理的实现、验证和编排记忆，不是任务来源。唯一范围与状态必须重新读取
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 条目。

## 当前阶段

- [x] 读取唯一反馈并领取任务。
- [ ] 审计 workout/睡眠任务的创建、Quick Start、任务选择器、详情页和计时入口。
- [ ] 参考 HealthKit、Apple Fitness 与 Apple HIG，确定仅同步产品语义及成熟库边界。
- [ ] 实现并验证 workout/睡眠任务不能由 Time Tracker 启动计时，只能由 Apple Health 同步。
- [ ] 使用 owned 模拟器完成普通交互与截图验收并清理资源。
- [ ] 执行 `CONFIGURATION=Release scripts/build_install_all.sh` 并由 Codex 标记完成。

## 唯一反馈边界

- Quick Start 不应允许开始 workout。
- Workout 应由 Apple 的健身 App 开始，并在 Time Tracker 中只作为 Apple Health 同步数据展示。
- 睡眠同样只允许从 Apple Health 同步，不允许在 Time Tracker 内主动计时。
- 不领取或实现后续 AI 提示词、Health 任务自动展示、Inbox 等反馈。

## 强制约束

- 先审计仓库现有实现和历史提交；若产品修复已完整存在，只补真实缺失的契约与验收，不重复造逻辑。
- 仅同步约束必须位于领域能力/动作边界，并覆盖 Quick Start、任务选择器、任务详情及其他启动入口，不能只隐藏一个按钮。
- HealthKit 数据读取与普通用户计时持久化语义不得混淆；不得为完成本任务写入伪造健康样本。
- 优先系统 HealthKit、SwiftUI 与仓库现有成熟依赖；一般拒绝 GitHub 低于 1k stars 的非用户指定库。
- UI 操作与截图只使用 owned 模拟器；物理 iPhone/iPad 只做最终 Release 安装和只读核验，不启动、不操作、不截图。
- 每个小 checkpoint 验证后提交；只暂存本任务状态差异，保护 `Docs/userfeedback.md` 中用户新增内容。

## 待审计问题

- Apple Health 特殊任务如何被识别：稳定来源字段、保留 task ID、category，还是展示层名称判断。
- 所有开始计时入口是否统一依赖同一个 capability/policy，还是 Quick Start、任务选择器、详情页各自判断。
- 既有 HealthKit workout/sleep 导入是否已建立只读任务，是否还可能被 pin 到 Quick Start 或经深链/恢复状态启动。
- Watch、Live Activity、快捷操作等外围入口是否需要沿用相同 fail-closed 规则。

## 资源所有权

- 尚未创建或启动本任务模拟器；后续必须记录 owned UDID、结果包、截图路径与完整清理结果。
- 既有 `AnalyticsReview-iPhone17Pro`（`E831B715-747C-478F-B8EE-539C48952444`）为 Shutdown 且不属于本任务，
  不得启动、关闭或删除。
