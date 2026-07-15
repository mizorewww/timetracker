# TimeTracker Agent 决策文档

状态：有效决策记录
最近更新：2026-07-15

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

决策：API key 存入 LLMCredentialStore，使用 AfterFirstUnlockThisDeviceOnly 且关闭 Keychain 同步。同步和导出过滤敏感键；遗留明文只用于一次迁移，随后清除或软删除。

后果：密钥不会跨设备同步，每台设备需单独配置。不得把秘密写入日志、测试 fixture 或诊断导出。“清空全部数据”同时清除本机密钥和设备本地的自动建议同意；若 SwiftData 清理失败，外部存储值需尽力补偿恢复并报告补偿失败。

验证：测试 Keychain round-trip、遗留值迁移、敏感键过滤、导出不含 secret，以及清空全部数据在成功/SwiftData 失败时的清除与补偿恢复。

## AD-006：JSON 导出不是备份

状态：Accepted

背景：当前设置页只有 JSON fileExporter，没有对应 fileImporter、版本预检、校验和或事务回滚。

决策：产品和文档只称其为数据导出或快照，不称为可恢复备份。

后果：若未来使用“备份”一词，必须先实现带格式版本、校验和、导入预检、冲突策略、staging/回滚和恢复等价性测试的 importer。

验证：用户文案无误导；恢复测试能从旧版本 fixture 重建等价业务事实。

## AD-007：Breaking schema 的批准与保留政策

状态：Accepted

背景：项目允许在开发阶段进行破坏性 schema 变更，但“breaking”不能成为静默丢失用户数据的许可。

决策：

- TaskNode、TimeSession、TimeSegment、PomodoroRun、InboxItem、ChecklistItem、TaskCategory 和用户可见设置默认必须保留。
- 派生缓存可在版本说明明确后重建。
- secrets 必须排除于 schema 导出和同步之外。
- 任何经批准的数据丢弃必须写明范围、理由、用户提示、备份/恢复要求和回滚边界。
- 迁移必须考虑幂等性、多设备版本偏差、CloudKit 状态和旧 store fixture。
- 无法安全迁移时，停止升级并显示可操作错误；不得静默创建空库替代。

后果：Breaking 迁移需要单独审核。发布说明必须说明不可逆边界，且至少保留一条经过验证的恢复路径。

验证：真实旧版本 store 迁移测试、重复启动测试、版本偏差测试以及迁移前后核心事实计数/身份校验。

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

状态：Accepted

背景：旧 iPhone 自绘六目的地 chrome、卡片式 Today、任务详情内联大编辑器和 Pomodoro 隐藏点击选择造成层级混乱、可发现性弱和不必要的维护成本。

决策：

- iPhone 使用五个系统 `Tab`；Settings 从 Today 工具栏进入。
- iPad regular width 和 macOS 使用 `NavigationSplitView`；iPad compact width 使用与 iPhone一致的五标签根导航。macOS 使用单实例主 `Window`；独立 Settings 场景与主窗口共享一个应用级 store。
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

状态：Accepted

背景：Today、Task、Settings 和 Analytics 的旧横向行同时承载图标、标题、路径、数值与操作。在 Accessibility Extra Large 等字号下，单纯放大字体会造成标题截断、计时按钮碰撞和底部内容被 tab bar 遮挡。

决策：触控平台必须支持完整 Dynamic Type 范围。`dynamicTypeSize.isAccessibilitySize` 时，信息密集的横向行改用纵向或分组布局；segmented picker 在空间不足时改为菜单；scroll content 为系统 tab bar/底部控件保留可滚动余量。可见标题、路径、状态和错误优先完整生长。仅装饰性、已从 accessibility tree 隐藏的图标可以保持稳定视觉尺寸；不得通过固定正文大小、缩放整行或永久单行截断来“通过”截图。

后果：同一组件允许普通字号和辅助功能字号使用不同 composition，但必须共享动作、语义、稳定 identity 与数据来源。新增水平密集行必须同时设计 accessibility-size 结构。

