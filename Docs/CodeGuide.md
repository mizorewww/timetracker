# TimeTracker 代码文档

状态：当前实现说明
校对日期：2026-07-15

本文面向维护者，说明当前代码边界、数据流、扩展方式和验证入口。架构目标与未完成计划分别见 [Architecture](Architecture.md) 和 [NextDevelopmentPlan](NextDevelopmentPlan.md)。

## 1. 工程与目标

主要 Xcode 工程为 timetracker.xcodeproj，包含：

| Target | 责任 |
| --- | --- |
| timetracker | iPhone、iPad、Mac 主应用 |
| timetrackerLiveActivityExtension | iPhone Live Activity |
| timetrackerWidgetExtension | 桌面小组件 |
| timetrackerWatchApp | Apple Watch 配套应用 |
| timetrackerTests | 单元、领域和源码契约测试 |
| timetrackerUITests | 端到端 UI 测试与截图基线 |

当前构建设置声明 iOS/iPadOS 26.2、macOS 15.7、watchOS 26.2。打开工程前使用与这些 SDK 匹配的 Xcode。

常用验证命令：

    xcodebuild test \
      -project timetracker.xcodeproj \
      -scheme timetracker \
      -destination 'platform=macOS' \
      -only-testing:timetrackerTests \
      -parallel-testing-enabled NO

    xcodebuild test \
      -project timetracker.xcodeproj \
      -scheme timetracker \
      -destination 'platform=macOS' \
      -only-testing:timetrackerUITests \
      -parallel-testing-enabled NO

每次重构的最终结果以 [审核报告](Audit-2026-07-14.md) 的“本轮重构结果”为准。历史上曾通过的套件不能替代当前工作树复验；模拟器截图也不能替代 Widget、Watch、Live Activity 和 CloudKit 的真机验收。

## 2. 代码地图

| 路径 | 主要责任 |
| --- | --- |
| timetracker/App | 启动、依赖组装、平台根视图、导航 |
| timetracker/Features | Today、Inbox、Tasks、Pomodoro、Analytics、Settings 等界面 |
| timetracker/Models | SwiftData 持久模型与 schema 版本 |
| timetracker/Commands | 可持久业务动作与 use case handler |
| timetracker/Repositories | SwiftData 查询与写入实现 |
| timetracker/Services | 分析、预测、同步、安全、维护与系统集成服务 |
| timetracker/Stores | `@Observable` UI 门面、领域快照、刷新规划和导航状态 |
| timetracker/Shared | App/扩展可共享的 DTO、字符串与辅助类型 |
| timetracker/SharedUI | 原生风格组件、布局策略和设计 token |
| SharedLiveActivity | 主应用与扩展共用的 Activity attributes |
| timetrackerLiveActivityExtension | ActivityKit 展示与属性 |
| timetrackerWidgetExtension | WidgetKit 时间线和共享快照读取 |
| timetrackerWatchApp | Watch UI、快照与连接命令 |
| timetrackerTests | 单元和契约测试 |
| timetrackerUITests | UI 流程与截图测试 |

`Features/Inspector`、`PhoneChromeViews`、Home 通用年月日进度卡、Pomodoro 自绘高刷新转场、`SettingsSectionsViews.swift` 和 `TimeTrackerServices.swift` 已不存在；不要继续把它们当作当前模块或扩展点。

本轮已完成八组关键职责拆分：

- Sync conflict：`SyncConflictService` 只保留 bootstrap/prompt；local mutation、Cloud import/export、recovery/resolution、state persistence、file lock/locations、export encoding、snapshot capture/分域 restore、snapshot state 与分域 record DTO 分文件。
- Analytics：root/category、overview row、metric/detail list、period control 与 store 的 metrics/breakdowns/overlap/task snapshot 分文件。
- Settings：display/timing、Pomodoro、countdown、sync、data、actions、bindings 与 support 分文件。
- Task Detail：canonical router 与 identity/checklist/overview/analytics/navigation/record sections 分文件。
- Ledger infrastructure：Cloud startup、persistence safety、timer DTO、aggregation、formatting、device identity 与 summary 分文件。
- Facade lifecycle：`TimeTrackerStore+Configuration.swift` 只负责首次配置、repository-only 系统表面组装和 post-commit surface refresh；`TimeTrackerStore+Lifecycle.swift` 负责 refresh、mutation 边界、恢复动作和通用错误，不再把启动迁移/seed/observer 安装混在同一大扩展。
- Widget：entry/provider/config、active-timer family layouts、supplementary/error states 与 deep-link/localization/color support 分文件。
- Watch：dashboard orchestration、timer rows、status/error/empty states 与 color support 分文件；`WatchAppStore` 保持 queue/connectivity state 单一所有者。

