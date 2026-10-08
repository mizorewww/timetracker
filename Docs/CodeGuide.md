# TimeTracker 代码文档

状态：当前实现说明

本文面向维护者，说明当前代码边界、数据流、平台 UI 合同与验证入口。目录级代码地图与分层规则在 [ProjectMap](ProjectMap.md)；架构目标在 [Architecture](Architecture.md)；用户可见行为在 [UserGuide](UserGuide.md)；构建/工具链命令在 [README](../README.md)。

## 1. 工程与目标

主要 Xcode 工程为 `timetracker.xcodeproj`，target：`timetracker`（iPhone/iPad/Mac 主应用）、`timetrackerLiveActivityExtension`、`timetrackerWidgetExtension`、`timetrackerWatchApp`、`timetrackerTests`、`timetrackerUITests`。当前构建设置声明 iOS/iPadOS 26.2、macOS 15.7、watchOS 26.2；打开工程前使用匹配的 Xcode。

验证命令经 Makefile：`make test`（单元）、`make build-macos`、`make build-ios`、`make format`/`format-check`、`make localization-check`，UI 用 `make UI_TEST_ONLY=... test-ui-ios|test-ui-macos`。完整清单见 [README](../README.md)，门禁与签名规则见 [Testing](Testing.md)。

## 2. 分层与数据流

```text
SwiftUI View
  → TimeTrackerStore facade / feature action
  → domain command
  → repository
  → SwiftData model context
  → domain store snapshot / read model refresh
```

`TimeTrackerStore` 是 `@MainActor @Observable` UI 门面，不是所有业务规则的最终归属。新功能先判断规则属于：View（布局/可访问性/展示）、Store（业务/UI 可观察状态、编排、导航、精确失效；不保存跨 scene 的 sheet 草稿或瞬时弹窗队列）、Command（一次明确可测试的业务写入）、Repository（模型查询与持久化细节）、Service（跨实体计算、同步、导入导出、系统集成）。视图不得直接复制领域判断，也不得绕过命令与仓储执行长期写入。

共享样式与控件只在至少两个 feature 使用（或明确即将使用）时才进入 `SharedUI`（second-caller 规则）；单调用方的一次性布局、行内容或卡片留在所属 feature 内。共享任务行/计时动作/Settings 行的既有所有者见 [ProjectMap](ProjectMap.md)。分层不等于每个文件都已单一职责拆分；仍较集中的文件列在 ProjectMap 的职责集中度表。

`Features/Inspector`、`PhoneChromeViews`、`SettingsSectionsViews.swift`、`TimeTrackerServices.swift` 等已删除代码的名字不是当前模块或扩展点。

## 3. 持久写入与 refresh

`TimeTrackerStore.perform` 与 `SystemActionCommandHandler` 用 `ModelContext.performAtomicMutation` 包住一个用户动作：命令/仓储内部的 `saveAfterMutationStep` 在独立调用时立即保存，在外层 transaction 中延迟到最后统一 `save()`；动作或最终保存抛错会 rollback 整个 unit of work。当前 scene 提交后只刷新自身必要 read models；这一步失败不能撤销已保存事实，因此 `perform` 仍返回成功并可展示“已保存但重新载入失败”。Feature 只有在 mutation 成功后才能清理 transient success/failure 与 selection/editor 状态。

每个持久 outer save 显式设置稳定的 `TimeTrackerHistoryAuthor`（普通 scene/fresh coordinator `.localMutation`，sync restore `.syncReconciliation`，启动 migration/seed `.bootstrapMaintenance`），嵌套 primitive 继承外层 author。Scene、App Intent 与 Watch 把同一 command outcome 的 exact `StoreDomainEvent` 交给 `SystemActionPostCommitEffects`，由 store-scoped `CommittedMutationSystemProjectionScheduler` 异步投影；调用方不等待投影 I/O，投影失败只保留 lane 诊断/重试，不写共享 `errorMessage`，也不改变业务结果。`StoreMutationBroadcaster` 让同进程其它 scene 只刷新 read models（不记录 snapshot、不重复副作用）。投影 request 显式区分 `.localCommit`/`.startupCatchUp`/`.surfaceCatchUp`；启动固定发送 `.startupCatchUp + .fullSync`。

