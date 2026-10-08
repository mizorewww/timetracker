# TimeTracker Agent 决策文档

状态：有效决策记录
最近更新：2026-10-08

本文件只收录跨领域架构、数据安全、兼容性或系统集成的**长期不变量**；每条给出一条规则和一条边界。单一功能内的 UI/展示细节写入对应功能文档或由行为测试表达；一次性验证证据写入交付该工作的 commit/PR；历史与已替代决策由 git 历史承载。

未列出的细节以代码和 [Architecture](Architecture.md)、[CodeGuide](CodeGuide.md)、[Testing](Testing.md) 为准。下文“合并原 AD-xxx”只说明来源，那些条目不再单独生效。

## 数据与协议

**AD-001：TimeSegment 是时间事实来源。**
- 规则：已发生的计时事实由 `TimeSegment` 表达；统计与展示只能从 canonical segment 及明确领域规则派生，缓存只能加速。
- 边界：用户可以更正或软删除错误记录，所以“事实来源”不等于 append-only。并行计时是合法状态：gross 为片段之和，wall 为区间并集，overlap 为 `gross - wall`。

**AD-002：持久写入经过 domain command 与 repository，并使用原子 mutation 边界（合并原 AD-018）。**
- 规则：View、App Intent、Watch 和维护工具不得各自直接操作 SwiftData；一个用户动作由 `ModelContext.performAtomicMutation` 定义 unit of work，嵌套步骤延迟到外层统一保存，动作或最终保存失败时整体 rollback。
- 边界：提交后的 refresh、snapshot 与系统表面投影单独报告，不改变 mutation 的成功结果；Keychain 等无法参与 SwiftData rollback 的 side effect 必须补偿并单独报告补偿失败。

**AD-003：本地优先 CloudKit，禁止静默伪装持久化成功；演示数据显式启用并与用户 store 隔离（合并原 AD-022）。**
- 规则：正常模式使用持久容器并可启用 CloudKit；fallback 必须显式记录和显示诊断状态，紧急内存存储不能被称为已保存。
- 边界：iCloud enablement 是设备本地 `UserDefaults` 启动配置，修改后下次启动生效，不进入 `SyncedPreference`、冲突快照或导出。`TIMETRACKER_AUTOMATIC_DEMO_DATA_MODE` 在 Debug/Release 默认均为 `off`；demo 使用无 CloudKit 的独立 store，UI test 使用独立内存 container。

**AD-004：系统表面共享领域命令、稳定 DTO 与有界快照。**
- 规则：App Intents、Live Activity、Widget 和 Watch 只做投影或入口；复用模型容器、用户偏好与原子 mutation，提交后只用窄依赖刷新，投影失败不得把已提交动作报告为失败。Live Activity/Widget 不保存唯一事实。
- 边界：Widget/Watch producer 按 Unicode 边界裁剪文本并共用 128 KiB 文本预算，不回写 canonical facts；Widget 快照 JSON 256 KiB、active/recent 各 64 项，Watch state 最多 64 active/256 recent，Watch 命令队列各 64 项、编码 512 KiB，非法读取是 corrupted 而非 empty。Widget 真机共享容器与 timeline 验证通过前不列为已完成发行能力；数值上限的准确清单见 [Architecture](Architecture.md) 与 `WidgetSnapshotLimits`/`WatchTransportLimits`。

**AD-005：API 密钥与秘密只保存在本机 Keychain，导出不是备份（合并原 AD-006）。**
- 规则：API key 存入 `LLMCredentialStore`，AfterFirstUnlockThisDeviceOnly 且关闭 Keychain 同步；同步与 JSON 导出过滤敏感键，遗留明文只用于一次迁移后清除或软删除。“清空全部数据”同时清除本机密钥与设备本地自动建议同意，清理失败时尽力补偿恢复并报告。
- 边界：导出（`timetracker.cloudSyncedData`）必须 fail closed：读取或编码失败时明确返回失败并阻止 `fileExporter` 呈现，不得用 `{}`、空数组或缓存内容伪装成功。产品和文档只称其为“导出/快照”，不称为可恢复备份。