分层不等于所有文件都已完成单一职责拆分。当前仍集中的 Watch connectivity store、Home 根组合与部分大型行视图已在 [CodeRefactorPlan](CodeRefactorPlan.md) 逐项列出；不要把已经完成的八组拆分重新列为“未来工作”，也不要用机械行数替代职责审核。

## 3. 运行时数据流

持久写入的推荐路径为：

    SwiftUI View
        → feature/store action
        → domain command
        → repository
        → SwiftData model context
        → read model/service refresh

`TimeTrackerStore` 是 `@MainActor @Observable` 的 UI 门面，但不是所有业务规则的最终归属。根视图用 `@State` 持有它，注入视图以普通引用读取，只有 sheet/item 等需要 Binding 的位置才建立局部 `@Bindable`。新功能应先判断规则属于：

- View：布局、可访问性、展示状态。
- Store：UI 可观察状态、动作编排、错误呈现和精确失效。
- Command：一次明确、可测试的业务写入。
- Repository：模型查询与持久化细节。
- Service：跨实体计算、同步、导入导出或系统集成。

视图不应直接复制领域判断，也不应绕过命令与仓储执行长期写入。计时文本用 `TimelineView` 做局部刷新；不得为了时钟显示让整个 facade 每秒发布一次状态。

`TimeTrackerStore.perform` 和 `SystemActionCommandHandler` 使用 `ModelContext.performAtomicMutation` 包住一个用户动作。命令/仓储内部的 `saveAfterMutationStep` 在独立调用时立即保存，在外层 transaction 中延迟到最后一次统一 `save()`；动作或最终保存抛错会 rollback 整个 unit of work。提交之后的 read-model refresh 或 sync snapshot 失败不可能撤销已保存事实，因此 `perform` 仍返回成功并展示“已保存但重新载入失败”。Feature 只能在 `perform == true` 后清理 transient success/failure 状态。Keychain 不能加入 SwiftData 的 ACID transaction：LLM 配置先记住旧密钥，将三项普通偏好批量成一次 SwiftData 保存，并在提交失败时尽力恢复旧密钥；恢复本身失败必须单独报告。任务、账本等 UI selection 也只在 `didSave` 后更新，因为它不会由 `ModelContext.rollback()` 自动恢复。

### 当前平台 UI 合同

- iPhone：五个系统 `Tab`（Today、Inbox、Tasks、Pomodoro、Analytics）；Settings 是 Today 导航栈中的目的地。
- iPad：regular width 使用 `NavigationSplitView` 侧边栏与详情；compact width 使用五标签根导航。从侧边栏或任务列表选择任务会打开同一个 `TaskDetailView`。
- macOS：单实例主 `Window` 承载 `NavigationSplitView` 工作区；独立系统 Settings scene、主窗口和 Settings 共享一个应用级 `TimeTrackerStore`，避免复制 CloudKit observers、自动 AI 建议与系统表面同步。
- Today：iPhone 使用 `List`；Active Timer、摘要、Quick Start、Forecast、Timeline、Countdown 按优先级排列，没有通用日/周/月/年进度卡。iPad/macOS 的宽屏 Today 通过 `HomeCountdownSection` 读取同一 `countdownEvents` 状态并展示 Countdown。
- Task Detail：只读优先的 `List`，铅笔按钮再打开编辑 sheet；清单完成状态可直接切换。
- Task availability：Today、Quick Start、Pomodoro、手工记录、Inbox 建议、App Intent 与任务动作共用祖先感知的可计时判定；归档活动子树前先停止计时，历史 segment 编辑可保留原任务。
- Settings：五类导航 IA，不提供应用级 appearance override。
- Pomodoro：Plan 和 Task 是两个可见 `Menu`，没有点击标题/计时器的隐藏选择逻辑。
- iOS 不设置 `CADisableMinimumFrameDurationOnPhone`；刷新率与帧调度交给系统，流畅度用 Release 截图/trace 和真实设备观察验证，不靠 Info.plist 强制覆盖。

## 4. 核心领域

### 时间事实