验证：至少覆盖 iPhone 深色 Accessibility Extra Large 的 Today、Tasks、Task Detail、Analytics 和 Settings，以及 iPad 宽屏；检查文本无重叠、主操作可见、列表最后一项可滚到 tab bar 上方，并运行相关 UI contract。

## AD-020：大规模拆分按职责固化，不复活退役聚合文件

状态：Accepted

背景：Analytics、Settings、Task Detail、ledger infrastructure 和 SyncConflict 曾由少数大文件混合路由、展示、算法、同步状态与 DTO。大文件让 UI 修改触及同步/安全代码，也让代码审核难以界定行为边界。

决策：保持以下当前所有权：Analytics 的 landing page 与 typed category-detail destination 分文件，period/detail-list 与 store metrics/breakdown/overlap/task-snapshot 文件继续聚焦；Pomodoro setup 由 composition、empty state、focus controls、Plan/Task selection 和 timer face 文件分担；Settings 使用 display/timing、Pomodoro、countdown、sync、data、actions、bindings 和 support 文件，共享 rows 另按 foundation/value、action/destructive、input、presentation 和 sync-feedback 分文件；Task Detail 使用 canonical router 加 identity/checklist/overview/analytics/navigation/record sections；ledger 使用 Cloud startup、persistence safety、timer DTO、aggregation、formatting、device identity 和 summary 文件；SyncConflict 使用 bootstrap/prompt、local mutation、Cloud import/export、recovery/resolution、state persistence/lock/locations、snapshot capture/分域 restore 和分域 record DTO 文件；Widget 使用 entry/provider/config、active layout、supplementary state 与 support 文件；Watch 使用 dashboard/timer/status/color UI 文件，并由 `WatchAppStore` 单独拥有 queue/connectivity state；facade 的 `Configuration` 负责首次配置/repository-only 系统表面装配，`Lifecycle` 负责 refresh/mutation/recovery/error。不得重新创建 `SettingsSectionsViews.swift` 或 `TimeTrackerServices.swift` 作为杂项聚合点，也不得让 closed-app post-commit 路径启动 migration、demo seed、observer 或自动 LLM 工作。

后果：文件移动必须保持一个权威领域规则，不能因“拆分”复制 LWW、时间聚合、恢复或 UI action。拆分后的 sync 继续作为语义高风险域接受完整行为测试；仍较集中的 Watch connectivity store、Home 和 row 文件按 [CodeRefactorPlan](CodeRefactorPlan.md) 的真实现状继续治理。

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

决策：所有 state read-modify-write 在一个递归进程锁和 POSIX `lockf` advisory file lock 内完成，形成跨进程 compare-and-swap 等价边界；JSON 使用原子替换，forced-upload mirror 服从权威 state。权威 state 限 128 MiB，recovery mirror 限 64 MiB；读取先做 metadata 大小预检，再用 `FileHandle` 最多读 `limit + 1`，以识别预检后文件增长的 TOCTOU。损坏或超限的权威 state 进入显式隔离恢复；损坏或超限的 pending mirror 被隔离并忽略，不能阻塞主库；超限文件通过 move 隔离，不整份载入内存。iOS 权威状态、pending forced-upload 恢复镜像和腐损隔离文件设置 `FileProtectionType.completeUntilFirstUserAuthentication`：本次启动首次解锁前不可读，解锁后允许后台 Shortcuts/CloudKit 使用。local mutation 推进 generation，import/恢复推进 epoch；export start 按 event ID 记录 epoch/generation/fingerprint，finish 只能确认同 epoch 且不早于已确认 generation 的 checkpoint。旧 state 清理被排除偏好时必须重算 fingerprint 并作废旧 payload checkpoints。checkpoint 限 16 个、24 小时。Snapshot restore 在建 three-way dictionary 前确定性去重重复 UUID，并规范化 Pomodoro duration/round 范围，不能让历史或损坏 transport 触发运行时 trap 或非法领域状态。

后果：禁止在锁外 load→mutate→save，禁止用任意成功 export 清除最新 pending winner，也禁止为每个 event 复制完整用户 snapshot。

