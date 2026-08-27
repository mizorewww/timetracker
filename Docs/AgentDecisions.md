# TimeTracker Agent 决策文档

状态：有效决策记录
最近更新：2026-08-27

本文记录自动化 Agent 和维护者在实现、审核、重构时必须保持的工程边界。它不是待办清单，也不替代代码审核。一次性发现与验证证据写入对应 commit/PR；未来计划写入明确标记的计划文档。

收录门槛：本文件只收录跨领域架构、数据安全、兼容性或系统集成决策。单一功能内的 UI/展示细节（布局、文案、卡片结构、对齐、样式、字号）不收录为 AD——它们写入对应功能文档，或直接由代码与行为测试表达。历史上误收的此类条目已于 2026-08-27 移出本文件，原文见 git 历史。已替代的决策与历史测试说明保存在 [AgentDecisionsArchive](AgentDecisionsArchive.md)，不再充当当前指令。

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

决策：业务约束以领域/集成测试验证，UI 流程以 accessibility identifier 和可见行为验证。不得通过读取 Swift 源文件并匹配字符串来约束实现；entitlement、Privacy Manifest 和迁移 store fixture 等产物契约不属于源码扫描。

后果：重构测试时先补行为覆盖再删除字符串断言。测试必须隔离 UserDefaults、Keychain、locale、时区和临时数据。

验证：等价重命名或视图抽取不会让行为测试失败；失败信息描述用户行为而非源码片段。

## AD-009：文档按“当前、未来、历史”分层

状态：Accepted；dated Audit 条款由 AD-141 替代

背景：README 与多个计划曾混合当前实现和未来目标，导致 Watch、Widget、CSV 和 Inspector 状态失真。

决策：

- README、UserGuide、CodeGuide、Architecture 和 ProjectMap 描述当前事实与所有权。
- NextDevelopmentPlan 等明确标为 future 的文档描述未来，并写清前置条件和验收门禁。
- 跨多会话的较大工作可使用 implementation memory 记录范围、测试契约和临时证据，保存在 `Docs/ImplementationContexts/`；一次性结果只留在对应 commit/PR，不新增长期生效的 dated Audit，也不再维护 Archive 目录（2026-08-27 起，历史记录由 git 历史承载）。
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

状态：Accepted（BlossomColorPicker 的定向例外由 AD-117 取代本决策中的“当前不新增第三方库”；其余依赖审查边界继续有效）

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

验证：默认先覆盖正常字号的受影响页面、主操作和 iPad 宽屏。只有变更直接触及上述密集行的重排/截断，或已有回归信号时，才定向增加对应页面的 Accessibility Extra Large；不再固定重跑全套页面。

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

状态：Accepted（请求投影条款由 AD-133 取代）

背景：endpoint/API key 在每次键入时持久化会产生半配置状态、Keychain 噪声和意外请求；“已配置”不等于同意自动发送工作内容。

决策：配置 sheet 使用独立 draft；Test 只校验 credential fingerprint 并加载模型，不保存；选择有效模型后用户明确 Save 才写 endpoint/model 与 device-only Keychain。endpoint、模型列表和已选模型由一个批量 preference command 做一次 SwiftData 提交；Keychain 不是该 transaction 的一部分，提交失败时尽力恢复旧密钥并准确报告补偿失败。修改凭证会取消旧请求和旧测试结果。自动建议是默认关闭、设备本地的第二个明确开关，不参与 CloudKit/JSON。Inbox/checklist 发送前共用 `LLMSuggestionInputPolicy`：候选最多 48 项/12 KiB JSON，prompt 24 KiB，request body 64 KiB，持久化 model ID 256 bytes，文本按 UTF-8/完整 `Character` 有界投影且不回写持久事实。model ID producer 上限必须与同步快照 compact-field restore 上限相同；模型 ID 是 opaque identifier，超限或含控制字符时整体拒绝，不能截断成可能碰撞的另一个 ID。Inbox 候选按固定→高频/近期→稳定补足取舍；模型只看 78 个精选语义图标，返回 UUID/icon 必须属于实际已公告集。

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

## AD-047：UI 测试 runner 单目标串行，验证矩阵显式并行

状态：Accepted

背景：UI 测试会启动同一个有状态 App、扩展与自动演示数据，并按顺序截图。共享 scheme 曾把 UI test target 标记为 parallelizable；一次断言失败后 Xcode 自动创建多个 Clone，第二个 runner 被 SpringBoard 拒绝启动，`xcodebuild` 随后卡在 test-session 清理，同时留下扩展进程和崩溃弹窗。继续增加 worker 不会提高这种有序端到端用例的有效吞吐量。

决策：主 scheme 只把 `timetrackerUITests` 标记为 nonparallelizable；`timetrackerTests` 继续并行。验收截图命令显式使用 `-parallel-testing-enabled NO -maximum-parallel-testing-workers 1`，每个 destination 只有一个 runner。多 agent 与 iPhone/iPad/macOS/watchOS 验证仍受鼓励；需要并行矩阵时，由主 Agent 为每个 destination 分配独立、可追踪的 UDID、result bundle 和 DerivedData，而不是让 Xcode 隐式克隆同一个有状态 runner。

后果：这是资源所有权和测试确定性约束，不是单 Agent 或低负载策略。每个模拟器批次结束时必须 terminate App、shutdown/delete 本批自建设备、关闭 Simulator/Problem Reporter，并确认没有 Booted 设备、`xcodebuild`、`xctest`、UI runner 或 App 扩展残留；不得关闭其他 agent 明确拥有的设备。不得为了让 UI 测试通过而禁用付费开发者签名或 entitlement。

验证：源码契约固定 unit target 为 `parallelizable=YES`、UI target 为 `parallelizable=NO`。iPhone 17 Pro 月导航用例在禁用并行克隆后只创建一个 runner，完整 xcresult 通过并输出两张截图；清理后 CoreSimulator 与进程审计为空。

## AD-051：系统表面把“打开”与“修改”分离并冻结陈旧计时

状态：Accepted；其中 Live Activity 可见停止控件与展开布局由 AD-118 替代，stale freeze 与自适应回退保留

背景：小组件空状态曾把整个背景 URL 改为第一项 recent task 的启动链接，点击非控件区域也会创建计时；Live Activity 虽然显示 stale 标签，计时文本和 VoiceOver value 仍持续增长。锁屏视图又把图标、任务、计时和停止按钮永久压在一个横行，长本地化标题、窄设备和辅助功能字号会互相挤压。

决策：Widget 容器背景只深链到“今日”，任何开始任务 mutation 都必须由带任务名的显式 Link 发起。Live Activity 以共享 `LiveActivityTimingPolicy` 同时生成八小时 `staleDate` 和 elapsed presentation；stale 后可见值与辅助功能值都冻结在同一边界。锁屏和 expanded 布局使用 Dynamic Type 分支与 `ViewThatFits` 提供堆叠/换行回退，停止动作维持 44×44 pt 独立目标；compact/minimal 继续服从系统的极窄 presentation 约束。

后果：背景点击不再产生意外账本事实；陈旧系统投影不会伪装成仍在实时同步；大字和窄宽度优先保留任务身份、冻结状态与停止能力。八小时后的主账本计时仍可继续，冻结只描述 Live Activity 投影可信度。

验证：纯行为测试固定 stale date、live/frozen 两种 presentation 与八小时秒数；源码契约固定 Widget 背景 URL、显式 Quick Start、冻结 formatter/value、布局回退和三语键集。受影响系统表面需保持自动签名与严格嵌入产物校验；一次性结果见 Audit §7（原 `Audit-2026-07-14.md`，已于 2026-07-25 退役，证据见 git 历史）。

## AD-052：APS 使用 provisioning profile 认可的规范 entitlement 键

状态：Accepted

背景：主 App entitlement 文件曾声明 `com.apple.developer.aps-environment`，但 Apple provisioning profile 和最终签名使用的规范键是 `aps-environment`。Automatic Signing 没有让构建失败，而是从生成的 `.xcent` 和最终 App 签名中移除了未知键；因此只检查源 plist 或“Build Succeeded”会误报 CloudKit 远程通知能力已进入产物。

决策：主 App 只声明 `aps-environment = development`，并由源码契约拒绝旧的非规范键。每次系统能力验证必须同时读取源 entitlement、embedded provisioning profile、生成 `.xcent` 和最终 `codesign -d --entitlements`；profile 中存在能力但最终签名缺失仍视为失败。

后果：开发构建会真正携带 APS entitlement，CloudKit 远程变更通知不再因键名错误被静默剥离。Release/Distribution 的环境值仍由对应 profile 和配置决定，不能把开发构建的 `development` 证据冒充发布证据。

验证：`SigningEntitlementContractTests` 固定规范键和值并禁止旧键。每次签名验收同时检查源 entitlement、`.xcent`、embedded profile、最终 signature 和嵌入产物严格校验；一次性结果见 Audit §7（原 `Audit-2026-07-14.md`，已于 2026-07-25 退役，证据见 git 历史）。

## AD-053：计时选择与停止使用彼此独立的显式命令

状态：Accepted

背景：Today 的主入口会明确显示 Start Timer、Start Another Timer 或 Switch Timer，但旧任务选择器把每个任务都包装成同一种整行按钮。点按未运行任务会开始计时，点按运行中任务却会立即停止并关闭选择器；同一个视觉与 VoiceOver 目标因此按隐藏状态改变命令，既不像“开始”，也没有清楚表达停止的影响。

决策：`TimerPickerCommandPolicy` 是选择器模式与任务选择命令的共同语义来源。没有活动计时时模式为 start；允许并行且已有活动计时时为 start another；独占模式已有活动计时时为 switch。运行中任务的选择命令恒为 `alreadyRunning`，不得触发 start、switch 或 stop。选择器把运行任务放入独立状态区，停止只能由同一行中可见、带任务名辅助标签的 Stop 按钮触发，且停止后不关闭选择器。可选任务行必须可见显示 Start 或 Switch；Switch 的三语 footer 与 VoiceOver hint 明说会先停止冲突计时。只有开始或切换写入成功才关闭选择器并更新全局任务 selection；写入失败保留原 selection 和当前上下文。

后果：任务行不再把状态伪装成动作，误点运行任务不会丢失正在记录的时间上下文；停止、开始与切换均有单独可发现的触点和稳定的 Voice Control/VoiceOver 名称。`TimeTrackerStore.startTask` 返回真实写入成功值，使 sheet 不会在写入失败时假装完成。其他计时入口如需复用选择器，必须调用同一 policy/Store 编排，不得在 View 中按 `activeSegment` 自行写成 toggle。

验证：行为测试覆盖模式矩阵、运行任务选择严格 no-op、显式 Stop、独占/并行语义和写入失败保留上下文；UI 契约固定分区、独立 Stop、成功后 dismiss 和三语语义。正常字号核心路径是默认 UI 验收；一次性结果见 Audit §7（原 `Audit-2026-07-14.md`，已于 2026-07-25 退役，证据见 git 历史）。

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

## AD-057：正常字号、核心操作路径与 HIG 是默认审核主线

状态：Accepted

背景：极端 Dynamic Type 专项已经帮助修复 Today、Tasks、Settings、Analytics、Widget 和 Live Activity 的信息丢失与布局问题，但持续把全库审查资源集中在最大辅助字号，会挤占正常字号、核心操作路径、平台原生行为、性能和系统能力验证。用户明确要求后续不再以极端 Dynamic Type 专项作为审核主线。

决策：产品继续保留基本且不可退化的辅助功能语义，包括有名称的原生操作、正确的 role/state/value、非纯颜色信息、合理触控目标和 VoiceOver 可理解性；已经实现的大字号自适应不得因资源优先级变化而主动移除。默认静态审查、截图、模拟器和实机矩阵优先覆盖正常字号、正常操作路径及当前平台 Apple HIG，包括信息层级、导航、反馈、键盘/指针、窗口适配、深浅外观和系统集成。极端 Dynamic Type 不再是每个小批次或全库收口的重复主线；只有变更直接涉及文本重排/截断、出现明确辅助功能回归、用户报告问题或发布风险要求时，才增加定向极端字号验证。

后果：主 Agent 应先完成常规体验与发行能力的高价值验证，再按风险投入辅助功能专项资源。不得把“不是默认专项”解释为允许删除 accessibility label、隐藏状态、仅靠颜色表达或回退已经通过的布局；也不得为了形式化矩阵反复启动高成本模拟器批次而延误核心路径审核。

验证：默认验收记录正常字号核心路径、平台 HIG 和基本辅助语义；任何极端 Dynamic Type 批次都说明触发风险、受影响页面和资源所有者，并遵守统一的模拟器清理合同。一次性截图、UDID 和 xcresult 证据继续记录在 Audit，而不是写入本决策。

## AD-058：同步恢复与日常同步操作分层

状态：Accepted

背景：旧“同步”Section 把开关、状态、检查、刷新和两个会覆盖一侧数据的恢复命令连续排列。恢复命令使用绿色/青色普通动作外观；用户即使在冲突时也看不到本机与 iCloud 摘要，只能根据“上传/下载”猜测哪一侧会被替换。

决策：`SyncSettingsSection` 只保留无数据覆盖语义的日常状态与操作；`SyncRecoverySettingsSection` 成为独立的低频危险区。无冲突时默认只显示“打开恢复选项”入口，用户主动展开后才出现两个覆盖方向；存在冲突时不增加这层操作，直接先展示 `SyncConflictPrompt` 的本机与 iCloud 摘要，再展示两个方向。恢复按钮使用系统 destructive role、共享红色 label，并直接写明“用本设备替换 iCloud”或“用 iCloud 替换本设备”。冲突时两个方向都调用 `resolveSyncConflict`，与全局冲突提示进入相同的冲突解析边界；无冲突时才使用基于当前 store 的手动恢复命令。二次确认使用简短替换动词，并同时说明其他设备传播、先完成同步以及 local-fallback 需重启排队的后果。

后果：Settings 的常用路径不会常驻两个高风险覆盖按钮，也不再把恢复工具伪装成普通刷新；真正发生冲突时，用户仍能立即比较两侧事实并选择权威副本。根 scene 只显示非阻断冲突提示（AD-075），真正的方向选择与确认只存在于 Settings。以后新增恢复命令也必须留在默认收起的危险区，不能混入日常状态 Section。

验证：源码合同固定两个 Section 的职责分离、两项 destructive role、冲突双摘要、明确确认动词和三语键。主 Agent 使用付费开发者身份执行同步冲突行为、Settings 安全合同与共享组件签名定向套件，55/55 通过；正常字号的 iPhone/iPad/Mac“数据与同步”页面及确认对话目视检查进入后续 UI 批次，任何模拟器都按批次明确拥有并在当批删除。

## AD-059：Settings 破坏性确认只有一个 Form-owned presentation owner

状态：Accepted

背景：`SettingsView` 曾在根列表连续附加重建 Demo、清除 Demo、清空全部、清理记录、替换 iCloud 和替换本机六个 `confirmationDialog`。正常字号 iPhone UI 测试发现点击“用本设备替换 iCloud”后没有任何确认；合并为一个可选枚举后仍不出现，证明 compact `NavigationLink` destination 还位于根列表 presentation modifier 的有效层级之外。这会让危险按钮表面看似有二次确认，实际却无反馈。

决策：Settings 所有破坏性动作以 `SettingsDestructiveConfirmation?` 表达唯一 pending intent。一个 `confirmationDialog` 根据该枚举生成标题、说明、红色确认动作和取消语义，并附着在实际包含 category sections 的 `Form`。动作 closure 捕获明确枚举 case 后再进入对应 Store/同步命令；不得恢复并列多个同类 presentation modifier，也不得把确认 owner 放在 compact navigation destination 之外。

后果：重建、清理、清空与两个同步覆盖方向共享相同且可达的系统 presentation 边界，不会因 modifier 顺序让只有最后一个动作能显示。新增 Settings 危险操作必须扩展枚举并复用该入口；普通刷新、检查和导航不进入这个状态机。iOS 27 可能把确认呈现为 popover，并通过弹窗外区域取消，测试不能为了关闭面板点击真实破坏性动作。

验证：UI 回归必须在正常字号下分别打开两个方向的确认，核对说明与 destructive action，并只用系统取消路径退出；源码契约固定 Form-owned 唯一 owner。一次性结果见 Audit §7（原 `Audit-2026-07-14.md`，已于 2026-07-25 退役，证据见 git 历史）。

## AD-060：恢复关键本机文件共享耐久提交与有界隔离 primitive

状态：Accepted

背景：主应用、Shortcuts 与扩展将逐步共享 outbox、恢复 artifact 和小型状态文件。各自重复实现 `Data.write(.atomic)`、路径字符串锁和损坏文件改名，无法统一证明进程死亡、目录 entry 持久化、符号链接、并发隔离、文件保护与诊断保留上限；原始候选实现还曾因 Foundation 对文件系统根目录父路径的新表示进入无限祖先循环。

决策：恢复关键的小型本机文件使用 `DurableLocalFile`/`PathFileLock` 作为文件系统底座，并由业务 owner 在其上提供版本、大小与语义验证。调用方为一个状态家族选择唯一、稳定且已存在的 durable root；同 root 的写入、删除和隔离共享保留锁文件。primitive 只接受普通 canonical 文件，拒绝符号链接、目录、特殊文件和锁文件本身；临时文件在发布前完成保护、backup metadata 与 full sync，再原子 rename 并同步目录。进程死亡遗留的严格命名临时文件在下一次同目录写入时有界清理。隔离目录跨 prefix 共用 8 文件、16 MiB、14 天上限，回滚失败必须暴露 canonical 和 quarantine 两个位置。

后果：调用者不能把 durable root 当作随调用变化的“目标父目录”，也不能把这套 primitive 当作 JSON validator、ACID 多文件事务或敌对进程防护。发布后目录同步失败意味着新文件可能已经可见，恢复逻辑必须可重入。高频账本写入不应为了复用而逐条调用 full sync；它只服务需要进程死亡/掉电恢复语义的小型状态边界。既有私有持久化 owner 逐个迁移并各自提交，不能在一次大替换中混合数据结构、幂等策略和 CloudKit schema。

验证：核心测试固定目录创建中断重放、发布前旧文件不变、崩溃临时文件回收、普通文件类型、保留锁路径、符号链接与 dangling symlink、跨 prefix 数量/字节/时间预算、超限删除、隔离回滚与回滚失败、硬链接别名互斥、写入/隔离共享 root 锁，以及每个生产文件不超过 160 行的职责合同。macOS 行为与结构套件、generic iOS 设备 SDK 自动签名构建都必须通过；iOS 构建还要保持主 App、Widget、Live Activity、Watch 的付费开发者签名及 APS、CloudKit、App Group 能力。一次性 xcresult 与路径记录在 dated Audit。

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

Deep link 返回 `handled`、`deferred` 或 `rejected`。需要导航或 modal 的动作必须先取得当前 scene 的 presentation slot，再修改 destination；slot 忙时进入既有 16 项、语义去重的 `PendingDeepLinkQueue`，sheet 关闭后有界重放。start/stop 不需要 modal，可以在无关编辑器打开时直接执行。瞬时错误的 scene 归属后续由 AD-077 完成；同步冲突的非阻断导航由 AD-075 完成。

