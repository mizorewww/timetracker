# 13：重复任务与简单任务量任务实现记忆

> 本文件只保存实现、验证和子代理编排记忆，不是任务来源。范围与完成状态必须重新读取
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中唯一的 `[~]` 项。

## 当前阶段

- [~] 领取反馈并建立活动链接。
- [ ] 完整读取 Apple HIG 与 SwiftUI 强制技能，审计现有 recurrence/quantity 模型和 UI。
- [ ] 锁定“每天 50 个俯卧撑”父任务自动生成每日任务量子任务的产品语义。
- [ ] 分小 checkpoint 实现创建、编辑、物化、完成记录与持久化。
- [ ] 完成相关回归、owned 模拟器交互和 simulator-only 截图验收。
- [ ] 执行 `CONFIGURATION=Release scripts/build_install_all.sh`，清理资源并由 Codex 标记完成。

## 唯一反馈边界

- 用户可以创建重复任务。
- 用户可以创建简单任务量任务。
- 真实案例必须成立：父任务“每天做 50 个俯卧撑”能自动生成每天的子任务，子任务是目标量为
  50 个俯卧撑的任务量任务。
- 不领取或实现本条之后的任何反馈。

## 初始约束

- 复用仓库现有 `TaskRecurrenceRule`、`TaskQuantityGoal`、`TaskQuantityEntry` 与命令/仓储能力；先审计，
  不平行造第二套模型。
- 使用 `apple-hig` 和 `swiftui-expert-skill`；普通字号、普通创建/编辑路径和平台惯例优先。
- 优先 Apple 框架与成熟库；新增 GitHub 依赖一般要求至少 1k stars，并核对维护、许可证与平台支持。
- 所有 UI 操作和截图只使用 owned 模拟器；物理设备仅执行最终 Release 安装，不启动、不操作、不截图。
- 每个小 checkpoint 验证并提交；只暂存当前任务文件，保护 `Docs/userfeedback.md` 末尾用户追加反馈。

## 子代理编排

- [ ] 现有 recurrence 数据模型、物化生命周期与测试审计
- [ ] quantity 数据模型、创建/编辑/记录入口与测试审计
- [ ] Apple HIG / SwiftUI UI 流程、成熟库与验收矩阵审计

## Checkpoint 记录

- [~] 当前 checkpoint：领取反馈并建立实现记忆与活动链接。