Keychain 不能加入 SwiftData ACID transaction：LLM 配置先记住旧密钥，把普通偏好批量成一次 SwiftData 保存，提交失败时尽力恢复旧密钥并单独报告补偿失败。任务、账本等 UI selection 也只在 `didSave` 后更新。

### 计时与账本领域

`TrackedTimePolicy` 是所有已记录时长的唯一读侧边界（`boundedEnd = min(endedAt ?? now, now)` 再裁到半开区间）；统计、gross/wall/overlap、Analytics、Forecast、timeline、cache、repository range query 与 rollup 都必须调用它，不得在 view/formatter 中直接用 `endedAt ?? Date()`。

`Services/TimeTracking/TimerAdmission*` 是统一计时协调器的纯值语义边界：只消费已 LWW/canonical 的 active snapshots，输出稳定 start/stop plan；它不解决跨 context/进程竞态——生产 writer 必须经过 store-specific lock + fresh context。`TimerRapidRestartPolicy` 定义普通 stopwatch 的严格 `<60s` 时间/source/task 条件，SwiftData 关系与 mutation 由 `SwiftDataTimeTrackingRepository+RapidRestart` 在 store-scoped Start 内处理（新 active segment ID、复用原 singleton session、墓碑旧 segment、确认 gap 内无其它可见工作、mutation timestamp 跨过 CloudKit 毫秒并支配 future-skewed winner）。

`TimerStoreScope`/`StoreScopedTimerMutationLock`/`StoreScopedTimerMutationTransaction` 是事务底座：持久 store 用解析既存祖先符号链接后的 canonical URL，内存 store 复用显式 UUID；transaction 先取得 store lock，再创建 fresh `ModelContext`、关闭 autosave、用一次 `performAtomicMutation` 保存或回滚，最外层 save 设置 history author。锁实现复用 `PathFileLockRegistry`/`PathProcessFileLock`（递归锁 + 跨进程 `flock`），锁文件是 store 同目录 `.timer-mutations.lock`。锁内只做授权/fresh fetch/plan/mutation/commit；timer、Pomodoro、segment 编辑、手工时间、task lifecycle/draft、category、checklist、recurrence、countdown、同步偏好、Inbox、AI workspace apply、设备本地 LLM Keychain 更新都在此域。`allowParallelTimers` 必须由 `TimerAdmissionPreferenceResolver` 在此 fresh context 内解析，调用方不得传入缓存 Bool。

日边界必须由 `Calendar.startOfDay` / `date(byAdding:)` 计算；`LedgerBucketCache` key 包含当前 Calendar 真实裁剪后的起止时刻，局部失效只删除与变更区间相交的 bucket。并行计时下 gross = 片段之和、wall = 区间并集、overlap = `gross - wall`；`AnalyticsStore+Overlap*` 文件族以 end-before-start sweep 计算并发度，参与任务用持久 task UUID 去重，excess 必须守恒，只展示部分窗口时同时公开隐藏窗口数与 excess。

`LedgerStore` 初次加载建立 segment ID/day/active/time-sensitive/array-index/session index，带日期范围的 mutation 只查询替换相交 segment 并输出 `LedgerSegmentChange`；range read 分离统计 cutoff 与真实 wall-clock reference（只有真实 clock rewind 才全量重评）。`LedgerStore+RecordIndexes` 为每个任务维护最近 8 条 segment ID。CloudKit 分批 materialize 时 `TimeTrackerStore+LedgerRelationshipVisibility` 只发布 task/session 关系完整的 segment。

## 4. 当前平台 UI 合同

