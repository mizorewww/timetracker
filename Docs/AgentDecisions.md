# TimeTracker Agent 决策文档

状态：有效决策记录
最近更新：2026-07-16

本文记录自动化 Agent 和维护者在实现、审核、重构时必须保持的工程边界。它不是待办清单，也不替代代码审核。一次性发现写入带日期的 Audit 文档，未来计划写入 Plan 文档。

## 1. 使用规则

每项决策包含状态、背景、决策、后果和验证方式。状态含义：

- Accepted：当前必须遵守。
- Proposed：尚未批准，不得当作既定架构实施。
- Superseded：保留历史，但由新决策替代。

修改 Accepted 决策时，应新增决策或明确标记替代关系，并同步更新受影响的用户、代码、隐私和版本文档。

## AD-001：TimeSegment 是时间事实来源

状态：Accepted

背景：总时长、墙钟时间、重叠时间、时间线和当前状态容易因多个缓存而产生分歧。

决策：已发生的计时事实由 TimeSegment 表达。用户可以更正或软删除错误记录，所以“事实来源”不等于 append-only；它表示统计和展示只能从 canonical segment 及明确领域规则派生，缓存只能加速，不能成为第二真相。

后果：并行计时必须被合法处理。修改统计需覆盖区间并集、相接、包含、跨日、时区和夏令时。

验证：领域测试比较 gross、wall-clock 和 overlap；缓存删除后可重建出相同结果。

## AD-002：持久写入经过命令和仓储

状态：Accepted

背景：SwiftUI View、App Intent、Watch 和维护工具若各自直接操作 SwiftData，会复制规则并造成跨入口差异。

决策：长期业务写入经过 domain command 与 repository。TimeTrackerStore 可以编排 UI 动作，但视图和系统扩展不得各自发明写入规则。

后果：新增入口应复用命令；直接 ModelContext 写入只允许在组装、迁移、fixture 或明确的基础设施层。

验证：同一操作从主应用、Intent 和 Watch 触发时满足相同前置条件与结果。

## AD-003：本地优先 CloudKit，禁止静默伪装持久化成功

状态：Accepted

背景：用户需要离线工作，同时 CloudKit、schema 或磁盘可能失败。

决策：正常模式使用持久容器并可启用 CloudKit。是否启用 iCloud 是设备本地 `UserDefaults` 启动配置，修改后下次启动生效，不得经 `SyncedPreference`、冲突快照或导出/恢复跨设备传播。fallback 必须显式记录和显示诊断状态；紧急内存存储不能被称为已保存。

后果：错误路径优先保留可诊断性，禁止悄悄切到空库并向用户展示“数据已同步”。

验证：容器故障测试检查模式标记、错误可见性和重启后的预期行为；偏好、快照与导出测试确认历史 `TimeTrackerCloudSyncEnabled` 被过滤，本地模式写入不生成全库冲突快照。

## AD-004：系统表面共享领域命令

状态：Accepted

背景：App Intents、Live Activity、Widget 和 Watch 是主应用的投影或入口。

决策：系统表面使用稳定 DTO、共享快照和领域命令。App Intents 与应用进程复用模型容器、遵守用户的并行计时偏好并使用原子 mutation；不得每次动作创建一套容器或硬编码不同规则。提交后只用窄依赖刷新 Widget、Watch、Live Activity 和同步 snapshot；投影失败不得把已提交动作报告为失败。Live Activity/Widget 不保存唯一事实。Widget/Watch producer 按 Unicode 字符边界裁剪投影文本，规范化 summary/timer start，并共用 128 KiB 文本预算，不回写 canonical facts。Widget 快照在保存和读取都经过 `WidgetSnapshotLimits`：JSON 256 KiB，active/recent 各 64 项，字段/时间/统计/唯一 ID 受限，非法读取是 corrupted 而不是 empty。Watch 命令以稳定 command ID 排队，必须收到手机 typed terminal result 或兼容快照反射后才确认；手机在任何 mutation 前拒绝超过 30 秒的旧命令，明确 retry 保留 ID 但刷新 `issuedAt`。Watch state 最多 64 active/256 recent；payload 与恢复队列统一经过 `WatchTransportLimits` 的日期、UTF-8、数量、唯一 ID、summary 和 encoded-size 边界；iPhone incoming、Watch pending/failed 各 64 项，队列编码最多 512 KiB，unsafe restore fail closed，overflow 成为明确失败而不是静默执行。Required Reason API 按 target 实际用途声明：主 App `1C8F.1`/`CA92.1`、Widget `1C8F.1`、Watch `CA92.1`；不能假定主 App manifest 自动覆盖扩展。

后果：扩展失败不应破坏主应用事实。跨进程格式必须版本化并保持向后兼容。

验证：Intent、Live Activity 和 Watch 增加集成测试；Start Timer Intent 与主应用的并行计时结果一致；过期 Watch 命令不写 receipt/ledger，同 ID 刷新时间后可重试且已完成命令仍保持幂等；Watch codec/queue 覆盖超限字段、重复 ID、损坏/过大恢复、pending/failed overflow 和有效边界 round-trip；Widget/Watch producer 覆盖 Unicode-safe prefix、summary/start clamp、count/text/JSON 预算与 canonical facts 不变，Widget store 覆盖 valid round-trip、保存拒绝、超 256 KiB、结构非法、重复 ID 与容器不可用。Widget 在真实设备共享容器与时间线验证通过前不列为已完成发行验收的能力；Archive 核对每个产物的 Privacy manifest 合并结果与 UserDefaults 实际调用。

## AD-005：API 密钥仅保存在本机 Keychain

状态：Accepted

背景：LLM API key 曾属于普通偏好路径，存在被 SwiftData、UserDefaults、iCloud 或 JSON 快照带出的风险。

决策：API key 存入 LLMCredentialStore，使用 AfterFirstUnlockThisDeviceOnly 且关闭 Keychain 同步。同步和导出过滤敏感键；遗留明文只用于一次迁移，随后清除或软删除。迁移先确保 Keychain 有安全副本，再以原子 SwiftData mutation redaction；保存失败必须 rollback SwiftData 变更，但可保留已建立的 Keychain 副本供重试。普通 legacy preference 导入也只在原子保存成功后设置完成 flag。

后果：密钥不会跨设备同步，每台设备需单独配置。不得把秘密写入日志、测试 fixture 或诊断导出。“清空全部数据”同时清除本机密钥和设备本地的自动建议同意；若 SwiftData 清理失败，外部存储值需尽力补偿恢复并报告补偿失败。

验证：测试 Keychain round-trip、遗留值迁移、敏感键过滤、导出不含 secret，以及清空全部数据在成功/SwiftData 失败时的清除与补偿恢复。真实只读磁盘 store 还需证明普通迁移保存失败不留 pending row/完成 flag，敏感 redaction 保存失败时 SwiftData 原值不被半改写而安全副本仍可用。

## AD-006：JSON 导出不是备份

状态：Accepted

背景：当前设置页只有 JSON fileExporter，没有对应 fileImporter、版本预检、校验和或事务回滚。

决策：产品和文档只称其为数据导出或快照，不称为可恢复备份。导出必须 fail closed：读取或编码失败时明确返回失败并阻止 `fileExporter` 呈现，不得用 `{}`、空数组或缓存内容伪装成功。

后果：用户不会把导出故障误认成一份有效但空的快照。若未来使用“备份”一词，必须先实现带格式版本、校验和、导入预检、冲突策略、staging/回滚和恢复等价性测试的 importer。

验证：用户文案无误导；有效导出包含业务事实，未配置或编码失败返回 `nil`/错误且不产生占位文档；恢复测试能从旧版本 fixture 重建等价业务事实。

## AD-007：Breaking schema 的批准与保留政策

状态：Accepted

背景：项目允许在开发阶段进行破坏性 schema 变更，但“breaking”不能成为静默丢失用户数据的许可。

决策：

- TaskNode、TimeSession、TimeSegment、PomodoroRun、InboxItem、ChecklistItem、TaskCategory 和用户可见设置默认必须保留。
- 派生缓存可在版本说明明确后重建。
- secrets 必须排除于 schema 导出和同步之外。
- 任何经批准的数据丢弃必须写明范围、理由、用户提示、备份/恢复要求和回滚边界。
- 迁移必须考虑幂等性、多设备版本偏差、CloudKit 状态和旧 store fixture。
- legacy Countdown 本机导入必须把 `UserDefaults` payload 当作不可信输入：JSON 限 256 KiB、源记录限 256、标题限 4 KiB UTF-8、日期限有限的 `[1900-01-01, 2201-01-01)`；保留合法 UUID，重复 UUID 以第一条合法记录为准。实际导入只能在 SwiftData save 成功后设置迁移 flag 并删除旧 payload，失败时保留重试条件。
- 无法安全迁移时，停止升级并显示可操作错误；不得静默创建空库替代。

后果：Breaking 迁移需要单独审核。发布说明必须说明不可逆边界，且至少保留一条经过验证的恢复路径。

验证：真实旧版本 store 迁移测试、重复启动测试、版本偏差测试以及迁移前后核心事实计数/身份校验。Countdown 迁移额外覆盖大小/数量/字段/日期边界、UUID 保留与首个合法重复语义、已有 SwiftData 事实的幂等退役与完成状态。

## AD-008：行为测试优先于源码字符串扫描

状态：Accepted

背景：测试套件大量读取 Swift 文件并匹配文本；等价的视图拆分、文案调整或导航重构会造成误报。

决策：业务约束以领域/集成测试验证，UI 流程以 accessibility identifier 和可见行为验证。源码扫描只保留少量、稳定且确实属于架构护栏的断言。

后果：重构测试时先补行为覆盖再删除字符串断言。测试必须隔离 UserDefaults、Keychain、locale、时区和临时数据。

验证：等价重命名或视图抽取不会让行为测试失败；失败信息描述用户行为而非源码片段。

## AD-009：文档按“当前、未来、历史”分层

状态：Accepted

背景：README 与多个计划曾混合当前实现和未来目标，导致 Watch、Widget、CSV 和 Inspector 状态失真。

决策：

- README、UserGuide、CodeGuide、Architecture 和 ProjectMap 描述当前事实与所有权。
- NextDevelopmentPlan、NativeUIPlan 等明确标为 future 的文档描述未来，并写清前置条件和验收门禁。
- 带日期的 Audit 记录该次审核的 baseline、实现结果与证据；它可以承载最终冻结工作树证据，但不替代当前用户/代码规范。
- 已归档或被替代的计划必须在顶部标明 superseded/historical，旧命令、绝对路径、未勾选项和临时 hard rule 均不得继续充当 Agent 指令或当前 backlog。CodeRefactorPlan 等标为 current status/guardrails 的文档则按当前工作树维护，不能因为名称含 Plan 就自动视为历史。

后果：代码变更若影响用户行为、隐私、target 或迁移，必须在同一提交更新当前文档。

验证：相对链接检查、target/目录对照、状态标签核对以及发行前文档走查；搜索旧 schema、旧 UI 流程、绝对路径和未兑现 hard rule，确保只出现在明确的历史说明中。

## AD-010：Widget 的发行门禁

状态：Accepted

背景：Widget target 和快照代码存在。2026-07-14 已为主应用及扩展补齐同一 App Group，并由自动签名成功生成 profile，但尚未完成真实设备端到端读写验证。

决策：同时满足 entitlement、签名 profile、共享容器读写、时间线刷新和真实设备测试前，Widget 只能标记为“代码侧完成、真机发行验收未完成”。

后果：不得用模拟器单次截图替代真机数据共享验证。

验证：主应用写入、Widget 读取同一版本化快照；升级、空数据、锁屏与离线状态均通过。

## AD-011：FlowDown 只作模式参考，不移植其依赖栈

状态：Accepted

