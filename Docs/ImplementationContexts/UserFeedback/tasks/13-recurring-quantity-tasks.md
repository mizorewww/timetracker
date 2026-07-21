# 13：重复任务与简单任务量任务实现记忆

> 本文件只保存实现、验证和子代理编排记忆，不是任务来源。范围与完成状态必须重新读取
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应反馈项；该项现已完成并标记为 `[x]`。

## 当前阶段

- [x] 领取反馈并建立活动链接。
- [x] 完整读取 Apple HIG 与 SwiftUI 强制技能，审计现有 recurrence/quantity 模型和 UI。
- [x] 锁定“每天 50 个俯卧撑”父任务自动生成每日任务量子任务的产品语义。
- [x] 分小 checkpoint 实现创建、编辑、物化、完成记录与持久化。
- [x] 完成相关回归、owned 模拟器交互和 simulator-only 截图验收。
- [x] 执行 `CONFIGURATION=Release scripts/build_install_all.sh`，清理资源并由 Codex 标记完成。

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
- simulator-only 截图：紧凑 iPhone 覆盖创建配置、保存后父子与日期、记录 20 后进度；常规 iPad
  覆盖保存后的父子列表、模板详情和记录 20 后进度。iPad 编辑器因 iOS 27 浮动数字键盘会残留视觉
  伪影，不把带键盘的画面冒充最终截图。

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
- [x] 任务列表角色、数量进度、重复页脚与真实创建路径验收：
  - 列表先构造一次 `TaskManagementRowSupplementProjection`，批量生成 recurrence role 与 quantity
    progress，再把 value supplement 传给每一行；不再由每个普通/重复任务行各自扫描全部 goal/entry 历史。
  - quantity 批量索引先在全局执行 LWW 去重，再按 taskID / deterministic goalID 双向 claim 建桶；跨任务
    goal/entry、winner tombstone 与 incomplete participant 均 fail-closed，不会让旧 loser 在局部桶中复活。
  - recurrence role 保留 incomplete template/generated 的泛化身份；合法 occurrence 依据其保存的时区将
    当日显示为 `Today’s Task`，历史 occurrence 显示本地化日期。canonical occurrence 校验与日期格式集中到
    `TaskRecurrenceOccurrenceSnapshot`，列表和详情共用。
  - 列表和 VoiceOver 同时展示 `Daily Template` / `Today’s Task` / 历史生成日期及 `20 / 50 reps`；移除会
    覆盖子控件 identifier 的 Section 容器标识。重复开关 footer 明确覆盖 off、paused、enabled、quantity、
    generated 与 active-work-blocked；任务编辑器和数量记录 Sheet 都有原生数字键盘 `Done`。
  - macOS 签名聚焦测试 20 项通过，新增 3 项批量投影/LWW 测试与 1 项 footer policy 测试；三语 key 对齐、
    `plutil`、diff 检查通过，generic iOS Simulator `build-for-testing` 成功。source-layout 与 primary-UI
    layout 通过；全目录 layout 仍只报告未由本任务修改的既存超限文件：`TimeTrackerStore.swift` 264/250、
    `TimeTrackerStore+AppleHealthTimeline.swift` 297/250、`TaskEditorSession.swift` 210/180、
    `TaskDetailAnalyticsViews.swift` 189/180。本 checkpoint 自有受限文件均在预算内。
  - 一次额外的 generic iphoneos 诊断命令强制覆盖 `CODE_SIGN_STYLE=Automatic`，与项目已手动指定的
    `TimeTracker HealthKit Development` profile 冲突而在 provisioning 阶段失败；没有修改签名设置，也不是
    编译错误。最终设备签名只由下一 checkpoint 的仓库精确 Release 安装脚本验证。
  - 最终冻结代码重新在 owned iPhone 17 Pro 与 iPad Pro 13-inch (M5) 模拟器各通过完整真实创建流程；
    iPhone 4 张、iPad 3 张 simulator-only 截图逐张检查。两份 iOS 27 xcresult 各保留 1 条精确发生在 XCTest
    `Synthesize event` 点击 quantity target 时的 `Invalid frame dimension` runtime warning；功能断言与截图
    均正常。所有 owned App/runner/diagnose/模拟器已停止并删除，仅非 owned AnalyticsReview 设备保持 Shutdown。
  - 仅复用 Foundation、SwiftUI、SwiftData、XCTest 与仓库现有组件；没有新增第三方依赖。