- Compact shell：窗口宽度低于 720 pt 或 size class 明确 compact 时使用五个系统 `Tab`（Today、Inbox、Tasks、Focus、Analytics）；Settings 从 Today 工具栏经 scene 的 `AppPresentationRouter` 打开，关闭后保留原 tab、任务路由与滚动上下文。Tab 切换完全用系统过渡，不给每页叠加重复 entrance。
- Regular shell：宽度 ≥720 pt 且非 compact 时 iPad 与 macOS 共享 `NavigationSplitView`；`AppRootView` 的 geometry transform 只输出 `RootLayoutPolicy.WidthBand`，root state 不保留原始宽度。regular detail 只拥有一个外层 `NavigationStack`，`DesktopContentView` 在其中替换主目的地内容并在切换时清空旧页 path；主目的地是平级关系，只允许短 opacity crossfade。不得用设备 idiom、屏幕型号或 `os(...)` 选择这两套布局。
- Motion：应用自有时长统一由 `AppMotion` 提供；披露操作用稳定 identity 的 chevron，不用广域 `withAnimation` 驱动列表高度；Reduce Motion 去掉自定义位移/缩放，滚动/row identity/图表/live resize/系统表面不加装饰性动画。
- Live resize：`DesktopMainView` 的 geometry 先映射到 Equatable `HomeViewportMeasurement`（8 pt 步长，720/800/1056/1236 pt 精确锚点，1236 pt 封顶）再进入 view state；`HomeLayoutPolicy` 是断点与列宽的唯一 owner。
- macOS capability：单实例主 `Window`、独立系统 Settings scene、原生菜单与键盘录制属于真实平台能力；主窗口与 Settings 共享一个应用级 Store，各自持有 scene router。`MacKeyboardShortcutSettings` 是设备本地 observable，注入主场景/Settings/`TimeTrackerCommands`；自定义写 `AppDefaults.shared` 的单个原子 blob，不进 `TimeTrackerStore`、SwiftData/CloudKit 或库的全局 hotkey 存储。`Command-N`/`Command-,` 保持标准命令。
- Scene presentation：每个 scene 一个 `AppPresentationRouter` + 一个 `AppPresentationHost.sheet(item:)`；router 忙时拒绝普通新请求，replace/dismiss 必须匹配当前 presentation ID。主窗口与 macOS Settings 共享 Store 但不共享 sheet。
- Scene feedback：每个 scene 一个 `AppSceneFeedbackRouter` + `AppSceneFeedbackHost`，FIFO 呈现，dismiss 必须匹配当前 feedback UUID；JSON 导出、数据库清理、同步恢复用 throwing 边界，失败只进入发起 scene 的队列。`ContentView` 对未迁移的 Store `errorMessage` 只作临时桥接，新代码不得扩展该共享槽位。
- Settings：五类导航 IA（通用/专注/数据与同步/AI 助手/高级），不提供应用级 appearance override，也不放“手动补录”。所有破坏性动作共用一个 `SettingsDestructiveConfirmation?` 状态与一个 `confirmationDialog`，modifier 必须附着在承载按钮的 `Form`；`SyncRecoverySettingsSection` 空间独立，无冲突时默认折叠，冲突时先显示本机/iCloud 摘要再显示两个方向。`CountdownTitleEditor` 用本地标题草稿，只在保存/Return/失焦时提交。
- Task 生命周期与行语法：任务没有产品层 workflow status；Checklist 是唯一完成/进度语义。普通任务只有 Archive/Restore（`deletedAt` 保留为兼容 tombstone）。`TaskSummaryRow` 是 Tasks/Sidebar/层级选择器/`TaskIdentityRow` 的共享视觉 owner（`.hierarchical` 只显示标题，`.standard` 显示不含自身的父级路径，`.compact` 用完整路径）；`TaskTimerActionButton` 是 Start/Switch/Stop 的共享视觉 owner，命令是独立控件，不能伪装成 metadata glyph 或整行 toggle。`TasksNavigationView` 是唯一任务导航容器，store-owned `TasksRoute?` 是页面事实来源，`selectedTaskID` 是业务选择。
- Task detail/editor：只读优先详情，身份卡显示标题与父级路径但不重复 Running；分析异步载入时只在自身 section 显示 `ProgressView`。编辑通过同一 workspace 的铅笔入口；stale 保存返回 `.saved/.stale/.failed`，Reload/Keep 必须显式确认并替换 session baseline 与 parent candidates。任务编辑器 checklist 删除按稳定 UUID 回调，行内无常驻 More/垃圾桶/上下按钮：iOS 用 `swipeActions(allowsFullSwipe:false)`，全平台用只含 Delete 的 `contextMenu`。崩溃/终止恢复是单个本地草稿镜像：autosave 是持久事实的唯一写入者，重开任务静默恢复最新镜像并只显示一条 inline notice，没有独立恢复管理界面。
- 符号/颜色：任务、分类、checklist、Pomodoro 计划共用 `SymbolColorPickerButton`/`SymbolColorWell`。iOS 复用 BlossomColorPickerCore 默认 layout 并按 `44 / BlossomConstants.petalSize` 等比放大；macOS 由所属颜色 well 的真实 `NSView`/`NSWindow` 换算屏幕坐标，不得用 `NSApp.keyWindow` 或复制花瓣几何。任意有效 sRGB 输入规范化为六位持久值；前景对比由 `TaskColorPalette.contrastingForegroundColor` 按实际背景选择。
- Analytics：`AnalyticsCategory.reviewCategories`/`exploreCategories` 显式定义首页顺序且对 `allCases` 完整无重复；category 用 typed `NavigationLink(value:)`/`navigationDestination`。loading presentation 把 snapshot 与 request 原子发布，跨周期冷缓存保留 section 壳但 redacted/禁用/隐藏旧语义，刷新指示器占用固定布局槽。`AnalyticsRefreshPlan` 只在 active scene 安排下一个分钟/本地日边界，不得恢复整页 `TimelineView`。Heatmaps 是独立 typed destination，复用 Today Heatmap 投影与 Settings 范围。
- Pomodoro：Plan 与 Task 是可见的原生 `Menu`（任务表用可搜索 sheet，只改局部 task ID，不启动计时、不改全局 selection）；单一主操作紧跟选择器，计划摘要同时公开 focus/短休/长休/轮数。`TimelineView` 只包围 `PomodoroActiveCountdownView`；停止确认固化发起时的 run ID。
- iOS 不设置 `CADisableMinimumFrameDurationOnPhone`；刷新率交给系统，用 Release trace 与真机验证流畅度。