后果：同一 scene 只有一个 App 级 sheet，脏编辑器不会被其他 feature 的 modal 请求覆盖；独立 Settings 不会把 UI 弹到主窗口。保存命令只返回业务成功，presentation 的关闭由 sheet 自己的 `dismiss` 负责；失败保持原草稿。新增 App 级 sheet 必须扩展 typed content 和唯一 host，不得在 feature 或共享 Store 重建平行 `.sheet` 状态。局部确认对话、文件 exporter 和真正属于单个控件的 popover 可以保留局部 owner，但必须与 App 级 slot 的职责区分。

验证：presentation/deep-link 套件固定 matching-ID 仲裁与有界排队；正常字号 UI 覆盖任务编辑→Focus 和 Today→任务选择器。一次性结果、签名与资源清理证据见 Audit §7（原 `Audit-2026-07-14.md`，已于 2026-07-25 退役，证据见 git 历史）。

## AD-073：同步覆盖确认绑定精确 conflict token，并在 state lock 内 CAS

状态：Accepted

背景：同步恢复确认曾只保存上传/下载方向。用户看到冲突 A 的本机/云摘要后，CloudKit observer 或本机 mutation 可能在最终确认前把 pending state 改成 B；按钮随后重新读取“当前冲突”并直接覆盖，等于按 A 的信息解决 B。即使逻辑冲突 ID 没换，pending 期间的新本机或云端改动也会改变实际 resolution snapshot，而旧实现仍保留原 ID并可能返回变化前 prompt。“最初无冲突”的手动恢复也可能在 confirmation 打开期间迎来新冲突，再错误清掉它。

决策：`pendingConflictID` 是用户看过的两侧摘要版本 token。pending 状态下，local branch 或 cloud branch 的 resolution-relevant snapshot fingerprint 变化时，在 `SyncConflictService` 的跨进程 state lock 内旋转 token，并从更新后的 state 重建 prompt。ContentView 的 `confirmationDialog(presenting:)` 与 `SettingsDestructiveConfirmation` 都捕获当次展示的 optional ID。`resolveSyncConflict(expectedConflictID:resolution:)` 在同一个 `withExclusiveStateAccess` 内先 locked-load，再精确比较实际 optional ID；比较早于 `advanceSyncEpoch`、snapshot restore、reset flag、`clearPendingConflict` 和 `saveState`。不匹配返回 `conflictChanged` 且零副作用；匹配后返回 `appliedImmediately` 或 `queuedForNextLaunch`。IO/restore/save 错误的新边界由 AD-077 取代：Store 直接抛出，由发起 Settings scene 呈现。

后果：旧确认不能覆盖后来到达或后来变化的同步版本；用户必须重新阅读最新摘要并再次选择方向。expected nil 表示“确认时仍应没有 pending conflict”，不是跳过校验。Store 不得在锁外先比较 cached prompt，也不得从当前 persistence mode 推测 queued/immediate。token 只在实际 branch fingerprint 变化时旋转，重复无变化通知不会制造确认风暴；检测时间保留首次冲突发生时间。

验证：冲突与 Settings 套件覆盖 matching/stale ID、expected-none、state/epoch/snapshot/fingerprint/用户数据零副作用、prompt 保留和 branch 变化后旧 token 失效。一次性结果与签名证据见 Audit §7（原 `Audit-2026-07-14.md`，已于 2026-07-25 退役，证据见 git 历史）。

## AD-074：读取冲突 prompt 失败不能伪装成“没有冲突”

状态：Accepted

背景：`SyncConflictService.prompt()` 曾用 `try? loadState()`，把损坏、超限、权限或文件系统错误全部降级成 `nil`。调用方无法区分“确实没有 pending conflict”和“权威状态没有读出来”，可能清空界面警告、继续恢复或在后台命令提交后把故障隐藏掉。

决策：`prompt()` 改为 throwing API。前台 mutation、sync observer 与 stale-confirmation reload 沿既有 throwing 边界传播，Store 再产生明确错误反馈；Watch 命令若业务提交已成功，则把 prompt 读取错误计为 post-commit refresh failure，仍返回原 terminal command result，不能谎称已提交命令失败。只有成功读到合法 state 且其中没有完整 pending conflict，才返回 `nil`。

后果：损坏 state 会被隔离并显式报告，不再被解释为“同步安全”；调用方新增 prompt 读取点必须处理错误，禁止重新加 `try?`。同样地，已提交的业务动作与提交后 projection/snapshot/prompt 刷新必须保持不同失败语义。

验证：冲突、resolution identity 与 Watch command 套件覆盖损坏 state 读取抛错/隔离，以及已提交 Watch 命令不反转 terminal result。一次性结果见 Audit §7（原 `Audit-2026-07-14.md`，已于 2026-07-25 退役，证据见 git 历史）。

## AD-075：同步冲突先非阻断导航，再在 Settings 主动确认

状态：Accepted

背景：启动 bootstrap、CloudKit import 或前台刷新一旦产生 pending conflict，`ContentView` 会自动弹出同时包含两个破坏性覆盖方向的 confirmation dialog；Settings 又提供相同动作和更完整的两侧摘要。用户可能在尚未看到副本差异时就面对高风险选择，启动 UI 被阻断，根 dialog 还会与错误 alert、scene sheet 竞争。

决策：根 scene 改为 `SyncConflictNotice`，只说明需要比较副本，并提供“查看副本”导航与本 scene 忽略。提示只在主持久化可写时出现，不能覆盖 `PersistenceRecoveryView`。iPhone、iPad 与 macOS 都由各自 shell 的顶部 safe-area inset 放置完整通知卡；禁止用固定 bottom padding 猜测系统 chrome，也禁止把多行通知放入会随 Tab Bar 收缩的 `tabViewBottomAccessory`。点按查看统一设置 `desktopDestination = .settings`，由 iPhone navigation、iPad detail 或 macOS Settings scene 按各自 shell 路由；提示本身没有上传/下载闭包。只有 Settings 的同步恢复区展示本机/iCloud 摘要、两个明确方向和随后 item-driven 破坏性确认。scene 记录已忽略的 conflict ID；同 token 不反复打扰，resolution-relevant 内容变化并旋转 token 后再提示。

后果：App 启动和后台同步不再强迫用户立即做数据覆盖决定；破坏动作发生前总有比较两侧摘要的路径。忽略只隐藏当前 scene 的提示，不清 pending state、不解除恢复保护；Settings 仍可随时解决。后续不得在根层重新加入自动冲突 confirmation，或让 notice 直接执行覆盖。

验证：presentation 契约与正常字号 UI 路径覆盖“提示 → 查看副本 → 两侧摘要”，并确认破坏动作只出现在摘要之后。一次性结果见 Audit §7（原 `Audit-2026-07-14.md`，已于 2026-07-25 退役，证据见 git 历史）。

## AD-076：只有完成恢复门控后才能启动并确认 CloudKit

状态：Accepted

背景：排队的 upload/download reset 曾在删除 store、删除同步状态或寻找受保护上传快照失败后仍继续创建 CloudKit container；只要容器随后成功，`recordCloudKitEnabled()` 就会清除 pending/error 标记。这会把没有执行的恢复误报为完成，download 方向还可能过早解除只读保护。恢复逻辑又位于 demo/用户禁用分支之前，存在不应进入 CloudKit 时先删除本地 store 的风险。

决策：恢复准备返回 typed `CloudRecoveryGate.completed/deferred/failed`。缺失或不可读的受保护上传快照返回 deferred；store 或同步状态删除失败返回 failed；两者都保留 pending 标记并阻止本次 CloudKit container 创建。只有 completed 携带不可由外部构造的 `CompletedCloudRecovery` token，CloudKit container 成功后 `recordCloudKitEnabled(after:)` 才能消费该 token 并清标记。factory 先处理 demo 与用户禁用分支，再运行恢复门控。恢复删除闭包显式属于 MainActor，避免同步文件操作跨隔离调用。

后果：失败或无法证明安全的恢复不会进入云容器、不会清 pending、不会宣称成功；用户修复文件保护/存储错误后可以在下次启动继续。无 pending 请求是唯一无需删除仍返回 completed 的情形。后续不得重新增加无 token 的 CloudKit-enabled 状态转换，或用 `try?`/Bool 把 deferred 与 failed 合并为可继续。

验证：恢复门控与 MainActor 套件覆盖快照缺失/不可读、不可 reset、无请求、两类删除失败和成功后才清标记。一次性结果见 Audit §7（原 `Audit-2026-07-14.md`，已于 2026-07-25 退役，证据见 git 历史）。

## AD-077：瞬时反馈归属发起 scene，共享 Store 不拥有 alert

状态：Accepted

背景：macOS 主窗口和 Settings 共享一个 `TimeTrackerStore`，但原来只有 `ContentView` 监听单个 `errorMessage`。Settings 导出、数据库清理或同步恢复失败时，错误会跑到主窗口，并可被后续后台/系统表面错误覆盖；任一 dismiss 又可能清掉不是它呈现的新消息。常规成功也使用 alert，额外打断 Settings 工作流。

决策：每个可见 scene 以 `@State` 持有独立 `AppSceneFeedbackRouter`，并通过唯一 `AppSceneFeedbackHost` 呈现。router 按 FIFO 保留消息；按钮、系统 dismiss binding 都必须回传当前 feedback UUID，旧 callback 不能清除后来消息。JSON export 和 sync resolution facade 改为 throwing，不写共享 `errorMessage`；数据清理继续使用已有 throwing mutation。Settings 成功、排队恢复与 conflict-changed 在对应 section 就地显示，真正失败进入 Settings scene router；取消 `fileExporter` 不是错误。`ContentView` 把尚未迁移的 Store 错误立即转入它自己的队列作为过渡桥，不代表共享槽位已可继续扩展。

后果：macOS Settings 的三类数据/同步操作不再在主窗口弹错，连续错误也不相互覆盖。`SyncConflictResolutionResult.failed` 和两个返回 optional 的旧 Store 恢复 facade 被删除，IO/restore/save 错误不再伪装成业务枚举或 `nil`。其他 Settings mutation、编辑器和后台健康错误仍需分批迁移；新代码不得使用过渡桥作为默认反馈 API。

验证：队列核心、scene 接线、JSON/清理 throwing 边界、同步冲突与 stale token 回归必须覆盖 FIFO、matching UUID、场景隔离和失败不伪装成业务结果。一次性结果见 Audit §7（原 `Audit-2026-07-14.md`，已于 2026-07-25 退役，证据见 git 历史）。

## AD-078：同步状态只陈述已完成且已在本机处理成功的 CloudKit 活动

状态：Accepted

背景：旧实现把后台通知后的本机 `refresh()` 时间写入 `lastSyncRefreshAt`，状态卡随即显示绿色“刚刚刷新”。失败的 CloudKit import 会被降级成普通 remote change；账户检查和显式恢复也可能留下看似同步完成的时间戳。因此 UI 无法区分“收到变化信号”“本机重载成功”和“CloudKit import/export 已成功结束”。

决策：以 `SyncActivityOutcome(kind, completedAt, result)` 取代裸时间戳。CloudKit import、export、setup 结束事件保留成功标志与系统 failure message；合并窗口中 conflict 优先于失败，失败优先于成功。只有事件成功，且本机 refresh 与冲突处理都成功后才记录成功。remote-store 通知本身不宣称云操作完成；任一后处理错误覆盖事件成功并记录失败。账户可用性检查和用户选择的覆盖恢复不生成 CloudKit 完成活动。状态卡优先显示账户不可用与实际失败，未来时间戳也不能进入 120 秒绿色窗口。

后果：失败事件不再短暂或持续显示为绿色；后台错误在 Settings 状态卡中可诊断，不占用 scene alert 队列。最近活动能明确区分 import、export 和 setup，但它仍是当前进程观察到的 CloudKit 事件，不是多设备端到端一致性的证明。

验证：同步活动、账户状态、冲突状态与 Settings 套件必须覆盖 event kind/result、优先级合并、remote-only 不成功、后处理失败、账户独立性与未来/过期时间。一次性结果见 Audit §7（原 `Audit-2026-07-14.md`，已于 2026-07-25 退役，证据见 git 历史）。

## AD-080：系统表面的停止操作固化具体时间片，绝不按数组顺序猜目标

状态：Accepted；其中 Live Activity 可见停止入口由 AD-118 替代，Activity immutable segment ID 生命周期与其余精确停止语义保留

背景：Shortcut、Widget/Live Activity 和无参数深链曾以 `activeSegments.last` 选择停止目标。允许并行计时时，repository 顺序不等于用户看到的目标；状态刷新或跨进程读取还可能让旧操作停止另一条活动计时。

决策：Stop Timer App Intent 使用 `ActiveTimerAppEntity` 选择并序列化 segment UUID；Widget 与 Live Activity 的 `Button(intent:)` 也把当前可见 segment UUID 写入 intent/deep link，Activity attributes 以 immutable `segmentID` 维持生命周期身份。命令层只接受唯一 segment 匹配；旧 task-ID 入口也必须只有一个匹配项。无目标兼容入口只在恰好一条活动时间片时执行，并行时拒绝，过期/无效目标绝不回退到其它时间片。

后果：系统表面的停止能力与用户看到的计时一一对应；并行计时、陈旧 Widget/Activity 或重复同步行都不能通过集合顺序误停其它工作。新增停止入口必须传 segment identity；“当前”不得成为“最后一条”的同义词。

验证：command/deep-link 行为测试覆盖唯一无目标兼容、并行拒绝、精确 segment 和过期目标不回退；系统表面契约固定 `Button(intent:)` 与 segment 序列化，并要求 generic iOS 自动签名和嵌入产物校验通过。一次性结果见 Audit §7（原 `Audit-2026-07-14.md`，已于 2026-07-25 退役，证据见 git 历史）。

## AD-081：CloudKit 恢复必须先完成同一 fresh store 的初始导入，再比较或解锁写入

状态：Accepted；补充并收紧 AD-076，AD-076 的 typed reset gate 与 completion token 继续有效

背景：AD-076 阻止 reset 失败后继续创建 CloudKit container，但“container 创建成功”仍不能证明 fresh cache 已经下载完整云端。setup、remote-store 通知或任意 import 都可能早于、晚于或属于另一 store；进程又可能在收到事件与保存回执之间退出。若自动重新启用 iCloud 先恢复本机快照，CloudKit 会在比较前导出并覆盖远端；若只凭 setup 解除只读，空 cache 会被误当成空云端。旧设置窗口还可能在 recovery container 已附着后改变上传/下载方向。

决策：恢复意图持久区分 `reconcileWithCloud` 与 `explicitlyReplaceCloud`。自动 fallback/重新启用只执行 reconciliation：保存受保护本机分支，建立 fresh cache，完整导入后比较；相同直接收敛，不同产生明确冲突，比较前禁止恢复/导出本机分支。只有用户明确选择本机赢家才执行 explicit replacement，并且 bootstrap across recovery→normal startup 只恢复一次。legacy nil intent 与缺少明确 upload marker 的镜像按 conservative reconciliation。

每次 download/reconciliation reset 建立 `CloudRecoveryImportSession(id, kind, startedAt)`。完成屏障必须依次记录成功且已结束的 setup 与其后的成功 import；两者 start 不早于本次 epoch，storeIdentifier 相同，import start 不早于 setup completion，并且 session kind 与当前 gate 相同。`CloudRecoveryImportBuffer` 在创建 ModelContainer 前开始接收事件，observer 安装后 drain；回执在 debounce/刷新前同步持久化。setup-only、remote change、失败/乱序事件、错误 kind、旧 epoch 或其它 store 不能解锁写入。

upload、download、reconciliation defaults marker 互斥；矛盾 legacy 请求返回 typed deferred 而不删除 store。recovery container 已附着后，所有会改变方向的 stage/force/accept/resolve API 拒绝陈旧命令。崩溃后只复用完整 setup+import 会话；不完整会话重新 reset fresh cache。恢复期 store 只配置读侧，推迟迁移、seed、Pomodoro reconciliation、账户检查与其它写侧副作用；完成广播更新每个 scene，而单个 store 的启动配置必须 single-flight，避免同步通知重入 bootstrap。

后果：自动重连不会在看见云端前静默覆盖 iCloud，空 fresh cache 不会被误判为权威空云端，下载/比较期间的新用户写入也不会落入即将再次删除的 store。一次通知丢失最多导致下一次安全重建，不会把半次 hydration 当成成功；显式本机覆盖仍保留，但只能来自清楚确认的方向。

验证：恢复 gate、activity、conflict、state-write、identity、persistence safety 与 test-host isolation 套件覆盖同 store setup→import、跨 service 回执持久化、错误 kind/epoch/store/顺序、未完成/完整崩溃重启、初始空云端、自动比较冲突、显式赢家只恢复一次、互斥/矛盾方向、陈旧 scene 命令拒绝、恢复期无迁移/seed/账户副作用，以及多 scene 完成广播。付费签名、当前 Team 与资源清理要求继续遵守 AGENTS；一次性执行证据只写 dated Audit。

## AD-082：Checklist 快捷命令与任务编辑器共享 store-scoped 事务域

状态：Accepted

背景：Task editor 保存完整 checklist 时已经在 store lock 内校验 task/checklist/visual baseline，但详情页 toggle、quick add 与 reorder 仍写 scene 持有的 SwiftData model 和缓存排序。兄弟 scene 删除 task/item、修改完成状态、移动父级或保存任务草稿后，旧窗口可以创建 item/visual 孤儿、覆盖或复活 tombstone、产生重复 sortOrder，并只失效旧父链。

决策：新增、显式完成状态和重排统一进入 `StoreScopedChecklistCommandCoordinator`，复用 AD-069 的 `StoreScopedTimerMutationTransaction`。取得锁后才创建 fresh context；新增先验证 canonical task 并复用 `ChecklistDraftPersistencePolicy`，再从 fresh visible items 计算 sortOrder；完成状态以 item ID + task ID + `clientMutationID` 为 baseline；重排以 task ID + 全部 visible item mutation map 为 baseline，并要求 ordered IDs 与 canonical 集合精确相等。成功 outcome 从 fresh task hierarchy 计算 ancestors；stale/unavailable 只刷新 read model 并报告明确错误，不记录本机同步 mutation。所有排序以完成状态、sortOrder、createdAt、UUID 完整决胜。

后果：Task editor 整表替换与详情页快捷操作不再互相旁路；旧 scene 只能先查看最新状态再重试。新增 Checklist writer 必须加入同一事务域；异步 visual suggestion 仍是后续需要单独协调的相邻写路径，不能因本决策被误报为已覆盖。

验证：跨 scene 套件覆盖较新完成状态不可被旧 toggle 覆盖、删除 item 不复活、删除 task 后不产生 item/visual、连续 scene 新增排序唯一、父级移动后使用新 ancestor、快捷新增与 editor 共用持久化限制、旧重排不覆盖较新 mutation；Task draft、forecast、localization 与 source-layout 回归必须继续通过。

## AD-083：Analytics 的排名、峰值与删除任务标题必须与输入顺序无关

状态：Accepted

背景：Task breakdown 先按 Dictionary 分组后只比较 gross seconds，Peak Hour 对 Dictionary 直接 `max`，删除任务标题从分组 session 取 `.first`。Dictionary 和 fetch 输入顺序不是稳定产品语义，同值数据会让 Top Task、Next Review、峰值小时或历史标题跨刷新/进程抖动。

