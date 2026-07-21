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
- 关闭数量目标属于破坏性操作：保存命令必须收到一次性明确确认；确认不会写入 recovery payload，
  autosave 成功后立即消费，重新开启后再次关闭必须重新确认。
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
- 数量 entry 的并发 baseline 使用固定大小、顺序无关的确定性 revision，不把全部 entry UUID 写进恢复文件；
  只有会清空 entry 的删除/复活路径比较该 revision，纯标题或目标值编辑不被并发记录阻塞。
- 已删除 goal 的显式重新开启复用同一确定性 ID，并以用户此次恢复操作覆盖旧 tombstone；若编辑器打开后
  出现新的有效 entry，则 revision 校验先失败，不会静默清除迟到进度。

## 验收矩阵

- 聚焦单元测试：policy 边界、draft/recovery/stale、原子创建与注入失败回滚、暂停恢复、数量累计/超额/
  清空、父拒绝记录与子接受记录。
- UI 测试：真实创建入口；简单数量任务；每日 50 个俯卧撑；非法输入 Save 禁用；重启同日幂等。
- simulator-only 截图：紧凑 iPhone + 常规 iPad，各覆盖创建配置、保存后父子与日期、记录 20 后进度。

## Checkpoint 记录

- [x] `5460714`：领取反馈并建立实现记忆与活动链接。
- [x] draft/baseline 与原子完整任务图：
  - `TaskEditorDraft`、恢复编码和 stale baseline 已接入 quantity goal、daily recurrence 与固定大小
    quantity-entry revision；旧 schema-1 恢复 JSON 继续可读。
  - 新建可在一次事务中保存父任务、模板 goal、rule、当天子任务、子 goal 与 occurrence；任意 checkpoint
    注入失败均整图回滚；proposed task ID 重试保持单一完整图。
  - 简单任务量、暂停规则持久化、并发 goal/rule/entry、partial claim、单位规范化、删除确认、恢复确认
    one-shot、创建/更新/恢复回滚与三语错误文案均已覆盖。
  - macOS 签名单元测试 60 项通过；未启动模拟器或物理设备。依赖仅用 Foundation、CryptoKit、
    SwiftData 与 SwiftUI，没有新增第三方库。
- [x] store-scoped quantity entry 命令与进度聚合：
  - 新增原子 record/update/delete 命令；基于 fresh context 校验任务、祖先、重复模板、goal/entry
    baseline、幂等 identity 与 LWW mutation，注入失败完整回滚。
  - 普通任务量任务和已物化的每日子任务允许记录；重复父模板、暂停模板、归档/删除分支与
    Apple Health sync-only 任务拒绝记录；历史 entry 即使任务之后归档仍可删除。
  - 进度完全由有效 entry 派生，安全累计并保留超额，remaining 下限为 0、fraction 限制为 0...1，
    不写回旧 `statusRaw`。
  - 同步恢复与本地写入共享 1900-01-01（含）到 2201-01-01（不含）的持久化日期契约；三语错误
    文案已补齐。
  - `TaskStore` 对不完整 quantity graph fail-closed；任务局部刷新会完整重读 quantity 小图，避免
    noncanonical goal 跨任务关系在局部刷新后丢失错误信号。该路径存在双 O(N) 性能债，但当前以
    正确性优先。
  - macOS 签名聚焦测试 18 项、相关 recurrence/draft/snapshot/preflight/heatmap/localization/layout
    回归 68 项通过；`plutil` 与 `git diff --check` 通过。未启动模拟器或物理设备。依赖仅使用
    Foundation、SwiftData 与仓库现有基础设施，没有新增第三方库。
- [x] 共享编辑器数量与每日重复配置：
  - 新建与现有任务共用原生 SwiftUI `Toggle`、`LabeledContent` 和 `TextField`；目标/单位加入共享
    FocusState，保存、取消和滚动收键盘路径保持一致。
  - 有数量记录后锁定单位但仍允许调整目标；不完整同步图禁用修改并显示行内错误，不能把 nil 误判为
    “零条记录”。
  - 关闭已有 quantity goal 必须经过破坏性确认；恢复文件刻意丢弃的一次性权限可以由用户重新确认，
    新建 goal 无法伪造清空权限。
  - 当天生成任务隐藏重复开关并指回父模板；普通任务正有 Timer/Pomodoro 时先要求停止，已有模板仍可
    暂停/恢复。
  - 英文、简中、繁中已补齐；31 项 quantity/editor/UI contract 测试与 48 项 editor/draft/recovery
    回归通过，三语 plist、focused source layout 与 diff 检查通过。只运行签名 macOS 测试宿主，未启动
    模拟器或物理设备；没有新增第三方库。
- [x] 任务详情数量汇总、进度记录和历史编辑：
  - 详情只读取同一次 canonical 校验生成的 value snapshot；进度与历史不会分别读取 SwiftData 对象，
    tombstone 被过滤，历史按记录时间和稳定 UUID 排序。
  - 普通任务与生成子任务可新增、编辑、删除数量记录；Sheet 捕获打开瞬间的 goal/entry baseline 和稳定
    operation ID，失败保留现场，保存前先 flush 详情草稿并清理焦点。
  - 父模板显示说明但不提供新增入口；已有记录的普通任务迁移为模板后，历史仍可查看但不伪装成可编辑。
    occurrence-only CloudKit 分阶段图会记录 incomplete recurrence claim，父/子均 fail-closed，不会短暂露出
    可录入入口。
  - 生成子任务按规则保存的时区解析并显示 occurrence 日期；Kiritimati、Adak 与非法日期/时区均有测试。
  - 英文、简中、繁中本地化和原生 `ProgressView`、`Form`、`TextField`、`DatePicker` 已接入；视图自有
    `@State` / `@FocusState` 保持 private。
  - 86 项 quantity/detail/recurrence/task UI/localization/layout 聚焦测试通过，generic iOS Simulator Debug
    编译通过；未启动模拟器或物理设备。没有新增第三方库。
- [~] 当前 checkpoint：补任务列表中的模板/生成角色与数量进度、修正重复开关页脚状态，并加入真实创建
  路径的 iPhone/iPad 模拟器验收。