**AD-007：Breaking schema 变更必须保留用户事实并保留旧 store 兼容层（合并原 AD-030）。**
- 规则：TaskNode、TimeSession、TimeSegment、PomodoroRun、InboxItem、ChecklistItem、TaskCategory 与用户可见设置默认必须保留；派生缓存只在版本说明明确后才可移除。
- 边界：每个新 schema 版本保留历史模型形状，旧版本把改动的模型解析回冻结快照类型；无法安全迁移时停止升级并显示可操作错误，不得静默创建空库。V9→V14 的移除/新增历史见 [Architecture](Architecture.md)。

**AD-013：Observation 与事件驱动刷新。**
- 规则：`TimeTrackerStore` 使用 `@MainActor @Observable`，根视图以 `@State` 持有、子视图按引用读取、需要 Binding 时局部 `@Bindable`；CloudKit 由 remote-store 与 import/export 通知驱动，短暂合并后走 refresh planner。
- 边界：不得重新引入 `ObservableObject/@Published` 或常驻轮询；计时 label 用局部 `TimelineView`，不得通过 facade 高频 publish 驱动全树。

**AD-014：确定性的 LWW 与 tombstone 语义（合并原 AD-065）。**
- 规则：先按 last-write-wins 选 winner，再过滤 tombstone；比较顺序为 `updatedAt`、同时间 tombstone 优先、`createdAt`，最后以 `deviceID`、`clientMutationID` 或 TimeSegment 稳定内容键打破平局；层级顺序同规则。
- 边界：任何可见查询不得在 LWW 之前过滤删除值；duplicate cleanup 的 tombstone 不得覆盖较新的 canonical row。普通 Local、iCloud、fallback 与 emergency 生产 store 永不物理 purge tombstone；只有隔离的 Demo/UI Test store 可清理过期 tombstone graph。

**AD-038：Inbox 建议驳回绑定不透明逻辑修订与读模型（合并原 AD-064、AD-087、AD-107）。**
- 规则：每个 Inbox item 保存不透明随机 `suggestionContextID` 与标题轮换的 `suggestionRevisionID`，dismissal 只对精确 `(context, revision)` 做字段级 OR，不跨 revision；内容字段走 LWW，dismissal 不参与内容 winner。
- 边界：普通 fetch/refresh 只发布不可持久化的 `InboxItemReadModel`，不得在读取路径写 SwiftData；identity 绝不从用户文本/规范化文本/哈希派生，同名独立条目保持独立。外部 capture 只有调用方提供的持久 `(origin, UUID)` key 才进入 receipt 幂等路径，标题/时间戳/模型 ID 不得充当去重依据。

## 任务与领域模型

**AD-008：普通任务只有可恢复的归档生命周期，tombstone 是兼容协议（合并原 AD-028、AD-121、AD-127）。**
- 规则：任务不再拥有产品层 workflow status：编辑器、行、详情、菜单和辅助功能值不显示状态选择器、徽章、Complete 或 Reopen；Checklist 是任务完成与进度的唯一产品语义，不锁住后续工作。
- 边界：任务行、侧边栏和详情复用 Archive/Restore 与同一套 `TaskSummaryRow`/`TaskTimerActionButton` 语法（状态只是被动图标，停止是独立动作）；归档活动 timer/Pomodoro 子树必须无写入地拒绝，命令不得静默停止工作。`TaskNode.deletedAt` 与历史 `statusRaw` 只作为旧 schema/snapshot/CloudKit 兼容字段，不得替代 `deletedAt`、不得批量回写 iCloud，也不得复活产品 Delete 链。

**AD-021：parentID 是层级权威，path 是稳定 locator。**
- 规则：`TaskNode.parentID` 是层级事实，`depth` 是可重建索引，`path` 固定为 `/<task UUID>`；显示路径由 `TaskTreeService` 按标题即时迭代生成并限制最近六级。
- 边界：启动、任务域刷新和 sync restore 运行确定性 orphan/cycle 修复；移动任务只写真正变化的节点，不得把 `path` 直接显示给用户。