## 5. 持久化、CloudKit 与迁移

当前 schema 为 V14（版本标识 `1.13.0`）。V8→V9 lightweight 移除持久 `DailySummary` 派生缓存（保留用户事实，分析摘要从 ledger 在内存重建）；V9→V10 custom 迁移为 Inbox item/suggestion 初始化不透明 context/revision UUID 并保留旧 dismissal；V11 加 durable Inbox capture receipt，V12 持久化 suggestion destination kind，V13 lightweight 加 recurrence/occurrence/quantity 表，V14 为 `ChecklistItem` 加 `sortOrderBeforeCompletion`（V13 及更早解析为冻结快照）。rule/occurrence/generated child/quantity goal 使用冻结 deterministic UUIDv8；四张 V13 snapshot table 为 optional（缺 key=未知，显式 `[]`=清空）。`TaskNode.statusRaw` 按 V4 兼容合同 round-trip，不新增 migration。迁移步骤与 schema 规则见 [Architecture](Architecture.md)。

磁盘兼容 fixture 覆盖 V4 分类迁移、V8 `DailySummary` 移除、V9 Inbox suggestion identity/dismissal、V11→当前 suggestion destination、V12→V13 task progress。它们真实关闭旧容器、打开磁盘 store 并核对事实，但不是已发布版本生成、带固定 hash 的不可变历史 artifact——后者仍是明确缺口（应从发布 tag/当时工具链生成无敏感数据的 SQLite bundle 并附 SHA-256 manifest）。