验证：同进程并发互斥、外部进程 `lockf`、两个 service 实例无 lost update、乱序完成、失败完成、过期/上限 pruning、旧 preference scrub checkpoint invalidation、损坏 mirror 隔离、forced-upload ack、重复 UUID restore、Pomodoro 范围规范化、128 MiB/64 MiB 稀疏超限文件的拒绝/隔离，以及 iOS 三类敏感文件的最终 protection attribute 测试。

## AD-024：Pomodoro 由持久 phase 状态派生 deadline，并与账本生命周期一致

状态：Accepted

背景：View-owned countdown 在后台挂起、重启或跨入口编辑后会漂移；删除活动 segment/task 可能留下仍在运行的 `PomodoroRun`。

决策：当前 phase 起点持久化在 `PomodoroRun.startedAt`，deadline 由状态和计划时长派生。启动、前台、页面出现与 scheduled task 幂等 reconcile 过期 focus，并把 segment/session 截在 deadline；break 不在后台擅自创建下一段 focus。通用 segment edit/delete、timer stop 和 task-tree delete 必须在同一原子动作中同步完成/取消/tombstone 对应 run，并保留有效历史。

后果：UI 只显示 deadline 派生的剩余时间。不能用 `Date()` 结束一个早已到期的 focus，也不能让 run 脱离 ledger 独自存在。

验证：后台/启动 reconciliation、deadline clipping、重复 reconcile、active segment edit/delete、过期删除、任务树含 timer/Pomodoro 与 break-state 删除测试。

## AD-025：增量 ledger/checklist/rollup 与 90 日 pace

状态：Accepted

背景：一次 segment 或 checklist mutation 若重新 fetch、过滤、排序和聚合完整历史，会随数据增长拖慢所有界面；历史 pace 若无窗口会不断增长。

决策：Ledger 维护 ID/day/active/session indexes 并只替换相交范围；Checklist 只替换 affected task buckets；Rollup 消费 `LedgerSegmentChange`、scoped checklist 和 task/ancestor IDs。完整历史 worked seconds 必须精确。Pace 只保留包含今天的最近 90 个本地日，对有记录的活跃日求平均，只用于把已有 remaining seconds 换算为预计活跃日。

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

决策：配置 sheet 使用独立 draft；Test 只校验 credential fingerprint 并加载模型，不保存；选择有效模型后用户明确 Save 才写 endpoint/model 与 device-only Keychain。endpoint、模型列表和已选模型由一个批量 preference command 做一次 SwiftData 提交；Keychain 不是该 transaction 的一部分，提交失败时尽力恢复旧密钥并准确报告补偿失败。修改凭证会取消旧请求和旧测试结果。自动建议是默认关闭、设备本地的第二个明确开关，不参与 CloudKit/JSON。

后果：不得把补偿式一致性写成跨存储原子性；失败必须逐项报告。发行前必须确认实际 endpoint 服务方、发送字段、用途、保留期和删除渠道；兼容协议不代表零保留。

验证：draft normalization、stale test cancellation、save enablement、一次 preference batch save、Keychain 补偿恢复、discard confirmation、Keychain migration/filtering、automatic-consent default 和网络边界测试。

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

决策：当前 schema 为 V9，版本标识 `1.8.0`。V8→V9 使用 lightweight migration 从当前 registry 移除 `DailySummary`，保留任务、时间账本、Pomodoro、checklist、Inbox、分类、倒计时与偏好等用户事实。Legacy `DailySummary` 类型只保留在 V1...V8 schema 历史中，使旧 store 可被迁移计划读取；当前 Analytics 只创建可丢弃、可重建的 `DailySummarySnapshot`。

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
3. 检查本地化、可访问性、隐私、迁移和同步。
4. 更新对应文档和决策。
5. 使用模拟器后关闭本次启动的设备并确认没有遗留 runner/trace 进程。
6. 报告仍为红色的测试与未验证环境，不宣称未获得的通过状态。

## 3. 相关文档

- [代码文档](CodeGuide.md)
- [隐私与安全](PrivacyAndSecurity.md)
- [2026-07-14 审核](Audit-2026-07-14.md)
- [版本与迁移](Versioning.md)