**AD-054：任务树 projection 由 mutation-owned read index 与有界缓存发布。**
- 规则：`TaskTreeReadIndex` 保存 canonical 顺序、可见 child ID buckets、section/root IDs、child count 与搜索值；只有语义变化才推进 `taskTreeReadIndexRevision`。`TaskTreeProjectionCache` 以 revision 失效，展开与搜索各保留容量四的 LRU，只保存 ID/value model。
- 边界：新增 task-tree surface 必须消费该 read index/projection，不得在 `body` 重新 filter/sort/group 全树或保留无界缓存。

**AD-024：Pomodoro 由持久 phase 状态派生 deadline，并与账本生命周期一致。**
- 规则：当前 phase 起点持久化在 `PomodoroRun.startedAt`，deadline 由状态与计划时长派生；启动/前台/页面出现/scheduled task 幂等 reconcile 过期 focus 并截断 segment/session。
- 边界：break 不在后台擅自创建下一段 focus；通用 segment edit/delete、timer stop 和 task-tree delete 必须在同一原子动作中完成/取消/tombstone 对应 run，并保留有效历史。

**AD-025：增量 ledger/checklist/rollup 与有界 90 日 pace。**
- 规则：Ledger 维护 ID/day/active/session indexes 并只替换相交范围；Checklist 只替换 affected task buckets；Rollup 消费增量 delta，base 负责 state/full rebuild。
- 边界：完整历史 worked seconds 必须精确；pace 只保留包含今天的最近 90 个本地日，只把已有 remaining seconds 换算为预计活跃日，不生成剩余工作量。View body 不得触发全量 rollup。

**AD-029：预计时长优先，Checklist 是证据回退。**
- 规则：`TaskEstimatePolicy` 接受 `0...600` 分钟、零表示未设置、正历史值最多规范化为 36,000 秒；明确预计时长优先，`estimatedTotal = max(explicitEstimate, ownWorked)`、`remaining = max(0, explicitEstimate - ownWorked)`。
- 边界：没有明确预计时长时才要求 checklist 至少完成一项且已有真实计时，再按等权完成项推导；父任务预计时长只属于当前任务自身，子任务预测独立递归相加。

**AD-032：日历日与未来边界由 `TrackedTimePolicy` 统一（合并原 AD-017）。**
- 规则：日边界必须用 `Calendar` 计算，不得用固定 86,400 秒；cache key 包含当前 Calendar 计算并裁剪后的真实起止时刻。所有已记录时间以 reference `now` 为唯一未来边界：`boundedEnd = min(endedAt ?? now, now)`，再裁到查询半开区间。
- 边界：本地 manual add/update 在 repository 层拒绝 future end/start 并返回 typed 错误，脏同步数据不迁移删除而是统一裁剪；UI/formatter 不得直接从 raw `endedAt` 派生时长。

**AD-033：持久偏好先做整批类型化预检。**
- 规则：`PreferenceJSON` 对持久路径提供 throwing checked encode/decode，按 `AppPreferenceKey` 解码为声明类型、规范化、重新编码；单项上限 256 KiB，`null`、畸形 JSON、错误类型和超限必须拒绝。
- 边界：`PreferenceCommandHandler` 在任何 fetch/insert/update 前准备完整批次，再用 `performAtomicMutation` 一次提交；legacy 无法 checked-encode 的值跳过，不得保存为 `null`。

**AD-036：分批导入的不完整账本采用读模型隔离。**
- 规则：原始 SwiftData 行保留，显式 snapshot preflight 允许“当前 payload 缺少关联记录”的 staged import；facade 每次 task/ledger 一致性刷新建立 relationship visibility，只有 task 存在、session 存在且 `session.taskID == segment.taskID` 的 segment 才进入可观察数组、indexed query、Pomodoro elapsed 和系统投影。
- 边界：父记录后续到达时由完整刷新自动解除隔离，不得用数据库清理或 snapshot 拒绝代替隔离，也不得只在某个图表临时过滤。

