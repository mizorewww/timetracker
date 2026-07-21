# 13：重复任务与简单任务量任务实现记忆

> 本文件只保存实现、验证和子代理编排记忆，不是任务来源。范围与完成状态必须重新读取
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中唯一的 `[~]` 项。

## 当前阶段

- [x] 领取反馈并建立活动链接。
- [x] 完整读取 Apple HIG 与 SwiftUI 强制技能，审计现有 recurrence/quantity 模型和 UI。
- [x] 锁定“每天 50 个俯卧撑”父任务自动生成每日任务量子任务的产品语义。
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

- [x] recurrence 审计：底层 daily rule、确定性 occurrence/generated task、当天物化、暂停恢复、
  CloudKit partial/tombstone 防复活与数量目标复制都已存在；生产代码没有任何创建调用。
- [x] quantity 审计：goal/entry、同步快照和热力图读取已存在；用户侧 goal/entry 写命令、进度聚合、
  编辑器与详情入口全部缺失。
- [x] UI / 库审计：复用共享 `TaskEditorSections`，采用原生 Toggle、数字 TextField、DatePicker、
  ProgressView 与 Button；普通字号在 iPhone/iPad 模拟器验收。

## 审计结论与实现决策

### 复用而不重造

- 保留现有 `TaskRecurrenceRule`、`TaskRecurrenceOccurrence`、`TaskQuantityGoal`、
  `TaskQuantityEntry` 和确定性 ID，不增加第二套领域模型。
- “每日一次”的日历运算采用 Apple Foundation `Calendar` / `TimeZone`；目标平台已原生提供
  `Calendar.RecurrenceRule`，当前反馈不扩张到周/月/RRULE，也不引入第三方 recurrence 包。
- UI 使用 SwiftUI 标准控件，持久化继续使用 SwiftData 与现有 store-scoped transaction；
  BlossomColorPicker、MarkdownView 与本功能无关，不为凑依赖强行使用。

### 已锁定的产品语义

- 普通任务量任务：开启数量目标、关闭每日重复；进度由有效 entry 累加派生，达到或超过目标即完成，
  不写回废弃的 `TaskNode.statusRaw == completed`。
- 每日任务量任务：父任务是 blueprint/container，不允许直接记录工作；按规则时区在 App 可运行的安全点
  只生成当前日子任务，不补离线历史。子任务复制生成当时的目标数量和单位，之后独立编辑。
- 新建“每天做 50 个俯卧撑”必须在同一个 store lock + atomic mutation 中保存父 TaskNode、模板 goal、
  rule、当天 occurrence、当天子 TaskNode 与子 goal；禁止 SwiftUI 串行调用多个 facade Bool API。
- 已创建规则的开始日期和时区保持底层 immutable 约束；编辑器只允许暂停/恢复。暂停期间不补任务，
  恢复时只生成当天。
- 关闭数量目标会同时软删除当前有效 entries，重新开启从零开始，避免旧进度意外复现。
- 已有进度时单位不可静默改写；提供明确的清空进度路径后再改单位。目标值可以调整，超额累计保留。
- 生成子任务持久化标题继续与模板一致；通过 occurrence day read model 在界面显示本地化日期，避免多天
  同名子任务无法辨认。

### 实现 checkpoints

1. Draft/validation/baseline 加入可选 quantity goal 与 daily recurrence，并把 goal + rule + 当天实例化
   接入任务保存的同一原子事务；覆盖旧 recovery JSON、并发 stale 与全图回滚。
2. 增加 store-scoped quantity entry 命令、进度聚合、记录/清空语义与聚焦测试。
3. 接入共享编辑器和详情页，补英文/简中/繁中本地化、日期元数据和 UI contract tests。
4. 只用 owned iPhone/iPad 模拟器走真实创建入口，验收创建配置、父子层级/日期、20/50 进度并截图；
   每批终止 App、删除 owned 模拟器和临时产物。
5. 运行聚焦回归和精确 Release 全设备安装；物理设备不启动、不操作、不截图。

### 风险与必须验证

- 模板 goal 必须先于当天 materialization 写入同一事务，否则同日确定性 claim 会永久留下无 goal 子任务。
- 已暂停规则恢复必须使用 fresh `TaskRecurrenceRuleMutationBaseline` 调用 enable mutation，不能重放 create。
- 非法目标/单位/日期/时区必须在首个持久化步骤前失败，不能留下半图。
- 父模板修改目标只影响未来新实例；历史子任务和用户修改不得被 materialization replay 覆盖。
- App 在 iOS 被系统挂起时不承诺午夜后台准点执行；返回前台后生成当日实例。

## 验收矩阵

- 聚焦单元测试：policy 边界、draft/recovery/stale、原子创建与注入失败回滚、暂停恢复、数量累计/超额/
  清空、父拒绝记录与子接受记录。
- UI 测试：真实创建入口；简单数量任务；每日 50 个俯卧撑；非法输入 Save 禁用；重启同日幂等。
- simulator-only 截图：紧凑 iPhone + 常规 iPad，各覆盖创建配置、保存后父子与日期、记录 20 后进度。

## Checkpoint 记录

- [x] `5460714`：领取反馈并建立实现记忆与活动链接。
- [~] 当前 checkpoint：实现 draft/baseline 与原子保存完整任务图。