TimeSegment 是计时事实来源。它不是“写入后永不可改”的 event：用户可以更正或软删除错误记录；这里的“事实来源”指所有派生统计、当前运行状态和时间线必须从 canonical segment 与明确规则重算，缓存不能成为第二真相。

并行计时是合法状态，因此：

- gross duration 是所有片段时长之和。
- wall-clock duration 是片段区间并集的长度。
- overlap 是由并行区间产生的差异。

改变统计算法时，必须覆盖边界相接、完全包含、跨日、时区与夏令时、多任务重叠等案例。

日边界必须由 `Calendar.startOfDay` 与 `date(byAdding: .day, ...)` 计算，不能用固定 `86_400` 秒代表一个本地日。Forecast 的“活跃天数”和 Analytics 的 day bucket 都遵守该规则。`LedgerBucketCache` 的 key 包含由当前 Calendar 计算并真实裁剪后的起止时刻；局部失效只删除与变更区间相交的 bucket，避免 DST 或同日不同子区间命中错误缓存。

### 任务和组织结构

Task、TaskCategory、ChecklistItem 和 InboxItem 形成用户组织层。树形视图需要稳定身份，ForEach 应使用持久标识符，不得依赖数组索引或可变标题。

归档与删除语义不同。删除任务树会在一个原子动作中先结束该树的活动 Pomodoro 和 timer，再软删除任务；历史 segment/session/run 继续保留。普通 Local、iCloud、local-fallback 和 emergency 生产模式没有跨设备删除确认，因此 `AppCloudSync.allowsPermanentTombstonePurge` 为 false，`DatabaseMaintenanceService` 直接返回 0。只有隔离的 Demo/UI Test store 可物理清理过期 tombstone graph。

`TaskNode.parentID` 是层级权威；`depth` 是可修复元数据；`path` 现在是稳定 canonical record locator `/<task UUID>`，不是祖先 UUID 链，也不是用户可见标题路径。显示路径由 `TaskTreeService` 根据当前标题迭代生成，并限制为最近六级。启动、任务域刷新和同步恢复都会运行 `TaskHierarchyMetadataService`：缺失父节点和循环会确定性地提升为根，随后重算 depth/canonical path。任务移动只更新真正变化的 depth/path，避免同深度跨根移动重写整棵后代。

持久实体去重遵循确定性 last-write-wins：先比较 `updatedAt`，同一时间 tombstone 胜过 active row，再以 `createdAt`、`deviceID`、`clientMutationID` 稳定打破平局；没有 mutation ID 的 `TimeSegment` 使用稳定内容键。清理产生的 duplicate tombstone 不得反过来覆盖真正的新 canonical row。所有“只取可见记录”的查询必须先 deduplicate/LWW、再过滤 tombstone，禁止把过滤顺序颠倒。

### 番茄会话

PomodoroRun、关联 TimeSession 与运行状态通过同一命令/仓储变更。`startedAt` 表示当前 focus/break phase 的起点，`phaseDeadline` 由持久状态与计划时长派生；它不是 View 本地倒计时。启动、前台、Pomodoro 页面出现和 deadline task 都会调用幂等 reconcile：过期 focus 在业务 deadline 截断 segment/session，避免后台挂起时间被算作专注；过期 break 不会自动新建 focus，下一轮仍需用户动作。

通用 ledger 编辑必须保持 Pomodoro 不变量。编辑活动 Pomodoro segment 会重绑 run 的 task/start；把 segment 关闭会按 deadline 完成或取消 run；删除活动 segment 会 tombstone run/session；删除任务树会结束所有活动 timer，并保留已产生的 Pomodoro 历史。相关写入必须在同一个 `performAtomicMutation` 中提交。

### 增量读模型与缓存

- `LedgerStore` 初次加载建立 segment ID、day、active、array-index 和 session index；带日期范围的 mutation 只查询/替换相交 segment 与相关 session，并输出 `LedgerSegmentChange`。
- `ChecklistStore.refreshTaskScoped` 只替换受影响 task 的 items/visuals，并同步维护 facade bucket，不在每次 toggle 后重新按全库分组。
- `RollupIncrementalIndex` 保存任务拓扑、segment delta、活动摘要、checklist 进度和近期日 bucket。普通 mutation 的工作量由变更记录、任务自身与祖先深度决定；完整历史 worked seconds 始终精确。
- Forecast pace 使用包含今天在内的最近 90 个本地日，只对有记录的活跃日求日均；它只把已有 remaining seconds 换算为预计活跃日，不生成 remaining seconds。Calendar/时区变化会重建这组有界 bucket。
- `AnalyticsStore` 的 overview 与 task snapshot cache key 包含 range、真实 period start 和可选 live-minute bucket。仅当前范围与活动 segment 相交时按分钟换 key；历史/静态范围稳定复用。ledger 事件按相交区间失效 day bucket，跨 period 会自然 miss。
- `CorePerformanceBudgetTests.fiftyThousandSegmentMutationUsesConstantSizedRollupDelta` 以 50,000 个 segment 约束单 segment 增量更新和 cached recent ranking；最终是否通过仍以冻结工作树的 xcresult 为准。