**AD-128：一分钟内的普通计时重启续接为一个 canonical 时间片。**
- 规则：只把普通 stopwatch 来源族（app/shortcut/watch/widget/liveActivity）在同一 canonical task 上 `0 <= gap < 60s`、gap 内无其它可见工作、上一条 session 可见且无可见 Pomodoro 引用时续接：保留原 singleton session、tombstone 旧 closed segment、新建不同 UUID 的 active segment 并把 start 前移。
- 边界：绝不重开旧 segment ID；`replaceAll`、Manual、Calendar、Pomodoro、恰好 60 秒都不续接；mutation timestamp 必须严格支配已观察到的 future-skewed winner。

**AD-129：重复任务先建立可恢复、可幂等的 V13 事实层，并拆出两套任务资格（合并原 AD-130）。**
- 规则：模板/occurrence/generated task/quantity goal 使用冻结 deterministic identity；materializer 只处理当前日、不回填，暂停/归档期间错过的日期永久跳过，重放保留用户对生成任务的编辑。
- 边界：Timer、Pomodoro、手工时间、break resume 和 App Intent 只接受 direct-work；父任务选择、任务菜单、Inbox、清单建议与 Heatmap 接受 parent/content；模板始终不可直接工作但仍可作为父级。

## 读侧与 Analytics

**AD-026：Analytics 求值与缓存共享完整 evaluation identity（合并原 AD-042、AD-043、AD-044、AD-088、AD-089、AD-096、AD-116）。**
- 规则：cache/request key 同时固化完整 interval 起止、当前 local-day 与 optional live-minute bucket，不从 cutoff 反推 period；只有真实 `clockReference` 位于 interval 内才生成 live bucket。已完成历史周期的 cutoff 精确为 `interval.end`，未来周期为 `interval.start`。
- 边界：环比使用同一日历进度的 `.matchedProgress`（否则 `.completePeriods`），无目标语境时增/减都只用 `.neutral`。缓存只持有不可变 read models，不保留 SwiftData segment；Today visual projection 可在后台 worker 计算，但不得捕获 `ModelContext`/Store/lock/binding。

**AD-055：Analytics 的选择、overlap 与任务查询必须确定且有界（合并原 AD-083、AD-091、AD-092、AD-093）。**
- 规则：Task breakdown 依次按 gross 降序、wall 降序、本地化标题升序、UUID 升序；peak-hour 并列取最早本地小时；删除任务标题按 startedAt/updatedAt/UUID 取最新有效 session，breakdown 与 overlap 共用同一 resolver。overlap 的唯一产品语义是 excess：固定窗口内 N 条 segment 贡献 `(N-1) × wall`，必须严格守恒到 `gross - wall`，参与者以持久 task UUID 为身份。
- 边界：Task Detail 周期统计与最近记录分离，planner 在日期索引与任务分支索引中选择较小候选集，不得扫描任务全部历史或全 App 周期记录。

## 边界与安全

**AD-015：LLM endpoint、redirect 与响应有固定边界（合并原 AD-034、AD-063）。**
- 规则：HTTP 仅允许 `localhost`/`.localhost` 保留域名以及经数值解析确认的 `127.0.0.0/8`/`::1`；带 Authorization 的 redirect 只允许 scheme/host/有效端口完全一致。生产 transport 使用专用 ephemeral session，资源 timeout 60 秒，响应读取在 2 MiB 实际字节处取消，非 2xx/声明超限在 headers 阶段取消。
- 边界：模型发现逐项解码并只保留升序前 256 个唯一有效 opaque model ID，不先物化整个数组。

**AD-035：设备身份是随机不透明 ID，不是设备指纹。**
- 规则：只复用当前平台 `mac|ios|watch` 前缀加大写连字符规范 UUID，完整值最多 42 UTF-8 bytes 且不得含控制字符；其余值随机重建并回写。
- 边界：不得加入主机名、账户名、序列号或硬件标识；Watch 命令去重使用随机 command UUID，而不是设备身份。