决策：`AnalyticsSelectionPolicy` 是确定性单值选择边界。Task breakdown 依次按 gross 降序、wall 降序、本地化标题升序、UUID 升序；peak-hour 并列选择最早本地小时；session fallback 只接受未删除且非空标题，按 `startedAt`、`updatedAt`、UUID 选择最新项。Task breakdown 与 overlap participants 共用同一个 resolver，禁止各自复制 comparator。纯汇总文件不再承担 task-ranking 职责，`AnalyticsStore+TaskBreakdown.swift` 独立所有。

后果：同一 canonical facts 的排列变化不会改变首页洞察、分类详情或删除任务身份；不同 locale 仍可按用户语言排序，而 UUID 保证同一 locale 下最终决胜。新增 `.first`/`max` 消费者必须先说明并测试完整 tie-break。

验证：permutation 测试覆盖等 gross/wall 任务、等峰值小时和新旧 session 正反输入；完整 Analytics timeline/store 回归继续覆盖快照、DST、overlap、cache 与历史周期。

## AD-084：Category 元数据与 task assignment 必须处于同一 store-scoped 事务域

状态：Accepted

背景：Category create/update/delete 直接使用 scene repository，而 task editor assignment 已使用 store lock。旧分类编辑器可以覆盖兄弟 scene 新值或在删除后静默保存；delete 与 assignment 交错时可能漏删新 assignment；两个 scene 创建又会从同一缓存 sortOrder 派生重复值。Repository 对 missing update/delete 的 silent return 还会让 sheet 关闭并谎称成功。

决策：`TaskCategoryEditorDraft` 固化 `TaskCategoryMutationBaseline(categoryID, clientMutationID)`；`StoreScopedTaskCategoryCommandCoordinator` 取得 AD-069 的共享锁后创建 fresh context。创建锁内计算排序；编辑/删除要求 baseline 精确匹配 canonical category；删除与 assignment 在同一 atomic mutation domain 内处理 category 及全部当前 assignment。Sheet 删除直接提交初始 baseline，不先从刷新后的 Store 回查对象。Repository missing category 显式抛出 `TaskRepositoryError.categoryUnavailable`。

后果：旧 scene 不能覆盖或删除后来版本，也不能复活墓碑；assignment-before-delete 被同次删除清理，delete-before-assignment 会被 task draft 的 category validation 拒绝。Stale 失败只刷新 task read model 并保留 sheet；用户必须查看最新版本后重试。分类 mutation baseline 独立放在 `TaskCategoryEditorDraftModels.swift`，不再膨胀通用草稿文件。

验证：跨 scene 套件覆盖 stale edit/delete、删除后 edit、assignment 两种提交顺序、并发 create 排序和 repository missing 错误；原 Category、Task Draft、presentation、本地化与 model source-layout 套件必须继续通过。

## AD-086：Task 草稿冲突必须可在当前编辑会话显式重载

状态：Accepted

背景：Store-scoped task draft 正确拒绝 stale baseline 后，sheet 仍持有不可变旧 baseline；用户无论保存多少次都会重复失败，只能关闭并重新进入。自动把最新数据覆盖进 editor 又会无提示丢失用户尚未保存的标题、备注、计划和 checklist。

决策：Store 暴露 `TaskDraftSaveResult.saved/stale/failed(message:)`。stale 分支先刷新 task/checklist/category read model但不写共享错误；editor 显示一次明确确认，Keep Draft 保留全部当前输入，Reload Latest 以刷新后的 task 建立新 draft，并同时替换 session discard baseline、parent candidates 和 checklist focus。Reload 使用破坏性角色和明确“未保存更改会被丢弃”文案。旧 Bool API 继续给非 UI 调用映射原有 errorMessage，不能让兼容层反向污染 typed editor 流程。

后果：用户无需关闭 sheet 就能继续编辑最新版本，也不会被自动合并或静默覆盖。重载后的未修改草稿可直接 Cancel，不出现虚假的放弃确认；后续保存使用最新 mutation IDs。真实三方字段合并不在本决策中，不能把 Reload 描述为 merge。

验证：领域测试先制造兄弟 context mutation，确认 typed save 返回 stale 且不写共享 error，再从刷新投影建立新 baseline 并成功保存；Task UI/presentation 契约固定显式 Reload/Keep、session baseline 和 parent candidate replacement。

## AD-087：Inbox 重排必须在 fresh logical set 上验证完整顺序基线

状态：Accepted

背景：Inbox View 从 scene facade 的 open item 缓存计算拖拽结果，旧实现随后仍在同一长期存活 `ModelContext` 内重排。另一 scene 可能已新增、完成、删除、编辑或重新排序条目；旧命令只比较 ID 集合，随后会给整组 item 重写 sort、updatedAt 与 mutation metadata，并在 logical sibling 收敛时物化旧 scene 看到的内容。

决策：重排进入 `StoreScopedInboxCommandCoordinator` 并复用 AD-069 的共享 store lock/fresh-context transaction。`InboxOrderMutationBaseline` 固化全部 open logical winner 的 `clientMutationID` 与按 sortOrder/createdAt/UUID 完全决胜的原顺序；锁内重新解析 current visible logical items，并要求 mutation map、原顺序、目标数量和目标 ID 集合全部精确匹配。无变化是 typed no-op；stale 只刷新 Inbox read model并展示明确错误，不写任何记录或推进同步 generation。

后果：旧窗口不能丢掉后来新增条目、把已完成项重新纳入 open 排序，或覆盖后来 revision；即使某个异常 writer 改了 sortOrder 却没旋转 mutation ID，原顺序基线仍能拒绝。当前决策只覆盖 reorder；add/toggle/title/delete/suggestion 等相邻 writer 仍需逐个迁入同一事务域，不能借本决策宣称所有 Inbox 写竞态已完成。

验证：跨 context 套件覆盖正常反转、较新 completion、并发 add、缺失 revision 的 order-only 变化，以及 facade 拒绝后刷新 open/completed 投影；原 Inbox logical identity、持久化、本地化与 UI source contract 继续通过。

## AD-088：Analytics 请求与缓存共享完整 evaluation identity

状态：Accepted

背景：`AnalyticsRefreshPlan` 会在静态当前范围的下一个本地午夜更新 `liveNow`，但 landing/category request 只有 range、period start、revision 与 optional minute bucket；无活动计时的当前 week/month 跨日后这些值全部不变，SwiftUI 不重跑 snapshot task。即使调用 Store，overview/task cache 也只验证 period start 与 minute bucket，会继续返回昨天的 visible-day、daily 和 matched-comparison 结果。

决策：`AnalyticsEvaluationCacheKey` 同时作为 View request 与 `AnalyticsStore` full/task cache identity。Key 固化完整 interval start/end、当前 local-day start 和 optional live-minute bucket；只有真实 `clockReference` 位于所选 interval 内才保存 local-day identity。生成者必须显式传递同一 key，低层 refresh 不得从 cutoff 猜测；cache lookup、保存、替换与失效集中在 `AnalyticsStore+Caching.swift`。

后果：静态当前 week/month 在午夜会同时改变 `.task(id:)` 和 cache identity，即使没有活动 segment；活动范围仍按分钟更新。Completed/future period 没有 live-day identity，不会因后来墙钟日期变化无意义失效。完整 interval end 也使时区/日历导致的 period 边界变化自然 miss。Task Detail 继续保留其既有调度形态，但使用相同 key，不能另造只含 start 的 task cache。

验证：UTC 同一周 23:59→00:01 的 request、overview cache 与 task cache 全部 miss；历史周跨后续墙钟日保持相同 request。原 period/cutoff、DST、comparison、timeline、live-bucket、LRU 与 overlap 套件继续通过。

## AD-089：Analytics 缓存只持有 read models，不保留 SwiftData segment

状态：Accepted

背景：`AnalyticsSnapshot` 与 `TaskAnalyticsSnapshot` 在已经生成 overview、daily、timeline、breakdown 和 recent records 后，仍把完整 `rangeSegments: [TimeSegment]` 保存在缓存对象里。生产没有读取该字段；full cache 的多个 range 与最多 24 个 task cache 因此长期强引用整月或整任务分支的 SwiftData 模型，扩大内存与 context 生命周期。

决策：两个 snapshot 删除 `rangeSegments` 字段和构造参数。Segment 数组只作为单次 generation pipeline 的局部输入，输出缓存仅保留不可变展示/决策 read models。测试不得为方便检查内部数组而重新暴露持久模型，必须通过 overview、daily、timeline、task/group 或 recent-record 投影验证结果。

后果：缓存容量现在近似由展示点数决定，不随原始 segment 数量额外线性持有 SwiftData 对象；cache 也不会成为第二个可误用的数据访问入口。真正的计算复杂度仍需通过 evaluation context、range-scoped query 和 merge 消重继续优化，本决策不宣称 full snapshot 已经 O(1)。

验证：重复 Cloud row 的快照测试同时核对 overview、daily、task breakdown、rhythm 与 timeline 只出现一个 winner；完整 AnalyticsStore/Timeline 回归继续通过。

## AD-091：无目标的 Analytics comparison 不做价值判断

状态：Accepted

背景：Analytics 的区间比较只有“本期相对上期的记录时长变化”，没有用户目标、预算或期望方向。旧实现把负向差值标为绿色 positive，却把正向差值标为 neutral，等价于擅自认定“记录更少就是更好”；这对时间记录工具没有通用依据，也可能误导用户解读工作量变化。

决策：没有显式目标语境时，gross duration 的增加和减少都使用 `.neutral` insight severity，只陈述变化事实与比较口径。只有未来引入用户明确设定的目标、上下限或预算，且能从该目标判断方向时，才允许输出 positive 或 warning；颜色不能替代目标语义。

后果：Analytics 不再用绿色奖励任一变化方向，用户可以结合自己的计划解释数据。该决策只约束无目标的 comparison insight，不阻止明确目标完成度、数据异常或真实风险使用语义化状态。

验证：`CoreAnalyticsStoreTests` 同时构造 gross duration 正差与负差，确认两者 comparison insight 都为 neutral；完整定向套件 37/37 通过。

## AD-092：Task Detail 分离周期分析输入与最近记录输入

状态：Accepted

背景：Task Detail 在相关任务存在活动 segment 时按分钟刷新。旧 facade 先通过 task ID index 取根任务与全部后代的完整历史，然后 domain 层才过滤当前周期、上一比较周期和最近 8 条；因此一个长期任务的每分钟刷新成本随全部历史线性增长，即使界面只展示有限数据。

决策：Task analytics 的统计输入只查询 `previous period start ... current period end` 的 Ledger day index，再按 task subtree 过滤；最近记录使用 `LedgerStore+RecordIndexes` 维护的每任务最近 8 条 ID，并跨 subtree 合并为全局最近 8 条。`AnalyticsStore.taskSnapshot` 显式区分 `segments` 与 `recentSegments`，session 查询也只跟随 recent records。最近顺序以 startedAt 降序、UUID 升序完整决胜。CloudKit 关系隔离过滤掉有界候选时允许 facade 回退完整 task index，以正确性优先；一致数据不得走回退路径。

后果：活动详情的分钟刷新不再扫描任务全部历史，长期使用的成本由两个日历周期内记录、任务分支宽度和固定 recent 上限决定。每个任务只额外保留最多 8 个 recent UUID；删除/改期会从现有 task ID set 补齐索引。该决策没有消除周期内数据量本身的线性聚合，后续若单月记录极密仍需 evaluation context 或后台计算。

验证：Ledger 回归覆盖有界索引、跨任务稳定合并和删除后补齐；Analytics 回归证明周期统计与独立历史 recent 输入不会串扰；架构合同禁止 facade 恢复 `visibleSegments(forTaskIDs:)` 全历史入口。付费签名的 Ledger、Analytics、Timeline、架构和三项 source-layout 合并批次 79/79 通过，重跑无新 Swift warning。

## AD-093：Task analytics 在日期与任务索引中选择较小候选集

状态：Accepted

背景：AD-092 删除了“先读取任务分支全部历史”，但 facade 仍先从 day index 物化当前与上一周期内全 App 的 `TimeSegment`，随后才按 task subtree 过滤。高频计时或大团队导入数据下，一个小任务的分钟刷新仍会为同周期的所有无关记录解析模型并执行可见性过滤。

决策：Ledger 提供 task-scoped interval query。Planner 不同时构造两份大 Set：先以 `segmentIDsByTaskID` 的计数与日期 day buckets、long-span、time-sensitive、clock-rewind 的候选上界比较；任务侧更小时合并 task ID buckets 后做 overlap，日期侧更小时使用原日期候选后按 snapshot.taskID 过滤。最终查询仍执行 `TrackedTimePolicy.overlaps` 精确校验，历史 cutoff 与真实 clock reference 保持分离；真实时钟回拨可以选择 task 侧，不必把无关任务纳入结果。

后果：Task Detail 周期计算的模型物化成本接近 `min(任务分支历史候选, 全 App 周期候选)`，而不是固定选择其中一侧；空 task set 立即返回。Planner 上界允许重复计数但绝不能低于真实唯一日期候选；如果未来增加新的索引候选来源，必须同步更新上界。该决策不改变 Analytics 数值或缓存 identity。

验证：Ledger 测试构造周期内 50 条无关记录、稀疏任务历史和深历史任务，分别覆盖任务侧与日期侧并只返回交集；完整 Ledger、Analytics、Timeline、架构与三项 source-layout 付费签名批次 80/80 通过，无新 Swift warning。

## AD-094：Fallback 最终快照与 destructive reset 必须共用一个外层 store lock

状态：Accepted

背景：Local fallback 的业务命令先提交 SwiftData，再在 post-commit 边界更新独立同步 state/mirror。进程在两者之间退出时，主 store 含最新事实而保护快照仍旧；下一次 CloudKit clean-store recovery 若直接依据旧 mirror 删除 store，会永久丢失最后一次已成功提交。仅在启动时先补快照、释放锁、随后重新取锁删除仍不够，另一个进程可以在两段锁之间提交并再次落入相同窗口。

决策：Cloud-enabled factory 统一调用 `performPendingCloudRecoveryResetAfterProtectingLocalFallback`。它按 canonical store URL 持有一个外层 `StoreScopedTimerMutationLock`，锁内顺序固定为：重开 local configuration、fresh full-domain capture、原子保存 authoritative state 与 forced-upload mirror、准备恢复 marker、执行 destructive reset。已有 snapshot transaction 与 reset helper 递归获取同一路径 `NSRecursiveLock + flock`；外层直到 reset 返回才释放。临时 local container 限定在被调函数的 autorelease scope，删除 SQLite 前必须释放。任一步抛错都返回仍完整的 local fallback。Pending download 表示用户明确选择云端赢家，因此跳过 recapture；upload/reconciliation 必须刷新最新本机分支。

后果：所有遵守共享 store lock 的进程都不能在最终 snapshot 与删库之间插入 commit；第一次 mutation 后立即崩溃、已有旧 mirror 后崩溃和显式 upload 都能保护最新数据。Fallback 重连会做一次 O(全量事实) capture；超过 snapshot 上限或文件保护/IO 失败时安全停留本地，而不是继续恢复。该保证不覆盖仍绕过共享锁的 legacy writer，Inbox/App Intent 等入口必须继续迁移，不能把本决策描述为任意 writer 的全局 ACID。

验证：真实磁盘 fixture 先保存旧保护快照，再提交未记录的新标题；启动 preflight 捕获最新标题后真实删除 SQLite。竞争线程在 reset hook 中无法取得同一 store lock，只有 reset 完成后才进入。CloudRecovery Gate、SyncConflict、StateWrite、StoreSerialization、ResolutionIdentity 与 SnapshotPreflight 六个付费签名套件 102/102 通过，无源码或运行时 warning。

## AD-096：Analytics 源文件按稳定计算边界拆分

状态：Accepted

背景：analytics 的 public API 和缓存语义已经稳定，但比较周期、原始指标、洞察文案、cache-aware daily assembly 与 facade 的轻量 read model 继续集中在四个文件中。它们超过职责/行数预算后，等价的小修正会继续扩大冲突面，也让 SwiftUI 调用者难以分辨 snapshot 生命周期与展示投影。

决策：`TimeTrackerStore+Analytics.swift` 只保留 snapshot/request 生命周期、live refresh bucket 和 scoped segment 输入；UI-facing overview/daily/hourly/task/overlap projections 归 `TimeTrackerStore+AnalyticsReadModels.swift`。`AnalyticsStore+ComparisonWindow.swift` 独立处理 previous period、DST 和短月的 matched-progress window；`Metrics` 只处理 bounded aggregation；`DecisionSupport` 只计算 comparison/range adapter；`Insights` 同时拥有 insight narrative 与其格式化 helpers；`Caching` 同时拥有 cache lookup/invalidation 和以 cached daily buckets 组装 snapshot 的边界。移动不得改变 public API、cache key、截断 cutoff、统计值或 iCloud 数据。

后果：各文件都处于 source-layout budget 内，DST/month-end comparison、缓存和 UI 的调用语义保持不变。新 analytics 行为必须落在既有 owner；若新逻辑跨越这些边界，应先增加明确的 domain/service owner，而不是重新合并文件。

验证：付费自动签名的 macOS `CoreSourceLayoutTests`、`CoreAnalyticsStoreTests` 与 `AnalyticsTimelineTests` 通过；本批未启动模拟器，临时 DerivedData 与 owned build/test 进程已在退出时清理。

## AD-098：Inbox 主命令与 App Intent capture 必须共用 store-scoped lock

状态：Accepted

背景：Inbox reorder 已在共享 store lock 中用 fresh context 复核完整排序 baseline，但新增、切换完成、改名、删除和丢弃建议仍通过 scene 长存的 `ModelContext` 写入；Shortcuts capture 更直接使用 App Intent context。两个场景、iCloud merge、恢复 reset 或快捷指令可以在错误的读取事实上并发写入，使新增排序冲突、旧操作覆盖新 revision，并继续留下 AD-094 的最终 snapshot/reset 间隙。

决策：`StoreScopedInboxCommandCoordinator` 是 Inbox primary writer 的唯一入口。新增在锁内 fresh visible open set 上分配顺序；单项命令携带 `(itemID, clientMutationID)` baseline，锁内重新选择逻辑 winner 并拒绝缺失或 revision 不匹配目标；重排仍要求完整 set、顺序和 revision map 精确一致。所有 outcome 只有实际 mutation 才推进 Inbox event、refresh 与同步 generation；stale rejection 只刷新 Inbox read model。`SystemActionCommandHandler.addInboxItem` 只接收 container 并调用该 coordinator，`AddInboxItemIntent` 只有 commit 后才创建新的 context 用于 snapshot 和 Widget/Watch/Live Activity projection。

后果：主 App 与 App Intent 的 primary Inbox command 与 timer、checklist、同步恢复等命令共享同一 store lock，不再用 scene 或 Intent context 作为并发边界。空 capture 和业务 no-op 不制造同步事实；已被其他场景修改或删除的目标不会被陈旧操作覆盖。此决定不覆盖 LLM suggestion 的异步 upsert、draft 保存或跨 Inbox/Checklist apply；这些仍必须在后续独立切片中迁入同一锁域并做 fresh task/suggestion revalidation。