## 5. 持久化、CloudKit 与迁移

当前 schema 为 V8，迁移计划覆盖 V1 至 V8。版本升级时：

1. 先声明哪些用户数据必须保留。
2. 为旧 schema 准备真实 store fixture。
3. 验证迁移可重复、不会生成重复事实。
4. 说明新旧设备同时在线时的版本偏差行为。
5. 明确失败后的回退边界；不要用空库或内存库静默伪装成功。
6. 更新 [Versioning](Versioning.md) 与 [AgentDecisions](AgentDecisions.md)。

当前兼容 fixture 主要覆盖 V4 到最新版本，仍需补齐其余重要版本。

CloudKit 模式与纯本地模式共用业务模型，但容器和同步状态不同。紧急内存 fallback 只能用于保持应用可诊断，绝不能被描述为持久存储。

同步刷新是事件驱动的：`NSPersistentStoreRemoteChange` 和 `NSPersistentCloudKitContainer.eventChangedNotification` 进入 `TimeTrackerStore+SyncObservers`，350 ms 合并窗口保留最高优先级原因，再由 refresh planner 执行一次一致性刷新。启动与 scene 回到 active 时仍会刷新；不要重新引入常驻 5 秒轮询。`SyncedPreferenceService.latestByKey` 必须先完成 LWW/tombstone 选择，再过滤已删除结果，否则旧 active preference 会复活。

`AppCloudSync.enabledKey` 是设备本地启动配置，只保存在 `UserDefaults`，修改后下次启动生效。它不属于 `AppPreferenceKey`，也不能进入 `SyncedPreference`、冲突快照或导出/恢复数据。历史 `TimeTrackerCloudSyncEnabled` 记录在这些边界统一过滤。普通 Local、Demo 和 UI Test 模式的 mutation 不生成冲突快照；CloudKit 活跃或存在待上传恢复时，`StoreDomainEvent` 只重抓受影响的 task、ledger、pomodoro、preference、countdown、checklist 或 inbox 域。仅 full sync、远程 import 和没有 baseline 的初始化需要捕获全部域。

同步文件所有权如下：

- `SyncConflictService.swift`：bootstrap 与 prompt 组装。
- `SyncConflictService+LocalMutation.swift`、`+CloudImport.swift`、`+CloudExport.swift`、`+Recovery.swift`、`+Resolution.swift`：本地变更、云事件与显式恢复流程。
- `SyncConflictService+State.swift`、`+StateLock.swift`、`+StateLocations.swift` 与 `SyncConflictState.swift`：本机状态持久化、pending forced-upload mirror、跨进程锁、文件位置与 epoch/generation/checkpoint state。
- `SyncConflictService+Export.swift`：过滤后的 JSON export encoding。
- `SyncDataSnapshot.swift`：版本化全域快照、摘要和 fingerprint。
- `SyncDataSnapshot+Capture.swift`、`SyncDataSnapshot+Restore.swift`、`SyncDataSnapshot+RestoreTasks.swift`、`SyncDataSnapshot+RestoreLedger.swift`、`SyncDataSnapshot+RestorePlanning.swift`、`SyncDataSnapshot+RestoreChecklist.swift` 与 `SyncDataSnapshot+RestoreInbox.swift`：按域捕获与一个原子事务中的分域恢复。
- `SyncSnapshotRecords.swift`、`SyncSnapshotLedgerRecords.swift`、`SyncSnapshotPlanningRecords.swift`、`SyncSnapshotChecklistRecords.swift` 与 `SyncSnapshotInboxRecords.swift`：组织/任务基础和分域跨版本 Codable record DTO；它们不是第二套业务模型。