**AD-031：系统输入路由必须有界并服从 scene 生命周期。**
- 规则：deep link 在立即执行或排队前都经过同一个 `AppDeepLinkRouter` 白名单验证（scheme、最长 2,048 bytes、禁止 credential/port/fragment、UUID 语法）；每个 scene 使用容量 16 的按语义去重 `PendingDeepLinkQueue`，scene 消失时清空。
- 边界：`WatchCommandRouter` 单独拥有进程级 bridge handler，以弱引用注册 scene store 并优先最近 active scene；新的进程级系统 callback 不得由 scene view 强持有业务 store。

**AD-060：恢复关键本机文件共享耐久提交与有界隔离 primitive。**
- 规则：恢复关键的小型本机文件使用 `DurableLocalFile`/`PathFileLock`，调用方为每个状态家族选择唯一、稳定、已存在的 durable root；写入先完整落盘并同步，再原子 rename；损坏文件统一进入有界 `.TimeTrackerQuarantine`。
- 边界：调用方负责版本、大小与语义验证；同一 canonical 文件不得混用不同 durable root。该 primitive 不是 JSON validator、ACID 多文件事务或敌对进程防护，也不用于高频 ledger 写入。

## 同步与并发

**AD-066：计时准入先冻结确定性纯值计划，偏好只在锁内读取（合并原 AD-101）。**
- 规则：`TimerAdmissionPolicy` 只消费已经 LWW/canonical 的 active snapshots，输出稳定 `TimerStartPlan`/`TimerStopPlan`：普通同任务 start 复用最早 survivor 并清理重复段，Pomodoro 等需要新 session 的路径显式 `replaceAll`；exclusive 停其他任务、parallel 保留；精确 segment stop 不回退，task stop 覆盖同任务全部活动段，current 取最新 startedAt 并以 UUID 决胜。
- 边界：public start 命令不接收调用方传入的 `allowParallelTimers`；`StoreScopedTimerCommandCoordinator` 在 store lock 内用 `TimerAdmissionPreferenceResolver` 从 canonical `SyncedPreference` 解析。纯 policy 不解决跨 context/进程竞态，生产 writer 仍必须走锁 + fresh context。

**AD-069：所有生产 writer 在 store-specific 锁 + fresh context 内提交。**
- 规则：`TimerStoreScope` 为每个 store 提供稳定 identity，`StoreScopedTimerMutationLock` 从 scope 派生同目录 `.timer-mutations.lock`（复用 `PathFileLockRegistry`/`PathProcessFileLock`），`StoreScopedTimerMutationTransaction` 的固定顺序是“取得 store lock → 创建 fresh `ModelContext` → 关闭 autosave → 一次 `performAtomicMutation`”，离开作用域释放锁。
- 边界：锁内只做授权、fresh fetch、plan、model mutation 和 commit，网络/UI 等待/post-commit refresh 留在锁外。timer、Pomodoro、手工时间、segment 编辑、task lifecycle/draft、category、checklist、recurrence、countdown、同步偏好、Inbox primary/suggestion、AI workspace apply 与设备本地 LLM Keychain 更新已共用此域（合并原 AD-082、AD-084、AD-098、AD-099、AD-108、AD-114、AD-115）；新增写入口不得退回 scene-owned `ModelContext`。

**AD-023：同步状态使用跨进程锁、有界 slot manifest 与 fail-closed 读（合并原 AD-073、AD-074、AD-104、AD-110、AD-111）。**
- 规则：每次 `SyncConflictState.json` read-modify-write 在递归进程锁 + POSIX `lockf` 内完成，形成跨进程 compare-and-swap；磁盘权威是 V1 小型 manifest（标量 + 至多八个 A/B slot 引用，带 byte count 与 SHA-256），slot 先经 `DurableLocalFile` 写入并同步，manifest 才是提交点。权威 state 限 128 MiB、mirror/slot 限 64 MiB，读取先做 metadata 预检再用 `FileHandle` 最多读 `limit+1`；损坏或超限进入显式隔离恢复。
- 边界：`prompt()` 是 throwing read boundary，只有合法 state 中确实没有完整 pending conflict 才返回 `nil`。`pendingConflictID` 同时是用户确认的版本 token：resolution-relevant snapshot 变化时在锁内旋转，`resolveSyncConflict(expectedConflictID:)` 在同一锁内先精确比较，不匹配返回 `conflictChanged` 且零副作用。UI 侧只有 Settings 的恢复区展示两侧摘要与两个明确方向，根场景只显示可忽略的非阻断提示。