- [x] 最终 checkpoint：
  - 冻结代码的 recurrence、quantity、draft、snapshot、preflight、lifecycle、UI 与 localization 回归共
    22 个 suite、129 项测试通过，0 failure。
  - 精确执行 `CONFIGURATION=Release scripts/build_install_all.sh`，退出码 0；iOS 主 App、内嵌 Watch
    companion 与 macOS App 的 Release 签名构建成功，产物签名均通过验证。
  - iOS App 已安装到 iPad Pro M4（`748D0137-ADC3-58AF-855C-1E98B3125F93`）与 iPhone Air
    （`FBA36694-D841-56D4-8ED6-21942873B21B`）；macOS App 已复制到 `/Applications/timetracker.app`。
    未连接可见的物理 Apple Watch，因此脚本无法验证 Watch 上的实际安装；已验证签名的 companion 嵌入
    iOS App，配对手表开启 Automatic App Install 后由系统安装。
  - 物理设备只完成安装，未启动、未操作、未截图；没有 owned `xcodebuild`、`xctest`、安装进程或 Booted
    模拟器残留。根目录 `README.md` 保持不存在，反馈文件末尾用户追加内容保持未暂存。
  - Codex 已将唯一反馈项标为 `[x]`，并移除 active link；本实现记忆作为已完成记录保留。

### owned 验收资源记录

- iPhone 17 Pro（第三次 UI 测试尝试）：`B5698361-0F4B-417C-9CA9-ED4D1C8E5C44`；测试失败后已
  terminate App 与 runner、shutdown、delete，并确认列表和进程无残留。失败证据保存在
  `build/Task13SimulatorValidation/iPhone-third.xcresult`，待定位后创建全新的 owned 模拟器重试。
- iPhone 17 Pro（第四次 UI 测试尝试）：`9E946C5E-6D22-4298-8442-48EA8B996594`；测试失败后已
  terminate App 与 runner、shutdown、delete，并确认列表和进程无残留。失败证据保存在
  `build/Task13SimulatorValidation/iPhone-fourth.xcresult`。
- iPhone 17 Pro（第五次 UI 测试尝试）：`5E12F9FD-8C96-4240-A6BC-9E1F7A51E840`；测试失败后已
  terminate App 与 runner、shutdown、delete，并确认列表和进程无残留。失败证据保存在
  `build/Task13SimulatorValidation/iPhone-fifth.xcresult`。
- iPhone 17 Pro（第六次 UI 测试尝试）：`F8718A8B-5777-4BD2-9550-7DB15332CA75`；测试失败后已
  terminate App 与 runner、shutdown、delete，并确认列表和进程无残留。失败证据保存在
  `build/Task13SimulatorValidation/iPhone-sixth.xcresult`。
- iPhone 17 Pro（第七次 UI 测试尝试）：`5E0E8DB5-EE08-4840-B21C-833674061F13`；测试失败后已
  terminate App 与 runner、shutdown、delete，并确认列表和进程无残留。失败证据保存在
  `build/Task13SimulatorValidation/iPhone-seventh.xcresult`。
- iPhone 17 Pro（第八次 UI 测试尝试）：`5EAA2DC4-8263-4393-83F6-EA6EAF7E06DC`；测试失败后已
  terminate App 与 runner、shutdown、delete，并确认列表和进程无残留。失败证据保存在
  `build/Task13SimulatorValidation/iPhone-eighth.xcresult`。
- iPhone 17 Pro（第九次 UI 测试尝试）：`FC1D7E0B-085E-4116-9EC0-9D34D0CF0023`；测试失败后已
  terminate App 与 runner、shutdown、delete，并确认列表和进程无残留。失败证据保存在
  `build/Task13SimulatorValidation/iPhone-ninth.xcresult`。
- iPhone 17 Pro（第十次 UI 测试尝试）：`1032C0B6-4C30-4EAE-9CD8-5C4AFE22D604`；测试失败后已
  terminate App 与 runner、shutdown、delete，并确认列表和进程无残留。失败证据保存在
  `build/Task13SimulatorValidation/iPhone-tenth.xcresult`。
- iPhone 17 Pro（第十一次 UI 测试尝试）：`8852B680-E86D-429C-BE03-6613C2AD295E`；测试失败后
  已 terminate App 与 runner、shutdown、delete，并确认列表和进程无残留。失败证据保存在
  `build/Task13SimulatorValidation/iPhone-eleventh.xcresult`。