`SyncConflictState.json` 的每次 read-modify-write 都在 `SyncConflictService.withExclusiveStateAccess` 内完成。进程内使用递归锁，跨主应用/Shortcuts 进程使用 POSIX advisory `lockf` 文件锁；两个进程不会用各自的旧状态副本互相覆盖。状态 JSON 原子替换，forced-upload mirror 只在权威 state 缺失/损坏隔离时恢复，并在下一次 locked load 校正。损坏的权威 state 会隔离并进入显式恢复；损坏的 pending mirror 也会隔离，但被安全忽略，不能阻塞仍可使用的主库。

在 iOS 上，权威状态文件、pending forced-upload 恢复镜像和腐损状态隔离文件写入后都设置 `FileProtectionType.completeUntilFirstUserAuthentication`。这些文件在设备本次启动首次解锁前不可读，首次解锁后可供后台 Shortcuts/CloudKit 流程继续使用；lock 文件不是用户快照，也不能被描述为同样的受保护数据文件。macOS 不套用 iOS Data Protection 属性。

Cloud export 不以“收到任意成功回调”作为本机已同步证明。每次 local mutation 推进 `localGeneration`；import/强制恢复推进 `syncEpoch`；export start 记录 event ID、epoch、generation、fingerprint 和 startedAt。成功 finish 只确认同 epoch 且不早于已确认 generation 的 checkpoint，乱序旧回调不能回退 base 或清除较新的 pending forced upload。旧 state 清理被排除偏好时会重算 fingerprint 并同时清空清理前 payload 的在途 checkpoints，使延迟回调不能恢复旧 base。checkpoint 最多保留 16 个、最长 24 小时，不为每个事件复制整份用户 snapshot。

Snapshot restore 把历史/外部 transport 当作不可信输入：同一 record 数组中的重复 UUID 会先按稳定规则确定性去重，再进入 three-way merge，避免 `Dictionary(uniqueKeysWithValues:)` 的 duplicate-key trap。Pomodoro restore 会把 focus/break/long-break 时长限制为至少 1 秒、target rounds 限制为 `1...24`、completed rounds 限制为 `0...target`，再写入领域模型。

### 演示与测试数据

`TIMETRACKER_AUTOMATIC_DEMO_DATA_MODE` 在 Debug/Release 工程配置中都为 `off`。Debug 才允许明确的 `seedIfEmpty` / `replaceOnLaunch` override；一旦启用，容器改用本地、无 CloudKit 的 `TimeTracker-Demo.store`。UI tests 使用独立内存 container。不要用自动 seed 填充真实 CloudKit store，也不要把 demo 记录上传为用户事实。

## 6. 偏好与秘密

普通偏好通过 SyncedPreference 保存并可参与 iCloud 同步。设备启动配置和秘密是例外：

- iCloud enablement 只保存在当前设备的 `UserDefaults`，不得从云端 preference 覆盖。

- LLM API 密钥写入 LLMCredentialStore。
- Keychain 可访问级别为 AfterFirstUnlockThisDeviceOnly。
- Keychain 条目标记为不同步。
- 每台设备必须单独设置密钥。
- 同步快照和 JSON 导出必须过滤敏感键。
- 旧版本遗留在 SwiftData 或 UserDefaults 的值只可用于一次迁移，随后必须清空或软删除。
- “清空全部数据”必须同时清除 Keychain 密钥和设备本地的自动建议同意；若 SwiftData 清理失败，外部存储值需尽力恢复并准确报告补偿失败。

任何新增 token、密码或私钥都默认遵守同样规则，除非有独立安全设计和用户授权。

`DeviceIdentity` 是本机 `UserDefaults` 中的随机平台前缀 UUID，仅用于同步 tie-break 和 mutation metadata。新 identity 不包含 Mac 主机名、账户名或其他可读设备名称。

Required Reason API 声明按 target 的真实 UserDefaults 边界维护：主 App 为 `1C8F.1` 与 `CA92.1`，Widget 为 App Group 场景的 `1C8F.1`，Watch 为自身偏好/队列场景的 `CA92.1`。Live Activity 当前没有独立 manifest；每次 Archive 必须检查合并结果和实际 API，不能用主 App 的声明替未覆盖 target 背书。

## 7. 系统集成

### App Intents

App Intent 只负责解析系统输入和展示结果，实际写入复用主应用的领域命令。新增意图时同时添加：

- 参数验证和歧义处理
- 本地化字符串
- 无匹配、权限和存储失败测试
- 与主应用相同的幂等或冲突规则