**AD-142：恢复门控与提交后投影按显式来源重放（合并原 AD-076、AD-081、AD-094、AD-103、AD-109、AD-137）。**
- 规则：恢复意图区分 `reconcileWithCloud` 与 `explicitlyReplaceCloud`：自动 fallback 只做比较（保护本机分支、建立 fresh cache、等完整 setup+import 屏障后比较），只有用户明确选择本机赢家才执行 explicit replacement。typed `CloudRecoveryGate.completed/deferred/failed` 与 `CompletedCloudRecovery` token 阻止失败或无法证明安全的恢复进入云容器；`performPendingCloudRecoveryResetAfterProtectingLocalFallback` 用一个外层 store lock 连续覆盖重开 local store、fresh 全域 capture、state/mirror 落盘、destructive reset。
- 边界：`CommittedMutationSystemProjectionRequest` 必须携带 `.localCommit`/`.startupCatchUp`/`.surfaceCatchUp`；只有前两者记录 sync recovery snapshot，启动固定发送 `.startupCatchUp + .fullSync`，durable mutation/Intent/Watch 终态都不等待投影 I/O，单 sink 失败只在下一次相关 generation 重试。普通本地提交经进程内 broadcaster 让其它 open scene 只刷新 read models（不记录 snapshot、不重复副作用）。

**AD-100：系统表面的陈旧投影冻结时间而非伪造实时状态（合并原 AD-051、AD-105、AD-118）。**
- 规则：Widget/Watch 只在快照 current 时用 system timer text；`.stale`/`.clockAdjusted`/Watch stale 时秒数固定为 `generatedAt - startedAt` 并显示 stale/clock-adjusted 状态。Live Activity 是可点开、不可就地修改账本的只读投影：锁屏与 expanded Dynamic Island 共用 extension 内唯一的 `LiveActivityTimerRow`，锁屏对齐 Today/Now 层级，expanded 普通字号只显示图标/标题/elapsed；点按只深链到 Today。
- 边界：Widget 的显式停止入口（携当前可见 segment ID，精确到该时间片）不受影响；不得恢复 Live Activity 内停止控件或不传 segment identity 的“最近一条”回退。

**AD-119：Watch 使用三页纵向分页，并解耦 Quick Start 与全任务排序。**
- 规则：`WatchDashboardView` 在同一 `NavigationStack` 使用 `.verticalPage` `TabView`（Active Timers / Quick Start / All Tasks）。第一次有效 snapshot 只做一次默认页选择；之后任何 snapshot/命令结果/status/stale 都不得抢走当前页，Quick Start/All Tasks 顶部提供至少 44 pt 的本地化“查看状态”按钮返回 Active Timers。
- 边界：Quick Start 排除运行任务并最多显示四项，All Tasks 不继承 pin 顺序、按 segment count/last-start/UUID 排序并保留运行任务；精确停止只属于 Active Timers 的 segment row。

## AI