CloudKit 模式与纯本地模式共用业务模型，容器与同步状态不同；紧急内存 fallback 只用于保持可诊断，绝不描述为持久存储。同步刷新由 `NSPersistentStoreRemoteChange` 与 `eventChangedNotification` 驱动，首个通知建立固定 350 ms 截止时间、后续合并进 batch（不取消后推计时器）；没有常驻 5 秒轮询。`AppCloudSync.enabledKey` 是设备本地启动配置，不进 `SyncedPreference`/快照/导出。Settings 同步状态用 typed `SyncActivityOutcome`，只有带结束时间且 `event.succeeded` 的 import/export/setup 在本机 refresh 与冲突处理都成功后才是 `.succeeded`。

`SyncConflictService.swift` 只保留 bootstrap 与 prompt 组装；扩展文件分别拥有 local mutation、Cloud import/export、recovery/resolution、state manifest/lock/locations、slot、filtered export encoding；`SyncDataSnapshot` 加 capture / preflight（结构 + 语义）/ 分域 restore / 版本化 record DTO。同步状态锁、128/64 MiB 上限、slot manifest、`prompt()` throwing 边界与 `pendingConflictID` CAS 见 [AgentDecisions](AgentDecisions.md) AD-023，恢复门控见 AD-142。`DurableLocalFile`/`PathFileLock` 只负责文件系统提交（普通文件、拒绝符号链接、原子 rename + 目录同步、有界 `.TimeTrackerQuarantine`），调用方必须完成 payload 大小/版本/时间/语义预检并传入稳定 durable root。

演示与测试数据：`TIMETRACKER_AUTOMATIC_DEMO_DATA_MODE` 默认 `off`；Debug 才允许明确 override，启用后容器改用本地无 CloudKit 的 `TimeTracker-Demo.store`，UI tests 用独立内存 container。测试进程必须通过 `AppDefaults.shared`/`AppRuntimeEnvironment` 隔离，绝不直接使用 `UserDefaults.standard`。

## 6. 偏好与秘密

普通偏好经 `SyncedPreference` 保存并可同步；`Models/PreferenceJSON.swift` 与 `PreferenceCommandHandler` 定义写边界（单项 256 KiB，整批预检后一次 `performAtomicMutation`，legacy 超限值跳过而不是保存 `null`）。设备启动配置与秘密是例外：iCloud enablement 只在当前设备 `UserDefaults`；LLM API key 写入 `LLMCredentialStore`（AfterFirstUnlockThisDeviceOnly、不同步），同步快照与 JSON 导出自带敏感键过滤，遗留明文只用于一次迁移后清除或软删除。“清空全部数据”同时清除密钥与设备本地自动建议同意。

`DeviceIdentity` 是本机随机平台前缀 UUID，只用于同步 tie-break 与 mutation metadata；只复用“当前平台前缀 + 大写连字符规范 UUID”的完整值，其余随机重建并回写。Required Reason API 按 target 真实 UserDefaults 边界声明（主 App `1C8F.1`+`CA92.1`、Widget `1C8F.1`、Watch `CA92.1`）；Live Activity 当前无独立 manifest，Archive 时必须核对合并结果。

## 7. 系统集成

**App Intents**：只解析系统输入并复用领域命令；新增意图需参数验证/歧义处理、三语本地化、无匹配/权限/存储失败测试，以及与主应用相同的幂等/冲突规则。实体查询排除 tombstone 与归档任务；写入必须走 store-scoped coordinator 的共享 lock + fresh context，不把 scene-less `ModelContext` 当并发边界。提交后由 `SystemActionPostCommitEffects` 把 exact events 交给 queued scene broadcaster 与 projection scheduler，然后返回。五个意图（Add Inbox Item、Start/Stop/Get Running/Stop All Timers）的能力矩阵见 [Shortcuts](Shortcuts/README.md)。

**Live Activity**：只读状态投影，attributes 小而稳定，extension 不直接写 SwiftData/iCloud。锁屏与 expanded Dynamic Island 共用唯一 `LiveActivityTimerRow`；锁屏沿用 Today/Now 层级，expanded 普通字号只显示图标/标题/elapsed，不显示路径/附加计时数量/停止控件；点按只打开 Today，停止由 Today 行完成。文本按 Unicode 边界投影到受限字段，stale 状态明确。