- iPhone 17 Pro（第十二次 UI 测试尝试）：`8E811EF3-8B47-48EE-9306-FFE5E774F7FB`；测试失败后
  已 terminate App 与 runner、shutdown、delete，并确认列表和进程无残留。失败证据保存在
  `build/Task13SimulatorValidation/iPhone-twelfth.xcresult`。
- iPhone 17 Pro（第十三次 UI 测试尝试）：`BADA72F0-33B5-403E-B1BF-E129C3A272D2`；模拟器返回
  `NSPOSIXErrorDomain Code=3`，App 未取得进程句柄，属于启动基础设施失败；随后已 terminate、shutdown、
  delete，并确认列表和进程无残留。证据保存在 `build/Task13SimulatorValidation/iPhone-thirteenth.xcresult`。
- iPhone 17 Pro（第十四次 UI 测试尝试）：`6FA6F57F-6764-436B-B9B4-B05ECC02CBAF`；测试已正确
  创建父模板与当天子任务，并进入子任务数量详情；XCTest 将 SwiftUI 的“记录进度”标识错误限定为
  `.buttons`，误判不存在后把列表滚到底，最终在第 2393 行失败。录屏第 78 秒确认初始详情已显示
  `0 / 50 reps`、计划日期与“Record Progress”。随后已 terminate App/runner、shutdown、delete，
  并确认列表和进程无残留。证据保存在 `build/Task13SimulatorValidation/iPhone-fourteenth.xcresult`
  与 `build/Task13SimulatorValidation/iPhone-fourteenth-generated-detail-78s.png`。
- iPhone 17 Pro（第十五次 UI 测试尝试）：`2E914FF6-D262-49C0-BBE6-4FAB1FB2C349`；确认 iOS 27
  连 `.any["task.detail.quantity.record"]` 也未暴露该 SwiftUI 标识，因此在重复滚动前主动中止测试，
  改用屏幕与 VoiceOver 同时可见的按钮标签 `Record Progress` 定位。App 与 runner 已停止，模拟器已
  shutdown、delete，并确认设备列表及进程无残留；证据保存在
  `build/Task13SimulatorValidation/iPhone-fifteenth.xcresult`。
- iPhone 17 Pro（第十六次 UI 测试尝试）：`9F44A70E-5CA6-417B-878C-69DA301139C6`；按钮标签
  `Record Progress` 可正常定位，且 XCTest 随后把该按钮报告为 `task.detail.quantity`，证明 Section 的
  容器 identifier 覆盖了内部按钮与 ProgressView identifier；测试在第 2392 行验证 progress 时失败。
  已移除冲突的容器 identifier，并增加源码契约防回归。App 与 runner 已停止，模拟器已 shutdown、
  delete，并确认设备列表及进程无残留；证据保存在
  `build/Task13SimulatorValidation/iPhone-sixteenth.xcresult`。
- iPhone 17 Pro（第十七次 UI 测试尝试）：`6511DD9E-D024-4F1A-8C95-75BC9FA5ED1F`；完整真实
  创建流程通过（1 test、0 failure、94.003 秒）：创建 `Pushups`、设置 `50 reps` 与每日重复、验证父模板/
  今日子任务角色和 `0 / 50 reps`、确认模板不能记录、在今日子任务记录 20 并验证 `20 / 50 reps` 与历史。
  `xcresult` 位于 `build/Task13SimulatorValidation/iPhone-seventeenth.xcresult`，四张 simulator-only 截图已
  导出到 `build/Task13SimulatorValidation/iPhone-seventeenth-export` 并逐张目视检查。测试结束后已 terminate
  App/runner，停止 Xcode beta 自动启动的 owned `simctl diagnose`，shutdown、delete 模拟器，并确认设备列表
  与进程无 owned 残留。结果中有一条 `Invalid frame dimension (negative or non-finite).` runtime warning；活动树
  将其精确定位到 XCTest 对 `task.editor.quantity.target` 执行 `Synthesize event` 的点击时刻。该渲染路径中的
  产品 `.frame` 参数均为有限常量或受下限保护，功能与截图无异常；iPad 批次继续交叉验证该模拟器自动化告警。