当前 Intent 与应用进程复用 `timetrackerApp.applicationModelContainer`，不为每次查询/动作重新创建容器。Start Timer 会读取同步偏好中的 `allowParallelTimers`，不得硬编码与主应用不同的并行规则；实体查询排除 tombstone 与归档任务。系统动作同样检查 recovery 只读状态并使用原子 mutation。

Intent durable mutation 提交后，`CommittedMutationSnapshotRecorder` 更新同步恢复状态，`CommittedMutationSurfaceSynchronizer` 用窄依赖配置刷新 task/ledger/preference read models，再投影到 Widget、Watch 和 Live Activity。它不会启动完整应用 lifecycle 或自动 LLM 工作。post-commit 失败只记录/呈现“已保存但投影刷新失败”，不得把已提交的非幂等动作返回为失败并诱发系统重试。

### Live Activity

Live Activity 是状态投影。Activity attributes 应保持小而稳定，不保存唯一业务事实。Activity 的 task identity、停止 deep link 和主应用命令必须一致；更新失败应重试或降级显示，但不应阻断主应用写入。扩展对任务文本使用隐私处理，并明确显示 stale 状态。

### Watch

Watch 使用持久快照加命令队列。每个 `WatchTimerCommand.id` 是幂等键；Watch 把队列编码到本地 UserDefaults，并同时走 durable `transferUserInfo` 与可达 `sendMessage`。手机返回七态 typed terminal result（success、duplicate、missingTask、missingSegment、invalid、failed、timeout），并用 durable user-info 再投递；20 秒无 terminal result 会进入可重试失败态，retry 保留 ID，用户也可 discard。快照反射只为旧手机兼容确认。Watch UI 以 Active Timer 为第一优先级，并区分首次等待、发送、排队、失败、离线和 stale。主 target 的 codec/state/processor 测试不能替代真机往返验证。

### Widget

Widget 从版本化共享快照读取数据，区分共享容器不可用、缺失与损坏，不把所有失败都显示成“没有计时”。时间线根据 snapshot freshness 和 active timer 安排刷新。主应用和扩展已启用 `group.me.mezorewww.timetracker`，Xcode 自动签名构建已生成带该 entitlement 的 profile；发行门禁仍要求真机验证共享容器 URL、读写、刷新策略、锁屏与离线状态。

## 8. AI 服务

LLMService 面向用户配置的 OpenAI-compatible endpoint。边界要求：

- 远程 endpoint 必须为 HTTPS。
- 仅 `localhost`/`.localhost` 保留域名以及经 `inet_pton` 数值解析确认的 `127.0.0.0/8` 或 `::1` 可使用 HTTP；`127.evil.com` 一类主机名不能靠字符串前缀伪装成本机。
- API key 只在请求 Authorization header 中使用。
- 带 Authorization 的 redirect 只允许保持相同 scheme、host 和有效端口；跨源、HTTPS 降级或模糊主机跳转必须拒绝，防止 credential 泄漏。
- 发送前按功能构造最小请求，不附带无关数据。
- 日志和错误信息不得打印密钥或完整敏感请求。
- 解码错误、限流、超时和无效模型必须转换为可操作错误。

Settings 采用 `LLMConfigurationDraft`：endpoint/API key/模型编辑先留在 sheet；“测试连接”只读取模型并验证当时的 credential fingerprint，不持久化；只有模型有效时才能“保存”。修改凭证会取消旧请求并清空旧模型结果，取消有改动的 sheet 会二次确认。保存时 endpoint、模型列表和已选模型由 `PreferenceCommandHandler.set(values:)` 在一个 SwiftData transaction 中一次提交；API key 的 Keychain side effect 不属于同一 ACID transaction，提交失败时只可用旧值补偿恢复，且补偿失败必须单独报告。

自动建议是另一个明确的本机同意开关，默认 false，不进入 CloudKit 或 JSON。只完成配置不会开启后台发送；开启后才会为 Inbox/checklist 触发受并发和退避控制的请求。发行时必须锁定默认 endpoint/第三方 endpoint 的运营方、用途、保留期、删除渠道和隐私披露；“OpenAI-compatible”不是数据不保留的保证。

Inbox 和 checklist 视觉自动建议各自最多同时发出 3 个请求；一个请求完成或过期后再补下一项。Checklist 失败按请求指纹记录并至少退避 60 秒，配置或内容变化后才立即形成新请求；保存失败必须保留对应错误状态，不能让网络成功掩盖持久化失败。