验证：付费自动签名 macOS 定向运行 `StoreScopedInboxCommandCoordinatorTests`、`CoreSystemActionCommandTests` 与 `CoreSyncConflictTests` 通过；新增覆盖单项 stale revision 拒绝、facade stale refresh、锁内 Shortcut capture 与 recovery write guard。没有启动模拟器；结束后没有 owned `xcodebuild`、`xctest` 或受测 App，既存 CoreSimulator 服务未被触碰。

## AD-099：Inbox suggestion 写入在锁内重验建议、任务和 Checklist

状态：Accepted

背景：AD-098 之后 primary Inbox command 已串行化，但手工 suggestion 草稿、LLM 网络回应的 upsert 和 suggestion apply 仍先从 scene read model 校验，再通过长存 context 写入。apply 同时会删除 Inbox、修改 suggestion、创建 Checklist/visual；旧 `checklistItems(for:)` 还可能让两个并发写入使用同一个 next sort order。异步 LLM 结果则可能在 title 改名、dismiss 或 task 失效后重新写回过期建议。

决策：在单独的 `StoreScopedInboxSuggestionCommandCoordinator` extension 中实现三个 writer。手工草稿使用 item mutation baseline，并在锁内 fresh task graph 上校验 trackable target；LLM completion 使用 request title 和 logical `(contextID, revisionID)`，以 fresh logical resolution（含 merged dismissal）和 canonical suggestion 重新判断可写性，纯 reorder 不参与该判断。apply 固化 item/suggestion mutation IDs 与 logical identity，锁内再次选择 ready canonical suggestion、验证 task eligibility、查询 visible Checklist 以计算 next sort order，并用 fresh task index 生成 ancestor IDs。apply outcome 同时发 Inbox 与 Checklist events；过期 LLM 响应返回 no-op 并仅收敛 read model，不向用户误报网络或存储错误。

后果：所有生产 Inbox suggestion writer 现在和 timer、checklist、同步恢复共享同一 store lock；已过期的手工操作不会覆盖新 title/suggestion，不能向刚完成、归档或删除的任务写入 Checklist，也不会产生并发排序冲突。LLM completion 仍在锁外进行网络请求，锁内只进行最终 fresh read-plan-write；网络延迟不会阻塞其他命令。底层 `InboxCommandHandler` 保留给可隔离的业务/rollback 单元测试，不是 production concurrency boundary。

验证：付费自动签名 macOS 定向回归覆盖 Inbox suggestion coordinator、primary coordinator、suggestion identity/apply/persistence、LLM cancellation、completed task、Core Inbox store 与 source layout，全部通过。generic iOS Debug 自动签名构建同样通过；主 App、Widget、Live Activity 和 Watch 均由 Team `LT98S43NKA` / `Apple Development: ZEXUAN GAO (PX46M259V3)` 签名。新增测试覆盖 stale manual draft、stale suggestion baseline、fresh Checklist sort order、任务在命令前失效、旧 title 的 LLM 回应静默丢弃，以及纯 reorder 后回应仍可保存。未创建模拟器；结束后无 owned `xcodebuild`、`xctest` 或受测 App。

## AD-100：陈旧的 companion snapshot 必须冻结时间而非伪造实时状态

状态：Accepted

背景：Widget 和 Watch 在超过十五分钟的 snapshot 上已经显示 stale 提示，但仍直接以 `Text(startedAt, style: .timer)` 渲染，时间会继续增长；Dynamic Island compact trailing 也绕过了 Live Activity 已有的 `context.isStale` 冻结策略。这会把“主机最后一次报告正在计时”误导为“现在仍在计时”，而 stopped/archived task 也可能已不再可操作。另一个遗漏是 `quickStartTaskIDs` 仅刷新 preference domain，没有重发直接依赖该偏好的 Watch snapshot。

决策：Widget 的 `WidgetTimerSnapshot` 和 Watch 的 `WatchActiveTimerSnapshot` 都把 current snapshot 作为唯一 live elapsed 条件；`.stale`、`.clockAdjusted` 或 Watch stale 时，秒数固定为 `generatedAt - startedAt`，并继续显示已有的 stale/clock-adjusted 状态。Live Activity 的 Lock Screen、expanded 和 compact trailing 全部复用 `LiveActivityTimingPolicy.elapsedPresentation`。`StoreRefreshCoordinator` 将 `refreshPreferences` 纳入 Watch snapshot publish 条件，但不为纯偏好变化重载无依赖的 Widget timeline。

后果：系统表面的 timer 只在有可信新鲜事实时动态计数，过期时仍保留最后已知值和明确的恢复路径；不会为“看起来更实时”而做无效轮询或额外 Widget reload。Quick Start 修改能立即收敛到 Watch 首页。该决策不改变 Watch command 的接收端保护：陈旧 stop/start 仍必须在主应用 fresh transaction 中重新验证目标与可追踪性。

验证：`CoreWidgetSnapshotTests` 覆盖 current、stale、clock-adjusted elapsed；`CoreWatchCommandTests` 覆盖 Watch stale freeze 与 preference refresh publish；system-surface source contract 固定 Widget/Watch/Live Activity 三处都不再存在 compact stale bypass。2026-07-17 付费自动签名 macOS 定向回归 56/56 通过，签名身份为 Team `LT98S43NKA` / `Apple Development: ZEXUAN GAO (PX46M259V3)`；本切片未创建模拟器，测试结束后清理了结果包且无 owned 测试进程。

## AD-101：计时准入设置只能在锁内读取，副作用只以实际 outcome 发布

状态：Accepted

背景：`allowParallelTimers` 原由主界面 Store、Watch router 或 App Intent 在提交锁外读取后传入。设置同步、另一 scene 的修改或等待 lock 的间隙可以使 Bool 过期，导致刚关闭“允许并行计时”的用户仍得到并行 segment。Watch router 还根据旧 Store projection 预猜 post-commit events，实际 fresh transaction 停止其他计时时，系统表面和同步 snapshot 可能漏掉被停项目。

决策：普通 timer start 的 public command surface 不再接收 `allowParallelTimers`。`StoreScopedTimerCommandCoordinator` 取得 store lock 并创建 fresh `ModelContext` 后，以 `TimerAdmissionPreferenceResolver` 从 canonical `SyncedPreference` 解析它，再产生 admission plan。Watch 的兼容 `process` 只返回原有 typed result；实际 router 使用 `processWithMutationOutcome`，从锁内 `StoreScopedTimerCommandOutcome.events` 刷新 Widget/Watch/Live Activity 与同步 snapshot，禁止从调用者 cache 推测。

后果：主 App、Watch 与 Shortcuts 在同一持久事实下决定 exclusive/parallel；重复 Watch delivery、无效和 missing command 不产生伪造 events。Pomodoro start/break-resume 与手工 Segment 编辑也复用同一 resolver；纯 `TimerCommandHandler`/`PomodoroCommandHandler` 仍保留 Bool 作为无存储事实的 policy input，不能把它们误当作跨进程 writer。

验证：timer、Pomodoro、Segment coordinator/system action/Watch suite 覆盖 canonical false preference 下的 exclusive reconcile、App Intent/handler 不再接收 caller Bool、Watch router 发布 actual outcome events。2026-07-17 的 Pomodoro/Segment 定向签名回归 71/71 通过，签名身份为 Team `LT98S43NKA` / `Apple Development: ZEXUAN GAO (PX46M259V3)`；本切片未创建模拟器，结束后删除结果包并确认无 owned 测试进程。

## AD-103：App Intent 提交后让同进程的已配置 scene 只收敛读模型

状态：Accepted

背景：App Intent 的写入由 fresh store-scoped coordinator 正确提交，但 post-commit 只创建临时 `TimeTrackerStore` 来更新 Widget、Watch 和 Live Activity。已经显示在屏幕上的 scene 则持有自己的 Inbox、ledger、Pomodoro 等 read-model cache，并不订阅普通本机写入；用户从 Siri 或 Shortcuts 新增 Inbox、开始或停止计时后，可以继续看见旧界面直到下一次前台或 CloudKit refresh。

决策：所有成功 App Intent 使用 `SystemActionPostCommitEffects`，按既有顺序记录 sync snapshot、更新系统表面，并发布带实际 `StoreDomainEvent` 的本机 mutation notification。每个已配置的 application-state `TimeTrackerStore` 订阅该 notification，并以既有 `StoreRefreshPlanner` 只执行 `refreshReadModels`。该 catch-up 不记录第二份 sync snapshot、不重复 Widget/Watch/Live Activity projection、不改变 command 成功结果，也不执行自动 Inbox/checklist suggestion。没有已配置 scene 时无需保留 transient notification；之后启动的 scene 从持久化事实完成正常首次 refresh。

后果：外部系统动作和当前界面以同一 outcome events 收敛，多个已打开 scene 不必依赖用户切换页面或 CloudKit remote-change 才更新。notification 是 post-commit 的 best effort：surface/snapshot/read refresh 的失败都不能把已保存的 Inbox 或计时动作伪装为可安全重试的失败。App Intent delivery 的持久 receipt/idempotency 仍是后续独立边界，尤其 Add Inbox 不能由本机广播代替去重。

验证：两个同容器、各有独立 `ModelContext` 的 scene Store 订阅后，外部 Start 与精确 Stop 同步收敛 active timer；回归还固定 App Intent 三条路径使用统一 effects，effects 同时保留 snapshot、surface 与 broadcaster，并确认 scene catch-up 走 `refreshReadModels`。一次性签名与清理证据写入 dated Audit。

## AD-104：SyncConflict state/mirror 的单文件提交必须使用 durable primitive

状态：Accepted

背景：`SyncConflictService` 已有跨进程 read-modify-write 锁和大小预检，但 state、recovery mirror、删除与腐损隔离仍各自调用 Foundation atomic write、remove 或 move。它们不能保证 rename 后的文件/父目录落盘，文件保护也曾在发布后设置；同时手写隔离绕开了 `DurableLocalFile` 的符号链接拒绝、有界诊断与回滚保证。

决策：保持既有 `SyncConflictService.withExclusiveStateAccess` 与 store → state lock 顺序，在锁内把权威 state、pending mirror、默认状态删除和损坏隔离统一交给注入的 `DurableLocalFile`。生产 state family 使用 Application Support 的稳定父目录为 `durableRootURL`，使首次 `TimeTrackerSync` 目录创建后的重试仍会同步发布它的父目录；测试/诊断 state override 只使用其被显式拥有的 state directory。权威 state 先完成 durable publish，随后 mirror write/remove；各单文件提交是耐久的，但不宣称两个文件组成 ACID transaction。若权威 state 已发布而 mirror 随后失败，下次 locked load 是既有的 repair 点；要消除这一双文件窗口必须另行设计 generation journal 或单一提交记录。

后果：任何新的 SyncConflict state artifact 都不得绕过这一 owner 使用 `Data.write(.atomic)`、`FileManager.removeItem` 或手写 move。超限/腐损文件沿用 `DurableLocalFile` 的全局 quarantine budget；超出预算时会耐久删除而不是无限保存诊断副本。`DurableLocalFile` 的 full sync 只适用于低频恢复状态，不得用于高频 ledger mutation。

验证：fault injection 覆盖 state publish 前失败仍保留最后 committed state/mirror、quarantine publish 失败回滚 canonical、正常小型损坏文件进入 `.TimeTrackerQuarantine`，以及超限诊断受预算删除；保留多 service 的跨进程 state serialization 覆盖。付费签名定向结果与清理记录写入 dated Audit。

## AD-105：Widget 与 Live Activity 的停止控件必须披露打开主应用的边界

状态：Widget 部分 Accepted；Live Activity 部分由 AD-118 替代

背景：Widget 和 Live Activity 的 App Intent 已把可见 segment ID 写入 `timetracker://timer/stop`，实际 SwiftData mutation 由主应用收到 deep link 后完成。旧的 stop glyph、`Stop` label 和 intent description 却暗示 extension 原地、立即停止；存储尚未初始化时命令还会排队，不能作出这种保证。

决策：这两个系统表面一律显示“打开 Time Tracker 后停止”及 app-opening symbol，Intent title/description 同样说明会打开 Time Tracker。仍保留 segment ID 精确路由，主应用准备完成后只尝试停止该 segment；目标已失效时不得回退停止另一个 timer。Widget/Live Activity 不在本次引入直接 SwiftData 写入、共享 CloudKit 权限或另一套 extension store。

后果：控件不再伪装为 extension 内立即写入，用户会预期切回 App；并行计时的目标精度和已有的 deep-link 安全解析保持不变。真正的 in-place system surface mutation 需要独立设计共享持久化、entitlement、并发锁和恢复语义，不能通过改一个 Intent 偷渡。

验证：source contract 固定两种 extension 都使用 app-opening copy/symbol、Intent description 与精确 `segmentID` URL；付费签名 macOS 定向回归覆盖 deep-link 路由只停止目标 segment。iPhone 正常字号模拟路径确认系统会先显示“Open in Time Tracker?”确认，故没有把未能在本机点击确认的路径伪报为已完成的实机 mutation。一次性模拟器、截图、result 与 owned process 清理记录写入 dated Audit。

## AD-107：Inbox 外部 capture 只能以调用方提供的稳定 key 获得回执

状态：Accepted

背景：`AddInboxItemIntent` 只有用户输入的标题，原实现每次调用都会创建一个新条目。标题、时间戳、SwiftData `clientMutationID`、App Entity persistent identifier 和在 `perform()` 内临时生成 UUID 都不能代表同一次调用：同标题 capture 是正常、有效的两次用户意图。将回执写到 `UserDefaults` 又会在 Inbox commit 后、receipt 写入前留下崩溃窗口。

决策：引入 `ExternalCommandKey(origin, UUID)` 与 `InboxCaptureCommand`。只有外部调用方持久并复用该 opaque key，才进入 `InboxCaptureReceipt` 路径；key 与 canonical payload fingerprint 在同一个 store-scoped fresh-context `performAtomicMutation` 中和 Inbox item 一起保存。重放相同 payload 返回既有 item ID、`didMutate = false` 与空 events；同 key 不同 payload 明确拒绝；不同 key 的相同标题继续产生两个条目。receipt 是独立 V11 SwiftData 模型，不能挪用用户 Inbox UUID，也不能只存在 `UserDefaults`。它纳入 CloudKit、sync snapshot、restore preflight 与全量清空 tombstone；缺少 V11 receipt table 的 legacy snapshot 只表示“未知”，不得删掉当前 receipt。Siri/App Shortcut 当前没有可信传入 key，因此保留 at-least-once capture，禁止在 Intent 内合成 key 或按内容去重。

后果：普通用户 capture 不会因标题相同而丢失；有完善重试协议的 integration 可在一个已串行化 store 内避免重复提交和崩溃窗口。跨设备同时把同一个外部命令投递到尚未合并的 store 仍需要未来的分布式 delivery/冲突协议，不能以本地 receipt 宣称全局 exactly-once；V11 在合并后若发现同 key 指向不同 payload 或 item，必须显式报冲突而非按更新时间选择结果。legacy snapshot 缺席 receipt table 表示未知而非空表；永久清理必须连同已删除 Inbox item 的 receipt 一起移除。也不得在没有调用方确认 horizon 时任意 prune receipt。

验证：领域回归覆盖相同 key 重放、不同 key 同标题、key/payload 不匹配拒绝、System Action outcome 与 receipt/item 共同持久化；snapshot/restore、legacy V10 兼容、schema registry 和清空 tombstone 另纳入签名回归。本小节在可读取 xcresult 后补填最终数字。

## AD-108：Checklist AI completion 必须验证手动视觉 revision

状态：Accepted

背景：Checklist 图标/颜色建议通过异步 LLM 请求返回。请求开始后，另一 iPad/macOS scene 可以在任务编辑器中手动调整同一条目的视觉；旧实现直接把当前 scene 缓存对象写回 SwiftData，既未比较 visual `clientMutationID`，也未在共享 lock 内重取 canonical visual，因此迟到的 AI 结果会覆盖明确的用户编辑并清除 `userEditedAt`。

决策：请求固化 item ID、task ID、item mutation ID、规范化标题以及 canonical visual 的可选 `(ID, clientMutationID, userEditedAt)`。completion 只在 shared store lock 和 fresh `ModelContext` 内检查 task 仍可追踪、item 未删除/完成且 revision 与标题一致、visual 仍是请求时的 logical winner 并仍满足 suggestion policy；通过后才调用 command handler。任一条件变化都返回无 mutation，当前 scene 只刷新 tasks/checklist read models。AI 输出始终是 advisory，stale 结果不显示为用户错误，也不能推进 sync generation。

后果：手动图标/颜色编辑优先于任何已在途的 AI 响应；跨 scene 标题、完成、删除和 task lifecycle 变化也不能被旧响应复活。新的 receipt-like baseline 是内存期请求合同，不进入 CloudKit；持久化表不增加 schema 字段。

验证：store-scoped 领域测试覆盖“另一个 context 手动视觉编辑后迟到 suggestion 被丢弃”和未变化 revision 正常应用。签名回归、资源清理与运行数字记录在 dated Audit。

## AD-109：普通本地提交必须使其它 open scene 收敛，但不能重复副作用

状态：Accepted

背景：每个 `ContentView` 持有独立的 `TimeTrackerStore` 与 `ModelContext`。原先只有 App Intent/System Action 通过进程内 notification 通知所有 scene；普通 UI 提交只刷新发送 scene，导致另一窗口保留过期任务、Checklist 或 timer read model，直到一次偶然的 CloudKit/前景刷新。把这类通知当成跨进程同步又不正确：`NotificationCenter.default` 仅限当前 App 进程。

决策：所有 `finishCommittedMutation` 在 durable mutation、当前 scene refresh 和 snapshot recording 后经 `StoreMutationBroadcaster` 发布准确的 `StoreDomainEvent` 集合，并把发送 store 作为 source。接收 scene 仅调用 `refreshCoordinator.refreshReadModels`，不 record snapshot、不发布新通知、不自动启动 LLM；若 plan 要求 task/ledger selection validation，则在读刷新后补做该本地导航校正。source identity 相同的发送 scene 跳过重复 refresh。system action 没有 scene source，继续广播给所有本进程 scene。跨进程收敛仍由 persistent store/CloudKit 回调、durable snapshot 和各系统 surface 的 post-commit path 负责。

后果：多窗口普通操作可立即收敛，且不会形成 notification loop、双写 snapshot 或重复 AI 请求。source identity 只存在于同步的进程内通知，不能进入 SwiftData、CloudKit 或被用于业务 identity；一个丢失的进程内通知只能延迟 UI 收敛，不能影响已提交数据的正确性。

验证：store-scoped 自动化回归覆盖一个 scene 通过正常 Checklist command 提交、另一个独立 context 自动获取新 read model，且两端均不启动 Inbox/Checklist AI 请求；System Action 的 all-scene 回归继续覆盖无 origin 广播。最终数字与资源清理记录在 dated Audit。

## AD-110：SyncConflict 快照以校验过的 slot manifest 提交

状态：Accepted

背景：旧的 `SyncConflictState.json` 同时内联 local、forced-upload、cloud 与 conflict-working 四份完整 `SyncDataSnapshot`。大型历史库在一次冲突或恢复时可将同一事实复制四次；即使有 128 MiB 文件上限，读取仍会在主同步状态路径一次载入整份 JSON，且相同 cloud/working baseline 会额外重复存储。