- iPad Pro 13-inch (M5) 12GB（第一次 UI 测试尝试）：`B3470365-B9A5-4FF7-812A-49DADE7EB25F`；
  数量目标已正确切换并输入 50，但第 2278 行用 identifier 的 `.firstMatch` 取到了非 hittable 的重复 `Done`
  元素，而录屏末帧确认用户可见的键盘工具栏 `Done` 正常显示；测试因此在进入重复配置前失败。该批次也把同一
  runtime warning 定位到 XCTest 点击 quantity target 的 `Synthesize event`，跨 iPhone/iPad 完全一致，确认是
  iOS 27 模拟器自动化点击层信号而不是业务布局结果。证据位于
  `build/Task13SimulatorValidation/iPad-first.xcresult` 与 `iPad-first-export`。App/runner 已停止，模拟器已
  shutdown、delete，并确认仅剩非 owned 的 `AnalyticsReview-iPhone17Pro`（Shutdown），无 owned 进程残留。
- iPad Pro 13-inch (M5) 12GB（第二次 UI 测试尝试）：`349B5532-4C64-40BD-BB9B-41047E816401`；
  identifier 与可见英文标签都返回同一个 XCTest 判定为 non-hittable、但录屏中实际可见的键盘工具栏 `Done`，
  因此第 2280 行仍在测试定位层失败。证据位于 `build/Task13SimulatorValidation/iPad-second.xcresult`；
  Xcode beta 自动启动的 owned `simctl diagnose` 已终止，App/runner 已停止，模拟器已 shutdown、delete，并确认
  无 owned 设备或进程残留。下一次改为在元素存在且 frame 有限时直接合成其中心坐标点击，绕过 iOS 27 的
  `isHittable` 误报；iPhone 继续使用正常 hittable 路径。
- iPad Pro 13-inch (M5) 12GB（第三次 UI 测试尝试）：`731ACB33-6C17-4CEB-A587-71EEBED71A19`；
  通过有限 frame 中心坐标成功点击键盘 `Done` 并关闭数字键盘；随后 XCTest 点击单位字段后仍把
  `hasKeyboardFocus` 留在 target 字段，`typeText("reps")` 因此在测试层失败。失败层级明确显示单位 TextField
  frame 为 `{{297.5, 344.5}, {476.5, 22.0}}`，产品布局有限且正常；下一次先输入单位并提交，再输入目标和关闭
  数字键盘，避免 iOS 27 模拟器在数字/字母键盘切换后保留错误焦点。证据位于
  `build/Task13SimulatorValidation/iPad-third.xcresult`。App/runner 已停止，模拟器已 shutdown、delete，并
  确认无 owned 设备或进程残留。
- iPad Pro 13-inch (M5) 12GB（第四次 UI 测试尝试）：`7208BCF9-F9D8-4F49-9693-527A5244B47C`；
  测试先输入单位仍未取得焦点。录屏与失败层级交叉确认：XCTest 把 unit field 的 y=366.5 报为 hittable，
  但模态 `New Task` 导航栏覆盖 y=378...432，合成点击实际落在遮挡层，产品字段并未收到点击；这是测试的
  可见性判定缺陷，不是字段失效。证据位于 `build/Task13SimulatorValidation/iPad-fourth.xcresult`、导出的
  UI hierarchy 与 `iPad-fourth-unit-tap.png`。下一次同时校验 hittable 和字段位于模态导航栏下方的几何条件，
  必要时小幅向下拖动表单再点击。App/runner 已停止，模拟器已 shutdown、delete，并确认无 owned 设备或
  进程残留。
- iPad Pro 13-inch (M5) 12GB（第五次 UI 测试尝试）：`81D78840-CF49-46C2-AF5C-1BEDBAD3466D`；
  模态导航栏下方几何校验生效，成功输入 `reps`/50、创建并保存父模板与今日子任务、检查列表角色、模板详情
  和生成任务详情，并在记录 Sheet 输入 20。随后第 2444 行发现真实 iPad 可用性问题：浮动数字键盘覆盖记录
  Sheet 右上角 Save，而该 Sheet 没有收键盘的 Done 工具栏；截图
  `build/Task13SimulatorValidation/iPad-fifth-save-progress.png` 清楚显示遮挡。下一次给该数字字段补原生键盘
  `Done`，测试先收键盘再保存。已有三张目标截图位于 `iPad-fifth-export`，但因整条流程未通过不作为最终验收。
  App/runner 已停止，模拟器已 shutdown、delete，并确认无 owned 设备或进程残留。