**Watch**：状态 owner 是同一个 `WatchAppStore` 类型，按 extension 文件拆开（base observable/恢复、Commands queue/timeout/persistence、Connectivity transport/payload/freshness、SessionDelegate callbacks）。每个 `WatchTimerCommand.id` 是幂等键，新命令与恢复命令走 durable `transferUserInfo`，可达时再用 `sendMessage` 加速；typed terminal result（success/duplicate/missingTask/missingSegment/invalid/failed/timeout）durable 回传，timeout 是 Watch 本机 20 秒等待。`WatchCommandProcessor` 在 mutation 前校验 DTO 与时间边界（命令最多 30 秒、允许最多 5 分钟未来偏差），过期/非法命令返回 invalid 且不写 receipt/ledger。三页分页、Quick Start/All Tasks 排序与上限见 AD-119 与 AD-004；payload 常量表是 `WatchTransportLimits`。

**Deep link**：`AppDeepLinkRouter` 只接受 `timetracker` scheme、最长 2,048 bytes、无 credential/port/fragment 的白名单路由并校验 UUID；`PendingDeepLinkQueue` 容量 16、按语义去重、满时丢最旧、配置成功后 drain、scene 消失清空。带 `taskID` 的停止链接只停该任务活动 segment，目标已停时 no-op，不回退停止其它并行计时。`WatchCommandRouter` 用弱 store 引用选择最近 active scene，最后注销时移除进程级 bridge closure。

**Widget**：从版本化共享快照读取，区分容器不可用/缺失/损坏，不把所有失败显示成“没有计时”。容器级 `.widgetURL` 永远是 Today；启动任务必须由显式 `Link(destination: WidgetDeepLinks.startTimer(...))` 发起。`WidgetSnapshotLimits` 是 consumer/store 唯一上限表（title/path/style 硬上限 4 KiB/16 KiB/256 UTF-8 bytes、最多 5 分钟未来偏差、summary/active-age 上限、唯一 ID）；`SharedWidgetSnapshotStore.save` 写入前拒绝非法/超限快照，`loadResult` 在 decode 前后双重验证，失败返回 `.corrupted`。elapsed 只在 `.current` 用 system timer，`.stale`/`.clockAdjusted` 冻结在 `generatedAt`。

## 8. AI 服务

`LLMService` 面向用户配置的 OpenAI-compatible endpoint：远程必须 HTTPS，HTTP 仅限 `localhost`/`.localhost` 与数值解析确认的 `127.0.0.0/8`/`::1`；带 Authorization 的 redirect 只允许同 scheme/host/有效端口；生产 transport 用 ephemeral session（禁用 cache/cookie、资源 60 秒、2 MiB 实际字节上限、headers 阶段拒绝非 2xx/声明超限）；模型发现逐项解码、只保留升序前 256 个唯一有效 opaque model ID。日志与错误不得打印密钥或完整敏感请求。精确字段与安全边界见 [PrivacyAndSecurity](PrivacyAndSecurity.md)。

Settings 用 `LLMConfigurationDraft`：endpoint/API key/模型/思考强度编辑先留在 sheet，“测试连接”只读模型并验证 credential fingerprint、不持久化，只有模型有效时才能“保存”；保存时四项由 `PreferenceCommandHandler.set(values:)` 一次 SwiftData 提交，API key 的 Keychain side effect 用旧值补偿恢复并单独报告失败。自动建议是默认关闭、设备本地的第二开关，不进 CloudKit/JSON。`LLMReasoningEffort` 只允许 DeepSeek 官方 `high`/`max`；三条生产 service 对 DeepSeek V4 显式开启 thinking、发送所选 effort、省略 temperature，workspace 工具会话省略 `tool_choice` 并把每轮完整 `reasoning_content` 原样带回，其它模型不发送这些专属字段。effort 是 request identity 的一部分，切换时取消旧请求。