决策：把磁盘权威格式升级为 V1 manifest。manifest 保留原有标量状态，快照改为带 slot、A/B generation、byte count 和 SHA-256 的引用；最多八个固定 slot 是唯一允许的 payload 位置。先以 `DurableLocalFile` 写入并同步新的 slot，再发布 manifest，manifest 才是提交点；成功后只删除未被新 manifest 引用的 slot。读取对每个引用有界读、长度和 digest 校验，任一缺失、损坏或不匹配都会隔离该 slot 和 manifest，显式进入恢复而不是降级成“无 pending conflict”。旧内联 state 首次 locked read 后重写为 manifest；`SyncConflictState` 仍是所有调用方的完整运行时读模型。新的 conflict 初始 working baseline 为空，读取时以 cloud baseline 作为 working fallback，只有真正分歧后才持久化另一份 working snapshot。

后果：同步恢复状态的根文件大小只随元数据增长，完整 snapshot 受每 slot 64 MiB 上限约束，且不会在 root 中四重复制。slot writer/reader 对已持有的 canonical JSON 直接计算 digest，避免为同一 payload 再编码一次。写入中断不会使旧 manifest 指向半写入 payload；没有被提交的 slot 可以在下一次成功保存时复用或清理。该格式仅位于设备本地 Application Support，不进入 SwiftData、CloudKit 或导出 JSON；因此不增加模型 schema migration，但不再支持把新 manifest 当作旧版内联 JSON 读取。默认状态清除必须同时删除 mirror、manifest 和全部 slot。

验证：付费自动签名 macOS XCTest 覆盖 legacy inline migration、精确 state/slot 边界、large snapshot manifest bound、sidecar hash 破坏后的 fail-closed quarantine、existing state/mirror write failure 与 source-layout；结果和资源清理记录在 dated Audit。

## AD-111：已提交的同步快照在同一锁内返回 conflict prompt

状态：Accepted

背景：普通 store mutation 已在 store → SyncConflict state lock 内捕获快照并发布 manifest，但 `TimeTrackerStore` 随后再调用 `prompt()` 取得 UI 提示。这会立刻重读 manifest 和所有已引用的 slot；对大型恢复快照而言，提交后不必要地再次解码同一份数据，也在两次锁之间引入新的 state 版本。

决策：`recordLocalMutation` 返回 `SyncLocalMutationSnapshotResult`。实际记录路径在同一把 state lock 内从刚保存的 runtime state 组装 `.recorded(prompt:)`；不需要记录快照的路径返回 `.notRecorded`，由既有调用方继续按原语义调用 throwing `prompt()`。正常 lifecycle 与 Watch post-commit refresh 消费已返回的 prompt；System Action 只需记录快照，显式忽略这个返回值。不得以 catch 后返回 `nil` 掩盖 state/slot 损坏或 I/O 失败。

后果：已记录 mutation 避免一次重复 manifest/slot 读取，同时 UI 看到的 prompt 恰是本次提交的版本。未记录路径的可见错误边界不变；这不是新锁或新的同步协议，也不改变 CloudKit、SwiftData 或恢复数据结构。

验证：付费自动签名 macOS SyncConflict、state-write、store serialization、System Action、Watch 与 source-layout 定向批次覆盖 returned prompt 和 manifest-backed Watch state；准确结果、首次失败重跑和资源清理记录在 dated Audit。

## AD-114：手工补录以锁内的任务可计时性作为最终准入

状态：Accepted

背景：Manual Time sheet 在打开时从 scene read model 选择可计时任务，旧保存路径也只检查同一份缓存，然后用 scene-owned repository 直接写入。另一窗口、App Intent 或 CloudKit 可以在两步之间完成、归档或删除任务及其祖先；旧 writer 因而能在目标已不再可接受新工作时创建新的 manual session/segment。

决策：`StoreScopedSegmentCommandCoordinator.addManualTime` 使用 AD-069 的 store lock 与 fresh `ModelContext`。它在锁内调用 repository 的 `preparedTrackableTitleSnapshot`/`addManualSegment`，由 canonical task hierarchy 给出最终 `taskUnavailable`、时间范围、未来时间和持久化校验。facade 的缓存检查只保留作未配置 store 与显而易见不可用目标的快速用户反馈，不能替代或绕过锁内准入；成功后才在锁外刷新、记录同步快照并广播 ledger event。

后果：补录与 timer、Pomodoro、segment edit/delete、task lifecycle 共享同一 writer domain，不会把新时间事实写到刚失效的任务。旧草稿因并发变更而被拒绝时，facade 刷新任务、ledger 与 Pomodoro read models，并显示既有的可计时性错误；用户需从最新可用任务重新提交。此规则不改变历史时间片继续保留原任务归属的读模型语义。

验证：store-scoped coordinator 测试先由 sibling context 完成目标任务，再确认 manual writer 在 locked fresh context 拒绝且不创建 segment；架构合同禁止 facade 回退到 `ledgerCommandHandler`/scene repository。付费签名定向 XCTest 结果和资源清理记录写入 dated Audit。

## AD-115：同步偏好、LLM 凭据配置与 Countdown 新建共用 store writer 域

状态：Accepted

背景：Timer admission 已在 store lock 内读取 `allowParallelTimers`，但 Settings 的同步偏好写入和 Countdown 新建仍使用 scene-owned `ModelContext`。多窗口同时保存时可能基于过期的 physical preference rows 生成额外 sibling；更严重的是完整 LLM 配置先在锁外读取旧 Keychain key，再写入新 key/SwiftData，失败补偿可覆盖另一个窗口已经完成的 API key 修改。

决策：`StoreScopedPreferenceCommandCoordinator` 和 `StoreScopedCountdownCommandCoordinator` 都使用 AD-069 的“lock → fresh context → atomic mutation”顺序。普通 synced preference 在锁内 canonicalize/logical-winner 更新；Countdown 新建也在同一临界区创建。完整 LLM 配置在该锁内按“读取旧 key → 写新 key → preference batch”执行，保存失败仅补偿同一临界区内捕获的旧 key；单独 API key 更新以不保存 SwiftData 的 fresh-read lock 与完整配置串行。锁不把 Keychain 和 SwiftData 宣称为一个 ACID transaction：Keychain 失败不写 preferences，SwiftData 失败仍必须报告和尽力恢复 Keychain，且不得在锁内做网络或 UI 工作。

后果：Settings scene、Timer admission、App Intent 和其它 store writer 不会以不同 context 交错修改同一 preference/Countdown 事实；成功 writer 仍在锁外执行 read-model refresh、snapshot recording 与跨 scene broadcast。已废弃的 facade handler instance 不再保留，command handler 只由拥有 fresh context 的 coordinator 构造。设备本地 `UserDefaults` 开关保持独立，不被误加入 CloudKit preference transaction。

验证：preference coordinator 测试覆盖 sibling preference 更新后锁内 logical winner；Countdown coordinator 测试覆盖 fresh-context 创建；架构合同固定 facades 不再用 `perform(event:)`/scene-owned add，并固定 coordinator 的 fresh mutation/Keychain lock boundary。付费签名定向 XCTest 结果和资源清理记录写入 dated Audit。

## AD-116：Analytics Today visual read models 与持久模型分隔主 actor

状态：Accepted

背景：AnalyticsView/Category Detail 的 `.task(id:)` 在 main actor 直接调用 facade；虽然有 request identity、cache、同周期保留和 `Task.yield()`，cache miss 仍会同步执行 segment canonicalize、daily/rhythm/quality、overlap sweep、timeline 与 read-model materialization。2026-07-17 的签名 macOS 基线中，720 条月度 fixture 的完整测试为 98 ms，2,000 条高重叠 Today fixture 为 284 ms；总时长包含 fixture 创建，不是 microbenchmark，却已足以说明主 actor 错过交互预算。

决策：R1 只建立一个明确边界。主 actor/Store 保留 SwiftData 可见性筛选、cache key/request identity、取消、最终缓存写入与 `@Observable` 发布；`TimeTrackerStore+AnalyticsLoading.swift` 把需要的 canonical `TaskNode`、`TimeSegment`、`TimeSession` 和路径/title fallback 投影成不可变 `Sendable` `AnalyticsVisualSnapshotInput`。后台任务只能接触该 input 与 `AnalyticsVisualSnapshotModels.swift` / `AnalyticsVisualSnapshotService.swift` / `AnalyticsVisualOverlapService*.swift` 中的纯 worker，并只计算 Today 的小时活动、timeline layout 和 overlap sweep；不得捕获 `ModelContext`、`PersistentModel`、SwiftUI binding、facade 或 mutation lock。core overview/comparison/rhythm/quality 仍留在 main actor，但必须以单独的 high-density residual budget 约束。返回时只发布仍匹配完整 request identity 的结果；range、calendar interval、revision 或 live bucket 改变时取消旧任务。不得为了绕过量测而增大缓存、降低输入精度、改变 gross/wall/overlap/comparison 语义，或把计算搬进未受控的 detached work 后继续读 SwiftData。

后果：第一次 cache miss 不再因 visual projection 独占 period 控件、滚动或导航；SwiftData 与 CloudKit 的线程/隔离边界保持完整。输入投影会增加一次有界复制，core assembly 仍会有受预算约束的短 main-actor 段，不能夸大成“全 snapshot 已后台化”。R1 已由 `55f19ae` 提交并停止主动重构；最终 universal macOS Release archive 已完成。

验证：为输入投影和后台 engine 增加与既有 hourly/timeline/overlap 同值的 deterministic regression，空 Today 保持 24 桶；facade 使用 task identity 与 cancellation handler 防止 stale result cache/publish。2,000 条高重叠 fixture 记录 main-actor projection `< 50 ms` 与 visual 后 core assembly `< 175 ms`；same-period refresh、task-detail snapshot 与 cache hit 继续由既有 contract 覆盖。最终定向签名 macOS 测试 139/139、完整性能预算测试 9/9 成功。本机 runner、trace、result/DerivedData 和任何 owned simulator 都在每批结束后清理。

## AD-117：共享 Blossom 颜色选择器并补足触控语义

状态：Accepted（macOS 顶层 presenter 条款由 AD-135 取代）

替代关系：本决策只对 BlossomColorPicker 取代 AD-011 的“当前不新增第三方库”；不得据此引入 FlowDown 的其余依赖栈。AD-135 只替代本决策的 macOS 顶层 presenter 条款。