**AD-132：AI 任务计划使用完整工作区工具提案与全量 CAS（合并原 AD-027、AD-133）。**
- 规则：每次用户明确 Generate 都在共享 store lock 下用 fresh context 捕获完整、确定性排序的 provider-visible Category/Task/Checklist snapshot（含稳定 UUID、关系、完整路径、可编辑元数据、归档状态、任务量目标与重复设置），不按任意实体数量或路径深度截断；发送前界面披露三类实体 counts。模型只能调用 strict OpenAI-compatible tools 修改纯内存 overlay，工具不能直接写 SwiftData；已有 Task/Checklist 只按 UUID 引用，Category 名称只有唯一规范化匹配时才复用。
- 边界：Apply 在同一 store lock/fresh context 中重新捕获完整 baseline 并对 provider-visible facts 与各类 revision 做保守 CAS，任何差异或保存失败都是零写入、零事件，Task removal 只 Archive。API key 只进入 Authorization header；reasoning/tool round/raw response 只在当前生成与审阅会话中临时存在，不持久化、不同步、导出或记录日志。配置采用 Test→Save 草稿；自动建议是默认关闭、设备本地的第二个明确开关；密钥不属于同一 ACID transaction，补偿失败必须单独报告。思考强度是 DeepSeek 官方 `high`/`max` 的同步偏好，切换时取消旧请求，迟到结果不得跨 effort 落库。

**AD-133：AI 请求发送完整上下文；生成验收不得伪造。**
- 规则：三条生产 AI 请求（Inbox / Checklist / 任务计划）发送完整规范化上下文与完整规范 SF Symbols 目录，不按人工候选数/JSON/字段/prompt/body 预算静默删除；真实边界（opaque model ID 256-byte、单响应 2 MiB、模型 reason 512-byte、endpoint/API key 上限）继续生效。
- 边界：预制 provider response、预造 plan 或 fake tool-call 序列不得充当模型生成验收；仓库**不存在** `make test-llm-live` 之类的 live gate——真实 endpoint 验收是一次性人工 smoke check，证据写入交付该工作的 commit/PR，不进默认测试套件。

## 平台、流程与 UI

**AD-139：主界面按窗口宽度选择共享 shell，平台分支只封装真实能力（合并原 AD-011、AD-012、AD-019）。**
- 规则：`AppRootView` 以实际测得的窗口宽度和系统 compact size class 选择 compact（<720 pt）或 regular（共享 `NavigationSplitView`）shell；业务 Store、scene router 与 durable navigation identity 位于分支之上。
- 边界：`#if os(...)` 只用于目标上不存在的框架/API、原生 scene/menu/window plumbing、系统 chrome、输入方式与真实 capability；同信息角色跨平台共享系统语义字体，不得按设备 idiom、屏幕或 os(...) 复制同一页面。Dynamic Type 不得退化为截断或固定字号；极端字号是风险触发的定向验证（见 [Testing](Testing.md)）。

**AD-117：第三方依赖经定向审查并锁定 revision；macOS 平台能力保持设备本地（合并原 AD-135、AD-136、AD-138）。**
- 规则：默认不新增第三方库；经审查的例外（MarkdownView 4.1.7、BlossomColorPicker 固定 revision、KeyboardShortcuts 3.0.1）必须记录许可证、供应链、体积、隐私与回退证据，并同时锁定 `Package.resolved` 与工程引用。
- 边界：任务/分类/Checklist/Pomodoro 的符号与颜色入口共用 `SymbolColorWell`；macOS 由所属颜色 well 的真实 `NSView`/`NSWindow` 换算屏幕坐标，不得用 `NSApp.keyWindow` 或复制花瓣几何。macOS 菜单快捷键是设备本地偏好，通过应用命令边界写单个有界原子 blob（不进 SwiftData/CloudKit），注册表覆盖稳定的主要操作，标准 `Command-N`/`Command-,` 保持不可改写。

**AD-141：文档只存当前规则，验证与测试以行为为准（合并原 AD-008、AD-009、AD-057）。**
- 规则：当前行为与所有权只写入 UserGuide/CodeGuide/Architecture/ProjectMap/Testing/PrivacyAndSecurity；一次性发现与验证证据写入交付该工作的 commit/PR，跨多会话的较大任务可在 `Docs/ImplementationContexts/` 保存进行中记忆并在完成后清理（历史由 git 承载）。
- 边界：业务约束以领域/集成测试验证，UI 流程以 accessibility identifier 和可见行为验证；不得通过读取 Swift 源文件匹配字符串来约束实现（entitlement、Privacy Manifest、迁移 fixture 产物契约除外）。默认审核主线是正常字号、核心操作路径与当前平台 HIG。