精确的数据字段与安全边界见 [PrivacyAndSecurity](PrivacyAndSecurity.md)。

## 9. 常见改动方式

### 新增持久字段

1. 先确认字段是事实、派生值还是缓存。
2. 更新 schema 版本与迁移计划。
3. 更新真实旧 store fixture 和 round-trip 测试。
4. 检查 CloudKit 可选性和默认值约束。
5. 更新导出格式、隐私文档和版本说明。

### 新增界面

1. 保持 View 的 body 可读，把可测试规则移入 command/service。
2. 使用稳定身份和精确 observation，避免整个根视图因计时 tick 重算。
3. 使用系统导航、控件、Dynamic Type、VoiceOver、键盘和窗口尺寸行为。
4. 添加行为测试；源码字符串扫描只能作为轻量架构护栏。
5. 在 iPhone、iPad、Mac 对应尺寸上验证，并检查深色模式与 Reduce Motion。

### 新增导出或恢复格式

导出不等于备份。可称为“备份”的功能至少需要：

- 明确的格式版本
- 完整性校验和
- 导入预检与冲突策略
- 事务性写入或可回滚 staging
- 多版本 fixture
- 成功恢复后的等价性验证

## 10. 测试策略

优先级从高到低：

1. 领域行为与迁移测试
2. Store/command 集成测试
3. UI 可访问性标识驱动的流程测试
4. 少量稳定截图测试
5. 源码结构契约

仍有部分测试通过读取 Swift 源文件并匹配字符串来约束 UI，这类测试会在等价重构后误报。逐步把它们替换为行为、accessibility identifier 和结构化 API 测试。

测试必须隔离 UserDefaults、Keychain、临时目录、时区与 locale。本轮已移除类别空分区测试对演示种子全局状态的依赖；新增测试仍应显式清理共享状态。

## 11. 代码注释与文档规则

- 对公共领域类型、迁移策略、数据安全边界和非直观算法添加 Swift DocC 注释。
- 注释解释原因、不变量和失败模式，不复述语法。
- 当前行为写入 UserGuide、CodeGuide 或 Architecture。
- 决策与权衡写入 AgentDecisions。
- 一次性审计事实写入带日期的 Audit 文档。
- 未来工作只写入计划文档，并明确状态。

当前生产 Swift 文件尚无系统性的三斜线 API 文档，这是需要持续偿还的文档债务。

## 12. 签名与系统能力

工程保持 `CODE_SIGN_STYLE = Automatic`，开发团队为 `LT98S43NKA`。主应用、Widget、Watch 与 Live Activity 需要真实 entitlement/profile 才能验证 CloudKit、App Group、WatchConnectivity 和 ActivityKit。

- 不要通过 `CODE_SIGNING_ALLOWED=NO`、`CODE_SIGNING_REQUIRED=NO` 或清空 `DEVELOPMENT_TEAM` 把签名错误隐藏成构建成功。
- Simulator 日志中的 `Sign to Run Locally` 是正常本机模拟器步骤；generic/device/Release 构建仍必须验证 Apple Development identity、team、profile 和 entitlements。
- CLI 优先使用仓库 scheme 和自动签名；只有 CLI 无法表达的 Xcode 账户/profile 操作才需要 Xcode UI。
- 模拟器可以验证布局、导航和大部分领域交互；不能证明 App Group、CloudKit 账户、Watch 往返、Live Activity 系统限制或发行 profile 在真机有效。

### FlowDown 参考与依赖边界

本轮参考的 [Lakr233/FlowDown](https://github.com/Lakr233/FlowDown) 固定快照为 commit `694ba5d`。只采用 RecoveryMode、版本化 importer/checksum/staging 和多 target 测试组织等模式，不复制 UIKit 组件，也没有把 SnapKit、ColorfulX、SPIndicator 或其传递依赖加入工程。当前工程没有因这次参考新增 Swift Package 依赖；未来引入任何依赖必须先满足 [AD-011](AgentDecisions.md) 的许可证、供应链、体积、性能、隐私与回退证据要求。

## 13. 相关文档

- [用户操作手册](UserGuide.md)
- [Agent 决策文档](AgentDecisions.md)
- [隐私与安全](PrivacyAndSecurity.md)
- [项目地图](ProjectMap.md)
- [本地化](Localization.md)
- [测试](Testing.md)