背景：任务、分类、Checklist 与 Pomodoro 计划共享同一组符号和颜色，但 iPhone 的完整 inline 色板会压缩符号 viewport；软件键盘出现后，小屏设备可能看不到可点图标。文字菜单虽然释放了空间，却把本应直接识别的颜色变成需要阅读和逐层扫描的命令。用户明确指定 [Lakr233/BlossomColorPicker](https://github.com/Lakr233/BlossomColorPicker/)；审查的官方提交 `9a1ee3df309e37ae271362818dcdfdb072ea9611` 使用 MIT 许可证、没有网络或数据访问，也没有传递依赖。其顶层 iOS presenter 固定使用 30 pt 花瓣并自行寻找 window，而且没有公开 `BlossomStyle` 参数；公开的 `BlossomColorPickerCore` 允许应用复用同一个默认花瓣视图、模型、色板、亮度滑杆和命中算法。首版适配虽然复用了 Core，却自行改成 44/88 pt 环半径，偏离了“只把上游组件放大”的用户要求。

决策：

- 工程通过 Swift Package Manager 固定官方 BlossomColorPicker 的精确提交，不复制或改写其色轮实现。`Package.resolved` 与工程引用必须同时锁定该 revision。
- iOS/iPadOS 使用原生 44 pt `Button` 作为当前颜色入口，并在 scene-owned 的系统 SwiftUI popover 中直接使用库公开的默认 `ExpandedBlossomView`、`BlossomColorPickerModel` 与 `PetalLayout()`。整个上游视图统一按 `44 / BlossomConstants.petalSize` 等比放大，使可见花瓣从上游 30 pt 变为 44 pt；花瓣相对位置、颜色、动画、亮度轨道和命中逻辑保持上游默认值。应用薄适配层只负责统一缩放、键盘焦点、popover 边界与十六进制 binding，不另造或重排色轮，也不在系统 popover 内添加第二张应用自有 picker 卡片。
- macOS 的展示与坐标换算由 AD-135 约束；平台差异只存在于同一个 `SymbolColorWell` 内。任务、分类、Checklist 与 Pomodoro 计划继续只复用 `SymbolColorPickerButton`，调用方不得复制 picker。
- 打开颜色入口前结束符号搜索焦点；即使软件键盘仍在，符号 viewport 也至少保留一个完整 44 pt 可点行。选择符号、提交搜索或滚动同样遵循统一的焦点规则。
- 人工选择可保存任意有效的六位 sRGB 十六进制值；既有 24 色只继续作为 AI 输出白名单，不能把 Blossom 选出的颜色在保存时偷偷量化回固定 palette。
- Blossom 包含的浅色在深色外观下不能继续叠加固定白色图标。选中符号、Checklist 完成标记和 Timeline 色块统一根据实际背景亮度选择黑/白前景，并保持至少 4.5:1 对比度。

后果：颜色重新成为直接、可视的二级选择，不再长期占据图标列表，也不需要阅读色名菜单；视觉与交互继续由 Blossom 自身定义，应用不再维护第二套花瓣几何。依赖回退只需移除一个 package 引用和 `SymbolColorWell` 适配文件；持久数据仍是可移植的六位 sRGB 字符串。未来升级必须重新审查许可证、公开 API、iOS scene/presentation 行为和触控尺寸，不能把上游固定 30 pt 的全窗口 presenter 直接恢复到 iPhone。

验证：单元测试固定十六进制规范化、任意 sRGB round trip、AI 白名单及 30→44 pt 等比系数；source contract 固定官方 URL/revision、默认 Core layout、统一缩放、禁止自建 `BlossomStyle` 和四类调用方复用。签名 macOS 与 iOS 构建必须同时编译；正常字号 iPhone/iPad 行为验证覆盖软件键盘上方的 symbol viewport、44 pt 颜色入口、Blossom 展开/选色/收起、搜索选图标及 Back 后外层草稿和颜色不丢失。截图、签名结果和 owned 资源清理写入 dated Audit。

## AD-118：Live Activity 只保留与 Today 一致的可扫读计时身份

状态：Accepted

替代关系：本决策替代 AD-051 的 Live Activity 可见停止控件与展开布局要求、AD-080 的 Live Activity `Button(intent:)`/停止入口，以及 AD-105 的 Live Activity 停止控件；Widget 的显式停止入口不变，AD-080 的 Activity immutable segment 身份、Shortcut/Widget 精确停止语义和 AD-100 的 stale elapsed 冻结规则仍然有效。

背景：锁屏 Live Activity 把图标、任务标题、路径、时间、附加计时数量、状态说明与停止动作同时塞进有限空间；展开 Dynamic Island 又把同一信息拆到多个 region。它既没有对齐 Today/Now 已经稳定的任务身份层级，也让用户难以在一眼内找到真正重要的任务和时间。用户明确要求锁屏对齐 Today/Now（不需要停止指示），并要求展开 Dynamic Island 只在同一行显示 icon、任务名称和时间。

决策：Live Activity 是可点开、不可就地修改账本的只读投影。锁屏与 expanded Dynamic Island 共用 extension 内唯一的 `LiveActivityTimerRow`。锁屏沿用 Today/Now 的 34 pt 任务图标、headline 标题、caption breadcrumb 与 title3 等宽 elapsed hierarchy；expanded 普通字号只显示 30 pt 图标、单行标题和 elapsed，不显示路径、附加计时数量、Elapsed caption 或停止按钮。整个表面只深链到 Today，用户在 Today 的正在计时行停止对应计时。普通字号优先横排；空间确实不足或辅助功能字号时允许共享行纵向回退，不能为了字面单行而裁掉身份。compact 由小图标、可截断标题和 frozen-aware time 组成；minimal 优先显示 frozen-aware time，并用任务色 keyline 保留身份，因为系统宽度无法容纳三项。

任务身份必须复用 `TaskIdentityPresentation` 的 canonical visual 与 readable/abbreviated breadcrumb，不再维护 Live Activity 专用 parent-path 算法。标题、两种路径、图标和颜色分别采用 Unicode-safe UTF-8 上限，使最大投影在 ActivityKit 4 KiB 边界内保留余量。相同开始时间以 segment UUID 作稳定次级排序；隐藏附加计时数量后将兼容字段固定为零，避免不可见状态触发无意义 Activity 更新。

后果：锁屏与应用内 Now 形成同一视觉语法，展开 Dynamic Island 只有一个主信息行；并行计时仍以最早活动时间片作为单一投影。移除 Live Activity stop intent 不会删除应用的精确 stop deep link、Shortcut 或 Widget 能力；immutable segment ID 仍用于 Activity 生命周期协调。stale 图标、冻结值、privacy-sensitive 任务文本和辅助功能值继续保留。

验证：系统表面与 deep-link source contract 必须固定共享 row、expanded 单一 bottom region、Today-only `widgetURL`、无 Live Activity `Button(intent:)`/stop URL/附加计时文案，并继续覆盖 Lock Screen、expanded、compact 与 minimal 的 stale elapsed policy。projection limits 测试覆盖 Unicode 边界与总预算；三语 localization parity、付费签名 macOS 定向测试、generic iOS extension build 和正常字号 iPhone 锁屏/展开 Dynamic Island 视觉证据完成后，才能勾选对应真人反馈。

## AD-119：Watch 使用三页纵向分页，并解耦 Quick Start 与全任务排序

状态：Accepted

关联关系：本决策只替代此前文档中“单一 Crown-scrollable 长列表、其余任务 push 到全部任务”的 UI 组织；AD-004 的 durable command/typed terminal result/payload 上限、AD-100 的 stale elapsed，以及 AD-101 的锁内并行偏好仍继续有效。

背景：旧 Watch dashboard 把活动计时、Quick Start、失败与“所有任务”入口串在一张列表里。用户有活动计时时，开始另一项工作需要先越过计时行再进入次级页面；Quick Start 的 pinned 顺序又和全任务列表混成同一个“近期任务”概念，无法清楚回答“正在做什么”“马上开始什么”“全部可工作任务是什么”。

决策：

- `WatchDashboardView` 在同一个 `NavigationStack` 中使用 `.verticalPage` `TabView`，固定三张同级页：Active Timers、Quick Start、All Tasks。第一次收到有效 snapshot 时只选择一次默认页：通常有活动计时进入 Active Timers，否则进入 Quick Start；若存在任何 status（sending/queued、connectivity error、stale）或 command failure，即使没有 timer 也进入 Active Timers，让恢复路径优先可见。之后任何 snapshot、命令结果、status/failure、stale 或连接刷新都不得抢走用户当前页；若用户停留在 Quick Start 或 All Tasks，页面顶部必须出现 label 高度至少 44 pt 的本地化“Review/查看状态”按钮，显式返回 Active Timers。
- Quick Start 排除运行任务，先按手机偏好的 pinned 顺序放入任务，再按全任务使用顺序补足，Watch 正常界面最多显示四项。All Tasks 不继承 pin 顺序，统一按 segment count 降序、last-start 降序、UUID 字符串升序；从未使用的任务以最早日期参与稳定尾部排序。
- All Tasks 必须保留运行任务，并以绿色 timer 图标表达运行状态；本地化的 Running 文案属于辅助功能标签，不在狭窄表盘上重复占据一列。点按运行任务只切回 Active Timers，不发送 stop；精确停止只属于 Active Timers 的 segment row。点按其它任务可以在已有计时时发送 start，最终并行还是先停止冲突计时由手机在 store lock 内读取全局 `allowParallelTimers` 决定。
- 传输继续使用既有 `recentTasks` key，并保留其 legacy pinned-first 数组顺序，避免旧 Watch 的 Quick Start 行为发生 wire break。`quickStartRank` 与 `allTasksRank` 都是可选字段，旧 payload 缺少时解码为 `nil`；两种 rank 各自必须唯一并落在对应 `WatchTransportLimits` 上限内。producer 在 256 个任务和与 active timers 共用的 128 KiB 文本预算内按四级优先级去重决定 membership：(1) Watch 实际传输且仍有 task projection 的 running tasks；(2) 新 `quickStartRank` pins；(3) 旧 Watch 会显示的前 `legacyQuickStartTaskLimit == 4` 个非运行 legacy Quick rows；(4) canonical usage remainder。只有集合固定后，才把入选项按 legacy order 重排为 wire array，并写入连续 `allTasksRank` 供新 Watch 恢复 All Tasks 的 usage 顺序；最终兼容重排不能改变 membership。旧 Watch 忽略两个新字段后继续得到既有前四项 Quick Start；新 Watch 连接旧手机时按 wire 顺序回退。任何 reservation 都不得偷偷改写带 rank 的 All Tasks 顺序。
- 失败预览、全部问题、pending/retry/discard、连接与 stale 状态继续属于 Active Timers 页，并固定排在 timer rows 之前；陈旧 elapsed 继续冻结，任务/计时/失败标题在 luminance-reduced/Always On 状态继续隐私遮盖。三页重排不得削弱这些既有安全边界。

后果：数码表冠在三个单一目的的同级页面之间自然移动；用户可以不先停止当前计时就去选择另一任务，同时明确知道运行项不会因整行点击被停止。Quick Start 仍尊重个人固定项，而 All Tasks 提供可解释、稳定、独立的使用排序。wire key、legacy 数组顺序和 optional 字段同时维持双向兼容；旧 payload 没有 rank metadata 时，新 Watch 的 Quick Start 与 All Tasks 都按收到的原数组稳定回退。

验证：2026-07-19 的冻结源码已完成 41/41 Watch command/projection/UI source-contract 定向回归与 3/3 相关 source-layout 预算回归，均为付费自动签名 macOS 测试且无 failed、skipped 或 runtime warning。generic iOS 与独立 generic watchOS Debug 自动签名构建均为 0 error/0 warning/analyzer warning；主 App、Watch、Widget 与 Live Activity 严格 codesign 通过，保留 Team `LT98S43NKA` 和付费开发签名。专属 Apple Watch SE 3 40mm / watchOS 27.0 模拟器覆盖三页、attention override、后续状态不抢页、44 pt Review、failure/status/timer 顺序、运行任务 timer 图标与回到 Active、pending、stale、connection error、大字号及空状态，截图与完整资源清理证据写入 dated Audit。未取得配对真机证据，因此 WatchConnectivity 往返、离线恢复、Always On 实机遮盖和功耗仍明确属于后续真机门禁。

## AD-120：移除任务工作流状态，仅保留归档兼容边界

状态：Accepted

替代关系：本决策完整替代 AD-028。AD-028 保留为历史记录；所有更早决策中“任务 completed 会阻止新工作”“显示任务状态/完成/重开”或“必须先重开完成路径”的局部条款同样由本决策替代，其余关于锁、fresh context、原子提交、stale 校验、账本和 Pomodoro 一致性的边界继续有效。

背景：`planned / active / completed / archived` 最初同时承担持久化兼容、任务组织和准入语义，后来又扩散成编辑器 Picker、列表/详情 badge、完成阻塞、路径级 Reopen 和多入口过滤。同一任务还拥有 Checklist 完成度，用户必须猜“完成任务”和“完成清单”之间的关系；旧 raw 值又已经存在于 V4 schema、本机/iCloud 数据和同步快照中，不能用一次破坏性的批量清洗换取表面简化。

决策：

- 任务不再拥有产品层 workflow status。编辑器、任务行、详情、菜单和辅助功能值都不显示状态选择器、状态徽章、Complete 或 Reopen。
- Checklist 是任务完成与进度的唯一产品语义，并继续提供 checklist-derived forecast evidence。全部 checklist 完成时自身 remaining 为零，但任务和后代仍可继续计时、编辑、添加清单或接收其它新工作；显式任务 estimate 与子任务 rollup 规则不变。
- `TaskNode.statusRaw` 作为旧 schema、snapshot 和 CloudKit record 的兼容字段保留。`LegacyTaskStatusRaw` 继续接受并 round-trip V4 的 `planned`、`active`、`completed`、`archived`，不迁移、不批量回写 iCloud；前三者完全不影响显示、层级、编辑、forecast 或 work admission。
- 归档是独立生命周期：`archivedAt != nil` 或 raw `archived` 任一成立就隐藏该分支并拒绝新工作；新的 Archive 命令同时写 `archivedAt` 与 raw `archived` 以兼容旧客户端。归档活动子树前只要求先停止其中的 timer/Pomodoro，不再存在“完成任务前停止”或“重开路径”。
- Delete 的 soft-delete/tombstone、历史 segment/session/Pomodoro 归属、生产 store 不永久清 tombstone 等规则不变。旧 `statusRaw` 也不能替代 `deletedAt`。

后果：任务层只有“可工作”与“已归档/已删除”这组可解释边界，清单完成不会制造不可见的写入阻塞；Today、Quick Start、Pomodoro、Manual Time、Inbox、App Intent、Watch 和新建/移动目标都把 legacy planned/active/completed 当作普通任务。兼容字段仍能让历史数据和旧客户端往返，新客户端不再为它维护第二套状态机。

验证：领域测试必须覆盖三种非归档 legacy raw 值仍可见、可编辑、可计时、可作父级并参与 forecast；archive 任一 marker 的读兼容、双写、活动子树拒绝和 marker 修复；snapshot preflight 四值接受且不批量改写；Checklist 全完成只把 checklist-derived remaining 置零。UI/source contract 必须确认状态 Picker、badge、Complete/Reopen 文案与命令入口消失，同时保留 Running、Archive、Delete 和 checklist 交互。签名测试、构建、三语 parity、正常字号操作路径和资源清理证据写入 dated Audit。

## AD-121：任务摘要行与计时动作只保留一套共享语法

状态：Accepted

替代关系：本决策替代 AD-050 中任务行必须维护多套视觉 composition 的条款、AD-097 中详情 identity row 显示运行状态的条款，以及 AD-102 中 Quick Start 额外显示 `RunningStatusBadge` 和由 feature-private `QuickStartTimerAction` 拥有控件外观的条款。AD-050 的完整 VoiceOver 投影、AD-053 的选择/停止命令分离和 AD-102 的任务导航/计时动作分离继续有效；当时保留的 AD-097 系统标题唯一性后来由 AD-124 替代。

背景：Tasks、Sidebar、层级选择器和 Quick Start 分别实现了标题、路径、checklist、运行状态、时长和动作。相同任务因此在一个表面把 Running 做成 badge，在另一个表面又同时出现 Stop；任务列表还维护普通、紧凑和辅助字号三套 row，标题、metadata 和导航符号的优先级会随入口漂移。计时选择器的 Running section 已经说明状态，再叠加 Running badge 和 Stop 是重复表达。

决策：

- `TaskSummaryRow` 是静态任务身份与摘要的共享视觉 owner。它消费 canonical `TaskIdentityPresentation`；标题拥有最高布局优先级，正常字号最多两行，辅助功能字号允许完整生长。
- `.hierarchical` 只显示标题，由现有树缩进、展开控件和 section 提供上下文；`.standard` 在标题下显示不含自身的父级路径，供搜索和平铺表面区分同名任务。调用方不得重新拆分 path 字符串。
- 摘要 metadata line 在正常字号按“checklist progress、flexible spacer、被动 `TaskRunningIndicator`、已工作时长、navigation/accessory”排列；在 `.hierarchical` 中它是标题后的第二个内容行，`.standard` 可以先插入父级路径。辅助功能字号可把 checklist 与 trailing facts 纵向拆开。被动 timer 图标只说明事实，不拥有 Stop 命令。选中 checkmark 和 navigation chevron 可以是 accessory；Start/Switch/Stop 这类命令不能伪装成 metadata glyph，也不能替换任务 identity icon。
- Tasks management row、Sidebar task tree、层级选择器的普通/单选行和 `TaskIdentityRow` 必须复用 `TaskSummaryRow`。Tasks 的 VoiceOver 仍由 `TaskManagementRowAccessibilitySnapshot` 补足完整路径、预测和子任务数，不要求这些扩展事实常驻挤压正常字号视觉行。
- `TaskTimerActionButton` 是主应用明确 Start/Switch/Stop 控件的共享视觉 owner，统一 bordered style、destructive role、满足 iOS/iPadOS 至少 44 pt 点击目标的尺寸、macOS 原生 28 pt 尺寸、icon-only/title-and-icon 分支，以及包含目标任务名的 accessibility label/hint。Today、Quick Start，以及计时选择器中未运行任务的 Start/Switch 和运行任务的 Stop 全部复用它；准入、并行和精确 segment 语义仍由 caller 与 timer command 决定。
- 计时选择器固定使用 icon-only 变体，把 Start、Switch 和 Stop 放在同一个尾部操作槽；该槽在 iOS/iPadOS 固定为 54×54 pt，在 macOS 固定为 28×28 pt。每行由独立的只读 `TaskSummaryRow` 与右侧原生 `Button` 组成；摘要保留自己的可访问语义，不能隐藏后让 SwiftUI 把唯一的 Stop 按钮提升成整行破坏性点击目标，也不能把摘要与动作互相嵌套。
- 只要同一表面已经提供 Stop，就不再重复 Running badge。计时选择器 Running 区域和运行中的任务详情只显示明确 Stop；Quick Start 的 elapsed 与 Stop 同样不再附加 Running。选择器 Stop 后保持打开，任务回到可选层级；只有成功 Start/Switch 才关闭。Pomodoro/Inbox 的 single-selection 行可以显示被动运行图标，但选择本身绝不启动或停止计时。

后果：长标题先于 checklist、状态和时长获得空间；树内与平铺上下文各自保留必要而不重复的信息。Running 作为被动事实只存在于没有停止命令的摘要表面，Stop 作为明确动作只存在于可改变账本的表面，不再同时堆叠。计时选择器跨运行状态保持相同的图标尺寸、纵向位置、尾缘和点击范围。以后新增任务表面必须先选择 identity context、metadata 和独立 action，不得复制另一套 row 或把状态与动作重新合成 toggle。

验证：共享组件、Task、Home 与 picker source contracts 固定复用边界、两行标题、metadata 顺序、无 `RunningStatusBadge` 和精确 Stop。行为测试固定 timer mode 把运行任务移出可选 rows、single-selection 仍允许选择运行任务。2026-07-19 冻结范围的 macOS contracts 为 92/92；正常字号 iPhone 17 Pro 与 iPad Pro 11-inch 各自通过 Tasks 长标题/被动 timer metadata 和 picker Stop-only/停止后继续选择两条路径，共 4/4。后续真人反馈收口再以 30/30 macOS 定向回归和 iPhone/iPad 各 1/1 的同屏 Start/Switch/Stop、Stop→Start 尺寸/尾缘断言冻结 54/28 pt 操作槽。generic iOS 与 macOS Debug 自动签名构建及严格 codesign 通过；截图、失败诊断边界和资源清理记录在 dated Audit。

## AD-127：普通任务只保留可恢复的归档，不再提供删除命令

状态：Accepted

替代关系：本决策替代 AD-120 中“保留 Delete 产品动作、Delete 文案与命令入口”的条款，也替代更早决策中普通任务行、详情、菜单或滑动操作必须提供 Delete/soft-delete 的局部规则。`deletedAt` 的同步、迁移、LWW、历史账本和生产 tombstone 保留边界不变。

背景：普通任务同时提供 Archive 和 Delete 时，两者都会把任务从日常界面隐藏，但 Delete 还会静默结束活动计时与番茄流程，并把恢复能力藏在实现层 tombstone 中。用户无法从界面稳定判断应该使用哪个动作；各表面又分别维护确认、路由、计时终止和删除 outcome，形成一条没有现存 UI caller 的重复命令链。与此同时，旧版本与 iCloud 已经存在 `TaskNode.deletedAt`，全量清空后用本机覆盖云端也依赖只含 tombstone 的快照，不能把“移除产品 Delete”误做成“移除 tombstone 协议”。

决策：

- 普通任务只有 Archive/Restore。任务行、侧边栏和详情复用 Archive；Settings 的 Archived Tasks 复用同一任务摘要并按父任务优先恢复。当前产品不显示任务 Delete 文案、确认框、按钮或滑动动作。
- Archive 不静默停止工作。目标分支仍有 timer 或 Pomodoro 时命令无写入地拒绝，界面说明先停止；成功归档隐藏分支但保留全部账本与番茄历史。
- 删除 `TimeTrackerStore.deleteSelectedTask`、task lifecycle coordinator `delete`、task handler/use case/repository 的 soft-delete API，以及只服务该链的 outcome/snapshot 类型。其它实体的合法 Delete（时间片、Checklist、Inbox、分类、倒计时、维护重置）不受影响。
- `TaskNode.deletedAt`、旧 schema、snapshot capture/restore、preflight、LWW/dedup、清空数据、历史 fallback 和生产 purge guard全部保留。旧客户端、CloudKit/import 或权威恢复带来的 tombstone 继续隐藏任务、拒绝新工作并保留历史关系；Restore 只清 archive marker，绝不能清 `deletedAt`。
- 兼容测试直接构造完整的外部 tombstone（同步推进 `updatedAt`、`deviceID` 与 `clientMutationID`），不得在测试支持层重造递归删除、停止 timer/Pomodoro 或清理 assignment 的产品命令。

后果：任务生命周期只剩一条可解释且可恢复的用户路径，菜单、滑动、Settings 和路由都围绕 Archive/Restore 收敛；旧 iCloud 数据仍不会复活，清空本机后覆盖云端仍能携带删除意图，历史分析与账本也不会失去任务归属。以后若要引入真正的永久删除，必须先定义跨设备确认、历史事实处置和恢复窗口，不能复活旧 soft-delete 链。

验证：source contract 固定普通任务 UI 与生产 task command/repository 文件不存在 Delete 链，同时保留 `deletedAt`、`task.deleted.path` 和三语 archive/restore 文案。行为回归覆盖任务行/侧边栏共享归档、活动子树阻止、跨 scene route/selection 收敛、Settings 父优先恢复，以及历史 tombstone 在 Analytics、ledger admission、stale draft、同步与维护中的兼容。每个 checkpoint 继续使用付费自动签名测试与构建，并在提交后运行全设备安装脚本。

## AD-128：一分钟内的普通计时重启续接为一个 canonical 时间片

状态：Accepted

背景：用户短暂误触停止后立刻重新开始同一任务时，账本会留下两个相邻时间片，Today 时间线、近期记录和 Analytics 的 segment count 都把一次连续工作显示成两次。只在读侧把两行画成一条又会让编辑、删除、Gross 和同步事实互相矛盾。另一方面，手动补录、日历导入和 Pomodoro 都拥有明确边界或额外业务关系，不能为了表面整洁无条件归并。

决策：

- 只把 `.timer/.shortcut/.watch/.widget/.liveActivity` 视为同一个普通 stopwatch 来源族。第二次 Start 与同一 canonical task 的上一条普通时间片满足 `0 <= gap < 60s` 时，短 gap 视为一次误停并计入连续工作；恰好 60 秒、负 gap、不同任务、手动补录、日历和 Pomodoro 都不续接。
- 判断发生在 `StoreScopedTimerCommandCoordinator.start` 已取得 store lock 并创建 fresh context 之后，只影响新的本地 Start，不在启动、CloudKit import、Analytics 或 Timeline 读取时回扫历史。
- gap 内存在任何其它可见正时长时间片时拒绝续接，避免 A → B → A 被错误扩成同时属于 A 的工作。上一条 session 必须可见、任务/起止/source 关系完整、只有这一条可见 segment，且没有可见 `PomodoroRun` 引用；任何异常都保守创建独立 session。
- 成功续接保留原 singleton `TimeSession` 及其 title snapshot、note、source、createdAt 和 start；旧 closed segment 写入更新后的 tombstone，新建一个不同 UUID 的 active segment，沿用原 session/source 并把 start 向前延伸到最初时间。session 重新打开并旋转 conflict metadata；mutation timestamp 留出完整的 CloudKit 毫秒安全间隔并严格支配已经观察到的 future-skewed duplicate，不能靠相同时间戳下的 device/mutation tie-break 碰运气。`restoreAsLocalWinner` 即使写入空 store，也必须推进 snapshot 自身的时间戳，避免同时间戳旧云副本重投后再次参与 tie-break。
- 绝不重新打开旧 segment ID。Watch、Widget、Shortcut 或任何仍固化旧 segment ID 的界面/系统入口都会指向 tombstone，因此只能 no-op；当前 Start 返回的新 ID 才能停止续接后的活动计时。`replaceAll` 继续明确创建独立时间片，不触发续接。
- outcome 对 replacement 发送 visible ledger event，对 predecessor 发送原时间范围的 history event；现有 refresh planner 合并两者并执行 ranged history refresh，跨午夜时也会从 scene index 删除旧 ID。普通 Start/Stop 复用 coordinator 已取的 active snapshot；Pomodoro 关系只单次读取 open working set，再按待停止 session 过滤，不扫描完整历史也不制造 N+1 查询。

后果：正常短暂停止/重启立即在 Today、近期记录和分析中表现为一个 canonical 时间片，经过时间包含不足一分钟的空档；跨普通系统表面启动仍保持同一工作意图。手动事实、导入事实、Pomodoro 轮次和既有远端历史完全不被静默改写；旧 segment tombstone 继续通过现有 snapshot/LWW 协议阻止 iCloud 复活。

验证：纯策略固定 0、59.999、60 和负 gap 以及完整来源矩阵。store-scoped 回归覆盖新 Stop identity、原 session/note/source 保留、旧 ID Stop no-op、新 ID 可停止、gap 内其它任务阻止、重复短重启链、`replaceAll` 排除、Pomodoro-linked session 与 duplicate winner 隔离、future-skewed session/segment LWW、快速重启后 Stop 对旧 active Cloud 副本重投的抵抗、snapshot restore 后 Cloud redelivery，以及跨午夜 history/rollup 收敛；真实内存 SwiftData store 另以 50,000 segment 固定查询预算。系统动作、timer admission 与 repository/source-layout 合同继续一起运行。

## AD-129：重复任务与任务量先建立可恢复、可幂等的 V13 事实层

状态：Accepted

背景：每天完成 50 个俯卧撑同时需要“重复模板”“当天真实任务”“可累计任务量”三种语义。若只在 UI 临时生成 checklist，跨设备会重复创建；若只新增模型却遗漏 conflict snapshot、清空或维护，空本地覆盖 iCloud 时又会遗留或复活历史数据。

决策：

- V13（`1.12.0`）在 V12 上 lightweight-add `TaskRecurrenceRule`、`TaskRecurrenceOccurrence`、`TaskQuantityGoal`、`TaskQuantityEntry`。全部字段有 CloudKit-safe 默认值，不使用 unique attribute 或 required relationship。
- MVP recurrence cadence 为 daily。一个模板任务只有一个 deterministic rule ID；rule/day 生成 deterministic occurrence receipt 和不同 domain 的 deterministic child Task ID。receipt 冻结 day key、template 与 timezone；停止重复用 `isEnabled`，不改写已生成的真实 Task。
- 一个任务只有一个 deterministic quantity goal；每次增量是独立 entry，entry UUID 是调用方 command idempotency key，数量完成以后续领域层对可见 entry 求和推导，不能把累计值当 LWW 单字段。rule start/timezone 与已提交 entry payload 在 MVP 中视为不可变身份边界。
- 四张 snapshot table 为 optional：legacy 缺 key 是 unknown/no-op，显式 `[]` 才能 tombstone 当前行。capture、three-way apply、preflight、restore、fingerprint、conflict summary、clear all、demo cleanup 与永久维护必须同批覆盖；本地 winner 与 clear tombstone 的 mutation time 必须严格支配已观察到的 future-skewed row。
- preflight 固定 deterministic identity、canonical `yyyy-MM-dd`、有效 timezone、正整数范围和同一快照内可证明的 rule/goal 引用；缺外键允许分阶段 Cloud import。receipt 不冻结 generated Task 当前 parent，用户移动任务或 hierarchy repair 后的快照仍必须可恢复。
- 持久层保留可见 orphan，维护只级联本批明确物理删除的父 ID；Task Store 只发布 task/rule/goal 关系完整的记录。单任务刷新必须按 task ID 查询、沿 occurrence 扩展 generated child 并局部合并，不能随 quantity entry 历史增长退化成全表 fetch/materialize。

后果：V13 先把 migration、iCloud 冲突、空数据覆盖和删除意图闭环，后续 materializer、累计命令与合并编辑 UI 可以建立在同一事实层上；当前 checkpoint 不宣称 recurrence 已可由用户创建，也不把 template 当作可计时的日常实例。

验证：付费自动签名构建覆盖主 App、Widget、Live Activity 与 Watch；真实 V12 磁盘 store 迁移后保留旧 Task 并可写四表。定向测试覆盖 deterministic UUID anchor、full/task-domain capture、legacy nil 与 explicit empty、三方合并、完整 JSON restore、staged hierarchy repair 自洽、preflight 拒绝、future timestamp clear、demo generated child cleanup、expired graph purge、visible orphan 保留/隐藏、Task Store full/scoped convergence，以及 rapid-restart identity 未漂移。实现边界记录在[重复任务运行时上下文](ImplementationContexts/2026-07-20-daily-recurrence-runtime.md)。

## AD-130：重复任务模板与当天工作实例使用两套任务资格

状态：Accepted

背景：V13 事实层能描述重复规则和当天实例，但若模板与实例都能直接计时，同一件“每天完成”的工作会同时落到蓝图和真实日期两处；若简单把模板从统一 `trackableTaskIDs` 中删除，父任务编辑、Inbox、任务菜单、Heatmap 和层级 picker 又会错误隐藏它。后台物化还必须面对跨设备分阶段到达、墓碑、暂停和设备时钟变化，不能把缺行一律解释成“需要修复”。

决策：

- 任务资格拆成 direct-work 与 parent/content。Timer、Pomodoro、手工时间、break resume 和 App Intent 只接受 direct-work；重复模板始终不可直接工作。父任务选择、任务菜单、Inbox、清单建议与 Heatmap 接受 parent/content 模板。计时 picker 可以显示不可选择的模板祖先，以便用户看到其可选择的当天子任务。
- daily rule 在创建时冻结时区和开始日期。`TaskRecurrenceDayKey` 使用该时区计算 canonical day；materializer 只尝试当前日，绝不回填过去。规则暂停、模板或祖先归档期间错过的日期永久跳过，恢复后只生成恢复当天。
- 规则、occurrence、generated task 与 quantity goal 使用冻结 deterministic identities。非 canonical rule ID 拒绝进入启停或物化路径。新建规则前若模板仍有活动 timer/Pomodoro，命令无写入地拒绝，避免既有工作悬挂到蓝图。
- 规则命令与 materializer 在现有 store-specific lock 的 fresh context 和单次 atomic mutation 中执行。首次创建任一步失败都回滚完整子图；幂等重放只补系统拥有的结构，不覆盖用户已经修改的生成任务。
- 任何可证明相同逻辑日的物理 occurrence claim、generated task/goal 行、墓碑或 staged partial CloudKit 行都会阻止后台重新创建。occurrence 先于 rule 到达时也足以把模板排除出 direct-work，避免同步窗口期间把工作写到模板。
- App 启动、scene active、任务读模型 revision、系统时钟变化和下一条规则午夜边界触发物化。时钟变化先立即尝试当前日再重排；归档后解除归档会因 revision 变化重新启动调度。

后果：重复模板继续承担组织、说明和父级语义，但每天只有一个真实实例承担计时与任务量。多设备重试和生命周期触发不会制造重复，用户编辑不会被后台覆盖，分阶段同步与墓碑不会被“修复”成复活数据。当前决策只完成运行时；没有创建规则与任务量录入 UI 前，用户反馈项仍保持未完成。

验证：纯日键和 store-scoped 回归覆盖未来开始日、当前日无回填、暂停重放、归档间隔、时钟偏移、非 canonical 规则、活动工作拒绝、每个原子 checkpoint 回滚、用户编辑保留、墓碑和 staged partial graph。入口回归覆盖 Timer/Pomodoro/manual/App Intent direct-work 拒绝、parent/content 保留和 picker 祖先容器。实现沟通与边界记录在[重复任务运行时上下文](ImplementationContexts/2026-07-20-daily-recurrence-runtime.md)。

## AD-132：AI 任务计划使用完整工作区工具提案与全量 CAS

状态：Accepted（请求预算与模型生成验收条款由 AD-133 取代）

背景：旧任务计划只把当次需求、规划指令和视觉白名单发给模型，再解析一棵只能新建的 flat JSON 草稿。模型看不到已有 Category、Task 或 Checklist，因而无法稳定复用已有实体，也不能表达更新、归档或删除；同名 `a` Category 会被无条件再次创建。若直接把 tool call 映射为单项持久化命令，模型又会绕过用户审阅，并在多 scene/CloudKit 并发变化后把陈旧操作部分写入。

决策：

- 每次用户明确 Generate 都在共享 store lock 下用 fresh context 捕获完整、确定性排序的 provider-visible Category/Task/Checklist snapshot。它包含稳定 UUID、关系、完整 Task path、完整相关文本、可编辑元数据、归档状态、任务量目标和每日重复设置，不使用任意实体数量或路径深度截断。provider-visible canonical snapshot 的 context fingerprint 绑定 request/review；本机 `clientMutationID` revision map 留在独立 baseline，不进入网络 DTO。
- 发送前界面披露三类实体 counts。完整 workspace 不复用 Inbox/checklist 的 24 KiB prompt 与 64 KiB body 投影；编码失败不发送请求，供应商以 HTTP 400/413/422 拒绝完整请求时返回包含 counts 与实际 encoded request bytes 的 typed error，不发送 partial context，也不回退 create-only JSON。4 KiB request/4 KiB synced instructions、2 MiB response transport ceiling、12 个 tool rounds 和 64 个 tool calls 继续作为字段/资源防护，不能解释为实体截断。
- 模型只能调用 strict OpenAI-compatible tools 修改纯内存 overlay：list/get；Category reuse/create/update/delete；Task create/update/archive；Checklist create/update/delete；finalize。schema 的声明属性全部 required 且禁止 additional properties。App 生成新实体 UUID 并返回 tool result，支持 read-after-write；已有 Task/Checklist 只按 UUID 引用，Category title 只有唯一规范化匹配时才复用，多个同名必须显式歧义。workspace 内文本全部是不可信 data，不得升级为 prompt 指令。Task 永远没有 hard-delete tool。
- Finalize 只生成 baseline→overlay 的确定性、只读 diff。预览显示 create/update/archive/delete/reuse counts、所属完整路径与 before→after；用户通过 `Apply N Changes` 明确提交，删除、归档或其它破坏性影响再使用原生 destructive confirmation。模型/工具不能直接写 SwiftData，stale 或失败保留 preview。
- Apply 在同一 store lock/fresh context 中重新捕获完整 baseline，并对 provider-visible facts 以及 Category、Task、assignment、Checklist、visual、quantity-goal、recurrence revisions 做保守 CAS。协调器必须重放 exact reviewed operations，复核跨类型/受保护身份、层级、活动 Timer/Pomodoro 与持久化字段策略，然后用一个 atomic mutation 提交。任何差异或 checkpoint/save 失败都是零写入、零事件；Checklist 精确编辑不能旋转无关 item/visual revision，Task removal 只 Archive 并保留 `deletedAt`。
- API key 只进入 Authorization header。prompt/tool context 排除时间 ledger/history、Pomodoro history、Health samples、Inbox、Keychain、设备 ID、同步 metadata 和本地 mutation baseline。reasoning/tool round/raw provider response 只在当前生成与审阅会话中临时存在，不持久化、不同步、导出或记录日志。

后果：模型可以在完整现状上复用已有 `a`，并以稳定身份提出混合 CRUD，而人仍拥有可读的最终 diff 和唯一提交权。任何同时发生的本机、其它窗口或同步修改都会让旧预览安全失效，不能产生 partial write。完整上下文扩大了向自定义 endpoint 发送的用户文本范围，因此发送前 counts、字段披露、typed size failure 与第三方处理政策成为发行安全边界。

验证要求：确定性 fake transport/overlay 测试覆盖完整无截断 workspace、context fingerprint、严格 tool roundtrip/reasoning passback、同名 Category 复用/歧义、read-after-write、prompt-injection-shaped data、非法 tool/error 和大于 legacy 64 KiB 的请求；store-scoped 测试覆盖混合 CRUD、每个 checkpoint rollback、完整 stale matrix、受保护身份/active work、Checklist revision isolation、零事件失败和 Task Archive-only。普通字号 iPhone/iPad/macOS UI 回归覆盖发送 counts、混合只读 diff、完整路径、破坏性确认、Apply 和 stale preview 保留；真实付费 endpoint 只能作为附加 smoke test。

## AD-133：AI 生成发送完整上下文，并以真实 DeepSeek 验收思考协议

状态：Accepted

背景：用 48 个候选、12/24/64 KiB 投影和 78 个精选图标替模型预先删除上下文，会让真实任务、分类、长文本或合法 SF Symbol 在请求前消失。把预制 provider JSON/tool call 当作模型生成验收，又会把对实际 DeepSeek 协议的猜测固化成“通过”；`tool_choice` 与 thinking mode 的真实 HTTP 400 就曾被这类测试漏掉。DeepSeek V4 官方只接受 `high`/`max` 思考强度，thinking 工具轮还要求完整回传 `reasoning_content`。

决策：

- Inbox 发送全部可工作 Task 和全部可见 Category；Checklist 发送完整标题与完整所属路径；任务计划发送完整需求、同步指令和完整 workspace。三条生产请求共用 picker 的完整规范 SF Symbols 目录。客户端只做规范化、去重和确定性排序，不按人工候选数、字段、JSON、prompt 或 request-body 预算静默删除相关上下文。
- 真实边界继续生效：opaque model ID 必须整体通过 256-byte 同步 compact-field 上限，endpoint/API key 保持配置上限，API key 只进入 Authorization header，模型 reason 按 512-byte 持久化字段归一化，provider 单响应保持 2 MiB 上限，严格工具 schema、overlay 校验、用户取消和原子 Apply 不放宽。
- `LLMReasoningEffort` 是同步普通偏好，只允许 DeepSeek 官方 `high` 和 `max`，默认 `high`。配置 Test→Save 草稿把 effort 与 endpoint、模型列表和模型 ID 同批提交。切换 effort 必须取消正在运行的 Inbox/Checklist 请求；完成回调与 Checklist fingerprint 必须包含 effort，旧请求不得在新设置下落库。
- 三条生产 service 遇到 `deepseek-v4-flash`/`deepseek-v4-pro` 时显式发送 `thinking.type=enabled` 和所选 `reasoning_effort`，省略无效 `temperature`；任务规划同时省略 thinking mode 不支持的 `tool_choice`，并在所有后续工具轮完整回传 assistant `reasoning_content`。其它模型继续使用既有兼容 temperature/tool controls，不发送 DeepSeek 专属字段。
- 纯请求序列化、schema、overlay、持久化、CAS 和 transport 安全边界可以使用确定性本地行为测试，但预制 provider response、预造 plan 或 fake tool-call 序列不得充当模型生成验收。`make test-llm-live` 必须从本地 `.env`/环境变量读取短期 key，以三条生产 prompt、prompt28、prompt150 和真实 Apply 验收实际 DeepSeek；key 不进入仓库、文档输出或测试日志。普通字号真实 UI 预览/Apply、截图与全设备 Release 安装仍是完成门禁。

后果：请求可能明显大于旧 64 KiB，完整 SF Symbols 目录本身也会增加 token/网络成本；若 endpoint 无法接收完整上下文，应用返回真实 provider 错误，不发送删减版。用户可以在配置中用官方 high/max 权衡速度与思考强度，三个 AI 功能使用同一选择。AD-027 的 Test→Save、Keychain 和自动发送单独同意仍有效，但其 48/12/24/64/78 投影被本决定取代；AD-132 的完整 workspace、严格 overlay 和原子 CAS 仍有效，但其 4 KiB/固定回合调用预算和 fake provider 作为生成验收的表述被本决定取代。

验证：本地测试读取实际编码的 `URLRequest`，证明 Inbox/Checklist 在 DeepSeek V4 下发送所选 `max`、thinking enabled、无 temperature，并覆盖 effort 同步/规范化、配置原子保存、切换取消与迟到结果拒绝。真实 gate 必须使用生产 service 让 DeepSeek V4 在 `max` 下完成 Inbox、Checklist、prompt28 和 prompt150；prompt150 还要通过生产 coordinator Apply 后重新读取 150 条持久事实。UI gate 截图真实 token progress、完整 Preview、reasoning/raw response 与 Apply 结果，不接受 fixture。

## AD-135：macOS Blossom 从所属颜色控件换算屏幕坐标

状态：Accepted

替代关系：本决策只替代 AD-117 的“macOS 直接使用库顶层 presenter”条款；其固定 revision、公开 Core、默认花瓣几何、任意六位 sRGB、对比度和四类编辑器共享入口要求继续有效。

背景：BlossomColorPicker revision `9a1ee3df309e37ae271362818dcdfdb072ea9611` 的 macOS 顶层 presenter 从 SwiftUI `GeometryReader` 取得 `.global` frame，却再通过 `NSApp.keyWindow` 转成屏幕坐标。颜色 well 位于应用自己的 SF Symbols popover 时，source view 所属窗口与 key window 不是同一个坐标空间；正常窗口位置下，194×194 pt 花瓣窗口中心会偏离 well 约 75 pt。上游默认分支与固定 revision 相同，没有提供 owner window 或 anchor `NSView` 注入点，也没有更新修复。

决策：

- macOS 继续直接复用 `BlossomColorPickerCore` 的公开 `ExpandedBlossomView`、`BlossomColorPickerModel`、默认 `PetalLayout()`、色板、亮度轨道、动画和 194 pt 默认总尺寸；不得复制花瓣布局、增加 magic offset 或引入第二个颜色库。
- `SymbolColorWell` 通过一个无视觉 `NSViewRepresentable` 取得真正属于该 well 的 anchor `NSView`。薄 AppKit presenter 必须先用 `anchorView.convert(anchorView.bounds, to: nil)` 得到所属窗口坐标，再由 `anchorView.window.convertToScreen` 得到屏幕坐标；不得使用 `NSApp.keyWindow`、`NSApp.mainWindow` 或假设外层 popover 位于主窗口。
- 默认空间以 well 中心作为 Blossom 中心，保持库原有“从色块绽放”的交互；只有接近屏幕工作区边缘时才按 owner screen 的 `visibleFrame` 夹紧窗口。picker 作为 owner window 的透明、无阴影、临时 child window 展示，因此 owner 移动、层级和关闭关系保持一致。
- 外部鼠标按下、应用失活、owner 关闭或 SwiftUI well 消失时必须收起模型并清理 event monitor、notification observer、child window 和延迟关闭任务。模型仍是颜色写回与展开状态的唯一 owner；iOS/iPadOS 的 scene-owned SwiftUI popover 与 30→44 pt 等比 Core 路径不变。
- 任务、分类、Checklist 和 Pomodoro 计划继续只通过共享 `SymbolColorWell` 获得该行为；应用不新增第三方依赖。BlossomColorPicker 仍是用户明确指定且经 AD-117 审查的低 star 例外，不能据此放宽 AD-011 的一般依赖门禁。

后果：macOS 花瓣从实际被点按的颜色 well 中心展开，不再因嵌套 popover 与 key window 的坐标空间不同而漂移；屏幕边缘仍能完整显示。应用承担一层很薄的 AppKit presentation lifecycle，但不维护颜色算法或视觉几何。未来升级上游时，若其 presenter 接受真实 owner/anchor 且通过相同回归，可删除本适配层。

验证：先失败的 macOS XCUITest 记录 well 中心与 Blossom 中心相距 75 pt；修复后用新建的 180...210 pt 方形窗口定位实际 194 pt Blossom，并断言普通位置中心距离不超过 4 pt。最终结果包 1/1 通过且 `runtimeWarnings` 为空，正常字号全屏截图确认 SF Symbols popover 与花瓣层级无漂移；现有 iPhone 与 iPad 图标/颜色选择 UI 回归各 1/1 通过。完整签名单元、格式、本地化、构建与全设备安装仍是任务关闭门禁。

## AD-136：macOS 菜单快捷键是设备本地应用内偏好

状态：Accepted

背景：macOS 的常用时间管理动作需要可发现、可录制且即时更新的菜单快捷键。只用 SwiftUI 可以绑定已知组合，却没有可靠的键码录制、菜单/系统冲突校验和键盘布局转换；自行复制这些能力会形成第二套脆弱实现。另一方面，成熟库的命名模式注册全局 hotkey，并固定写入 `UserDefaults.standard`，不符合本应用只在前台响应、使用隔离 `AppDefaults`、可测试原子写入的要求。主应用 target 同时进入 macOS 与 iOS 构建图，也不能让 macOS-only 包污染 iOS 链接。

决策：

- 使用精确锁定的 Sindre Sorhus `KeyboardShortcuts 3.0.1`（revision `49c3fc04ea827f816df67843bfcc57286b47ff06`、MIT、审计时约 2.7k stars）提供 binding recorder、键码转换、本地化和菜单/系统/不可用组合冲突策略；不得在应用内重写录制器或键码表。
- 远程包经本地 `MacKeyboardShortcuts` Swift Package 的 `.when(platforms: [.macOS])` 条件适配进入共享 Xcode target。适配层只 re-export 库，不拥有行为或视觉实现。
- 触发继续由原生 SwiftUI `Commands` / `keyboardShortcut` 负责，因此只在 Time Tracker 为当前应用时响应，菜单始终展示当前组合。应用根持有一个 `MacKeyboardShortcutSettings`，同一实例注入主场景、Settings 场景和 Commands；修改发布 revision，使相关菜单项无需重启即可重建。
- 只开放添加时间、开始所选任务、开始番茄钟和刷新数据。`Command-N`、`Command-,`、`Command-1...5` 依照平台惯例保持固定；库判定的菜单冲突、系统冲突和不可用组合全部阻止。应用命令边界还拒绝动作间重复、固定组合和无修饰普通键，功能键可以单独使用。
- 自定义属于设备与键盘布局偏好，不进入 `TimeTrackerStore`、SwiftData、CloudKit 或同步导出。`MacKeyboardShortcutPreferenceCommand` 只通过 `AppDefaults.shared` 写一个 4 KiB 上限的原子 Codable blob；缺少动作继承默认，`disabled` 是显式清空，`custom` 是覆盖。损坏、超限、未知 schema、不可表示、重复或保留组合在读取时整体回退默认且不回写。
- 不使用库的 `KeyboardShortcuts.Name` / global hotkey 存储路径；Settings 必须使用 binding recorder，持久化和 durable validation 仍属于应用命令边界。

后果：用户获得符合 macOS 菜单习惯的即时自定义能力，同时不会在后台抢占系统按键，也不会把一台 Mac 的物理键盘选择同步到其它设备。应用维护少量动作策略和原子 payload，但录制、键码与底层冲突识别由成熟库承担。新增快捷动作必须同时定义默认/保留策略、菜单可用条件、三语文案和命令边界测试，不能把标准菜单快捷键改作可配置动作。

验证：行为测试覆盖四项默认、跨实例覆盖、显式清空、自定义覆盖、重置、损坏/超限回退、重复、固定组合和无修饰普通键拒绝。macOS UI 自动化在普通字号下确认四个原生 recorder、默认组合和默认态禁用的重置按钮，保存 Settings 与带快捷键的 File 菜单截图，并实际按下 `Shift-Command-M` 触发 focused-scene 的添加时间动作。iOS 签名构建证明条件依赖没有进入非 macOS 产品。完整 `make test`、格式、本地化和 `make build-install-all` 仍是任务关闭门禁。

## AD-137：提交后同步保护与系统表面按 persistent history 异步收敛

状态：Accepted

替代关系：本决策替代 AD-004 中由 mutation 调用方直接刷新 sync snapshot/Widget/Watch/Live Activity 的编排、AD-020 中 `Configuration` 装配 repository-only 系统表面的具体所有权、AD-098 中“App Intent 提交后创建新 context 做 snapshot/system projection”、AD-103 中“System Action 同步记录 snapshot/更新系统表面后再广播”、AD-109 中“普通 Scene 在 snapshot recording 后才广播且系统表面依赖各自同步 post-commit path”，以及 AD-111 中“普通 mutation/Watch 调用方直接消费锁内 prompt 或把后续 prompt 读取失败报告为 post-commit refresh failure”的条款。上述决策的共享命令/稳定 DTO/传输上限、职责拆分、store-scoped writer、exact events、兄弟 Scene 只读收敛、无副作用循环和 conflict ID/CAS 要求继续有效。本决策不替代 AD-018、AD-074、AD-076、AD-081 或 AD-094；尤其 AD-094 的 destructive reset 前最终保护快照与同一外层 store lock 保证完整保留。

背景：sync recovery snapshot、Widget App Group 写入、WatchConnectivity payload 与 Live Activity reconciliation 都曾串在 durable commit 之后。大型 store、跨进程状态锁或系统框架延迟会延长 Scene、Shortcuts 与 Watch 命令返回；任一表面失败还会共享错误槽位，混淆“业务事实已保存”和“只读投影尚未收敛”。仅把工作包进非结构化 Task 又没有跨进程 frontier、reset fence 或 per-sink acknowledgement，进程退出和 store replacement 后无法证明哪些效果已完成。

决策：

- 每个持久 SwiftData outer save 明确写稳定 history author：普通 Scene/fresh coordinator 为 `localMutation`，sync restore 为 `syncReconciliation`，migration/seed 为 `bootstrapMaintenance`；未知或缺失 author 不能推断成本机 mutation。Scene、App Intent 与 Watch 把同一 command outcome 的 exact `StoreDomainEvent` 和可选 forced sink 作为一个 receipt 交给物理 `TimerStoreScope` 共享的 `CommittedMutationSystemProjectionScheduler`。Scene 只等待自身必要 read-model refresh；App Intent 与 Watch 在 durable result 后返回，不等待 projection。
- scheduler 维护 sync snapshot、Widget、Watch、Live Activity 四条独立 lane。`PersistentHistoryProjectionDriver` 用短生命周期 `@ModelActor` 分页读取 chronological history，先固定 tail，再在 effect 成功后对该 lane 的 opaque token 做单调确认；四条 cursor、full-reconciliation attempt、store UUID 与 reset epoch 各自耐久化。sync lane 只响应 `localMutation` 领域，三个系统表面消费所有相关 author；未知实体提升为 `.fullSync`。lane 不删除共享 history，单 lane 失败不确认、不阻塞 sibling，也不写共享 `errorMessage`。
- 三个系统表面每 generation 由 fresh background materializer 读取一次 committed facts 并复用不可变 DTO；Widget App Group 写入在专用 actor 串行，框架 publication 才回到所需 actor。reset epoch 在 driver begin/ack 重验，container revision 在物化、缓存、框架调用前后与确认处检查；观察到 replacement 时丢弃旧 DTO，但框架调用与并发 replacement 不是一个原子事务。替换前开始的工作可完成，硬保证是不能为 replacement store 确认旧 frontier。pending receipt/events 有界合并，超限安全降级 `.fullSync`。
- forced current-state 是指定系统表面的请求，不伪造 `.fullSync`；effect 成功后可以确认已经真实扫描的 frontier，包括对该 sink 无关的 transaction。iPhone `handleWatchCommand` 产生的每个 outcome 都强制 Watch：真实 mutation 在同一 receipt 携带实际 events；duplicate/missing/invalid/failed 等无 mutation结果使用空 events，只刷新 Watch。Watch 本机 20 秒 timeout 不经过 iPhone scheduler。启动额外 force Watch，弥补进程退出打断的 forced-only publication。
- 启动、前台与 remote import 在 read-model refresh 后 enqueue history-backed catch-up；它们不重复 suggestion 或发送 Scene 的副作用。进程内 `StoreMutationBroadcaster` 仍只让兄弟 Scene 下一 MainActor turn 读取收敛。
- sync lane 成功后发布 prompt-change notification。Scene 通过单一 serialized reader、single-flight 加一次 trailing refresh、有界退避和 latest-request-wins 异步更新；失败保留最后已知 prompt，前台重读，显式 resolution 广播 sibling clear。prompt I/O 不改变 Watch/App Intent 终态。
- Cloud enablement 的本机赢家 staging、显式 conflict/recovery/force upload/import、AD-094 destructive reset 前最终保护，以及 Settings 的手动 Live Activity Retry 仍是明确同步安全/人工重试边界；不得为追求“全异步”削弱它们。

后果：提交调用方不再等待四类投影 I/O，失败按 lane 隔离并可由后续提交、启动、前台或 remote import 恢复；persistent history、幂等 snapshot postcondition、cursor CAS、epoch/container fence 共同提供 at-least-once 收敛而不伪造业务失败。forced-only Watch request 是进程内调度状态，不得描述成持久业务 transaction；跨进程恢复承诺来自 history frontier/interrupted full attempt，Watch 无 history 的终态由下次 App 启动明确 force current state。应用增加少量最多 64 KiB、排除备份的本机 cursor/attempt metadata，但不改变 SwiftData/CloudKit schema、Widget/Watch/Live Activity wire payload、用户可见设计或 Privacy Manifest API 声明。实现只使用 SwiftData persistent history、Structured Concurrency、Foundation、WidgetKit、WatchConnectivity、ActivityKit 与现有 `DurableLocalFile`，不新增第三方依赖。

验证：行为测试覆盖 author provenance、真实 opaque token/过期恢复、四 lane 独立 ack/failure/retry、同 receipt/coalescing/有界 backlog、forced-current-state、container/reset fence、单次后台物化、MainActor heartbeat、sync snapshot 幂等重放、Scene/App Intent/Watch 调用方、启动/前台/import catch-up，以及 prompt 乱序/失败/兄弟 Scene。完整签名单元、性能预算、格式、本地化、全设备 Release 安装与资源清理仍是任务关闭门禁；本次没有视觉、文案或 DTO 变化，截图不能验证异步时序与恢复语义。

## AD-138：macOS 可配置快捷键覆盖稳定的主要操作

状态：Accepted

替代关系：本决策替代 AD-136 中“只开放四项动作”、`Command-1...5` 固定不参与配置，以及验收只覆盖四个 recorder 的条款。AD-136 的设备本地存储、成熟录制库、应用前台菜单触发、原子 payload、冲突策略和标准 `Command-N` / `Command-,` 约束继续有效。

背景：四个可配置动作只覆盖手动补录、两种开始计时和刷新，用户仍需频繁在菜单、侧边栏和任务行之间移动。macOS 菜单应让稳定的主要命令可发现并可按个人工作流分配，但不应为低频或依赖选择的动作擅自抢占系统组合，也不能让删除、停止全部计时或数据重置获得容易误触的全局入口。

决策：

- `MacKeyboardShortcutAction` 是唯一稳定注册表，按创建、计时、整理、导航和数据五组覆盖 16 项：手动补录、选择任务开始、开始/停止所选任务、添加子任务、开始番茄钟、归档所选任务、新建/排序分类、生成 AI 任务计划、五个主目的地和刷新数据。
- 高频既有组合保留为默认：`Shift-Command-M/S/P`、`Command-1...5` 和 `Command-R`。选择任务开始、停止、添加子任务、归档、分类管理和 AI 计划默认 `nil`，但始终出现在 Settings recorder 与原生菜单；用户可以录制、清空或恢复默认。
- `Command-N` 与 `Command-,` 继续是不可改写的标准命令。删除、停止全部计时、重置数据等 destructive 动作，以及只属于局部控件的筛选/编辑键盘行为不进入注册表。
- 所有菜单动作复用既有 store 或 scene presentation router 边界；需要任务选择、活动 segment、可归档子树或空闲 presentation host 的动作在前置条件不满足时置灰，不隐藏也不猜测目标。
- 读取与写入共享同一语义 assignment validation，拒绝不可转换、无修饰普通键、标准保留、系统占用或动作间重复的组合；无默认动作清空后不写冗余 disabled override。

后果：用户可以为大部分稳定 Mac 工作流自行建立键盘路径，同时默认安装不会新增低频按键占用或扩大 destructive 操作面。菜单与设置增加动作数量和分组维护成本；任何新增动作必须同时定义分组、默认/排除理由、菜单可用条件、三语文案、命令边界测试和普通字号 UI 验收。实现继续使用锁定的 `KeyboardShortcuts 3.0.1`，不新增依赖或自制录制器。

验证：表驱动行为测试验证 16 项注册表、五组完整性、默认唯一性、default-nil 的分配/清空、损坏与语义非法 payload 只读回退、重复/保留拒绝和 revision 稳定。macOS XCUITest 在真实 Settings scene 中确认 16 个 recorder 与默认组合，验证默认 Add Time 组合触发同一 focused-scene 动作、Task 菜单持续暴露九个主要动作，并保存分组设置与展开菜单截图。完整签名单元、格式、本地化和全设备 Release 安装仍是任务关闭门禁。

## AD-139：主界面按窗口宽度选择共享 shell，平台分支只封装真实能力

状态：Accepted

替代关系：本决策完整替代 AD-049 的设备 idiom 根导航规则；其它关于 durable write、scene-owned presentation、系统表面和输入方式的决策继续有效。

背景：设备身份不能可靠描述窗口可用空间。iPad 分屏与 Stage Manager 会产生手机级宽度，macOS 窗口也可以收窄；反过来，按 `os(...)` 分叉相同内容的字号和布局会让共享界面逐步漂移。仓库曾删除设备 idiom 读取并建立宽度 shell，但绑定决策和平台字体映射没有同步收口，后续实现仍可能把产品语义误写成平台差异。

决策：

- `AppRootView` 是根 shell 的唯一选择者。`RootLayoutPolicy` 以实际测得的窗口宽度和系统 compact size class 选择 compact 或 regular：低于 720 pt 或系统明确 compact 时使用单列 `TabView` shell，其余使用共享的 `NavigationSplitView` shell。
- 业务 Store、scene presentation/feedback router 和 durable navigation identity 位于 shell 分支之上。子视图只消费根发布的 `layoutShell` 或自己的有限容器宽度；不得读取 `UIDevice.current.userInterfaceIdiom`、`UIScreen`/`NSScreen` 来决定产品布局，也不得用平台编译条件复制同一页面。
- `#if os(...)` 只用于目标上不存在的框架/API、原生 scene/menu/window plumbing、系统 presentation/list chrome、键盘与指针/触控输入差异、HealthKit/Watch/ActivityKit 等真实 capability。平台分支不得只为同一用户信息选择不同字号、间距、卡片或内容顺序。
- 用户身份、答案、说明、状态、警告与有文字的操作使用同一跨平台系统语义字体；path、timestamp、badge、count、chart axis/range 等 metadata 也按信息角色共享紧凑语义。需要不同密度时由 compact/regular shell、容器宽度或明确的组件 style 决定，而不是操作系统名称。
- 新增平台 UI 分支必须在当前工程文档说明 capability 理由和验证表面；若共享 SwiftUI、宽度策略或系统容器能表达同一行为，则删除分支。

后果：iPhone、iPad 分屏和窄 Mac 窗口在相同宽度下获得相同的信息架构；宽 iPad 与宽 Mac 共享 sidebar/detail shell。真正的平台能力仍保持原生，触控目标与指针控件可按输入方式不同。字体和内容语义不再因为 target 漂移，平台条件编译的审查范围也更明确。

验证：`RootLayoutPolicy` 行为测试覆盖 compact size class、719/720 pt 边界和首次测量；`AdaptiveShellUITests` 从可见 Tab Bar/Sidebar 判断实际 shell，并在普通字号的紧凑/常规宽度保存截图。代码审查逐项分类生产 UI 的平台分支，确认没有设备/屏幕身份布局读取；格式、本地化、完整签名测试和全设备安装仍是关闭门禁。

## AD-141：活动文档只保存当前规则，完成证据归档到 Git 历史

状态：Accepted

替代关系：本决策替代 AD-009 允许新建 dated Audit 的条款，并统一替代旧决策验证段落中“写入 dated Audit”的流程要求；那些段落仍是历史事实，不再授权创建新的审计快照。

背景：一次性审计、实现记忆和当前工程规则长期并列后，活动文档数量膨胀，旧命令与已完成状态也容易重新被当作当前约束。

决策：当前行为和所有权只写入 UserGuide、CodeGuide、Architecture、ProjectMap、Testing、PrivacyAndSecurity 等当前文档。一次性发现与验证证据写入交付该工作的 commit/PR；跨多会话的较大任务可以在 `Docs/ImplementationContexts/` 保存进行中的实现记忆，完成后随收口清理，不再维护 Archive 目录（历史由 git 承载）。AgentDecisions 只接收跨领域架构、数据安全、兼容性或系统集成决策；单一 UI/Analytics 展示细节写入对应当前功能文档。

后果：不得新建长期生效的 dated Audit。归档内容保留历史可追溯性，但不能充当当前指令、待办或已验证声明。

验证：活动文档链接与状态检查不再发现完成中的 memory、过期 Audit 入口或相互冲突的 Makefile/测试规则；一次性执行证据可从对应 Git 提交追溯。

## AD-142：提交后投影按显式来源重放当前事实

状态：Accepted

替代关系：本决策完整替代 AD-137 的 persistent-history lane、cursor、attempt、reset epoch、store UUID 与 CAS 协议。AD-137 关于 durable command 不等待投影、四个 sink 独立失败、同 generation 共享 DTO、forced Watch、prompt-change 通知及系统框架边界的要求继续有效。

背景：四套持久 history frontier 只用于跳过重复的当前状态发布，却引入 driver、分页 history reader、sidecar cursor/attempt、reset fence、跨进程 CAS 和两套事件筛选。实际投影仍会从 SwiftData 全量读取当前事实；App Intent 和扩展也不运行这些 lane。保留这套增量确认协议无法减少物化成本，却让一次 Widget/Watch/Live Activity 收敛依赖约 1,500 行恢复元数据代码。

决策：

- `CommittedMutationSystemProjectionRequest` 必须携带显式来源：`.localCommit`、`.startupCatchUp` 或 `.surfaceCatchUp`。只有 local commit 与 startup catch-up 可以记录 sync recovery snapshot；Cloud remote import、前台/冲突解决后的 surface catch-up 和 forced-only Watch 不得被推断成本机 mutation。
- scheduler 继续按 sink 过滤 exact events、合并 generation、隔离失败并在下一次相关 generation 重试。三个系统表面每 generation 共享一次 fresh-context 当前事实物化；sync snapshot 使用原始事件独立记录。durable mutation、App Intent 与 Watch 终态都不等待这些 I/O。
- 启动固定发送 `.startupCatchUp + .fullSync`，以一次幂等完整 snapshot 和全部系统表面重投影关闭“commit 已保存、进程在投影前退出”的窗口。前台、remote import、显式 sync resolution 只重投影系统表面；它们不会制造本地同步代次。
- registry 仍按物理 `TimerStoreScope` 共享 scheduler，并在 container 替换时清空旧 materialization。框架发布前后各验证一次 container revision；不再维护与 physical store reset 并行的 history reset fence。
- 删除 `PersistentHistoryProjectionDriver`、`PersistentHistoryLaneCursorStore`、`PersistentHistoryProjectionImpact` 及其 cursor/attempt/fence 测试。旧 sidecar 不再读取；以后若发生显式 store reset，会随既有 store-prefix 清理被移除，不增加一次性迁移。

后果：投影恢复承诺变成简单的“每次相关 commit 重放、启动完整补偿”，不再声称逐 transaction 持久确认。最坏情况是重复发布幂等 DTO；单用户应用可以接受这一成本。history author 仍用于写入来源和其它同步安全边界，但不再驱动系统表面。SwiftData/CloudKit schema、snapshot/Widget/Watch/Live Activity DTO 和用户可见行为不变。

验证：行为测试冻结三种来源到四个 sink 的映射、forced-only Watch、sync exact events、单 generation 单次物化和失败后的下一相关 generation 重试；Cloud recovery 测试继续证明 store 文件在共享 mutation lock 内删除。完整签名单元、iOS/macOS 构建、格式与本地化通过后才能提交。

## 2. Agent 工作清单

工作流、验证门禁、签名规则与模拟器/进程资源清理的权威出处是 [AGENTS.md](../AGENTS.md) 与 [Testing](Testing.md)；本节不再重复维护一份清单。

## 3. 相关文档

- [代码文档](CodeGuide.md)
- [隐私与安全](PrivacyAndSecurity.md)
- [已替代决策归档](AgentDecisionsArchive.md)
- [版本与迁移](Versioning.md)