背景：2026-07-14 对 [Lakr233/FlowDown](https://github.com/Lakr233/FlowDown) 仓库快照 `694ba5d` 进行了定向参考。它包含成熟的恢复、设置备份和测试组织方式，也包含面向 UIKit 的专用 UI 与较多第三方依赖。

决策：当前不新增第三方库。可借鉴但需按本项目模型重新实现的模式：

- RecoveryMode 的显式失败状态、诊断和恢复入口。
- SettingsBackup importer 的版本、校验和、预检和恢复流程。
- 显式 xctestplan 对测试配置、环境和 target 的管理。
- App Intent 与 Live Activity 的集成测试组织。
- OrderedCollections 仅在 profiling 证明存在“既需稳定顺序又需高频键查找”的热路径时评估。

不直接引入或用来替代原生 SwiftUI 的内容：

- UIKit 专用 ListViewKit 与 AlertController。
- SnapKit、ColorfulX、SPIndicator。
- 用第三方列表、弹窗或进度提示替代 SwiftUI List、系统 alert、ProgressView 或平台导航。
- 为复制局部实现一次性引入大量传递依赖。

后果：借鉴代码前需重新验证许可证、数据模型、并发模型、平台可用性和可访问性。依赖提案必须证明自研成本、二进制体积、维护/供应链风险和原生方案不足。

后续触发条件：

- 备份 importer 进入排期时，参考其版本/校验和模式并写独立设计。
- 启动失败恢复进入排期时，参考 RecoveryMode 的状态机，不复制 UI。
- 测试矩阵出现重复 scheme 参数或 CI 需求时，引入 xctestplan。
- Instruments 显示有序字典热路径且标准库实现成为可测瓶颈时，单独评估 swift-collections。

验证：Package.resolved 或工程依赖变化必须对应已批准的 ADR、许可证记录、性能/体积证据和回退方案。

## AD-012：平台原生导航与只读优先任务详情

状态：Accepted（iPad 根导航条款由 AD-049 部分替代）

替代关系：AD-049 取代本决策中“iPad compact width 切换为五标签根导航”的条款；其余平台导航、Today、任务详情、Settings 和 Pomodoro 条款继续有效。

背景：旧 iPhone 自绘六目的地 chrome、卡片式 Today、任务详情内联大编辑器和 Pomodoro 隐藏点击选择造成层级混乱、可发现性弱和不必要的维护成本。

决策：

- iPhone 使用五个系统 `Tab`；Settings 从 Today 工具栏进入。
- iPad 在所有窗口宽度都保持同一个 `NavigationSplitView`，窄窗口只由系统折叠或显示列；macOS 使用 `NavigationSplitView` 和单实例主 `Window`，独立 Settings 场景与主窗口共享一个应用级 store。
- Today 只保留当前计时、今日摘要、Quick Start、可解释预测、时间线和用户倒计时。
- Task Detail 是阅读、执行和证据页面；编辑通过明确铅笔入口进入 sheet。
- Settings 按通用、专注、数据与同步、AI 助手、高级分类；外观跟随系统，不提供应用级亮/暗覆盖。
- Pomodoro 通过明确 Plan/Task 菜单选择，不使用无标签隐藏手势。
- 不设置 `CADisableMinimumFrameDurationOnPhone` 强制改变 iPhone 最小帧时长；交给系统按设备、功耗和内容调度，性能结论来自 Release runtime 证据。

后果：允许打破旧导航和 UI 流程，但深链接、selection 和返回路径必须稳定。新增交互优先使用 `Button`、`List`、`Form`、`Menu` 和系统 toolbar；关键触控目标以 44 pt 为默认。

验证：iPhone、iPad、Mac 窄/宽窗口导航测试；任务行、Today 条目、sidebar 任务都能到同一详情；Dynamic Type、VoiceOver、键盘和深色模式复验。

## AD-013：Observation 与事件驱动刷新

状态：Accepted

背景：`ObservableObject/@Published` facade 加前台周期轮询会扩大 SwiftUI 无关失效，并让 CloudKit 刷新频率取代真实事件语义。

决策：`TimeTrackerStore` 使用 `@MainActor @Observable`。根视图以 `@State` 持有，子视图按引用读取，需要 Binding 时局部使用 `@Bindable`。CloudKit 由 remote-store 和 import/export 通知驱动，短暂合并后走 refresh planner；启动和回前台做一致性刷新，不运行常驻 5 秒轮询。冲突快照同样使用 `StoreDomainEvent` 只刷新受影响的持久域；Local/Demo/UI Test 模式不为普通 mutation 捕获冲突快照。

后果：focused values 传递 store 本身，不保存动作 closure；计时 label 使用局部 `TimelineView`，不得通过 facade 高频 publish 驱动全树。

验证：源码护栏检查主 store 不含 `@Published`/`ObservableObject`；事件映射、debounce 优先级、foreground refresh 和关键导航状态有行为测试；性能分析关注 view invalidation fan-in。

## AD-014：确定性的 LWW 与 tombstone 语义

状态：Accepted

背景：重复 UUID、同步偏好和软删除在相同时间戳或清理流程中可能因输入顺序而复活旧值、覆盖新值或跨设备不一致。

决策：持久实体与 `SyncedPreference` 先按 last-write-wins 选 winner，再过滤 tombstone。比较顺序为 `updatedAt`、同时间 tombstone 优先、`createdAt`，最后以 `deviceID`、`clientMutationID` 或 TimeSegment 稳定内容键打破平局。duplicate cleanup 的 tombstone 必须早于被保留 canonical row，且不得改写已有较新 tombstone。任何可见查询不得在 LWW 之前过滤删除值。legacy `UserDefaults` 偏好迁移必须从 logical-key LWW winner 判断已迁移 key；winning tombstone 仍占用该 key，禁止旧本机值将其复活。普通 Local、iCloud、fallback 与 emergency 生产 store 永不物理 purge tombstone；只有隔离的 Demo/UI Test store 可清理过期 tombstone graph。

后果：任何新同步模型都必须定义相同时间戳和删除/恢复冲突；数组顺序不是冲突策略。

验证：正反输入顺序、active/tombstone 同时戳、更新后恢复、重复清理、多设备稳定 tie-break，以及 tombstone 阻止 legacy `UserDefaults` 重新导入的迁移测试。

## AD-015：LLM endpoint 与 Authorization redirect 边界

状态：Accepted

背景：字符串前缀判断 loopback 可接受伪装主机；默认重定向可能把 bearer credential 发送到不同源或从 HTTPS 降级。

决策：HTTP 仅允许 `localhost`/`.localhost` 保留域名以及经 `inet_pton` 数值解析确认的 `127.0.0.0/8` 或 `::1`。带 Authorization 的 redirect 只允许 scheme、host 和有效端口完全一致；跨源、协议降级和模糊主机全部拒绝。

后果：用户自定义 OpenAI-compatible 服务若使用域名必须为 HTTPS。endpoint、redirect 和 bracketed IPv6 规范化由一个网络边界实现，不在各 feature 重复判断。

验证：合法 IPv4/IPv6 loopback、伪装域名、远程 HTTP、HTTPS 降级、跨 host/port redirect 和同源 redirect 测试。

## AD-016：保留自动签名与付费开发者能力

状态：Accepted

背景：CloudKit、App Group、Widget、Watch 和 Live Activity 的真实验证依赖 entitlement、开发团队与 provisioning profile。关闭签名会产生不能证明能力可用的“成功构建”。

决策：工程保持 `CODE_SIGN_STYLE = Automatic` 和开发团队 `LT98S43NKA`。面向 generic/device/Release 的能力验证不得通过 `CODE_SIGNING_ALLOWED=NO`、`CODE_SIGNING_REQUIRED=NO`、ad-hoc 签名或清空团队设置绕过问题。Simulator 构建由 Xcode 显示 `Sign to Run Locally` 属于正常模拟器流程，不代表关闭工程自动签名，也不能替代设备 profile 验证。CLI 优先；只有账户/profile 等 CLI 无法完成的操作才使用 Xcode UI。

后果：签名问题必须作为签名问题修复并保留证据。模拟器构建用于 UI/逻辑验证，不能冒充 entitlement 真机验收。

验证：检查工程设置、签名 identity、embedded profile 和最终 app/extension entitlements；真机分别验收 CloudKit、App Group、Watch 和 ActivityKit。

## AD-017：本地日历日与精确区间缓存

状态：Accepted

背景：固定 86,400 秒在夏令时切换日不等于一个本地日；只用 day start 作为缓存 key 会让同一天不同裁剪区间发生碰撞。

决策：日边界必须通过 `Calendar` 计算。Forecast 活跃天、Analytics bucket 和失效区间都使用真实本地日；cache key 包含由当前 Calendar 计算并裁剪后的真实起止时刻，局部失效按区间相交处理。

后果：时间算法不得用固定秒数模拟“昨天/明天”，除非语义确实是精确持续时间。

验证：23/25 小时 DST 日、跨午夜、同日多个子区间、时区变化和局部缓存失效测试。

## AD-018：用户动作使用原子持久化边界

状态：Accepted

背景：一个用户动作可能经过多个 command/repository 步骤。若中途各自 `save()`，后续步骤失败时会留下半完成事实；相反，保存已成功后 read-model 刷新失败，也不能假装业务写入已经回滚。

决策：Store 和系统动作使用 `ModelContext.performAtomicMutation` 定义一个 unit of work。嵌套步骤调用 `saveAfterMutationStep`，在外层 mutation 中延迟到最后统一保存；动作或最终保存失败时 rollback。提交后的 refresh、Widget/sync snapshot 等派生步骤单独报告，不能改变 mutation 的成功结果。Feature 只有在 mutation 成功后才能清除与该操作相关的错误、editor 或 selection 状态。Keychain 等无法参与 SwiftData rollback 的 side effect 不能被宣称为同一个 ACID transaction；若流程先写外部存储再提交模型，必须保存旧值、在模型提交失败时执行补偿，并单独报告补偿失败。

后果：新增多实体动作必须从入口到最后一次保存处保持同一 `ModelContext`。不得在原子边界内开启另一容器或用无法回滚的中间保存切断 transaction。

验证：注入中间步骤/最终 save 失败并确认所有插入、更新、删除一起回滚；注入 post-commit refresh 失败并确认事实仍存在、返回成功且用户得到准确提示。

## AD-019：辅助功能字号触发结构重排，不以截断换紧凑

状态：Accepted（持续验证资源优先级由 AD-057 部分替代）

替代关系：本决策定义的信息完整性和布局行为继续有效；是否把极端 Dynamic Type 作为每轮全库专项，由 AD-057 的风险分级验证策略决定。

背景：Today、Task、Settings 和 Analytics 的旧横向行同时承载图标、标题、路径、数值与操作。在 Accessibility Extra Large 等字号下，单纯放大字体会造成标题截断、计时按钮碰撞和底部内容被 tab bar 遮挡。

决策：触控平台必须支持完整 Dynamic Type 范围。`dynamicTypeSize.isAccessibilitySize` 时，信息密集的横向行改用纵向或分组布局；segmented picker 在空间不足时改为菜单；scroll content 为系统 tab bar/底部控件保留可滚动余量。可见标题、路径、状态和错误优先完整生长。仅装饰性、已从 accessibility tree 隐藏的图标可以保持稳定视觉尺寸；不得通过固定正文大小、缩放整行或永久单行截断来“通过”截图。

后果：同一组件允许普通字号和辅助功能字号使用不同 composition，但必须共享动作、语义、稳定 identity 与数据来源。新增水平密集行必须同时设计 accessibility-size 结构。

验证：至少覆盖 iPhone 深色 Accessibility Extra Large 的 Today、Tasks、Task Detail、Analytics 和 Settings，以及 iPad 宽屏；检查文本无重叠、主操作可见、列表最后一项可滚到 tab bar 上方，并运行相关 UI contract。

## AD-020：大规模拆分按职责固化，不复活退役聚合文件

状态：Accepted

背景：Analytics、Settings、Task Detail、ledger infrastructure 和 SyncConflict 曾由少数大文件混合路由、展示、算法、同步状态与 DTO。大文件让 UI 修改触及同步/安全代码，也让代码审核难以界定行为边界。

决策：保持以下当前所有权：Analytics 的 landing page 与 typed category-detail destination 分文件，period/detail-list 与 store metrics/breakdown/overlap/task-snapshot 文件继续聚焦；Pomodoro setup 由 composition、empty state、focus controls、Plan/Task selection 和 timer face 文件分担；Settings 使用 display/timing、Pomodoro、countdown、sync、data、actions、bindings 和 support 文件，共享 rows 另按 foundation/value、action/destructive、input、presentation 和 sync-feedback 分文件；Task Detail 使用 canonical router 加 identity/checklist/overview/analytics/navigation/record sections；ledger infrastructure 使用 Cloud startup、persistence safety、timer DTO、aggregation、formatting、device identity 和 summary 文件，ledger domain index 又把 ordered flat-array mutation 与 day/change index 分开；rollup base 负责 state/full rebuild，Mutation extension 负责 scoped delta/replacement，pace/topology/activity 保持各自 owner；SyncConflict 使用 bootstrap/prompt、local mutation、Cloud import/export、recovery/resolution、state persistence/lock/locations、snapshot capture/分域 restore 和分域 record DTO 文件；Widget 使用 entry/provider/config、active layout、supplementary state 与 support 文件；Watch 使用 dashboard/timer/status/color UI 文件，`WatchAppStore` base 负责 observable state/restore，Commands extension 负责 queue/timeout/persistence，Connectivity extension 负责 WCSession transport/payload/freshness，SessionDelegate extension 独立承接 callbacks；facade 的 `Configuration` 负责首次配置/repository-only 系统表面装配，`Lifecycle` 负责 refresh/mutation/recovery/error。不得重新创建 `SettingsSectionsViews.swift` 或 `TimeTrackerServices.swift` 作为杂项聚合点，也不得让 closed-app post-commit 路径启动 migration、demo seed、observer 或自动 LLM 工作。

后果：文件移动必须保持一个权威领域规则，不能因“拆分”复制 LWW、时间聚合、恢复或 UI action。拆分后的 sync 继续作为语义高风险域接受完整行为测试；仍较集中的 Home 和 row 文件按 [CodeRefactorPlan](CodeRefactorPlan.md) 的真实现状继续治理。

验证：`CoreSourceLayoutTests` 检查关键文件存在、退役文件不存在及分组大小预算；行为测试、签名构建和最终 runtime 验证证明拆分没有改变跨平台结果。

## AD-021：任务层级以 parentID 为权威，path 是稳定 locator

状态：Accepted

背景：把完整祖先 UUID 链持久化到每个 `TaskNode.path`，会让根节点改名/移动造成整棵子树写放大；导入的缺失父节点和循环还会让递归遍历失控。

决策：`parentID` 是层级权威，`depth` 是可重建索引，`path` 固定为 `/<task UUID>` 的 canonical locator。用户可见路径由 `TaskTreeService` 根据标题即时、迭代生成并限制最近六级。启动、任务域刷新和 sync restore 运行 `TaskHierarchyMetadataService`，确定性修复 orphan/cycle 并重算 depth/path。

后果：不得把 `TaskNode.path` 直接显示给用户，也不得恢复祖先 UUID chain。App Entity、Watch、Analytics 和 AI candidate 必须使用派生标题路径。移动任务只写真正变化的节点。

验证：覆盖 orphan、cycle、深层树、移动、同深度跨根和 restore normalization；持久 path 长度不随树深度增长。

## AD-022：演示数据必须显式启用并与用户 store 隔离

状态：Accepted

背景：Debug 自动 `seedIfEmpty` 可能在 CloudKit 用户库为空或未完成 import 时写入 demo facts，并随后上传。

决策：Debug 与 Release 的 `TIMETRACKER_AUTOMATIC_DEMO_DATA_MODE` 默认均为 `off`。只有 Debug/内部明确 override 才允许 demo 创建；demo 使用无 CloudKit 的 `TimeTracker-Demo.store`，UI test 使用独立内存 container。

后果：截图工具必须显式声明 demo mode，结束后释放模拟器；不能依赖“Debug 自带数据”。CloudKit 模式启动会关闭本地 demo override。

验证：构建设置、容器 URL、CloudKit configuration 和 lifecycle tests 证明 demo 与用户 store 不相同且默认不 seed。

## AD-023：同步状态使用跨进程锁与 export generation checkpoint

状态：Accepted

背景：主应用与 App Intents/Shortcuts 可并发读写 `SyncConflictState.json`；单纯 atomic file replace 不能防止两个进程基于旧状态各自覆盖。CloudKit export 回调还可能乱序或属于已失效的恢复 epoch。

决策：所有 state read-modify-write 在一个递归进程锁和 POSIX `lockf` advisory file lock 内完成，形成跨进程 compare-and-swap 等价边界；JSON 使用原子替换，forced-upload mirror 服从权威 state。权威 state 限 128 MiB，recovery mirror 限 64 MiB。读取先做 metadata 大小预检，再用 `FileHandle` 最多读 `limit + 1`，以识别预检后文件增长的 TOCTOU。写入先编码并同时验证权威 state 与所需 mirror，只有两者均在上限内才解析路径或修改文件；独立 mirror rewrite 在最终写边界再次校验。大小拒绝必须保留现有有效 state/mirror。损坏或超限的权威 state 进入显式隔离恢复；损坏或超限的 pending mirror 被隔离并忽略，不能阻塞主库；超限文件通过 move 隔离，不整份载入内存。iOS 权威状态、pending forced-upload 恢复镜像和腐损隔离文件设置 `FileProtectionType.completeUntilFirstUserAuthentication`：本次启动首次解锁前不可读，解锁后允许后台 Shortcuts/CloudKit 使用。local mutation 推进 generation，import/恢复推进 epoch；export start 按 event ID 记录 epoch/generation/fingerprint，finish 只能确认同 epoch 且不早于已确认 generation 的 checkpoint。旧 state 清理被排除偏好时必须重算 fingerprint 并作废旧 payload checkpoints。checkpoint 限 16 个、24 小时。Snapshot restore 在原子 mutation 前拒绝数量/文本超限、重复 UUID、非法日期/数值/raw value/Pomodoro/preference JSON 和能证明的关联矛盾；缺失关联允许 staged import，任一失败都不改写事实或 tombstone。非法 transport 不作静默去重或钳制；这个边界仅适用于显式 snapshot restore，不被表述为初始 CloudKit import 的通用拦截层。

后果：禁止在锁外 load→mutate→save，禁止用任意成功 export 清除最新 pending winner，也禁止为每个 event 复制完整用户 snapshot。

验证：同进程并发互斥、外部进程 `lockf`、两个 service 实例无 lost update、乱序完成、失败完成、过期/上限 pruning、旧 preference scrub checkpoint invalidation、损坏 mirror 隔离、forced-upload ack、128 MiB/64 MiB 稀疏超限文件的拒绝/隔离、写端 state/mirror 分别超限时旧文件不变、精确边界接受、独立 mirror rewrite 复检，以及 iOS 三类敏感文件的最终 protection attribute 测试。Snapshot 额外覆盖记录/文本边界、重复 UUID 拒绝、日期/sort order/raw value、Pomodoro 和 preference 语义拒绝、关联矛盾、staged 缺失关联通过，以及失败时 sentinel/tombstone 不变。

## AD-024：Pomodoro 由持久 phase 状态派生 deadline，并与账本生命周期一致

状态：Accepted

背景：View-owned countdown 在后台挂起、重启或跨入口编辑后会漂移；删除活动 segment/task 可能留下仍在运行的 `PomodoroRun`。

决策：当前 phase 起点持久化在 `PomodoroRun.startedAt`，deadline 由状态和计划时长派生。启动、前台、页面出现与 scheduled task 幂等 reconcile 过期 focus，并把 segment/session 截在 deadline；break 不在后台擅自创建下一段 focus。用户继续 break 时，在同一原子 mutation 内从 canonical 任务树重做 trackable admission；任务或祖先已完成、归档、删除或缺失时，必须在任何 ledger stop/start 前作为零副作用 no-op 拒绝。通用 segment edit/delete、timer stop 和 task-tree delete 必须在同一原子动作中同步完成/取消/tombstone 对应 run，并保留有效历史。

后果：UI 只显示 deadline 派生的剩余时间。不能用 `Date()` 结束一个早已到期的 focus，也不能让 run 脱离 ledger 独自存在。

验证：后台/启动 reconciliation、deadline clipping、重复 reconcile、active segment edit/delete、过期删除、任务树含 timer/Pomodoro 与 break-state 删除测试；另覆盖 facade cache 过期时完成、归档和缺失任务的 break resume 均不推进 run、不新建 segment、不停止其他 timer 且不发布刷新/同步副作用。

## AD-025：增量 ledger/checklist/rollup 与 90 日 pace

状态：Accepted

背景：一次 segment 或 checklist mutation 若重新 fetch、过滤、排序和聚合完整历史，会随数据增长拖慢所有界面；历史 pace 若无窗口会不断增长。

决策：Ledger 维护 ID/day/active/session indexes 并只替换相交范围；day/change 与 ordered flat-array index 使用不同 extension owner。Checklist 只替换 affected task buckets。Rollup 消费 `LedgerSegmentChange`、scoped checklist 和 task/ancestor IDs；base 负责 state/full rebuild，Mutation extension 负责 delta/replacement application。完整历史 worked seconds 必须精确。Pace 只保留包含今天的最近 90 个本地日，对有记录的活跃日求平均，只用于把已有 remaining seconds 换算为预计活跃日。

后果：full refresh 仅用于首次载入、树拓扑变化、远程全量 import、calendar/time-zone 变化或无法精确描述范围的事件。View body 不得触发全量 rollup。

验证：增量结果与全量重建等价、DST/窗口滑动/旧记录编辑/活动 segment 更新；50,000 segment 单记录 mutation 和 cached ranking 预算。

## AD-026：Analytics snapshot 按 period 与 live bucket 缓存

状态：Accepted

背景：在 SwiftUI `body` 或每秒 Timeline tick 中重建 overview/task analytics，会把无关观察更新放大成全历史计算；只按 range 缓存又会跨日返回旧数据。

决策：缓存 key 至少包含 range、Calendar 计算的 period start；task snapshot 另含 task ID。只有所选范围与活动 segment 相交时加入分钟级 live bucket。ledger mutation 清除 snapshot 并按相交区间失效 day bucket；跨 period 自动 miss。重计算在 `.task(id:)` 等明确异步更新边界发生，不在 `body` 隐式执行。

后果：历史范围稳定，当前活动数据最多一分钟陈旧；缓存可丢弃并从 facts 重建。

验证：同 period hit、跨 period miss、active minute rollover、task key、mutation invalidation 和 snapshot correctness 测试。

## AD-027：AI 配置采用 Test→Save 草稿，自动发送需单独同意

状态：Accepted

背景：endpoint/API key 在每次键入时持久化会产生半配置状态、Keychain 噪声和意外请求；“已配置”不等于同意自动发送工作内容。

决策：配置 sheet 使用独立 draft；Test 只校验 credential fingerprint 并加载模型，不保存；选择有效模型后用户明确 Save 才写 endpoint/model 与 device-only Keychain。endpoint、模型列表和已选模型由一个批量 preference command 做一次 SwiftData 提交；Keychain 不是该 transaction 的一部分，提交失败时尽力恢复旧密钥并准确报告补偿失败。修改凭证会取消旧请求和旧测试结果。自动建议是默认关闭、设备本地的第二个明确开关，不参与 CloudKit/JSON。Inbox/checklist 发送前共用 `LLMSuggestionInputPolicy`：候选最多 48 项/16 KiB JSON，prompt 24 KiB，request body 32 KiB，持久化 model ID 256 bytes，文本按 UTF-8/完整 `Character` 有界投影且不回写持久事实。model ID producer 上限必须与同步快照 compact-field restore 上限相同；模型 ID 是 opaque identifier，超限或含控制字符时整体拒绝，不能截断成可能碰撞的另一个 ID。Inbox 候选按固定→高频/近期→稳定补足取舍；模型只看 78 个精选语义图标，返回 UUID/icon 必须属于实际已公告集。

后果：不得把补偿式一致性写成跨存储原子性；失败必须逐项报告。发行前必须确认实际 endpoint 服务方、发送字段、用途、保留期和删除渠道；兼容协议不代表零保留。

验证：draft normalization、stale test cancellation、save enablement、一次 preference batch save、Keychain 补偿恢复、discard confirmation、Keychain migration/filtering、automatic-consent default 和网络边界测试。请求额外覆盖大任务库优先级、输入顺序无关取舍、UTF-8 安全边界、最终 prompt/body 字节、精选 icon 合同、非候选 UUID 拒绝与返回字段归一化。

## AD-028：完成任务保持可见，可工作性与可见性分离

状态：Accepted

背景：把 `completed` 与 `archived` 都从任务树和选择器隐藏，会让用户无法回看详情和历史，也无法理解为何子任务不能继续工作；反过来，允许完成分支继续接收计时和新内容，又会让完成状态失去含义。

决策：`TaskTrackingAvailabilityService` 分别计算 `visibleTaskIDs` 与 `trackableTaskIDs`。归档或删除的任务会连同后代隐藏；完成任务与后代仍显示在任务树、详情和历史中，但任何祖先处于完成状态时，都不得接收新 timer、manual entry、Pomodoro、Quick Start、Inbox checklist、App Intent 或新建/移动目标。已存在的活动 timer 必须仍可见并可停止。用户选择“重新打开”时，把从目标到根路径上的所有完成阻塞项一起设为 active，不改写无关后代状态。

后果：完成、归档和删除是三个不同概念。所有系统入口、仓储层级写入和 UI picker 必须共用 trackable 判定；只读导航使用 visible 判定。完成或归档活动子树前必须先停止活动计时。

验证：覆盖完成父/子分支的可见性、全部写入口拒绝、历史 segment 保留原归属、既有 active timer 可停止、create/move 目标拒绝、App Intent 过滤，以及一次 reopen 原子恢复多个完成祖先。

## AD-029：预计时长优先，Checklist 是证据回退

状态：Accepted

背景：旧文档把任务预计时长称为纯展示 metadata，导致用户填写计划后仍看不到预测；仅靠 checklist 又会排除不适合拆成等权步骤的任务。另一方面，父任务预算若隐式覆盖子任务，会造成重复或模糊计数。

决策：`TaskEstimatePolicy` 接受 `0...600` 分钟，零表示未设置，正的历史值最多规范化为 36,000 秒。任务已完成或 checklist 全完成时，自身剩余为零；否则明确预计时长优先，`estimatedTotal = max(explicitEstimate, ownWorked)`、`remaining = max(0, explicitEstimate - ownWorked)`。没有明确预计时长时，才要求 checklist 至少完成一项且当前任务已有真实计时，再按等权完成项推导。明确预计时长只属于当前任务直接工作，子任务预测独立递归相加。最近 90 个本地日 pace 只能把已有 remaining seconds 换算为活跃日，不能生成 remaining seconds。

后果：Home、Analytics 和 Task Detail 必须展示相同来源与父子汇总；编辑器、迁移输入和 forecast service 共用一个规范化范围。预测理由必须说明是用户预计还是 checklist 证据。

验证：覆盖零/负值/超上限规范化、明确预计无 checklist、worked 超过 estimate、完成状态优先、checklist fallback、父自身 estimate 与子 forecast 分开累加、单子分支 drill-down、多子分支汇总和 90 日 pace 不造工时。

## AD-030：V9 移除持久 DailySummary 派生缓存

状态：Accepted

背景：`DailySummary` 可由 canonical `TimeSegment` 与聚合规则完全重建。把它留在当前 SwiftData/CloudKit schema 会形成第二份可漂移事实，也扩大同步、迁移和维护面。

决策：V9 的版本标识为 `1.8.0`。V8→V9 使用 lightweight migration 从当前 registry 移除 `DailySummary`，保留任务、时间账本、Pomodoro、checklist、Inbox、分类、倒计时与偏好等用户事实。Legacy `DailySummary` 类型只保留在 V1...V8 schema 历史中，使旧 store 可被迁移计划读取；当前 Analytics 只创建可丢弃、可重建的 `DailySummarySnapshot`。

后果：生产查询、同步 registry、导出与维护路径不得重新持久化 `DailySummary`。以后移除任何派生缓存都必须先证明其事实来源完整、迁移不删除事实，并保留旧 schema 声明直到支持窗口结束。

验证：真实 V8 磁盘 store fixture 包含任务与 legacy summary；打开 V9 后任务仍存在、当前 schema/CloudKit model registry 不含 `DailySummary`，分析结果可从 ledger 重建。V4→当前分类迁移 fixture 继续通过。

## AD-031：系统输入路由必须有界并服从 scene 生命周期

状态：Accepted

背景：Widget/Live Activity URL 可能在 SwiftData 初始化前到达；未经验证的无限队列会积累恶意或陈旧输入。WatchConnectivity 又只有一个进程级 callback，而 iOS `WindowGroup` 可以创建多个 scene；让 `ContentView` closure 强持有 store 会泄漏旧 scene，也可能把手表命令交给错误窗口。

决策：deep link 在立即执行或排队前都经过同一个 `AppDeepLinkRouter` 白名单验证：`timetracker` scheme、URL 最长 2,048 bytes、禁止 credential/port/fragment，并按 host/path/query/UUID 语法解析。初始化前每个 scene 使用容量 16 的 `PendingDeepLinkQueue`，按语义 action 去重、满时移除最旧项，repository ready 后顺序 drain，scene 消失时清空。`WatchCommandRouter` 单独拥有进程级 bridge handler，以弱引用注册 scene store，优先最近 active scene，清理释放/注销项，并在没有 route 时卸载 handler；bridge 自身继续负责无 handler 时的 durable 排队。

后果：新增系统 URL 必须扩展白名单 parser 和行为测试，不能直接执行任意 URLComponents。新的进程级系统 callback 也不得由 scene view 强持有业务 store；路由所有权、选择规则和 teardown 必须显式。

验证：覆盖超长/credential/port/fragment/重复 query/非法 UUID 拒绝，pending queue 语义去重、FIFO 上限、drain/clear，以及 Watch router 弱引用、active scene 优先、fallback、unregister 和最后 route 清除 bridge handler。

## AD-032：所有已记录时间以 reference now 为唯一未来边界

状态：Accepted

背景：本地 UI 可阻止新建未来记录，但 iCloud、导入、旧版本和设备时钟偏差仍可能带来 future-ended 或 future-started segment。若 Analytics、Forecast、timeline、cache 和 view 各自解释 `endedAt ?? Date()`，尚未发生的时间会被提前计入，增量结果也会与全量重建分叉。

决策：`TrackedTimePolicy` 是唯一读侧边界：`boundedEnd = min(endedAt ?? now, now)`，再裁到查询的半开区间；`startedAt >= now` 或空交集贡献零。本地 manual add/segment update 在 repository 层拒绝 future end 或 future active start，返回 typed `futureTime` 与三语通用错误。已同步/导入/遗留的脏数据不被迁移删除，而在 gross/wall、ledger summary、Analytics、Forecast、Pomodoro elapsed、timeline、cache、repository query 和 rollup 统一裁剪。UI 写入 DatePicker 不得越过 `now`；Today/Task Detail/共享 duration 通过 `TrackedTimeDisplaySnapshot` 展示，任何 UI/formatter 不得直接从 raw `endedAt` 派生时长。

后果：future-ended 记录随 `now` 增长到其真实结束后停止，future-only 区间在开始前为零。active 与 future-ended row 进入 time-sensitive set，正常时钟前进保持增量；clock rewind 稀有发生时重评全库，保证 incremental 与 full rebuild 等价。DST 计算使用绝对 elapsed seconds，本地日边界仍使用 `Calendar`。

验证：覆盖 future write rejection、`startedAt == now`、future-only、future-ended 随时间增长/停止、半开区间、DST、gross/wall/timeline/forecast/cache/repository 裁剪、时钟前进、clock rewind、incremental/full rebuild 等价，以及 editor DatePicker/validation/duration 与 timeline/recent/shared label 显示契约。

## AD-033：持久偏好先做整批类型化预检

状态：Accepted

背景：非 throwing JSON 编码曾在超限/编码失败时返回 `null`，raw preference command 又可逐项直接写入。错误类型或批次后项失败可能留下不可恢复的偏好或前项 pending mutation。

决策：`PreferenceJSON` 对持久路径提供 throwing checked encode/decode，并按 `AppPreferenceKey` 将值解码为声明类型、规范化、重新编码。单项上限 256 KiB；`null`、畸形 JSON、错误类型和超限必须拒绝。`PreferenceCommandHandler` 在任何 fetch/insert/update 前准备完整批次，再用 `performAtomicMutation` 一次提交；独立调用的 save 失败同样 rollback。Legacy 无法 checked-encode 的值跳过，不得保存为 `null`。

后果：新增 preference key 必须同时加入 canonical switch、读取 sanitizer、迁移与错误测试。不得在 apply 循环里边验证边修改，也不得把 fallback decode 当持久化校验。

验证：覆盖 malformed/`null`/wrong-type/oversized、后项失败前项不变、canonical clamp、真实只读 store rollback、legacy 超限跳过与三语错误键。

## AD-034：LLM 响应必须流式、有界且可取消

状态：Accepted

背景：`URLSession.data` 会在解码前完整缓冲响应；第三方 endpoint 可省略或伪造 Content-Length、返回巨大错误页或长期悬挂，造成内存和任务生命周期风险。

决策：生产 LLM transport 使用专用 ephemeral session，禁用 cache/cookie，资源 timeout 为 60 秒。响应使用 `AsyncBytes`；headers 阶段先处理 HTTP 状态和 2 MiB Content-Length，非 2xx/声明超限立即取消且不读取 body，实际读取也在第一个超限字节取消。父 Task 取消传到底层 task；timeout 转 typed error。注入 transport 的三个 service 对成功 body 重做 2 MiB 校验，但保留响应类型与 HTTP 状态优先级。

后果：不得恢复 `URLSession.shared.data` 或只信 Content-Length。未来提高上限必须同时评估 decoder 复杂度、内存峰值和隐私披露。

验证：ephemeral 配置、精确上限、首个越界字节、headers preflight、非成功优先、等待 headers 取消、timeout、注入 transport 与三语错误测试。

## AD-035：设备身份是随机不透明 ID，不是设备指纹

状态：Accepted

背景：`deviceID` 只用于同步 tie-break/mutation metadata；无界复用 UserDefaults 字符串会传播畸形、跨平台或可能含可识别信息的旧值。

决策：只复用当前平台 `mac|ios|watch` 前缀加大写连字符规范 UUID，完整值最多 42 UTF-8 bytes 且不得含控制字符。其余值随机重建并回写。不得加入主机名、账户名、序列号或硬件标识。

后果：平台迁移会得到新的本地 identity，这是预期行为；它不是用户设备列表或认证凭据。

验证：跨平台、超限、控制字符、畸形/非规范 UUID 拒绝，合法值稳定复用，生成值不含 host/account，并执行 iOS/macOS 签名构建。

## AD-036：分批导入的不完整账本采用读模型隔离

状态：Accepted

背景：CloudKit 可以分批 materialize task、session 与 segment。若 snapshot restore 或维护任务直接拒绝/删除缺父记录的行，稍后到达的父记录无法恢复完整事实；若照常发布，孤儿或 task/session 错配的 segment 会污染 Today、Analytics、Rollup、Widget 与 Watch。

决策：原始 SwiftData 行保留，显式 snapshot preflight 继续允许“当前 payload 缺少关联记录”的 staged import。Facade 每次 task/ledger 一致性刷新建立 relationship visibility：task ID 必须存在，session ID 必须存在，且 session.taskID 必须等于 segment.taskID；只有满足三项的 segment 才进入可观察数组、indexed query 结果、Pomodoro elapsed 和系统投影。`refreshVisible` 同步刷新受影响 session index。父记录后续到达时由完整刷新自动解除隔离，不修改 segment 身份或时间事实。

后果：不得用数据库清理、snapshot 拒绝或 tombstone 代替隔离；也不得只在某一个图表临时过滤。新增依赖账本的系统表面必须消费 facade 的可读 segment，而不是直接抓取未经关系验证的 SwiftData 行。隔离不是永久数据修复：长期缺父记录仍应作为同步诊断呈现。

验证：缺 task 与缺 session 的 segment 保持持久但不进入统计，父记录导入后原 ID 自动恢复；session/task 错配始终不进入 Home、Analytics 或系统表面；staged snapshot restore 兼容测试继续通过。

## AD-037：倒计时标题采用显式草稿提交

状态：Accepted

背景：逐字符持久化会制造写入风暴，把尚未输入完成的标题同步到其他设备，也无法在模型变更前给出稳定的验证反馈。

决策：标题编辑器维护本地草稿，只在点按“保存”、Return 或输入框失焦时提交。命令在任何模型变更前先去除首尾空白并验证：标题不能为空、不得包含换行或控制字符，UTF-8 编码后不得超过 4 KiB。提交失败时保留草稿并显示可访问的行内错误；外部持久化值刷新不得覆盖脏草稿。日期选择器保持独立的即时保存行为。

后果：未提交文字不是同步事实，输入过程不会按字符写入 SwiftData；用户仍可明确看到保存状态和失败原因。

验证：覆盖草稿状态、失败时模型零变更、UTF-8 精确边界、界面契约与本地化，并以 iOS 模拟器截图和 UI 测试确认实际交互。

## AD-038：Inbox 建议驳回绑定不透明逻辑修订

状态：Accepted

背景：旧实现用物理 `InboxItem.id` 关联建议，并把“生成过但当前无建议”当作驳回。iCloud 合并、快照恢复或去重若以另一物理 UUID 重建同一逻辑条目，旧驳回会丢失并再次触发 AI；按标题或标题哈希关联又会泄露可推测标识并错误合并同名独立条目。

决策：V10（`1.9.0`）为每个 Inbox item 保存不透明 `suggestionContextID` 与 `suggestionRevisionID`，suggestion 同步保存二者，item 只保存当前 `dismissedSuggestionRevisionID`。context 在物理 row 重建时保持，真实标题修改轮换 revision 并允许重新建议。逻辑合并分成两层：title、notes、completion、completedAt、sortOrder 等内容先按 `updatedAt` last-write-wins 选择整行（同时间 tombstone 优先），dismissal marker 再只对完全相同的 `(context, revision)` 做字段级 OR；marker 不参与内容 winner 选择，也绝不跨 revision。快照 capture/restore 必须保留同一规则。所有 item mutation（包括 reorder）同时 tombstone 同 context 的物理 sibling，且不能先按 UUID 去重而漏掉同 ID 的不同 SwiftData 对象；建议 mutation 同时处理同 context/revision 的记录。异步建议的成功与失败都绑定请求时的完整 identity 和规范化标题；apply 边界重新抓取并只消费当前 canonical、active、title-match、ready suggestion。identity 只能是随机 UUID 或迁移时的 legacy record UUID，禁止从用户文本、规范化文本或哈希派生。

后果：同名独立 Inbox 条目不合并，旧副本不能复活已驳回建议，标题真正改变后仍可获得新建议；较旧的 dismissal 也不能把较新的 notes、完成状态或顺序整行回滚。每个 item/suggestion 只增加固定数量 optional UUID，不新增无界 dismissal log。字段会随业务记录进入 CloudKit/JSON，但不增加用户文本或内容指纹。V9 model shape 必须冻结，旧 snapshot 缺少字段时以物理 UUID 兼容恢复并推断旧 dismissal；以 snapshot 为本地赢家时，缺席的逻辑 sibling 墓碑必须早于恢复 row。

验证：同 ID 与不同 ID sibling 都覆盖“newer 内容字段 + exact-revision dismissal”，另测跨 revision 不传播；覆盖相同标题独立 context、revision 轮换、suggestion index、discard/delete/reorder sibling 清理、A→B→A 的 stale success/failure、canonical apply 的墓碑/旧 sibling/旧刷新 ID/标题不匹配、V9 磁盘迁移、缺字段旧 JSON 恢复、opaque 字段导出和 tombstone sibling restore。所有签名构建保留团队 `LT98S43NKA`。

## AD-039：Today 采用单一计时主动作与有界自适应层级

状态：Accepted

背景：旧 Today 把摘要、通用新建任务、计时入口、预测和时间线放在相近视觉层级，手机上首屏目的不明确，宽屏又把卡片无限拉长。各 section 独立查询和分组同一批数据，还会让一次 view composition 重复扫描账本。辅助功能字号下保留横向密集行则会截断任务名、趋势和操作。

决策：Today 的信息优先级固定为 Now、Overview、Quick Start、Timeline，再到 Forecast 和 Countdown。无活动计时时只有一个突出的 Start Timer；已有活动计时时根据 `allowParallelTimers` 显示次级 Start Another Timer 或 Switch Timer。通用新建任务不与 Today 计时操作并列，只保留在任务域和任务选择器。iPhone 使用单栏顺序；iPad/macOS 先从详情 viewport 扣除两侧 page padding，再以 1180 pt 为内容宽度上限。实际内容宽度达到 1000 pt 且存在辅助内容时，Quick Start/Timeline 为主栏，Forecast/Countdown 为 360 pt 辅助栏，否则回到单栏。根组合每次只构造一个 `TodayHomeContent`，向各 section 传入稳定、去重的预计算数组。摘要先规范化一次候选 segment，再用单个循环同时聚合今日与前一日；Wall 只在各自区间列表上做合并。每秒 `TimelineView` 只包住活动时长，结束记录保持静态，摘要每 30 秒刷新。辅助功能字号使用纵向指标、可换行任务操作和更高的任务选择器 presentation。

后果：可以打破旧 Today 顺序、按钮名称和宽屏排版，但所有平台共享同一计时命令、任务可用性、读模型事实与可访问性标识。新增 Today 卡片必须说明它属于主工作流还是辅助信息，不得重新引入第二个竞争主动作、无界宽度或 section 内重复全量查询。第三方列表/布局库不能仅为这个原生层级引入；FlowDown 继续只作模式参考。

验收要求：Home read-model/布局/UI contract 覆盖稳定去重、单次 segment 遍历、动作语义、扣除 page padding 后的 1000 pt 双栏边界、1180/360 pt 上限和辅助字号重排；iPhone Large 与 Accessibility、iPad 横竖屏和 macOS 窗口截图检查真实层级。UI 测试先等待 `home.view`，再滚动并操作 `home.startTimer`，只有任务选择器真实打开才算通过；模拟器结束后恢复字号/方向并关闭设备。contract 与 regression 的提交本身不代表运行通过，必须另外保留成功的 signed test/result bundle。构建保留 Automatic signing、团队 `LT98S43NKA` 和付费开发者能力。

## AD-040：Focus 展示采用显式会话层级与有限倒计时刷新

状态：Accepted

背景：旧 Focus 设置页没有“下一次会话”层级或最近记录上下文，Plan/Task 被包装成卡片式自绘选择，长任务只显示标题，计划摘要还遗漏长休息。活动页把整个滚动页面放进每秒 `TimelineView`，导致任务查询、操作和布局一起失效；break 过期后仍无限轮询，而且命令虽允许明确提前继续，界面却强制等待归零。

决策：Focus 设置以一个“下一次专注”主面板和一个最近记录面板组成；空间足够时双栏，窄屏单栏。页面必须从外层有限 viewport 只选择一棵布局树，辅助字号强制单栏；不得让嵌套 `ViewThatFits` 同时测量包含 Menu、Picker 与账本的完整双栏/单栏子树。Plan/Task 保持两个带标签的原生 `Menu`，Task 展示派生标题路径，只保留一个紧跟选择器的 prominent“开始专注”，方案摘要随后公开 focus、short break、long break 与 rounds。iOS 滚动内容必须为浮动标签栏保留末端余量；section accessibility identifier 只附着在标题或明确容器元素，不能从整张卡片覆盖 Menu/Button 的稳定标识。iPhone tab、iPad/macOS sidebar 与页面标题统一使用独立的 `nav.focus`；`nav.pomodoro` 保留给账本来源、设置和分析领域。活动页仅让 `PomodoroActiveCountdownView` 进入 timeline；`PomodoroCountdownSchedule` 从当前 entry 有限推进到 deadline，低频模式按 60 秒推进，deadline 不存在或已过时不继续轮询。break 未归零时显式操作为“跳过休息”，归零后改为“开始下一轮专注”，两者调用同一带 run ID/expected state 的 resume 命令，后台仍不得自动创建 focus segment；Task 不可工作时 UI 禁用恢复入口。停止确认保存发起时的 run ID，active run 被替换或结束时撤销旧确认，禁止旧 UI 状态停止另一条 run。Timer face 合并阶段、完整任务路径和本地化剩余时长的 VoiceOver 语义，重复的视觉进度条从辅助功能树隐藏。

后果：不得恢复标题/计时器隐藏点击、卡片内嵌卡片选择器、只显示任务短标题、遗漏长休息的摘要、根页面 periodic timeline 或 break 归零后的无限刷新。UI 可以改变布局与提前继续的操作时机，但 deadline、reconcile、run/session/segment 写入及停止确认仍由既有领域命令负责。

验证：行为测试覆盖内建 plan identity、有限 schedule 精确包含 fractional deadline、nil/past deadline 单 entry、break action 文案切换和可朗读 duration；source contracts 固化自适应布局、单一主操作、局部 timeline、完整路径、Dynamic Type 与三语键。Focus UI test 必须按当前系统 TabBar 的真实 frame 把主操作完整滚到其上方，不能以部分可点的 `isHittable` 代替无遮挡。最终发布前仍需保留付费开发者签名，完成 iPhone/iPad/macOS build，并以普通/最大辅助字号、VoiceOver、长同名任务、break 未到期/刚到期及宽窄窗口做实机或模拟器截图验收；每次使用后释放模拟器资源。

## AD-041：Analytics 首页先复盘，再渐进披露图表与指标

状态：Accepted

背景：旧首页在摘要后继续以一个“分类”列表平铺概览、时间、任务、番茄钟、决策和质量。首两行重复摘要的 gross/wall 值，真正帮助用户判断下一步的决策与质量信号被埋在下方。

决策：保留系统 `List`、typed `NavigationLink(value:)` 和六个既有详情目的地，但首页分成两个显式顺序：`reviewCategories` 先展示 Decisions/Quality，`exploreCategories` 再展示 Time/Tasks/Pomodoro/Metrics。原 Overview 用户文案改为 Metrics，避免与首页摘要同名。两组必须不重不漏地覆盖 `AnalyticsCategory.allCases`，不引入新的自绘导航或第三方 dashboard 容器。

后果：首屏优先呈现可行动的复盘入口，详细趋势、分布、专注记录和术语继续渐进披露；路由值、快照数据和详情内容不变。任何新 category 都必须显式归入一组，不能因 `allCases` 自动追加到意外位置。

验证：单元测试固定两组顺序与完整性；source contract 固定分组、三语键与稳定 accessibility identifier；iPhone UI 测试滚动到最后的 Metrics 入口，并按真实 Tab Bar frame 验证整行无遮挡。后续仍需覆盖最大 Dynamic Type、深色、iPad 和 macOS 宽屏截图。

## AD-042：Analytics 刷新由数据截止时间驱动

状态：Accepted

背景：Analytics landing 与 category detail 原先各自用 30 秒 `TimelineView` 包裹整页。即使没有活动计时或用户正在查看历史，两棵视图树仍持续失效；两个周期还可能错开，不能保证在 cache 使用的真实分钟边界更新。长时间打开历史周/月时，单纯停止周期刷新又会让本地日期和时区变化长期冻结。

决策：`AnalyticsRefreshPlan` 根据同一 `liveRefreshBucket` 计算下一个绝对分钟边界；只有所选当前 period 与活动 segment 相交时走分钟刷新。静态当前范围通过 `Calendar.dateInterval(of: .day).end` 等待下一本地日边界，禁止用固定 86,400 秒推算；历史范围不保留 clock task。plan identity 包含生成它的 wall-clock sample，确保同一分钟内的系统时钟回拨也会重启等待。根 `AnalyticsView` 只在 active scene 以 `.task(id: refreshPlan)` 持有结构化、可取消 sleep，进入后台即取消，并在 scene 回到 active、日历日、系统时钟或时区变化时立即重采样 `Date()`。category detail 复用根页面的 `liveNow`，snapshot 仍只由 versioned `.task(id: request)` 计算。日期选择和 period 切换以用户动作发生时的当前时间重判是否跟随当前 period。

后果：静态与历史 Analytics 不再每 30 秒让整页失效；活动数据仍最多延迟到下一个真实分钟边界。导航进入详情不会叠加 timer。未来增加新的 Analytics destination 必须复用共享时间语义，不能自行创建根级周期时钟；系统时间向后或时区改变必须重新安排 deadline。

验证：行为测试覆盖 59.9 秒到整分钟、过期 bucket 回退、历史范围不调度、同 bucket 新 wall-clock sample 改变 plan identity，以及 DST 跳时日从 00:30 到下一本地午夜为 22.5 小时。源码契约确认 landing/detail 都没有全页 `TimelineView`，并保留 active-scene request/refresh 两个有 ID 的 task。签名构建和 UI 回归使用付费开发者配置；模拟器批次结束后必须关停设备和 runner。

## AD-043：Analytics 历史求值分离周期、截止点与墙钟

状态：Accepted

背景：历史 Analytics 曾把选中周期替换为 `period.end - 1 second` 并把该值同时当作 period anchor、统计 `now` 和系统墙钟。由于所有时间事实使用半开区间且秒数在读模型边界转为整数，这会让午夜前最后一秒消失，让 23:00 到 00:00 只得到 3,599 秒；同时 Ledger 看到“now 早于 index evaluation date”后会把候选集扩张为全部历史，导致每次历史查询退化成全库过滤。若直接改成 `period.end` 而仍从该日期反推 period，又会错误落入下一日、周或月。

决策：`AnalyticsPeriodEvaluation` 是 landing/detail 的共享求值上下文，分别保存选中的 Calendar `DateInterval`、聚合 cutoff 和真实 `clockReference`。当前周期 cutoff 为 live wall clock；已完成历史周期 cutoff 精确为 `interval.end`；未来周期 cutoff 为 `interval.start`，因此开始前贡献零。Analytics facade、domain snapshot、daily cache、timeline、group breakdown 和 comparison 显式传递 period/cutoff；cache request 只使用 period start，不从 cutoff 反推周期。Live-minute bucket 只在 `interval` 包含真实 `clockReference` 且活动 segment 相交时生成，因此历史范围稳定为 nil。Ledger range query 新增 `evaluatedAt`/`clockReference` 双时间边界：前者用于 day index overlap 与 `TrackedTimePolicy` 裁剪，只有后者早于 index evaluation date 才启用全库 clock-rewind fallback；旧 `now` API 继续把两者设为同一值，保持当前读模型兼容。

后果：完整历史日/周/月保留所有 `< period.end` 的事实，最后一秒和跨午夜整小时不再丢失；历史开放 segment 在周期末裁剪，未来或零长度行不计入。历史读取继续使用 range-scoped day index，不因选择旧日期而扫描全部 ledger；真实系统时钟回拨仍保持安全的全量候选。任何新增历史统计都必须携带显式 period/cutoff/clock reference，禁止重新引入 `end - epsilon` 或用 cutoff 反推 calendar period。

验证：覆盖当前/历史/未来 evaluation、23/25 小时 DST 日、today/week/month 最后一秒、零长度、历史开放 segment 精确裁剪、cache 以选中 period start 命中，以及 40 条跨日 ledger 中历史 query 只选中目标日、真实 rewind 才扩大到全量。签名测试必须显示团队 `LT98S43NKA`、付费 Apple Development identity 和既有 CloudKit/App Group entitlement。

## AD-044：Analytics 环比使用相同日历进度

状态：Accepted

背景：当前日、周或月只走到 cutoff，但旧 comparison 会把它与上一个完整日、周或月比较。上午数据因此几乎必然被判定为“下降”；当前月越靠近月初，偏差越大。直接按 elapsed seconds 截断上一周期又会让 23/25 小时 DST 日的本地钟点错位，按月减一也不能可靠表达 3 月 31 日对 2 月的边界。

决策：`AnalyticsComparisonWindow` 显式携带 current、previous 与 basis。cutoff 位于周期内部或周期开始时，basis 为 `.matchedProgress`：current 从 period start 到 cutoff；previous 使用相同的日历日序与本地时分秒，DST 跳时仍对齐用户看到的钟点，长月不存在的 previous 日期在 previous interval end 截止。cutoff 精确等于已完成 period end 时，basis 为 `.completePeriods`，两个窗口都保持完整。gross 与 wall 使用相同窗口；指标脚注和 comparison insight 依据 basis 显示“上一周期同期”或“上一个完整周期”，不得再使用含糊的“上一范围”。

后果：实时 Today/Week/Month 的变化值可直接用于决策，不再混入上一周期尚未走到的时间；历史周期仍保留完整对完整语义。未来周期的 cutoff 位于 start，因此 current 与 previous 都是零长度 matched window。任何新环比指标必须复用 comparison window，不能另外按固定 86,400 秒、7 天或 30 天切片。

验证：行为测试覆盖当前日排除昨日下午、当前周与月的同日序/同钟点、夏令时跳时日的本地 noon 对齐、3 月 31 日映射到 2 月末、完整历史月 full-to-full，以及未来月的双零长度窗口；三语本地化 parity 继续通过。

## AD-045：Analytics 月导航保留原始日号锚点

状态：Accepted

背景：直接对当前参考日期执行 `Calendar.date(byAdding: .month, ...)` 会把不存在的日期夹到短月末，并把这个临时结果误当成下一步锚点。因此 Jan 31 → Feb 28 后继续前进会落在 Mar 28，而不是恢复到 Mar 31。单纯改用月份 interval start 又会丢失用户选择的日号与日内时间；把锚点放在 `ViewThatFits` 的某个分支或 landing 页面局部状态，还会在宽窄布局切换或进入详情时再次丢失。

决策：月份身份只通过所选月份的 `Calendar.dateInterval(of: .month).start` 做月位移。`AnalyticsMonthNavigationAnchor` 独立保存连续导航开始时的本地 day/hour/minute/second；把锚点映射到目标月时，日号只对该月的有效 day range clamp，锚点自身不变，并使用 Calendar 的匹配策略处理本地时区与 DST。根 `AnalyticsView` 持有该状态，landing、category detail 和 `ViewThatFits` 的所有 period control 共享同一 binding。直接日期选择、range 变化和 Today 操作清除旧锚点；目标月份为当前或未来时返回 `liveNow` 并清除锚点。

后果：Jan 31 可以稳定往返 Feb 28/29 与 Mar 31，反向导航和 DST 偏移变化也保留原本地时分秒。用户明确选择新日期后会以新日期建立下一段导航语义；进入当前月后重新跟随真实时间。任何新增 Analytics 月导航入口都必须复用根锚点，不能自行从短月结果推导下一步日号。

验证：行为测试覆盖非闰年 Jan 31 → Feb 28 → Mar 31、闰年 Feb 29、Mar 31 → Feb 28 → Jan 31、跨 DST offset 的本地时分秒，以及进入当前月返回 `liveNow` 并清除锚点。源码契约确认锚点由根页面持有、由 landing/detail 共享，日期选择与 Today 会重置它；统一签名/build/UI 验证由主 Agent 在付费开发者配置下执行。

## AD-046：Analytics 日趋势只发布已开始日期并保留秒级精度

状态：Accepted

背景：DailySummary 会为完整周/月生成 bucket。旧趋势把当前月尚未到来的日期也映射成零值，折线因此在“今天”之后人为跌到零；同时 View 直接用 `Int seconds / 60`，不足一分钟的真实记录也会画成零。Wall 柱与 Gross 线只靠蓝绿颜色区分，没有可见图例。

决策：完整 calendar period 的 daily buckets 继续留在 `LedgerBucketCache`，确保 key 与局部失效稳定；只有向 read model 映射时才用 `DailySummaryService.visibleSummaries` 过滤 `date < clamp(cutoff, period.start...end)`。当前周/月包含正在进行的本地日、排除未来日；完整历史周期包含全部日；未来周期为空。`DailyAnalyticsPoint` 在模型层以 `Double(seconds) / 60` 提供分钟值，Chart 不得做整数除法。Swift Charts 使用 blue Wall bar、green Gross line、可见原生图例，并保留每个 mark 的日期与完整 duration VoiceOver 值。

后果：趋势线不会把未来误表示为低产出，也不会把 1...59 秒误表示为零；缓存仍可跨 cutoff 复用完整周期的固定日 bucket。颜色不是唯一解释渠道，mark 类型、文字图例和辅助语义共同区分 Wall/Gross。任何新增趋势筛选都必须发生在 cache lookup 之后，不能让展示 cutoff 改变 bucket identity。

验证：当前 4 月 28 日只生成 1...28，完整历史 4 月生成 1...30，未来月生成空数组；相同缓存仍保留 30 个 bucket；30 秒与 15 秒分别得到 0.5 与 0.25 分钟。source contract 固定 fractional properties、foreground scale、底部图例与逐点 VoiceOver；三语键和 iPhone 周/月趋势截图必须通过。

## AD-047：UI 测试 runner 单目标串行，验证矩阵显式并行

状态：Accepted

背景：UI 测试会启动同一个有状态 App、扩展与自动演示数据，并按顺序截图。共享 scheme 曾把 UI test target 标记为 parallelizable；一次断言失败后 Xcode 自动创建多个 Clone，第二个 runner 被 SpringBoard 拒绝启动，`xcodebuild` 随后卡在 test-session 清理，同时留下扩展进程和崩溃弹窗。继续增加 worker 不会提高这种有序端到端用例的有效吞吐量。

决策：主 scheme 只把 `timetrackerUITests` 标记为 nonparallelizable；`timetrackerTests` 继续并行。验收截图命令显式使用 `-parallel-testing-enabled NO -maximum-parallel-testing-workers 1`，每个 destination 只有一个 runner。多 agent 与 iPhone/iPad/macOS/watchOS 验证仍受鼓励；需要并行矩阵时，由主 Agent 为每个 destination 分配独立、可追踪的 UDID、result bundle 和 DerivedData，而不是让 Xcode 隐式克隆同一个有状态 runner。

后果：这是资源所有权和测试确定性约束，不是单 Agent 或低负载策略。每个模拟器批次结束时必须 terminate App、shutdown/delete 本批自建设备、关闭 Simulator/Problem Reporter，并确认没有 Booted 设备、`xcodebuild`、`xctest`、UI runner 或 App 扩展残留；不得关闭其他 agent 明确拥有的设备。不得为了让 UI 测试通过而禁用付费开发者签名或 entitlement。

验证：源码契约固定 unit target 为 `parallelizable=YES`、UI target 为 `parallelizable=NO`。iPhone 17 Pro 月导航用例在禁用并行克隆后只创建一个 runner，完整 xcresult 通过并输出两张截图；清理后 CoreSimulator 与进程审计为空。

## AD-048：Analytics 小时活动采用全日共享 gross 尺度

状态：Accepted

背景：Today 的小时活动图曾把完整 plot 高度交给每个非空小时的 task stack。于是 30 秒与 60 分钟都会画成同样满高，用户无法比较小时强弱；若直接把单小时固定夹到 3,600 秒，并发计时产生的 gross 又可能超过一小时。旧 stack 还把层间 spacing 算在切片之外，导致“task 高度之和”和最终柱高使用不同口径。

决策：`HourActivityScale` 在同一日的 24 个 `HourTaskActivity.totalSeconds` 上建立共享尺度，上限为 `max(3_600, maxHourlyGrossSeconds)`。每小时以秒级比例映射到有限 plot 高度，零值保持零高，30 秒等亚分钟值保留 fractional height；并发 gross 超过 3,600 秒时，整日所有柱使用同一个扩展上限。`HourStackLayoutEngine` 只接收该小时的目标高度，按每个正时长 task 的秒数分配全部 slice，并校正浮点残差，使所有 slice 高度守恒。层间视觉分隔使用不参与布局的单像素 overlay，极薄 slice 不叠加 separator；图高随 Dynamic Type 缩放，辅助字号横轴只保留 0/12/24 三个刻度并把图例收敛成单列。三语 subtitle 明说“柱高比较时长、颜色区分任务”，每小时仍以本地化 VoiceOver value 报告真实总时长和完整 task 明细。

后果：非空小时不再自动满高，同一天的柱高可直接比较；并发不会被错误截断为一小时，亚分钟记录也不会消失。背景槽仍提供 24 小时位置参照，颜色、分隔和 VoiceOver 共同表达 task 分层。任何新增小时图都必须复用共享尺度，禁止在单个 bar 内按自身最大值重新归一化，或用分钟整数除法计算高度。

验证：单元测试覆盖 3,600 秒下限、7,200 秒并发上限、30 秒的 1.25pt fractional height、空值/非有限几何输入，以及 task slice 高度严格回收到目标柱高；UI source contract 固定共享尺度、`@ScaledMetric`、零 spacing、overlay separator、底部 target frame、辅助字号单列图例与既有 VoiceOver 语义。付费开发者签名的最终 macOS 定向套件 40/40 通过；默认字号和 Accessibility XXXL iPhone 截图此前均通过。AX 截图揭示双列图例换行过窄后，最终源代码改成单列并通过签名编译与契约测试；随后的两次新模拟器复验均被 iOS 27 XCTest runtime 在测试入口前以 `Timed out waiting for AX loaded notification` 拦截，不属于 App crash 或断言失败。所有成功与失败批次的专用模拟器都已关闭并删除，最终进程审计无 runner、`xcodebuild` 或诊断残留。

## AD-049：iOS 根导航由稳定设备 idiom 选择

状态：Accepted

背景：旧 `iOSRootView` 把 `horizontalSizeClass == .regular` 当成 iPad，其他宽度当成 iPhone。iPad 进入分屏、Stage Manager 窄窗口或中间宽度时会变为 compact，于是整个 `NavigationSplitView` 被替换成五标签 `TabView`；sidebar selection、detail navigation 和各根容器内部状态都可能被重建。大屏 iPhone 横屏也可以出现 regular width，size class 并不是设备类型。

决策：`RootLayoutPolicy` 只将稳定 interface idiom 映射为 `.phone` 或 `.pad` shell。iOS 根视图在初始化时从 `UIDevice.current.userInterfaceIdiom` 构造策略，iPhone 始终使用五标签根导航，iPad 始终使用同一个 `NavigationSplitView`。宽度变化仍可以驱动页面内容重排和 split view 的系统列折叠，但不得改变根 shell 身份。未支持 idiom 在 iOS target 安全回落到 phone shell，不假设其具有 iPad 导航语义。

后果：iPad 在全屏、Split View 和 Stage Manager 间调整尺寸时保留 sidebar/detail 上下文；`NavigationSplitView` 依旧使用 `preferredCompactColumn` 和系统 Show Sidebar 操作适配窄宽。功能内局部布局可继续使用 size class，但新的设备级根分支必须使用 idiom 或显式平台信号。

验证：纯策略测试覆盖 phone、pad 和 unsupported 映射；源码契约确认 `iOSRootView` 使用 `UIDevice.current.userInterfaceIdiom`、不再读取 `horizontalSizeClass`。付费开发者签名的 macOS 策略/契约套件 31/31 通过，截图基础设施调整后的最终契约套件 8/8 通过。iPad Pro 11-inch 的串行 UI 用例使用系统 Show Sidebar，选择合并语义后的 task row，再在同一 scene 中竖屏→横屏→竖屏；三次都保留 `ipad.splitNavigation`、同一 task detail 和只读状态，三张屏幕级截图目视通过。Stage Manager 紧凑窗口仍保留在最终人工矩阵，不以旋转测试替代。所有专用模拟器都已终止、关闭并删除，最终进程与 Booted 设备审计为空。
## AD-050：辅助字号保留主动作文字与任务行完整事实

状态：Accepted

背景：iPhone Today 在已有活动计时且进入 Accessibility Dynamic Type 后，把 Start Another Timer / Switch Timer 从 Now 内容流移到 section header，并只留下图标。视觉用户需要猜测这个唯一计时入口的含义；VoiceOver 虽有补充 label，仍不能弥补可见操作文字消失。Tasks 的专用辅助字号行则只保留标题、异常状态和运行状态，删除了普通/紧凑行已有的完整路径、已工作时长、清单进度、预测和子任务数，导致放大文字反而降低信息完整性。

决策：Today 的已有计时主动作始终是 Now section 内的带文字原生 `Button`；文字允许纵向生长，section header 只承担标题，不承载仅图标主操作。Tasks 的辅助字号布局按标题、去重后的完整路径、状态/运行中、已工作时长、清单/预测和子任务数纵向展示，与普通布局共享同一个 `TaskManagementRowPresentation`。任务详情按钮继续保持一个原生 Button、稳定 identifier 和 hint；`TaskManagementRowAccessibilitySnapshot` 以有序组件生成完整 label/value，禁止通过 `accessibilityRepresentation` 或 `.accessibilityElement(children: .ignore)` 覆盖后只手工补回部分字段。

后果：Accessibility 字号会使用更多垂直空间，但不会把关键动作变成谜语，也不会以“简化”为名删除任务事实。视觉布局和 VoiceOver 投影可以分别优化呈现方式，字段集合必须保持同步；新增任务行元数据时必须同时更新普通/紧凑/辅助布局、语义快照和测试。

验证：源码契约固定 Today 无字号分支的完整文字操作、Tasks 辅助布局的路径/时长/进度/预测/子任务字段以及不使用语义替换或忽略 children；单元测试固定语义快照的字段顺序、阻塞状态替换和重复路径消除。Team `LT98S43NKA` / `Apple Development: ZEXUAN GAO (PX46M259V3)` 签名的 macOS 定向套件 50/50 通过，xcresult 为 `/tmp/timetracker-accessibility-context-final-20260716.xcresult`。显式拥有的 iPhone 17 Pro（iOS 27）以 Accessibility XXXL 串行执行 Today、Tasks、Settings 三条 UI 用例，3/3 通过；xcresult 为 `/tmp/timetracker-accessibility-context-ui-20260716.xcresult`，导出的三张截图位于 `/tmp/timetracker-accessibility-context-ui-images-20260716` 并已目视检查文字换行、字段完整性与主动作可见性。UI 测试检查了 VoiceOver 使用的 accessibility label/value 投影，但未把它冒充真人 VoiceOver 遍历；该项仍属于最终人工矩阵。专用设备 `9CEA8CAE-F2B6-4AE7-B092-DEFB389653F4` 已终止、关闭并删除，最终无 Booted 设备、runner、`xcodebuild`、`xctest`、Simulator 或 Problem Reporter 残留。

## AD-051：系统表面把“打开”与“修改”分离并冻结陈旧计时

状态：Accepted

背景：小组件空状态曾把整个背景 URL 改为第一项 recent task 的启动链接，点击非控件区域也会创建计时；Live Activity 虽然显示 stale 标签，计时文本和 VoiceOver value 仍持续增长。锁屏视图又把图标、任务、计时和停止按钮永久压在一个横行，长本地化标题、窄设备和辅助功能字号会互相挤压。

决策：Widget 容器背景只深链到“今日”，任何开始任务 mutation 都必须由带任务名的显式 Link 发起。Live Activity 以共享 `LiveActivityTimingPolicy` 同时生成八小时 `staleDate` 和 elapsed presentation；stale 后可见值与辅助功能值都冻结在同一边界。锁屏和 expanded 布局使用 Dynamic Type 分支与 `ViewThatFits` 提供堆叠/换行回退，停止动作维持 44×44 pt 独立目标；compact/minimal 继续服从系统的极窄 presentation 约束。

后果：背景点击不再产生意外账本事实；陈旧系统投影不会伪装成仍在实时同步；大字和窄宽度优先保留任务身份、冻结状态与停止能力。八小时后的主账本计时仍可继续，冻结只描述 Live Activity 投影可信度。

验证：纯行为测试固定 stale date、live/frozen 两种 presentation 与八小时秒数；源码契约固定 Widget 背景 URL、显式 Quick Start、冻结 formatter/accessibility value、Dynamic Type 分支、`ViewThatFits` 和两行回退；三语本地化键集保持一致。Team `LT98S43NKA` 的签名定向套件 39/39 通过，xcresult 为 `/tmp/timetracker-widget-liveactivity-semantics-20260716.xcresult`；generic iOS 自动签名构建及主 App、Widget、Live Activity、Watch 的 embedded binary validation/严格签名校验通过，构建结果为 `/tmp/timetracker-widget-liveactivity-signed-build-20260716.xcresult`。小屏普通字号与最大辅助字号截图仍由主 Agent 在后续显式拥有的模拟器批次完成并清理资源。

## AD-052：APS 使用 provisioning profile 认可的规范 entitlement 键

状态：Accepted

背景：主 App entitlement 文件曾声明 `com.apple.developer.aps-environment`，但 Apple provisioning profile 和最终签名使用的规范键是 `aps-environment`。Automatic Signing 没有让构建失败，而是从生成的 `.xcent` 和最终 App 签名中移除了未知键；因此只检查源 plist 或“Build Succeeded”会误报 CloudKit 远程通知能力已进入产物。

决策：主 App 只声明 `aps-environment = development`，并由源码契约拒绝旧的非规范键。每次系统能力验证必须同时读取源 entitlement、embedded provisioning profile、生成 `.xcent` 和最终 `codesign -d --entitlements`；profile 中存在能力但最终签名缺失仍视为失败。

后果：开发构建会真正携带 APS entitlement，CloudKit 远程变更通知不再因键名错误被静默剥离。Release/Distribution 的环境值仍由对应 profile 和配置决定，不能把开发构建的 `development` 证据冒充发布证据。

验证：`SigningEntitlementContractTests` 固定规范键和值并禁止旧键，签名定向运行 1/1 通过，xcresult 为 `/tmp/timetracker-aps-entitlement-contract-20260716.xcresult`。使用 Team `LT98S43NKA` 与 `Apple Development: ZEXUAN GAO (PX46M259V3)` 的 generic iOS 自动签名重建通过，结果为 `/tmp/timetracker-aps-entitlement-signed-build-20260716.xcresult`；源 entitlement、生成 `.xcent`、embedded profile 和最终 App signature 均确认为 `aps-environment = development`，并同时保留 CloudKit、App Group 与相同 team identifier。主 App 及所有嵌入目标通过 `codesign --verify --deep --strict` 和 Xcode embedded binary validation。

## AD-053：计时选择与停止使用彼此独立的显式命令

状态：Accepted

背景：Today 的主入口会明确显示 Start Timer、Start Another Timer 或 Switch Timer，但旧任务选择器把每个任务都包装成同一种整行按钮。点按未运行任务会开始计时，点按运行中任务却会立即停止并关闭选择器；同一个视觉与 VoiceOver 目标因此按隐藏状态改变命令，既不像“开始”，也没有清楚表达停止的影响。

决策：`TimerPickerCommandPolicy` 是选择器模式与任务选择命令的共同语义来源。没有活动计时时模式为 start；允许并行且已有活动计时时为 start another；独占模式已有活动计时时为 switch。运行中任务的选择命令恒为 `alreadyRunning`，不得触发 start、switch 或 stop。选择器把运行任务放入独立状态区，停止只能由同一行中可见、带任务名辅助标签的 Stop 按钮触发，且停止后不关闭选择器。可选任务行必须可见显示 Start 或 Switch；Switch 的三语 footer 与 VoiceOver hint 明说会先停止冲突计时。只有开始或切换写入成功才关闭选择器并更新全局任务 selection；写入失败保留原 selection 和当前上下文。

后果：任务行不再把状态伪装成动作，误点运行任务不会丢失正在记录的时间上下文；停止、开始与切换均有单独可发现的触点和稳定的 Voice Control/VoiceOver 名称。`TimeTrackerStore.startTask` 返回真实写入成功值，使 sheet 不会在写入失败时假装完成。其他计时入口如需复用选择器，必须调用同一 policy/Store 编排，不得在 View 中按 `activeSegment` 自行写成 toggle。

验证：行为测试覆盖模式矩阵、运行任务选择严格 no-op、显式 Stop 才结束该 segment、独占切换停止旧计时、并行开始保留旧计时，以及写入失败时不改变原任务 selection。UI source contract 固定运行/可选分区、独立 Stop 标识、成功后才 dismiss、Start/Switch 基本语义、任务身份色与三语键。付费 Apple Development 签名的 command/UI 定向套件 9/9 通过（`/tmp/timetracker-timer-picker-layout-macos-rerun-20260716.xcresult`）；正常字号 iPhone 17 Pro / iOS 27 操作与截图 1/1 通过（`/tmp/timetracker-timer-picker-ui-color-retry-20260716.xcresult`）。截图确认顶部搜索、完整标题、仅父级路径、分行 Start/Running/Stop，以及任务身份主文本色与红色 Stop 图标/文字；一次中间重跑只在 App launch 阶段超时，不计为通过。两台专用设备均在各自批次后终止、关闭并删除，不为极端字号另开专项批次。

## AD-054：任务树 projection 由 mutation-owned read index 与有界缓存发布

状态：Accepted

背景：`TasksView` 与 `SidebarView` 已使用持久 UUID 作为 `ForEach` identity，也已有 task/path/children 基础索引，但每次 SwiftUI `body` 求值仍会重新去重 category、按 category 分组 root、遍历展开树，并在每个可见 row 再过滤一次 children。搜索状态还会因 timer、selection 等无关失效而重扫全部 task。层级越大，稳定的既有索引反而没有成为 UI 的真正读取边界。

决策：`TaskTreeService` 在 task mutation/refresh 时建立排序、循环/孤儿修复和显示路径基础索引；`TimeTrackerStore.rebuildTaskTreeReadIndex` 是 task、category 与 assignment 对 UI 层级 projection 的唯一失效 owner。不可变 `TaskTreeReadIndex` 保存 canonical source order、可见 child ID buckets、稳定 section/root IDs、每行 child count 和标题/显示路径/notes 搜索值。只有这些值语义变化时才推进 `taskTreeReadIndexRevision`。`TaskTreeProjectionCache` 以 revision 自动清空旧 projection，并分别用容量四的 LRU 缓存 expansion set 与 search query；缓存只保存 ID/value model，不保留 SwiftData object。展开 projection 对每个可见 task 只查一次 child bucket，不在 row/body 排序、过滤或走祖先链。`TaskTreeRowModel.id` 继续等于持久 task UUID，category section ID 继续等于 category UUID 派生值，未分类 section 使用固定 ID。

后果：无关 timer、ledger、selection 或重复等价 task refresh 不再重建任务树/搜索 projection；task/category/assignment 的真实语义变化会在同一 store refresh 边界使所有 UI surface 看到新 revision。展开或新 query 的首次读取仍按可见行或可搜索 task 数线性计算，但同 key 重绘为有界 cache hit。新增 task-tree surface 必须消费该 read index/projection，不得在 `body` 重新 `filter/sorted/grouping` 全树；新增搜索字段必须同时进入 read-index equality/失效语义。容量不得改成无界历史。

验证：等价性测试把新 projection 与旧 category+flattener 语义逐项比较，覆盖归档分支、分类/未分类、深度、child count、标题路径和 notes 搜索；identity 测试确认输入顺序改变不改变 hierarchy row/section IDs。cache 测试覆盖重复命中、LRU 容量、revision 失效和 store 对无关刷新/等价 refresh 不推进 revision。5,000 节点测试固定 fully-expanded projection 为每个可见 task 一次 child bucket lookup，并固定重复 projection/search 不增加 build count。旧的 624 行聚合实现进一步按 model、read index、projection cache、repair、service、flattener 与 read-index assembly 拆为 7 个 50–121 行文件，并由每文件不超过 160 行的结构合同约束。主 Agent 使用付费开发者身份执行签名的 task-ledger、task-tree read-index 与 task UI 定向套件，65/65 通过；精确 source-layout/Project Map 合同 3/3 通过。该批不需要模拟器；完整 SourceLayout suite 仍有既存 Analytics 文件预算红项，不能由本切片冒充全绿。

## AD-055：Analytics 重叠明细以 excess 守恒而非墙钟跨度计量

状态：Accepted

背景：overview 已把 overlap 定义为 `gross - wall-clock`，但旧 sweep 明细只选前两个活动 segment，并把每个并发窗口的墙钟长度显示为 overlap。两条记录并发时两者数值刚好相等，三条以上并发时则不再成立：五条记录同时运行一小时，overview 为四小时，而旧明细只有一小时；按可变标题构造行身份还会在同名或改名后失稳。直接列出全部活动记录又会让密集 overlap 回退到逐事件扫描活动集合。

决策：overlap 的唯一产品语义是 excess。固定 sweep 窗口内有 N 条 segment 时，精确贡献为 `(N - 1) × elapsed window`；全窗口整数秒经过确定性的余数分配后必须严格等于同一批 bounded items 的 `gross - wall-clock`。`OverlapAnalyticsPoint` 分开 start/end、墙钟秒数、excess 秒数、并发 segment 数和唯一 participant task 数。参与者以持久 task UUID 为身份，标题仅展示；每个窗口最多物化三个稳定排序的参与者，其余只公开数量。sweep 在相同时间先处理 end 再处理 start；只有边界前后并发度与 task membership 都不变时才合并相邻窗口。同一任务的连续 segment 可以因此合并，真正的参与者或并发度变化不能被抹平。参与者使用带 resident ID 的 lazy min-heap，保持 `O(n log n)`；界面显示 excess 最大的六个窗口，并汇总未显示窗口数与隐藏 excess。

后果：明细与总览在任意并发度下守恒，不再把“发生并发的 1 小时”误报为“五路计时多出的 1 小时”。同一 task 的重复 segment 会增加并发度和 excess，但参与任务只出现一次。跨日与 DST 先在 bounded read boundary 裁剪，再按绝对 elapsed seconds 计算；UI 的时间范围只描述墙钟窗口，数值明确标为 excess。不得重新引入 title-based identity、只取前两个 segment 的 pair 模型，或隐藏剩余窗口却不公开其 excess。

验证：覆盖五路同窗、三路交错、同 task 重复 segment、同名 task 仍按 UUID 分离、同边界替换并合并、隐藏 participant 替换不合并、仅边界相接不重叠、零/负时长排除、春秋 DST 跨午夜裁剪、稳定 tie 顺序、输入倒序和亚秒余数守恒；presentation 测试确认可见 excess 与隐藏 excess 合计不丢秒。source contract 固定 wall/excess 分离、UUID participant、明确 excess 文案与隐藏汇总。主 Agent 使用付费开发者身份执行 Analytics store、timeline 与 UI contract 签名定向套件，86/86 通过；正常字号的 Analytics 实机目视验收并入后续单设备 UI 批次，不另开辅助功能专项批次。

## AD-056：定向停止链接不得回退到其他计时

状态：Accepted

背景：Live Activity 的停止链接携带所属任务的 `taskID`，共享 system-action command 也接受可选任务 identity。两处旧处理逻辑都把“未找到该任务的活动 segment”和“动作没有 taskID”合并成 nil-coalescing 回退；如果用户延迟点击已结束任务的陈旧系统表面，而另一任务正在计时，就会误停后者。

决策：停止深链分为两种明确语义。带 `taskID` 的定向动作只查询该任务的活动 segment，目标不存在时无操作；只有不带 `taskID` 的通用动作才选择当前最近的活动 segment。路由校验与 Store 执行都保留这个 optional identity，禁止用一次 `flatMap ?? fallback` 再次抹平两种状态。

后果：陈旧 Live Activity、Widget 或外部定向链接不会修改无关任务；通用“停止计时”链接仍能停止当前最近计时。新增系统入口必须明确选择定向或通用语义，不能在定向目标失效时扩大 mutation 范围。

验证：Store 与共享 system-action command 的行为测试都构造“目标任务已停止、另一任务仍运行”，固定定向停止后无关 segment 在内存 read model 与 repository 中保持活动；既有无目标测试继续约束通用动作停止最近计时。主 Agent 使用付费开发者身份执行 deep-link 与 system-action 签名定向套件，23/23 通过；该批不需要模拟器，结束后设备、构建、测试 runner 与 App 进程审计均为空。

## AD-057：正常字号、核心操作路径与 HIG 是默认审核主线

状态：Accepted

背景：极端 Dynamic Type 专项已经帮助修复 Today、Tasks、Settings、Analytics、Widget 和 Live Activity 的信息丢失与布局问题，但持续把全库审查资源集中在最大辅助字号，会挤占正常字号、核心操作路径、平台原生行为、性能和系统能力验证。用户明确要求后续不再以极端 Dynamic Type 专项作为审核主线。

决策：产品继续保留基本且不可退化的辅助功能语义，包括有名称的原生操作、正确的 role/state/value、非纯颜色信息、合理触控目标和 VoiceOver 可理解性；已经实现的大字号自适应不得因资源优先级变化而主动移除。默认静态审查、截图、模拟器和实机矩阵优先覆盖正常字号、正常操作路径及当前平台 Apple HIG，包括信息层级、导航、反馈、键盘/指针、窗口适配、深浅外观和系统集成。极端 Dynamic Type 不再是每个小批次或全库收口的重复主线；只有变更直接涉及文本重排/截断、出现明确辅助功能回归、用户报告问题或发布风险要求时，才增加定向极端字号验证。

后果：主 Agent 应先完成常规体验与发行能力的高价值验证，再按风险投入辅助功能专项资源。不得把“不是默认专项”解释为允许删除 accessibility label、隐藏状态、仅靠颜色表达或回退已经通过的布局；也不得为了形式化矩阵反复启动高成本模拟器批次而延误核心路径审核。

验证：默认验收记录正常字号核心路径、平台 HIG 和基本辅助语义；任何极端 Dynamic Type 批次都说明触发风险、受影响页面和资源所有者，并遵守统一的模拟器清理合同。一次性截图、UDID 和 xcresult 证据继续记录在 Audit，而不是写入本决策。

## AD-058：同步恢复与日常同步操作分层

状态：Accepted

背景：旧“同步”Section 把开关、状态、检查、刷新和两个会覆盖一侧数据的恢复命令连续排列。恢复命令使用绿色/青色普通动作外观；用户即使在冲突时也看不到本机与 iCloud 摘要，只能根据“上传/下载”猜测哪一侧会被替换。

决策：`SyncSettingsSection` 只保留无数据覆盖语义的日常状态与操作；`SyncRecoverySettingsSection` 成为独立的低频危险区。恢复按钮使用系统 destructive role、共享红色 label，并直接写明“用本设备替换 iCloud”或“用 iCloud 替换本设备”。存在冲突时，两个动作之前必须展示 `SyncConflictPrompt` 的本机与 iCloud 摘要，而且两个方向都调用 `resolveSyncConflict`，与全局冲突对话进入相同的冲突解析边界；无冲突时才使用基于当前 store 的手动恢复命令。二次确认使用简短替换动词，并同时说明其他设备传播、先完成同步以及 local-fallback 需重启排队的后果。

后果：Settings 的常用路径不再把恢复工具伪装成普通刷新；用户在选择权威副本前能比较两侧事实。全局冲突对话与 Settings 使用相同的方向性文案。恢复实现、iCloud 数据结构和排队语义不在此 UI 批次修改；以后新增恢复命令也必须留在危险区，不能混入日常状态 Section。

验证：源码合同固定两个 Section 的职责分离、两项 destructive role、冲突双摘要、明确确认动词和三语键。主 Agent 使用付费开发者身份执行同步冲突行为、Settings 安全合同与共享组件签名定向套件，55/55 通过；正常字号的 iPhone/iPad/Mac“数据与同步”页面及确认对话目视检查进入后续 UI 批次，任何模拟器都按批次明确拥有并在当批删除。

## AD-059：Settings 破坏性确认只有一个 Form-owned presentation owner

状态：Accepted

背景：`SettingsView` 曾在根列表连续附加重建 Demo、清除 Demo、清空全部、清理记录、替换 iCloud 和替换本机六个 `confirmationDialog`。正常字号 iPhone UI 测试发现点击“用本设备替换 iCloud”后没有任何确认；合并为一个可选枚举后仍不出现，证明 compact `NavigationLink` destination 还位于根列表 presentation modifier 的有效层级之外。这会让危险按钮表面看似有二次确认，实际却无反馈。

决策：Settings 所有破坏性动作以 `SettingsDestructiveConfirmation?` 表达唯一 pending intent。一个 `confirmationDialog` 根据该枚举生成标题、说明、红色确认动作和取消语义，并附着在实际包含 category sections 的 `Form`。动作 closure 捕获明确枚举 case 后再进入对应 Store/同步命令；不得恢复并列多个同类 presentation modifier，也不得把确认 owner 放在 compact navigation destination 之外。

后果：重建、清理、清空与两个同步覆盖方向共享相同且可达的系统 presentation 边界，不会因 modifier 顺序让只有最后一个动作能显示。新增 Settings 危险操作必须扩展枚举并复用该入口；普通刷新、检查和导航不进入这个状态机。iOS 27 可能把确认呈现为 popover，并通过弹窗外区域取消，测试不能为了关闭面板点击真实破坏性动作。

验证：首轮 UI 失败保留为缺陷发现证据，不计通过。修复后 iPhone 17 Pro / iOS 27 正常字号 UI 回归分别打开“替换 iCloud”和“替换本机”确认，核对方向性按钮和说明，随后只点击系统 `PopoverDismissRegion`；1/1 通过，xcresult 为 `/tmp/timetracker-sync-confirmation-rerun3-20260716.xcresult`。Settings 安全合同与同步冲突签名回归 43/43，xcresult 为 `/tmp/timetracker-settings-confirmation-macos-20260716.xcresult`，Team `LT98S43NKA`，identity `Apple Development: ZEXUAN GAO (PX46M259V3)`。专用模拟器已删除，设备、runner 与测试进程审计为空。

## AD-060：恢复关键本机文件共享耐久提交与有界隔离 primitive

状态：Accepted

背景：主应用、Shortcuts 与扩展将逐步共享 outbox、恢复 artifact 和小型状态文件。各自重复实现 `Data.write(.atomic)`、路径字符串锁和损坏文件改名，无法统一证明进程死亡、目录 entry 持久化、符号链接、并发隔离、文件保护与诊断保留上限；原始候选实现还曾因 Foundation 对文件系统根目录父路径的新表示进入无限祖先循环。

决策：恢复关键的小型本机文件使用 `DurableLocalFile`/`PathFileLock` 作为文件系统底座，并由业务 owner 在其上提供版本、大小与语义验证。调用方为一个状态家族选择唯一、稳定且已存在的 durable root；同 root 的写入、删除和隔离共享保留锁文件。primitive 只接受普通 canonical 文件，拒绝符号链接、目录、特殊文件和锁文件本身；临时文件在发布前完成保护、backup metadata 与 full sync，再原子 rename 并同步目录。进程死亡遗留的严格命名临时文件在下一次同目录写入时有界清理。隔离目录跨 prefix 共用 8 文件、16 MiB、14 天上限，回滚失败必须暴露 canonical 和 quarantine 两个位置。

后果：调用者不能把 durable root 当作随调用变化的“目标父目录”，也不能把这套 primitive 当作 JSON validator、ACID 多文件事务或敌对进程防护。发布后目录同步失败意味着新文件可能已经可见，恢复逻辑必须可重入。高频账本写入不应为了复用而逐条调用 full sync；它只服务需要进程死亡/掉电恢复语义的小型状态边界。既有私有持久化 owner 逐个迁移并各自提交，不能在一次大替换中混合数据结构、幂等策略和 CloudKit schema。

验证：核心测试固定目录创建中断重放、发布前旧文件不变、崩溃临时文件回收、普通文件类型、保留锁路径、符号链接与 dangling symlink、跨 prefix 数量/字节/时间预算、超限删除、隔离回滚与回滚失败、硬链接别名互斥、写入/隔离共享 root 锁，以及每个生产文件不超过 160 行的职责合同。macOS 行为与结构套件、generic iOS 设备 SDK 自动签名构建都必须通过；iOS 构建还要保持主 App、Widget、Live Activity、Watch 的付费开发者签名及 APS、CloudKit、App Group 能力。一次性 xcresult 与路径记录在 dated Audit。

## AD-061：iPhone 长页面使用系统 Tab Bar 下滚收起行为

状态：Accepted

背景：iOS 27 的 Liquid Glass Tab Bar 浮在滚动内容之上。正常字号截图证明 Focus 主动作和 Analytics 最后一组都可以滚到系统栏上方，但默认 `.automatic` 在 iOS 不会收起五项 Tab Bar，长页面浏览时持续占据较大的底部视觉层。给每个页面叠加固定 safe-area padding 会与动态系统 chrome 和既有 List/ScrollView inset 重复，且不能解决内容本身的信息层级问题。

决策：仅 iPhone 的根 `TabView` 使用系统 `.tabBarMinimizeBehavior(.onScrollDown)`。首屏保留 Today、Inbox、Tasks、Focus、Analytics 五个顶级导航项；向下浏览长内容时由系统缩成当前标签，点按或回到顶部时按系统规则恢复。页面继续使用原生 List/ScrollView 安全区，不增加全局自制底栏或固定 bottom safe-area 补偿。Focus 首屏重排、任务身份去重等内容问题另行修复，不能用收起 Tab Bar 掩盖。

后果：长页面获得更多可读空间，同时保持 Apple 平台原生导航、滚动与恢复动画。iPad 继续使用 Sidebar/Detail shell，不套用 iPhone 收起行为。以后若引入 `tabViewBottomAccessory`，必须重新验证 accessory placement 与收起后的内容边界，不能同时叠加固定底部空白。

验证：正常字号 iPhone UI 测试必须让 Focus 主动作和 Analytics 最后一项完整位于当前系统 chrome 顶部至少 8 pt；截图同时确认首屏五项 Tab Bar 完整、下滚后缩为当前标签。generic iOS 设备 SDK 自动签名构建继续保留主 App、Widget、Live Activity、Watch 的付费签名与 APS、CloudKit、App Group。一次性设备与结果路径只记录在 dated Audit。

## AD-062：Focus 首屏优先完成设置与启动

状态：Accepted

背景：正常字号 iPhone 的 Focus 首屏把计时器、计划、任务、主操作和四项计划摘要排成过高的纵向卡片。任务选择又同时显示标题和包含该标题的完整路径，造成重复；四项计划摘要固定为 2×2 网格，进一步把“开始专注”后的必要上下文推到浮动 Tab Bar 下方。此前 112 pt 固定底部 content margin 还与系统滚动安全区和可收起 Tab Bar 重复。

决策：紧凑宽度使用 18 pt 卡片内边距、20 pt section spacing 和 16 pt 页面垂直边距；常规宽度保留 24 pt 节奏。任务选择主行只显示任务标题，第二行显示不重复标题的父级路径；Picker 菜单继续使用完整路径区分同名任务。四项计划指标优先在一行展示，宽度不足时由 `ViewThatFits` 回退到 2×2 Grid。正常字号滚动末端只保留 16 pt 内容节奏并依赖系统 safe-area/tab chrome inset；不得再用大块固定空白掩盖首屏层级问题。

后果：正常字号 iPhone 首屏可以同时看到完整设置卡、开始专注和全部四项计划事实，最近记录仍作为次级可滚动内容。Mac、iPad 和宽窗口继续使用更宽松间距；同名任务的区分能力保留在父级路径和完整 Picker 项中。后续新增 setup 信息必须先判断是否属于启动前必要事实，不能继续纵向堆叠到主操作之前。

验证：布局策略与源码契约固定紧凑/常规间距、页面垂直边距和“标题 + 父级路径”任务身份。付费签名的 macOS 合并定向回归 72/72 通过；正常字号 iPhone 17 Pro / iOS 27 Focus UI 1/1 通过，截图确认完整设置、主操作及四项摘要都位于系统 Tab Bar 上方。generic iOS 设备 SDK 自动签名构建 0 error/0 warning，主 App、Widget、Live Activity、Watch 均保留 Team `LT98S43NKA` 与付费 Apple Development 身份，主 App 保留 APS、CloudKit 和 App Group。一次性证据路径与设备清理记录见 dated Audit。

## AD-063：LLM 模型发现于解码阶段保持固定上限

状态：Accepted

背景：模型响应虽然已有 2 MiB transport 上限，旧 `LLMModelListResponse` 仍会先把整个 `data` 数组解码为 `[Model]`，随后才建立无界 `Set`、排序并交给偏好 sanitizer 截到 256 项。异常服务可以在字节预算内返回大量短 ID，使临时对象数量、集合和排序开销显著高于最终 UI/偏好能够使用的范围。

决策：模型列表使用 unkeyed container 逐项解码，并把 ID 立即送入共享 `LLMModelIDAccumulator`。Accumulator 复用偏好层的完整 opaque ID 验证，始终只保留按字符串升序最小的 256 个唯一有效 ID；新值只有进入这个有界前缀时才插入，超出后立即丢弃。模型 ID 仍按完整 UTF-8 值比较和发送，不裁剪、不改写；偏好数组与网络响应必须得到相同的确定性结果。

后果：模型发现的业务内存与排序集合固定在 256 项，不再随服务返回的 model count 增长；transport 的 2 MiB 总字节上限仍是外层防御。若将来 UI 支持分页或服务端搜索，应新增明确协议而不是扩大这个本地全量列表。不得重新先解码整个 `[Model]` 或为“显示更多”维护无界集合。

验证：测试覆盖精确 256 项、超限后更小 ID 替换、重复/空白/控制字符、256-byte ASCII/Unicode 边界和超限 Unicode，并确认网络响应结果与偏好 sanitizer 完全一致。付费签名 macOS `LLMSettingsTests` 21/21、0 error/0 warning；当前合并工作树 generic iOS 自动签名构建 0 error/0 warning，主 App 与所有嵌入目标保留 Team `LT98S43NKA`、付费 Apple Development 签名及主 App 的 APS/CloudKit/App Group。一次性 xcresult 见 dated Audit。

## AD-064：Inbox 刷新只发布合并读模型，不写回持久 winner

状态：Accepted

背景：CloudKit 可能暂时 materialize 同一 Inbox 逻辑条目的多个物理 sibling。内容以 LWW winner 展示，dismissal 则必须按精确 `(contextID, revisionID)` 从所有 sibling 合并。旧 `fetchInboxItems` / `InboxStore.refresh` 为了让 UI 看见 dismissal，会在读取时直接给 winner 写 `dismissedSuggestionRevisionID`；没有用户动作的一次 refresh 因此把 `ModelContext` 标为 changed，随后任意无关保存都可能把派生合并结果作为新同步事实上传。

决策：`InboxItemMergeResolution` 生成不可持久化的 `InboxItemReadModel`，其中只保存 winner 引用与合并后的 dismissal revision。Inbox domain store 排序并发布这些 read model；facade 为当前物理 winner 建立索引，所有 suggestion display、自动生成准入和异步结果落库前校验都使用 read model 的合并状态。普通 fetch/refresh 不再调用 materialize。只有明确的 Inbox mutation command 在完成身份和文本预检后，才通过现有 logical-mutation 边界把 dismissal 物化到需要写入的 sibling。

后果：启动、CloudKit 通知和普通 domain refresh 都保持 `ModelContext.hasChanges == false`，同时 UI 仍正确隐藏已驳回的当前修订，并阻止自动/延迟建议复活。读模型不成为第二套持久事实；每次 refresh 都从当前物理行重建。新增 Inbox 读取入口必须消费同一 resolution/read-model 语义，不得重新在 getter、sort、index rebuild 或 View 中写 SwiftData。

验证：真实内存 SwiftData context 构造“旧 sibling 有 dismissal、新 winner 有更新内容”的逻辑条目，确认刷新后 winner 字段保持未改、建议不可见、state 为 dismissed 且 `context.hasChanges == false`。付费签名的 Inbox identity/apply/persistence/cancellation/store/write-safety 六套定向回归 46/46、0 error/0 warning；当前合并工作树 generic iOS 自动签名构建同样 0 error/0 warning并保留全部付费签名与主 App 能力。一次性 xcresult 与资源审计见 dated Audit。

## AD-065：任务域排序必须有持久 UUID 终局比较

状态：Accepted

背景：生产 repository 已用 depth、sortOrder、createdAt、UUID 排序，但 `TaskStore.refreshTaskScoped` 在合并未受影响行与局部 fetch 后只比较前三项。CloudKit 同时创建、导入或测试夹具可以产生前三项完全相同的任务；此时 comparator 对两种方向都返回 false，最终顺序受字典/fetch 输入影响，造成任务树重绘和选择上下文抖动。

决策：TaskStore 的 scoped 合并顺序与 repository 层保持相同的严格全序：depth、sortOrder、createdAt，最后比较持久 `TaskNode.id.uuidString`。标题、数组位置、对象地址和当前输入顺序都不能成为 tie-break。

后果：相同事实集合在全量与局部刷新后得到相同任务顺序和稳定 SwiftUI identity。UUID 只解决真正相等的展示顺序事实，不改变用户显式 sortOrder，也不替代任务树 projection cache。

验证：固定 UUID、相同 depth/sortOrder/createdAt 且反向输入的回归确认 scoped refresh 恒按 UUID 排列；付费签名 macOS `CoreTaskStoreTests` 6/6、0 error/0 warning。一次性 xcresult 见 dated Audit。

## AD-066：计时协调先冻结确定性纯值准入计划

状态：Accepted

背景：当前 UI facade、SystemAction、Watch、App Intent 和 Pomodoro 可以各自读取 active segments 后再写入。跨 context/进程的“检查后创建”尚未串行化，直接一次性替换所有 writer 风险过高；同时，旧代码对同任务重复活动段、通用 current、精确 segment 和 Pomodoro 必须替换现有段的语义分散，若先写锁再临场决定规则，会把不确定行为藏进临界区。

决策：先以不依赖 SwiftData 的 `TimerAdmissionPolicy` 冻结协调器输入/输出。输入 `TimerActiveSegmentSnapshot` 必须来自 fresh context 中已完成 LWW 的 canonical active set，并按 startedAt、segment UUID 建严格全序。普通 start 可复用同任务最早稳定 survivor 并停止其余重复段；需要新 session 的 Pomodoro 路径显式选择 `replaceAll`。Exclusive start 停止所有其他任务，parallel start 保留其他任务。Stop target 分为精确 segment、task 全部活动段和 current；精确目标失效必须 no-op，current 选择 startedAt 最新、同刻 UUID 最大的段。策略只返回 `TimerStartPlan` / `TimerStopPlan`，不持有 model object、不保存、不刷新 UI。

后果：生产竞态在本提交后仍然存在，不能宣称已修复；下一阶段必须让所有 active-segment writer 一次性切到同一个 store-specific 进程锁、fresh `ModelContext` 和统一提交边界，禁止只给某一个入口加锁。纯策略允许在接线前验证输入顺序无关、重复清理、显式替换和停止范围，协调器只负责授权、重取、应用、保存与 post-commit projection。

验证：12 项纯策略测试覆盖 exclusive/parallel、reuse/replaceAll、同任务重复段、四种输入排列、同刻 UUID tie-break、精确 segment 不回退、task stop all、current latest、逻辑重复输入和应用后的幂等收敛。付费签名 macOS 定向运行 12/12、0 error/0 warning；本批未启动模拟器。一次性 xcresult 见 dated Audit。

## AD-067：iOS 编辑器子流程在同一个外层导航栈内推进

状态：Accepted

背景：任务、分类和 checklist 的符号/颜色入口位于本身已经由 sheet 承载的编辑器中。旧 iOS 实现再次打开带独立 `NavigationStack` 和 Done 按钮的 sheet，形成 sheet 叠 sheet、两套导航与一个没有提交语义的伪确认；返回外层页面时，新建任务标题的自动聚焦任务还会再次运行并重新弹出键盘。macOS 的 popover 没有这一层级问题。

决策：iOS 的 `SymbolColorPickerButton` 使用 `NavigationLink`，把 `SymbolAndColorPicker` 推入 `TaskEditorPanel` 已有的外层 `NavigationStack`；macOS 继续使用轻量 popover。符号和颜色仍通过 binding 即时更新编辑草稿，子页面的 Back 只负责导航，不表示保存或提交；唯一持久提交和取消边界仍是外层编辑器的 Save/Cancel。新建任务标题只在本次编辑会话首次出现时自动聚焦，键盘支持 Done 提交与交互式滚动收起，页面从子流程返回时不得再次抢占焦点。

后果：iPhone 不再叠加 modal、重复导航标题或显示无意义 Done；用户可以选择符号后返回继续填写同一草稿，最终仍能整体保存或取消。以后在 sheet 编辑器中增加父任务、分类、日期等多步子流程时，应优先复用同一个导航栈；只有独立、可单独取消且有明确事务边界的任务才新开 sheet。macOS 小型选择器继续遵循 popover 习惯。

验证：源码合同固定 iOS push、macOS popover 和不存在内层 sheet/Done；付费签名 macOS `TaskUIContractTests` 34/34、0 error/0 warning。正常字号 iPhone 17 Pro / iOS 27 UI 回归完成“新建任务 → 输入草稿 → 搜索并选择 calendar → Back”，确认 sheet 数不增加、草稿和选择保留、返回后键盘不重弹，1/1、0 warning。generic iOS 设备 SDK 自动签名构建 0 error/0 warning，主 App、Widget、Live Activity、Watch 均保持 Team `LT98S43NKA` 与付费 Apple Development 身份，主 App 保留 development APS、CloudKit 和 App Group。一次性证据与模拟器清理记录见 dated Audit。

## AD-068：独立任务表面显示标题与父级上下文，动作图标不冒充身份

状态：Accepted

背景：Quick Start 在 iPhone 同时显示任务标题和包含该标题的完整路径，造成重复；iPad/macOS tile 则只显示标题，并把任务自己的 symbol 替换成播放或停止图标。结果是同名子任务无法区分，用户也无法稳定识别任务本身，三个平台和编辑器使用了不同的身份表达。View 直接调用 `path(for:)` 还让展示规则分散，并可能诱使后续代码通过拆分带 `/` 的可变标题来推导父级。

决策：`TaskIdentityPresentation` 是脱离任务树上下文的统一展示投影，由既有 `TaskTreeIndexes` 使用 task、parent path 和 full path 索引 O(1) 构造。`.hierarchical`、`.standard`、`.compact` 分别表达只有标题、标题加父级路径、单行完整路径三种明确上下文；根任务的空父路径规范为 nil。`TaskVisualPresentation` 在 SwiftUI 边界前把未知 symbol 和颜色规范为 canonical fallback。Quick Start 的 iPhone 行、iPad/macOS tile 和编辑器使用 `.standard`：任务 symbol 始终表达身份，播放/停止 glyph 始终单独表达动作，不得互相替换。路径仅作展示，不从字符串反向解析层级。

后果：同名子任务可通过父级路径区分，根任务不再重复标题，标题中包含 `/` 也不会破坏身份推导；三个平台和编辑器共享一致信息层级。以后迁移任务选择器、Pomodoro、Widget 或 Watch 时可以按所在表面选 context，但必须继续消费索引投影，不在 View 中重造路径或视觉 fallback。该投影不改变持久模型或 iCloud schema。

验证：纯值与索引测试覆盖根/子任务、同名任务、标题内 `/`、三个 context 和无效视觉 fallback；源码合同固定 Quick Start 不调用 `store.path(for:)`、身份与动作 glyph 分离。付费签名 macOS 定向套件 22/22、0 warning；正常字号 iPhone 交互与截图 1/1、0 warning，确认根/子任务、独立动作 glyph 和编辑器层级。generic iOS 自动签名构建严格验证全部嵌入 bundle 与主 App entitlement。macOS UI runner 两次因系统认证正在运行而在测试初始化前被系统取消，不计作 UI 通过，也不继续重试；一次性设备、截图、失败发现和 xcresult 只记录在 dated Audit。

## AD-069：计时事务先按持久 store 串行化，再创建 fresh context

状态：Accepted

背景：纯值 `TimerAdmissionPolicy` 已冻结 start/stop 语义，但 UI facade、SystemAction、Watch、App Intent 和 Pomodoro 仍可在不同 `ModelContext` 甚至不同进程中各自执行“读取 active → 判断 → 写入”。只在现有 context 外套进程内 actor 无法覆盖扩展进程；先创建 context 再等待文件锁又可能把锁前的旧 snapshot 带入临界区。持久 store 还可能通过带符号链接的不同路径被引用，若锁 identity 不先 canonicalize，会把同一数据误当作两个 store。

决策：`TimerStoreScope` 为每个计时 store 提供稳定 identity：持久 store 解析已存在祖先的符号链接并保留尚未创建的尾部组件，内存 store 由 container owner 在整个生命周期复用显式 UUID。`StoreScopedTimerMutationLock` 从 scope 派生同目录 `.timer-mutations.lock`，复用已经审计的 `PathFileLockRegistry` 和 `PathProcessFileLock`，不再实现第二套 `flock`。`StoreScopedTimerMutationTransaction` 的固定顺序是“取得 store lock → 创建 fresh `ModelContext` → 关闭 autosave → 执行一次 `performAtomicMutation`”；operation 抛错或最终保存失败时回滚，离开作用域释放锁。

后果：未来 coordinator 可以在单一临界区内重新读取 canonical active facts、计算 admission plan 并提交，且不同 store 不互相阻塞。锁内不得做网络、UI、系统 surface 刷新或返回依赖 context 生命周期的可变 model；提交后的 facade projection 与扩展通知在锁外进行。该提交只提供底座，没有迁移任何生产 writer，因此竞态仍然存在；后续接线必须一次覆盖所有 active-segment writer，禁止只保护某个 UI 入口后宣布完成。

验证：6 项付费签名 macOS 测试覆盖持久路径别名、内存 lifetime identity、同 store 串行、不同 store 并行、抛错释放、锁内 fresh context、不同 context 实例，以及一次提交与抛错回滚；结果 6/6、0 error/0 warning。合并工作树 generic iOS 设备构建继续通过严格签名与 entitlement 审计；本批未创建模拟器。一次性 xcresult 见 dated Audit。

## AD-070：任务列表与详情共享一个系统导航栈，route 不冒充业务选择

状态：Accepted

背景：任务详情曾同时由 `TasksView` 的本地 `detailTaskID`、facade 的 `desktopTaskDetailID` 和桌面根视图条件分支控制。iPhone 需要相互同步两份状态；iPad/macOS 打开详情则直接把整个任务列表根替换掉。自绘 Back 再分别调用 store 和 `dismiss()`，容易产生双重 pop、失败删除仍退出、返回后搜索/展开状态丢失，以及侧边栏选中项与真实页面脱节。

决策：`TasksNavigationView` 在三平台持有唯一 `NavigationStack` 和唯一 `TasksView` 根，使用 `navigationDestination(item:)` 直接绑定 store-owned `TasksRoute?`。当前 route 只表达页面导航；`selectedTaskID` 继续表达计时和业务选择。打开任务由 facade 先验证存在且未删除，再更新 route、selection 和 Tasks 目的地；系统 Back 只把 route 设为 nil。详情不再提供自绘 Back 或手动 `dismiss()`。删除成功、维护成功或 refresh 发现任务失效时清 route；写入失败不改变 route/selection。sidebar selection 从 route/destination 派生，并随任务树 revision 重算当前任务祖先展开，不保存镜像 selection。

后果：返回任务列表时，原 `TasksView` 实例及其搜索、展开状态都保留；iPhone、iPad、macOS 和 deep link 复用同一条路由路径。删除父任务会关闭后代详情，外部删除会在下一次一致性 refresh 后 pop；普通 Back 不会改变计时器的已选任务。后续若任务域需要更多详情子页面，应扩展 typed `TasksRoute`，不得重新引入 root 条件替换、本地 task ID 镜像或伪系统返回按钮。

验证：付费签名 macOS route/deep-link/lifecycle/UI-contract 定向套件 75/75、0 error/0 warning；正常字号 iPhone 17 Pro / iOS 27 系统 Back UI 1/1，截图确认详情返回后 `Study` 分支仍展开。generic iOS 自动签名设备构建 0 error/0 warning，主 App、Widget、Live Activity、Watch 严格签名验证通过并保留 Team `LT98S43NKA`、付费 Apple Development、development APS、CloudKit 与 App Group。iPad Pro 首次自动化启动在进入 App 前 timeout，Xcode 收尾又挂起，因此终止该 owned build/diagnose 并记为基础设施阻塞，不计 UI 通过；两个专用 UDID 均已删除，最终无 Booted 设备或 owned runner/process。一次性证据见 dated Audit。

## AD-071：App 级 sheet 按 scene 仲裁，共享 Store 不共享 presentation

状态：Accepted

背景：主 App 曾把任务、分类、手工时间、segment、Inbox 和任务选择器的 presentation 状态放在应用级 `TimeTrackerStore`，Today、Tasks、Timeline、Pomodoro 与 Settings 又各自附加独立 `.sheet`。这允许同一 scene 的多个入口同时竞争、覆盖带未保存修改的 draft，也会让 macOS Settings 中触发的“手动补录”错误出现在主窗口。任务选择器进入新建任务还依赖先关闭再 `Task.yield()`，存在 presentation 空窗；启动时连续 deep link 则能在先改导航后才发现 modal 冲突。共享 Store 对 CloudKit observers 和领域状态是正确的，但对窗口局部 UI 生命周期不是正确所有者。

决策：每个可呈现 UI 的 scene 以 `@State` 持有一个 `AppPresentationRouter`，并只附加一个 `AppPresentationHost.sheet(item:)`。`AppPresentation.Content` 以 typed payload 承载任务编辑、分类编辑、手工时间、segment 编辑、任务选择器、Quick Start 和 LLM 配置；Store 不再保存这些 draft 或 `isPresented`。router 忙时拒绝普通新请求，不替换当前编辑；replace/dismiss 必须匹配当前 presentation ID，旧 closure 不能关闭后来内容。任务选择器进入新建任务使用 matching-ID 原子替换，不经过异步 dismiss/yield。主窗口与 macOS Settings 共享应用级 Store、但各自拥有 router；focused Mac 命令只使用当前主 scene 的 router，并在 slot 忙时禁用。Settings 删除“手动补录”入口，补录保留在任务/时间线工作流和 Mac `Shift-Command-M`。未被任何生产入口使用的 Inbox suggestion editor UI 被删除，Inbox 继续保留明确的 apply/discard 流程。

Deep link 返回 `handled`、`deferred` 或 `rejected`。需要导航或 modal 的动作必须先取得当前 scene 的 presentation slot，再修改 destination；slot 忙时进入既有 16 项、语义去重的 `PendingDeepLinkQueue`，sheet 关闭后有界重放。start/stop 不需要 modal，可以在无关编辑器打开时直接执行。全局 store error 与 sync-conflict alert/dialog 仍是下一项独立的 scene 归属问题，本决策不把它们伪装成已经解决。

后果：同一 scene 只有一个 App 级 sheet，脏编辑器不会被其他 feature 的 modal 请求覆盖；独立 Settings 不会把 UI 弹到主窗口。保存命令只返回业务成功，presentation 的关闭由 sheet 自己的 `dismiss` 负责；失败保持原草稿。新增 App 级 sheet 必须扩展 typed content 和唯一 host，不得在 feature 或共享 Store 重建平行 `.sheet` 状态。局部确认对话、文件 exporter 和真正属于单个控件的 popover 可以保留局部 owner，但必须与 App 级 slot 的职责区分。

验证：付费签名 macOS presentation/deep-link/refactor/completed-task/UI-contract 定向套件 96/96，0 skip、0 runtime warning；正常字号 iPhone 17 Pro / iOS 27 的任务编辑→Focus 与 Today→任务选择器两条 UI 流程 2/2，截图导出到 `/tmp/timetracker-scene-presentation-iphone-images-20260716`。任务编辑截图底部出现的是该新模拟器的一次性 iOS 键盘教学浮层，不是 App 自绘内容；另外两张确认 Today 与单一任务选择 sheet 的正常层级。generic iOS 自动签名构建 0 error/0 warning，主 App、Widget、Live Activity、Watch 均通过 `codesign --verify --deep --strict`，保持 Team `LT98S43NKA`、`Apple Development: ZEXUAN GAO (PX46M259V3)`；主 App 保留 development APS、CloudKit 与 App Group。唯一专用 UDID `4ECB7632-880B-45B8-9E04-7045B511B895` 已终止、关闭并删除，最终无 Booted device、owned build/test/runner、Simulator 或 Problem Reporter。本批只验证正常字号常规路径，没有安排 Accessibility 专项。

## AD-072：任务行的菜单与滑动删除共用一个确认 owner

状态：Accepted

背景：Tasks 与 Sidebar 的每个任务行都在 row 内为 context menu 保存删除确认 Bool、附加 `confirmationDialog`，随后 `TaskRowSwipeActions` 又保存第二个同名 Bool 并附加第二个相同 dialog。同一视图分支因此存在两个互不仲裁的删除 modal owner，可能竞争 presentation 或重复发起删除；同一动作在菜单又叫 “Soft Delete/软删除”，在滑动和确认中叫 “Delete/删除”，把持久实现细节暴露成了用户概念。

决策：`TaskRowSwipeActions` 只负责操作发现与转发，删除按钮调用必传的 `requestDelete`；它不持有确认 state，也不附加 dialog。`TaskManagementFlatRow` 与 `SidebarTaskTreeRow` 分别让 context menu 和 swipe 接到本 row 唯一的 `isDeleteConfirmationPresented`，确认时继续传显式 `task.id`，不从可变化的全局 selection 推断目标。Task Detail 作为不同页面保留自己唯一的确认 owner。菜单、滑动和确认统一使用 Delete/删除；未使用的 soft-delete 三语键删除。

后果：一行一次只能有一个删除确认，取消与确认路径一致；共享 swipe modifier 不再暗中引入 modal 状态。后续新增任务行入口必须复用 `requestDelete`，不得为了入口便利再在 modifier 中叠加 confirmation。领域层仍保留 tombstone 和历史账本，这不需要成为用户操作名称。

验证：付费 Apple Development 签名的 `TaskUIContractTests` 最终 34/34、0 skip/runtime warning，source contract 固定 swipe modifier 无 `@State`/`confirmationDialog`、两个 row 各只有一个 dialog、两入口共用 callback，并固定用户文案不再引用 `task.action.softDelete`；xcresult 为 `/tmp/timetracker-delete-confirmation-tests-final-20260716.xcresult`。本批未创建模拟器，结束后无 owned build/test/runner 或 Booted device；只检查正常交互结构，没有启动 Accessibility 专项。

## AD-073：同步覆盖确认绑定精确 conflict token，并在 state lock 内 CAS

状态：Accepted

背景：同步恢复确认曾只保存上传/下载方向。用户看到冲突 A 的本机/云摘要后，CloudKit observer 或本机 mutation 可能在最终确认前把 pending state 改成 B；按钮随后重新读取“当前冲突”并直接覆盖，等于按 A 的信息解决 B。即使逻辑冲突 ID 没换，pending 期间的新本机或云端改动也会改变实际 resolution snapshot，而旧实现仍保留原 ID并可能返回变化前 prompt。“最初无冲突”的手动恢复也可能在 confirmation 打开期间迎来新冲突，再错误清掉它。

决策：`pendingConflictID` 是用户看过的两侧摘要版本 token。pending 状态下，local branch 或 cloud branch 的 resolution-relevant snapshot fingerprint 变化时，在 `SyncConflictService` 的跨进程 state lock 内旋转 token，并从更新后的 state 重建 prompt。ContentView 的 `confirmationDialog(presenting:)` 与 `SettingsDestructiveConfirmation` 都捕获当次展示的 optional ID。`resolveSyncConflict(expectedConflictID:resolution:)` 在同一个 `withExclusiveStateAccess` 内先 locked-load，再精确比较实际 optional ID；比较早于 `advanceSyncEpoch`、snapshot restore、reset flag、`clearPendingConflict` 和 `saveState`。不匹配返回 `conflictChanged` 且零副作用；匹配后返回 `appliedImmediately` 或 `queuedForNextLaunch`，IO/restore/save 错误由 Store 映射为 `failed` 与错误反馈。

后果：旧确认不能覆盖后来到达或后来变化的同步版本；用户必须重新阅读最新摘要并再次选择方向。expected nil 表示“确认时仍应没有 pending conflict”，不是跳过校验。Store 不得在锁外先比较 cached prompt，也不得从当前 persistence mode 推测 queued/immediate。token 只在实际 branch fingerprint 变化时旋转，重复无变化通知不会制造确认风暴；检测时间保留首次冲突发生时间。

验证：付费签名 macOS 的完整 `CoreSyncConflictTests`、新 resolution identity 套件与 Settings 安全合同最终 47/47、0 skip/runtime warning（`/tmp/timetracker-conflict-identity-tests-rerun4-20260716.xcresult`）。覆盖 matching/stale ID、expected-none、state bytes/epoch/local+cloud snapshot/模型 fingerprint/用户数据零副作用、Store prompt 保留，以及 pending local/cloud 变化后旧 token 失效。generic iOS 自动签名构建 0 error/0 warning（`/tmp/timetracker-conflict-identity-ios-signed-20260716.xcresult`）；主 App、Widget、Live Activity、Watch 均通过严格签名，保持 Team `LT98S43NKA`、付费 Apple Development，主 App 保留 development APS、CloudKit 与 App Group。本批未创建模拟器，最终无 owned build/test/runner 或 Booted device；没有安排 Accessibility 专项。

## AD-074：读取冲突 prompt 失败不能伪装成“没有冲突”

状态：Accepted

背景：`SyncConflictService.prompt()` 曾用 `try? loadState()`，把损坏、超限、权限或文件系统错误全部降级成 `nil`。调用方无法区分“确实没有 pending conflict”和“权威状态没有读出来”，可能清空界面警告、继续恢复或在后台命令提交后把故障隐藏掉。

决策：`prompt()` 改为 throwing API。前台 mutation、sync observer 与 stale-confirmation reload 沿既有 throwing 边界传播，Store 再产生明确错误反馈；Watch 命令若业务提交已成功，则把 prompt 读取错误计为 post-commit refresh failure，仍返回原 terminal command result，不能谎称已提交命令失败。只有成功读到合法 state 且其中没有完整 pending conflict，才返回 `nil`。

后果：损坏 state 会被隔离并显式报告，不再被解释为“同步安全”；调用方新增 prompt 读取点必须处理错误，禁止重新加 `try?`。同样地，已提交的业务动作与提交后 projection/snapshot/prompt 刷新必须保持不同失败语义。

验证：付费 Apple Development 签名的 macOS `CoreSyncConflictTests`、resolution identity 与 Watch command 套件 74/74、0 skip/runtime warning（`/tmp/timetracker-throwing-conflict-prompt-tests-rerun-20260716.xcresult`），新增损坏 state prompt 抛错并隔离测试；签名身份为 `Apple Development: ZEXUAN GAO (PX46M259V3)`、Team `LT98S43NKA`。本批未创建 simulator，测试后终止 owned app/TestManager，最终无 build/test/runner 或 Booted device。

## 2. Agent 工作清单

开始 Apple 平台或 SwiftUI 工作前：

1. 完整阅读 [AGENTS.md](../AGENTS.md) 指定的仓库本地 skills。
2. 读取任务相关的 HIG 与 SwiftUI reference，不凭记忆猜 API。
3. 检查工作树，保留用户和其他 Agent 的现有改动。
4. 明确当前事实、计划目标和历史记录，不混写。
5. 优先读取领域模型、命令和测试，再改 UI。
6. 把可独立复验的小批变更及时提交；只 stage 自己已核对的文件，不把其他 Agent 或用户的并行改动夹带进 commit。

完成前：

1. 运行与风险相称的 build/test。
2. 验证 iPhone、iPad、Mac 以及受影响的扩展。
3. 检查正常字号下的 HIG、本地化、隐私、迁移和同步；保留低成本基础语义，但除非用户明确要求，不启动极端动态字号、VoiceOver 或专项 Accessibility 截图/trace 批次。
4. 更新对应文档和决策。
5. 使用模拟器后关闭本次启动的设备并确认没有遗留 runner/trace 进程。
6. 报告仍为红色的测试与未验证环境，不宣称未获得的通过状态。

## 3. 相关文档

- [代码文档](CodeGuide.md)
- [隐私与安全](PrivacyAndSecurity.md)
- [2026-07-14 审核](Audit-2026-07-14.md)
- [版本与迁移](Versioning.md)