任务计划链：`LLMTaskWorkspacePlanningService` → `AITaskWorkspaceOverlay` → `AITaskWorkspacePlanGeneratorViews` → `StoreScopedAITaskAtomicMutationCoordinator` → `TimeTrackerStore+AITaskPlanCommands`。捕获/Apply 在共享锁 + fresh context 中做完整 workspace CAS（见 AD-132）；工具只改内存 overlay，schema 全部属性 required 且 `additionalProperties: false`，无效参数返回零变更 `{ok:false}`，未知工具/重复 call ID/混合 finalize 显式失败；只有 `finalize_plan` 结束生成。Finalize 生成 baseline→overlay 只读 diff，预览显示 create/update/archive/delete/reuse、完整路径与 before→after，`Apply N Changes` 是唯一提交入口，破坏性影响用原生确认；Task removal 只 Archive。已替换的 create-only `LLMTaskPlanService`/`saveAITaskPlan` 链不得恢复。

## 9. 常见改动方式

- **新增持久字段**：先判断事实/派生/缓存 → 更新 schema 版本与迁移计划 → 更新真实旧 store fixture 与 round-trip 测试 → 检查 CloudKit 可选性与默认值 → 更新导出格式、隐私文档与版本说明。
- **新增界面**：保持 `body` 可读，把可测试规则移入 command/service；用稳定 identity 与精确 observation；先验证正常字号的系统导航/控件/键盘/窗口与平台 HIG，保留 Dynamic Type/VoiceOver 基础语义；添加行为测试（不新增源码字符串扫描）；在 iPhone/iPad/Mac 对应尺寸验证并检查深色模式与 Reduce Motion。
- **新增导出或恢复格式**：导出不等于备份。可称“备份”的功能至少需要格式版本、校验和、导入预检与冲突策略、事务写入或可回滚 staging、多版本 fixture 与恢复等价性验证；导出边界必须 fail closed。
- **新增系统入口**：复用领域命令与 store-scoped coordinator，提交后只 enqueue exact events，不创建临时 facade/context，也不同步等待投影。

## 10. 代码注释与文档规则

- 对公共领域类型、迁移策略、数据安全边界和非直观算法添加 Swift DocC 注释；注释解释原因、不变量与失败模式，不复述语法。
- 当前行为写入 UserGuide/CodeGuide/Architecture；决策与权衡写入 AgentDecisions；一次性审计与验证事实写入提交该工作的 commit/PR；跨会话实现记忆只服务进行中的工作并随收口清理；未来工作只写入计划文档并明确状态。
- 当前生产 Swift 文件尚无系统性的三斜线 API 文档，这是需要持续偿还的债务。

## 11. 签名与依赖边界

签名与系统能力规则（`CODE_SIGN_STYLE = Automatic`、team `LT98S43NKA`、禁止绕过、APS 规范键 `aps-environment`、CLI 优先、模拟器证据边界）的权威出处是 [Testing](Testing.md)。

第三方依赖默认不新增；经审查的例外是 MarkdownView `4.1.7`（任务备注证据态）、BlossomColorPicker 固定 revision `9a1ee3df309e37ae271362818dcdfdb072ea9611`（MIT、无传递依赖）、KeyboardShortcuts `3.0.1`（macOS 菜单录制，经本地 `MacKeyboardShortcuts` 条件包适配）。依赖 revision/version、`Package.resolved` 与 [AgentDecisions](AgentDecisions.md) AD-117 必须同步；移除 BlossomColorPicker 只删 package 引用与 `SymbolColorWell` 适配，六位 sRGB 数据不需迁移。

## 12. 相关文档

- [用户操作手册](UserGuide.md)、[架构](Architecture.md)、[项目地图](ProjectMap.md)
- [Agent 决策文档](AgentDecisions.md)、[隐私与安全](PrivacyAndSecurity.md)
- [本地化](Localization.md)、[测试](Testing.md)、[Versioning](Versioning.md)