- iPad Pro 13-inch (M5)（第六次 UI 测试尝试）：`7F3CBA07-D96F-4049-92CF-8BDC1BEAB472`；新增的
  数量录入键盘 `Done` 已成功露出 Save，但 iOS 27 XCTest 在浮动键盘消失后仍保留不可见的全局
  `Keyboard` 容器，第 2439 行用 `waitForNonExistence` 因测试层假阴性失败。产品流程已走到保存前；随后
  改为验证真正的用户结果——Save 重新可见且可点击。证据位于
  `build/Task13SimulatorValidation/iPad-sixth.xcresult`。App/runner 与 owned `simctl diagnose` 已停止，
  模拟器已 shutdown、delete，并确认无 owned 残留。
- iPad Pro 13-inch (M5)（第七次 UI 测试尝试）：`1786A5FB-24F9-47E6-B1A0-292E121A2CA0`；完整流程
  通过（1 test、0 failure、147.192 秒），但逐张目视检查导出截图时发现 XCTest 快速 `typeText` 只留下
  标题 `Pu`，编辑器截图还包含 iPad 的浮动数字键盘。因此该批次只证明功能路径通过，不作为最终视觉证据；
  标题输入改为逐字符确认，iPad 最终截图只保留保存后的干净界面。证据位于
  `build/Task13SimulatorValidation/iPad-seventh.xcresult` 与 `iPad-seventh-export`。App/runner 与 owned
  `simctl diagnose` 已停止，模拟器已 shutdown、delete，并确认无 owned 残留。
- iPad Pro 13-inch (M5)（第八次 UI 测试尝试）：`452E283F-5AAE-4510-A7B8-C19B0EB701BA`；逐字符标题
  输入已确认得到完整 `Pushups`，但测试仍以 iOS 27 的全局 `Keyboard` 容器消失作为断言，在第 2307 行
  重现测试层假阴性。移除该错误断言后保留实际可操作性检查；同一 owned 模拟器卸载 App 清空数据后用于
  最终重试。失败证据位于 `build/Task13SimulatorValidation/iPad-eighth.xcresult`，owned diagnose 已停止。
- iPad Pro 13-inch (M5)（第九次、最终 UI 验收）：`452E283F-5AAE-4510-A7B8-C19B0EB701BA`；完整真实创建
  流程通过（1 test、0 failure、127.959 秒）：逐字符确认 `Pushups`，设置 `50 reps` 和每日重复，验证
  `Daily Template` / `Today’s Task` 与 `0 / 50 reps`，确认模板不能记录，在当天子任务记录 20，并验证
  `20 / 50 reps`、剩余 30 与历史。`xcresult` 位于
  `build/Task13SimulatorValidation/iPad-ninth.xcresult`；三张保存后 simulator-only 截图已导出到
  `build/Task13SimulatorValidation/iPad-ninth-export` 并逐张目视检查，标题和布局均正确。结果保留一条与
  iPhone 相同、精确发生在 XCTest 点击 quantity target 时的 `Invalid frame dimension` 模拟器 runtime
  warning，产品截图与功能路径无异常。App/runner 与 owned `simctl diagnose` 已停止，模拟器已 shutdown、
  delete；当前仅有非 owned `AnalyticsReview-iPhone17Pro` 且为 Shutdown，无 owned 设备或进程残留。
- iPhone 17 Pro（投影重构后最终重验）：`3A56C61D-29A1-44B8-8B08-3E04640388E2`；冻结代码完整流程通过
  （1 test、0 failure、108.076 秒）。`xcresult` 位于
  `build/Task13SimulatorValidation/iPhone-current.xcresult`；四张截图位于 `iPhone-current-export`，已逐张
  检查编辑器 50 reps + daily、父子角色与 0/50、模板只读、当天子任务 20/50 和历史。App/runner 已结束，
  模拟器 shutdown、delete，无 owned 残留。
- iPad Pro 13-inch (M5) 12GB（投影重构后最终重验）：
  `57AD8308-F4AC-4D69-9790-E84B0EB5167A`；冻结代码完整流程通过（1 test、0 failure、147.656 秒）。
  `xcresult` 位于 `build/Task13SimulatorValidation/iPad-current.xcresult`；三张保存后截图位于
  `iPad-current-export`，已逐张检查父子角色与 0/50、模板只读和当天子任务 20/50。Xcode 自动启动且明确
  携带该 UDID 的 owned `simctl diagnose` 在测试完成后收尾卡住，已单独终止；App/runner 已结束，模拟器
  shutdown、delete。仅非 owned AnalyticsReview 设备保持 Shutdown，无 owned 残留。
