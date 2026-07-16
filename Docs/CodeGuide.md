# TimeTracker 代码文档

状态：当前实现说明
校对日期：2026-07-16

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

本轮已完成以下关键职责拆分：

- Sync conflict：`SyncConflictService` 只保留 bootstrap/prompt；local mutation、Cloud import/export、recovery/resolution、state persistence、file lock/locations、export encoding、snapshot capture/分域 restore、snapshot state 与分域 record DTO 分文件。
- Analytics：root landing page 与 `AnalyticsCategoryDetailView` 分文件；category 使用 typed `NavigationLink(value:)` / `navigationDestination` 路由。首页顺序由 `AnalyticsCategory.reviewCategories` 和 `exploreCategories` 显式定义，两组合并必须对 `allCases` 完整、无重复；overview row、metric/detail list、period control 与 store 的 metrics/breakdowns/overlap/task snapshot 各有所有者。分布图切片值由 `AnalyticsDistributionSlice.swift` 持有，分组聚合与 “Other” 折叠规则由 `AnalyticsGroupBreakdownPresentation.swift` 持有，分段宽度算法由 `AnalyticsGroupBarLayout.swift` 持有；Today 小时活动的跨小时共享尺度与 task stack 守恒算法由 `HourStackLayoutEngine.swift` 持有，视图文件只保留组合与展示。
- Pomodoro presentation：`PomodoroPageLayout` 从外层 `GeometryReader` 的有限 viewport 派生唯一布局分支，负责宽屏双栏、窄屏/辅助字号单栏，并为 iOS 浮动标签栏保留滚动末端余量；禁止用嵌套 `ViewThatFits` 同时测量整棵 primary/secondary 子树。setup composition、空状态、参数控件、Plan/Task 选择、timer face、active composition、active countdown、有限 timeline schedule 和 ledger 各有所有者。页面容器不承担 deadline 或账本写入。
- Settings：display/timing、Pomodoro、countdown、sync、data、actions、bindings 与 support 分文件；`SharedUI/Components` 中的 foundation/value row、action/destructive label、text/number input、presentation modifier 和 sync feedback 也各有所有者。
- Task Detail：canonical router 与 identity/checklist/overview/analytics/navigation/record sections 分文件。
- Ledger infrastructure：Cloud startup、persistence safety、timer DTO、aggregation、formatting、device identity 与 summary 分文件。
- Facade lifecycle：`TimeTrackerStore+Configuration.swift` 只负责首次配置、repository-only 系统表面组装和 post-commit surface refresh；`TimeTrackerStore+Lifecycle.swift` 负责 refresh、mutation 边界、恢复动作和通用错误，不再把启动迁移/seed/observer 安装混在同一大扩展。
- Widget：entry/provider/config、active-timer family layouts、supplementary/error states 与 deep-link/localization/color support 分文件。
- Watch：dashboard orchestration、完整任务列表、失败问题页、timer rows、status/error/empty states、command presentation index 与 color support 分文件；`WatchAppStore.swift` 保留 observable state/安全恢复，`WatchAppStore+Commands.swift` 负责 queue/timeout/persistence，`WatchAppStore+Connectivity.swift` 负责 transport/payload/freshness，`WatchAppStore+SessionDelegate.swift` 独立承接 WCSession callbacks。
- Ledger/Rollup index：ordered flat segment array mutation 独立到 `LedgerStore+FlatSegmentIndex.swift`；增量 rollup 的 scoped mutation/replacement 独立到 `RollupIncrementalIndex+Mutation.swift`。
- Today：`HomeViews.swift` 只组合宽屏优先级，`PhoneHomeSections.swift` 组合紧凑屏顺序，各 section 文件拥有具体内容；`TodayHomeContent` 在一次组合中集中生成 active/timeline、Quick Start、forecast 和 countdown 读模型，避免各 section 重复查询与分组。

分层不等于所有文件都已完成单一职责拆分。仍较集中的大型行视图已在 [CodeRefactorPlan](CodeRefactorPlan.md) 逐项列出；不要把已经完成的 Home 组合拆分重新列为“未来工作”，也不要用机械行数替代职责审核。

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

视图不应直接复制领域判断，也不应绕过命令与仓储执行长期写入。计时文本用 `TimelineView` 做局部刷新；不得为了时钟显示让整个 facade 每秒发布一次状态。Today 的活动计时行只让正在运行的行按秒刷新，已结束时间线保持静态；摘要每 30 秒刷新。`TodayHomeContent` 的数组在根组合处构造一次，Quick Start 去重并保留稳定任务 ID。Today 指标先规范化一次候选 segment，再以单个循环同时裁剪今日和前一日、累加 Gross；两组区间各自合并后得到 Wall。需要重叠时间时由 Gross 与 Wall 的差得到，不再扫描 segment。不得让每张卡重新遍历完整账本。

`TimeTrackerStore.perform` 和 `SystemActionCommandHandler` 使用 `ModelContext.performAtomicMutation` 包住一个用户动作。命令/仓储内部的 `saveAfterMutationStep` 在独立调用时立即保存，在外层 transaction 中延迟到最后一次统一 `save()`；动作或最终保存抛错会 rollback 整个 unit of work。提交之后的 read-model refresh 或 sync snapshot 失败不可能撤销已保存事实，因此 `perform` 仍返回成功并展示“已保存但重新载入失败”。Feature 只能在 `perform == true` 后清理 transient success/failure 状态。Keychain 不能加入 SwiftData 的 ACID transaction：LLM 配置先记住旧密钥，将三项普通偏好批量成一次 SwiftData 保存，并在提交失败时尽力恢复旧密钥；恢复本身失败必须单独报告。任务、账本等 UI selection 也只在 `didSave` 后更新，因为它不会由 `ModelContext.rollback()` 自动恢复。

### 当前平台 UI 合同

- iPhone：五个系统 `Tab`（Today、Inbox、Tasks、Focus、Analytics）；Settings 是 Today 导航栈中的目的地。`nav.focus` 是 iPhone tab、iPad sidebar、macOS sidebar 与 Focus 页面标题的统一导航文案；`nav.pomodoro` 仍只描述账本来源、设置和分析中的 Pomodoro 领域，不得拿它恢复平台间不一致的导航标题。
- iPad：设备 idiom 稳定选择 `NavigationSplitView` 侧边栏与详情；分屏、Stage Manager 或旋转造成的 compact width 只由该 split view 折叠列，不切换成 iPhone 根导航，因此当前目的地、sidebar selection 和详情状态不会随窗口宽度丢失。从侧边栏或任务列表选择任务会打开同一个 `TaskDetailView`。
- macOS：单实例主 `Window` 承载 `NavigationSplitView` 工作区；独立系统 Settings scene、主窗口和 Settings 共享一个应用级 `TimeTrackerStore`，避免复制 CloudKit observers、自动 AI 建议与系统表面同步。
- Today：iPhone 使用 `List`，顺序为 Now、Overview、Quick Start、Timeline、Forecast、Countdown。iPad/macOS 共享 `TodayHomeContent`；详情 viewport 扣除两侧 page padding、再受 1180 pt 上限约束后才得到实际内容宽度。该宽度达到 1000 pt 且存在辅助内容时，Quick Start/Timeline 进入主栏，Forecast/Countdown 进入 360 pt 辅助栏，否则保持单栏。Today 只有一个当前计时入口：无活动计时时为 Start Timer；有活动计时时根据并行偏好显示 Start Another Timer 或 Switch Timer。这个主动作在 Now 内容流中保留可见文字。`TimerPickerCommandPolicy` 以 `.start`、`.startAnother`、`.switchTimer` 固化入口模式，并把任务选择命令限定为开始、切换或 `alreadyRunning`。运行中任务只作为状态行出现，停止必须经过独立 Stop 按钮；选择行不得根据运行状态暗中改成停止命令。只有成功开始或切换后才关闭选择器，停止与失败都保留当前上下文。通用新建任务只存在于任务域和任务选择器，不与计时主操作竞争。
- Task Detail：只读优先的 `List`，铅笔按钮再打开编辑 sheet；清单完成状态可直接切换。
- Task rows：普通/紧凑布局与 Accessibility 布局必须表达同一组事实。辅助字号按标题、完整路径、状态/运行中、已工作时长、清单/预测、子任务数纵向排列，不得只留下标题与异常徽章。`TaskManagementRowAccessibilitySnapshot` 是任务详情按钮的单一 VoiceOver 投影，依次保留状态、去重后的路径、运行状态、已工作时长、清单、预测与子任务数；不要用 `accessibilityRepresentation` 或忽略 children 后只补部分字段。
- Task availability：`TaskTrackingAvailabilityService` 一次线性扫描分别产出 `visibleTaskIDs` 与 `trackableTaskIDs`。归档/删除分支不可见；完成分支仍可浏览详情与历史，但自身和后代不能接收新工作，直到 `reopenTaskForWork` 把路径上的完成阻塞项一起恢复为 active。Today、Quick Start、Pomodoro、手工记录、Inbox 建议、App Intent、任务创建/移动与任务动作共用该判定；归档或完成活动子树前先停止计时，历史 segment 编辑可保留原任务。
- System routing：`AppDeepLinkRouter` 严格解析 URL；`PendingDeepLinkQueue` 只缓存初始化前已经通过相同验证的语义动作，按动作去重、先进先出且最多 16 项。`WatchCommandRouter` 用弱 store 引用选择最近活跃 iOS scene，并在最后一个 scene 注销后移除进程级 bridge handler。
- Settings：五类导航 IA，不提供应用级 appearance override。`SyncSettingsSection` 只拥有开关、状态和日常检查/刷新；`SyncRecoverySettingsSection` 空间上独立展示会覆盖一侧数据的恢复命令，冲突时先显示本机与 iCloud 摘要，按钮与确认都必须使用破坏性语义和明确的替换方向。有 pending conflict 时两个方向都调用 `resolveSyncConflict`，与全局冲突对话进入相同的冲突解析边界；只有无冲突的手动恢复才调用 force-upload/current-cloud reset。所有 Settings 破坏性动作共用一个 `SettingsDestructiveConfirmation?` presentation state 和一个 `confirmationDialog`，而且 modifier 必须附着在实际承载按钮的 category `Form`；不得在根列表串联多个 presentation modifier，或把 modifier 放到 compact `NavigationLink` destination 之外。`CountdownTitleEditor` 持有仅属于界面的标题草稿，`CountdownTitleDraft` 负责脏状态、外部刷新合并和错误呈现；只有保存按钮、Return 或失焦会调用 `CountdownCommandHandler`。命令先规范化并验证标题，再执行 SwiftData 变更，因此逐字符输入不会产生数据库写入或半成品同步事实。日期仍通过独立动作即时保存。
- Pomodoro：下一次专注是唯一主流程，旁边或下方展示最近记录。Plan 和 Task 是两个可见的原生 `Menu`，Task 使用可完整换行的派生标题路径区分同名项，不能用固定两行省略号抹掉末级任务名；单一主操作紧跟选择器，计划摘要随后同时公开 focus/short break/long break/rounds。section 测试标识只能属于标题或显式容器元素，不得从整张卡片覆盖 Menu/Button 自身标识；没有点击标题/计时器的隐藏选择逻辑。活动 break 在到期前提供“跳过休息”，到期后显示“开始下一轮专注”，两者都调用同一个显式 resume 命令；Task 当前不可工作时 UI 禁用入口。停止确认保存发起时的 run ID，active run 被替换后必须撤销旧确认，不能对“当前任意 run”执行破坏动作。
- iOS 不设置 `CADisableMinimumFrameDurationOnPhone`；刷新率与帧调度交给系统，流畅度用 Release 截图/trace 和真实设备观察验证，不靠 Info.plist 强制覆盖。

## 4. 核心领域

### 时间事实

TimeSegment 是计时事实来源。它不是“写入后永不可改”的 event：用户可以更正或软删除错误记录；这里的“事实来源”指所有派生统计、当前运行状态和时间线必须从 canonical segment 与明确规则重算，缓存不能成为第二真相。

`TrackedTimePolicy` 是所有已记录时长的唯一读侧边界。对明确的 reference `now`：effective end 为 `min(endedAt ?? now, now)`，再与查询的半开 `DateInterval` 取交集；`startedAt >= now` 或无正区间的记录贡献零。统计、gross/wall/overlap、Analytics、Forecast、Pomodoro elapsed、timeline layout、repository range query、cache signature 和 rollup 都必须调用该 policy，不得在 view/formatter 中直接使用 `endedAt ?? Date()`。

Analytics 不能把一个历史周期压缩成单个“结束前一秒”的伪 `now`。`AnalyticsPeriodEvaluation` 显式携带三项：选中的 Calendar `interval`、用于 `TrackedTimePolicy` 裁剪的 `cutoff`、用于识别真实系统时钟回拨的 `clockReference`。当前周期的 cutoff 是真实墙钟；已完成历史周期的 cutoff 必须精确等于半开区间的 `end`，未来周期的 cutoff 是 `start`。Ledger 的 range query 分别接收 `evaluatedAt` 和 `clockReference`；只有后者早于 index evaluation date 才能触发全库回拨候选，禁止把历史 cutoff 当作时钟回拨。

`AnalyticsComparisonWindow` 是环比统计的唯一窗口定义。当前或未来周期使用 `.matchedProgress`：current 从周期开始裁到 cutoff，previous 按相同日序与本地时分秒映射，不能用固定秒数位移；DST 保留本地钟点，长月映射到短月时在 previous period end 截止。cutoff 精确等于已完成周期 end 时使用 `.completePeriods`，比较两个完整周期。gross、wall、指标脚注和 insight 必须消费同一个 window/basis，禁止 UI 自行推断“上一范围”。

Analytics 月导航先从所选月份的 `Calendar` interval start 位移到目标月，再把根页面持有的 `AnalyticsMonthNavigationAnchor` 映射回目标月。锚点保存原始本地日号和时分秒；目标月缺少该日时只对当月结果 clamp 到月末，不修改锚点，所以 Jan 31 → Feb 28/29 后仍会得到 Mar 31。该状态由 landing 与 category detail 共用，也必须跨 `ViewThatFits` 布局分支保持一致。直接选日期、切换 range、回到今天或进入当前月会清除旧锚点；目标为当前月或未来月时返回真实 `liveNow`，不得停在未来。

本地 `addManualSegment` 和 `updateSegment` 在 repository 写入前拒绝未来结束时间或未来 active start，返回 typed `TimeTrackingRepositoryError.futureTime` 与三语 `segment.error.timeNotFuture`。CloudKit、导入和旧 store 可能已含时钟偏差值；不为“修复”而删除事实，而是在每条读/聚合路径安全裁剪。DST 中的持续时长使用绝对 elapsed seconds，本地日 bucket 边界仍交给 `Calendar`。

SwiftUI 写入表面也共用这一语义：`ManualTimePanel` 和 `SegmentEditorPanel` 的开始/结束 `DatePicker` 上限为当前 `now`，时长与保存 enablement 调用 `TrackedTimePolicy`。`TrackedTimeDisplaySnapshot` 是 Today timeline、Task Detail recent records 和 `DurationLabel` 的共享显示适配层；future-ended 只显示到 `now`，future-only/future-active 在开始前显示 0，已结束的固定 label 不启动每秒刷新。

并行计时是合法状态，因此：

- gross duration 是所有片段时长之和。
- wall-clock duration 是片段区间并集的长度。
- overlap/excess 只能表示 `gross - wall-clock`，不是“发生过并发的墙钟时段长度”。固定 sweep 窗口内有 N 条记录并发时，该窗口贡献 `(N - 1) × wall duration`；所有窗口的 `excessDurationSeconds` 必须严格加总为 overview 的 `overlapSeconds`。

`AnalyticsStore+Overlap` 文件族先消费已经按选中周期与 cutoff 裁剪的 `AnalyticsBoundedSegment`：`AnalyticsStore+Overlap.swift` 入口负责规范化，`AnalyticsStore+OverlapSweep.swift` 以 end-before-start 的同边界 sweep 计算并发度，`AnalyticsStore+OverlapParticipants.swift` 维护稳定参与者解析与最小堆，`AnalyticsStore+OverlapMaterialization.swift` 负责整数秒分配和最终排序。参与任务使用持久 task UUID 去重，标题只用于展示；同一 task 的片段在同一边界替换且并发度不变时可以合并相邻窗口，参与集合或并发度变化时不得合并。`OverlapAnalyticsPoint` 明确分开墙钟窗口、并发 segment 数、唯一 participant 数和 excess；列表只展示 excess 最大的前几个窗口时，必须同时公开隐藏窗口数与隐藏 excess 总量，不得把墙钟跨度标成 overlap。整数秒展示使用确定性的余数分配与 overview 对齐，避免亚秒边界破坏守恒。

改变统计算法时，必须覆盖边界相接、完全包含、跨日、时区与夏令时、多任务重叠等案例。

日边界必须由 `Calendar.startOfDay` 与 `date(byAdding: .day, ...)` 计算，不能用固定 `86_400` 秒代表一个本地日。Forecast 的“活跃天数”和 Analytics 的 day bucket 都遵守该规则。`LedgerBucketCache` 的 key 包含由当前 Calendar 计算并真实裁剪后的起止时刻；局部失效只删除与变更区间相交的 bucket，避免 DST 或同日不同子区间命中错误缓存。

### 任务和组织结构

Task、TaskCategory、ChecklistItem 和 InboxItem 形成用户组织层。树形视图需要稳定身份，ForEach 应使用持久标识符，不得依赖数组索引或可变标题。

Inbox capture 以 `TimeTrackerStore.addInboxItem` 的 `Bool` 返回值作为 durable commit 契约。`InboxCaptureDraft` 只在返回 true 后清空；空输入、recovery write guard、未配置 context 或保存错误都保留原始草稿。`InboxCaptureRow` 不再自行假定 callback 成功并重复清空 binding。任何新增 quick-capture 表面都必须复用相同语义。

Inbox AI 状态不再只依赖物理 `InboxItem.id`。`suggestionContextID` 是逻辑条目的不透明 UUID，`suggestionRevisionID` 在真实标题修改时轮换，`dismissedSuggestionRevisionID` 只标记当前修订。`InboxSuggestionIdentityService` 用纯 resolution 分开计算内容 LWW winner 与 dismissal identities：只有 exact `(context, revision)` 的 marker 会字段级合并，不能让旧 dismissal 整行覆盖较新的 notes、completion、completedAt 或 sortOrder，也不能跨标题 revision。读取层显式 materialize marker；command 通过身份/文本预检后才在原子 mutation 内 materialize，保证无效 reorder 等路径零写入。command 在驳回、删除、应用、重排或标题修改时同时处理同一 context 的 sibling（包括同 UUID 的不同 SwiftData 对象）与 suggestion。异步建议成功和失败都校验请求时标题与完整 identity；apply 必须从 context 重选 canonical active/ready suggestion，不能信任 UI 缓存对象。禁止用标题、规范化标题或其哈希生成 identity；相同标题的独立条目必须保持独立。每条 item/suggestion 只增加固定数量 UUID 字段，不维护无界驳回历史。

任务状态与可见性是两个维度。`completed` 表示“保留在任务树和历史中、暂停接收新工作”，`archived` 表示“隐藏整个分支”。完成祖先会阻塞所有后代的新 timer、manual entry、Pomodoro、Quick Start、Inbox conversion、App Intent 以及新建/移动目标；既有活动 timer 仍必须可见并可停止。重新开始工作时应恢复从所选任务到根路径上的全部完成阻塞项，而不是偷偷改变后代自身的状态。

归档与删除语义不同。删除任务树会在一个原子动作中先结束该树的活动 Pomodoro 和 timer，再软删除任务；历史 segment/session/run 继续保留。普通 Local、iCloud、local-fallback 和 emergency 生产模式没有跨设备删除确认，因此 `AppCloudSync.allowsPermanentTombstonePurge` 为 false，`DatabaseMaintenanceService` 直接返回 0。只有隔离的 Demo/UI Test store 可物理清理过期 tombstone graph。

`TaskNode.parentID` 是层级权威；`depth` 是可修复元数据；`path` 现在是稳定 canonical record locator `/<task UUID>`，不是祖先 UUID 链，也不是用户可见标题路径。显示路径由 `TaskTreeService` 根据当前标题迭代生成，并限制为最近六级。启动、任务域刷新和同步恢复都会运行 `TaskHierarchyMetadataService`：缺失父节点和循环会确定性地提升为根，随后重算 depth/canonical path。任务移动只更新真正变化的 depth/path，避免同深度跨根移动重写整棵后代。

任务树 UI 不直接从 `body` 重建层级。`TimeTrackerStore.rebuildTaskIndexes` 在 task mutation/refresh 后建立排序后的 `TaskTreeIndexes`、可见性和显示路径；task category 或 assignment mutation 也进入同一个 `rebuildTaskTreeReadIndex` 失效边界。不可变 `TaskTreeReadIndex` 只保存稳定 task/category ID、已过滤的 child buckets、section root IDs、child count 和搜索值，不保存第二份持久事实。只有新 index 与旧 index 在语义上不同才推进 `taskTreeReadIndexRevision`。`TaskTreeProjectionCache` 以该 revision 为失效 token，为展开状态和搜索 query 各保留最多四个 ID/value projection；命中时不得再排序 category、过滤每行 children、遍历祖先标题路径或扫描全部搜索文档。timer、ledger、selection 等无关刷新不拥有这个 revision。row identity 始终是持久 `TaskNode.id`，category section identity 始终来自 category UUID（未分类使用固定 `uncategorized`）；不得把标题、数组位置或展开状态变成 identity。任何直接改变会影响层级、可见性、标题路径或搜索文本的模型写入，都必须完成既有 task/category domain refresh，使上述唯一失效 owner 能发布新 index。

持久实体去重遵循确定性 last-write-wins：先比较 `updatedAt`，同一时间 tombstone 胜过 active row，再以 `createdAt`、`deviceID`、`clientMutationID` 稳定打破平局；没有 mutation ID 的 `TimeSegment` 使用稳定内容键。清理产生的 duplicate tombstone 不得反过来覆盖真正的新 canonical row。所有“只取可见记录”的查询必须先 deduplicate/LWW、再过滤 tombstone，禁止把过滤顺序颠倒。

### 番茄会话

PomodoroRun、关联 TimeSession 与运行状态通过同一命令/仓储变更。`startedAt` 表示当前 focus/break phase 的起点，`phaseDeadline` 由持久状态与计划时长派生；它不是 View 本地倒计时。启动、前台、Pomodoro 页面出现和 deadline task 都会调用幂等 reconcile：过期 focus 在业务 deadline 截断 segment/session，避免后台挂起时间被算作专注；过期 break 不会自动新建 focus，下一轮仍需用户动作。

从 break 继续下一轮 focus 是一次新的计时准入。`PomodoroCommandHandler` 必须在同一个原子 mutation 内重新读取 LWW 后的 canonical 任务树，并用 `TaskTrackingAvailabilityService` 验证 run 的任务及全部祖先仍可接收工作；完成、归档、删除或缺失任务都返回 canonical no-op。该拒绝发生在 ledger admission 之前，不停止其他 timer、不创建 segment、不推进 run，也不发布刷新或同步事件；不能只信任 facade/UI 可能过期的 `trackableTaskIDs`。

`PomodoroCountdownSchedule` 只从当前时间产生到 `phaseDeadline` 为止的有限序列；低频模式使用 60 秒步进，deadline 已过或不存在时只产生当前 entry。`TimelineView` 只包围 `PomodoroActiveCountdownView`，不能重新包住整个页面、最近记录或停止操作。视觉 `ProgressView` 从辅助功能树隐藏，由 timer face 统一朗读阶段、完整任务路径与本地化剩余时长，避免重复语义。

通用 ledger 编辑必须保持 Pomodoro 不变量。编辑活动 Pomodoro segment 会重绑 run 的 task/start；把 segment 关闭会按 deadline 完成或取消 run；删除活动 segment 会 tombstone run/session；删除任务树会结束所有活动 timer，并保留已产生的 Pomodoro 历史。相关写入必须在同一个 `performAtomicMutation` 中提交。

### 增量读模型与缓存

- `TaskTreeReadIndex` 在 task/category/assignment refresh 边界预先保存可见 child ID buckets、分类 section roots、child count、显示路径搜索值与稳定顺序。`TaskTreeProjectionCache` 用 store-owned semantic revision 失效，并把展开树与搜索结果分别限制为四个 LRU entry；SwiftUI `body` 只消费 projection。5,000 节点 operation-count 测试要求一次 fully-expanded miss 对每个可见 task 只做一次 child bucket lookup，同一 revision/key 的重复读取 build count 不增加。缓存只持有 ID/value read model，不能持有 SwiftData 对象或无界 query/expansion 历史。
- `LedgerStore` 初次加载建立 segment ID、day、active、time-sensitive、array-index 和 session index；`LedgerStore+SegmentIndex.swift` 协调 day/change index 与 scoped replacement，`LedgerStore+FlatSegmentIndex.swift` 用稳定 start/UUID 顺序维护 UI 所需 flat array。带日期范围的 mutation 只查询/替换相交 segment 与相关 session，并输出 `LedgerSegmentChange`。range read 把统计 cutoff 与真实 wall-clock reference 分开：历史读取继续命中日期索引；active 和 future-ended closed row 在时钟向前时局部重评；只有真实 clock rewind 才全量重评，因为届时任何历史结束时间都可能重新跨过墙钟。
- CloudKit 可能分批 materialize task、session 与 segment。`TimeTrackerStore+LedgerRelationshipVisibility.swift` 因此保留原始 SwiftData 行，但只发布 task 存在、session 存在且两者 task ID 一致的 segment；不完整/错配行不得进入 Home、Rollup、Analytics、Widget、Watch 或 Pomodoro elapsed。任务或会话稍后到达时，下一次一致性刷新会自动解除隔离，不做破坏性清理。
- `ChecklistStore.refreshTaskScoped` 只替换受影响 task 的 items/visuals，并同步维护 facade bucket，不在每次 toggle 后重新按全库分组。
- `RollupIncrementalIndex` 保存任务拓扑、segment delta、活动摘要、checklist 进度和近期日 bucket；base 文件负责状态与 full rebuild，`RollupIncrementalIndex+Mutation.swift` 负责 scoped delta/replacement 应用。普通 mutation 的工作量由变更记录、任务自身与祖先深度决定；完整历史 worked seconds 始终精确。
- `TaskEstimatePolicy` 统一预计时长输入与旧数据规范化：`0...600` 分钟、`0` 表示未设置、正数最多 36,000 秒。明确预计时长只属于当前任务自身，预计总时长至少等于已经记录的时间；没有明确值时才使用 checklist 证据模型，子任务始终单独递归汇总。
- Forecast pace 使用包含今天在内的最近 90 个本地日，只对有记录的活跃日求日均；它只把已有 remaining seconds 换算为预计活跃日，不生成 remaining seconds。Calendar/时区变化会重建这组有界 bucket。
- `AnalyticsStore` 的 overview 与 task snapshot cache key 包含 range、`AnalyticsPeriodEvaluation.interval.start` 和可选 live-minute bucket，不能从 cutoff 反推 period。当前范围与活动 segment 相交时才按 `clockReference` 分钟换 key；历史/未来范围没有 live bucket。snapshot、daily、timeline、group breakdown 与 comparison 统一消费显式 period 和 cutoff；ledger 事件按相交区间失效 day bucket，跨 period 会自然 miss。
- `LedgerBucketCache` 继续为完整 calendar period 保留稳定 daily bucket；`DailySummaryService.visibleSummaries` 只在 bucket lookup 之后按 `summary.date < clamp(cutoff, period)` 生成可见 read model。当前周/月包含正在进行的本地日但不发布未来零日，完整历史周期发布全部日，未来周期发布空数组。`DailyAnalyticsPoint` 以 `Double(seconds) / 60` 向 Chart 提供分钟值，禁止在 View 中做整数除法；Wall/Gross 必须使用显式图例、不同 mark 类型和逐点 VoiceOver 值。
- Today 小时活动图的 24 根柱必须共享 `HourActivityScale`：纵轴上限为 `max(3_600, 当日单小时 grossSeconds 最大值)`，所以普通一小时以 3,600 秒为满高，并发使单小时 gross 超过 3,600 秒时才统一扩展全日尺度。每小时目标高度按秒级 `totalSeconds / upperBoundSeconds` 计算，零值为零高，1...59 秒不得先取整为分钟；`HourStackLayoutEngine` 必须保留所有正时长 task slice，且 slice 高度之和等于该小时目标高度。层间分隔线只能用不参与布局的 overlay，不能把间距额外加到柱高或覆盖极薄的数据层。可视比例不替代语义：每小时 VoiceOver value 继续列出真实总时长与各 task 时长，图高使用 Dynamic Type-aware `@ScaledMetric`，辅助字号下横轴从五个刻度收敛到 0/12/24 三个刻度；可见刻度对辅助技术隐藏，避免在逐小时语义之后重复朗读。
- `AnalyticsRefreshPlan` 是 Analytics 页面时钟的唯一调度 owner：活动当前范围使用与 cache bucket 完全一致的绝对分钟边界，静态当前范围等待 `Calendar` 给出的下一个本地日边界，历史范围不调度。plan identity 保留生成它的 wall-clock sample，所以同一分钟内的系统时钟回拨也会取消旧 sleep 并重新安排。`AnalyticsView` 只在 active scene 用 `.task(id:)` 持有可取消 sleep，并在 scene 激活、日历日、系统时钟或时区变化时重采样；category detail 复用根页面的 `liveNow`，不得再用全页 `TimelineView` 建立第二套刷新树。用户切换日期时必须以动作发生时的 `Date()` 判断是否重新跟随当前 period。
- 月范围的前后导航只用 interval start 确定目标月份，不能把上一步被月末 clamp 的日期当成新的 day-of-month 锚点。`AnalyticsMonthNavigationAnchor` 必须由 Analytics 根状态持有并传到所有 period controls；手动日期选择和 range/Today 操作负责重置它。
- `CorePerformanceBudgetTests.fiftyThousandSegmentMutationUsesConstantSizedRollupDelta` 以 50,000 个 segment 约束单 segment 增量更新和 cached recent ranking；最终是否通过仍以冻结工作树的 xcresult 为准。

## 5. 持久化、CloudKit 与迁移

当前 schema 为 V10（版本标识 `1.9.0`），迁移计划覆盖 V1 至 V10。V9 通过 V8→V9 lightweight migration 移除持久化 `DailySummary` 派生缓存；V10 通过 V9→V10 custom migration 为 Inbox item/suggestion 初始化不透明 context/revision UUID，并把旧版“已有 generatedAt 且没有 active suggestion”转换为该修订的显式 dismissal。任务、segment、session、Pomodoro、checklist、Inbox、倒计时、分类和偏好等用户事实仍保留。`DailySummary` 类型只留给 V1...V8 schema 读取与迁移，V9 Inbox 类型保留冻结旧形状；当前 registry 不包含 `DailySummary`。版本升级时：

1. 先声明哪些用户数据必须保留。
2. 为旧 schema 准备真实 store fixture。
3. 验证迁移可重复、不会生成重复事实。
4. 说明新旧设备同时在线时的版本偏差行为。
5. 明确失败后的回退边界；不要用空库或内存库静默伪装成功。
6. 更新 [Versioning](Versioning.md) 与 [AgentDecisions](AgentDecisions.md)。

当前运行时生成的磁盘兼容 fixture 覆盖 V4 分类迁移、V8 `DailySummary` 移除迁移与 V9 Inbox suggestion identity/dismissal 迁移；它们会真实关闭旧容器、打开磁盘 store 并核对事实记录，但不是由已发布版本生成且带固定 hash 的不可变历史 artifact。后者仍是明确缺口：应从发布 tag/当时工具链一次性生成无敏感数据的 SQLite bundle，附 schema/app/build、seed、工具链和 SHA-256 manifest，每次复制到唯一临时目录后迁移；不得从当前分支临时生成后冒充历史发布 fixture。

legacy `CountdownEventsJSON` 是一次性 `UserDefaults`→SwiftData 迁移，不是可信的当前数据源。`LegacyCountdownMigrationPolicy` 限制 JSON 为 256 KiB UTF-8、源数组最多 256 条、标题最多 4 KiB UTF-8，日期必须有限且处于 `[1900-01-01, 2201-01-01)`。合法 legacy UUID 原样保留；同一 UUID 只接受源顺序中第一条通过所有校验的记录，无 ID 的不同记录不按内容合并。实际导入时只有 `context.save()` 成功后才设置完成 flag 并删除旧 payload；保存失败必须保留两者以便重试。若 SwiftData 已有 Countdown 事实，则不重复导入并直接退役旧 payload。

偏好迁移实现集中在 `Models/SyncedPreferenceMigrations.swift`。普通 legacy `UserDefaults` 导入通过 `performAtomicMutation` 一次保存，保存成功后才设置 migration flag；失败会 rollback 所有待插入记录并保留源值与未完成标记。敏感偏好迁移先确保 device-only Keychain 有安全副本，再删除本机旧 secret，并把所有 SwiftData redaction 放在一个原子 mutation；保存失败时 redaction 回滚，已建立的 Keychain 副本作为可重试的安全落点保留。不得把这个跨 Keychain/SwiftData 流程描述为 ACID transaction。

普通偏好的当前写边界由 `Models/PreferenceJSON.swift` 与 `PreferenceCommandHandler` 共同定义。每个 raw JSON 最多 256 KiB；command 在抓取或改写任何模型前，先把整批 `(AppPreferenceKey, JSON)` 按 key 解码为声明类型、应用现有 sanitizer/clamp，再编码为 canonical JSON。JSON `null`、畸形文法、错误类型和超限 payload 会抛出可本地化错误，整批保持不变。预检通过后，写入本身再进入 `performAtomicMutation`；独立 command 的最终 `save()` 失败会 rollback，嵌套在 store mutation 中则只由最外层统一提交。Legacy 值使用 throwing checked encoding，超限旧值被跳过，绝不能静默保存成字符串 `"null"`。

CloudKit 模式与纯本地模式共用业务模型，但容器和同步状态不同。紧急内存 fallback 只能用于保持应用可诊断，绝不能被描述为持久存储。

同步刷新是事件驱动的：`NSPersistentStoreRemoteChange` 和 `NSPersistentCloudKitContainer.eventChangedNotification` 进入 `TimeTrackerStore+SyncObservers`，350 ms 合并窗口保留最高优先级原因，再由 refresh planner 执行一次一致性刷新。启动与 scene 回到 active 时仍会刷新；不要重新引入常驻 5 秒轮询。`SyncedPreferenceService.latestByKey` 必须先完成 LWW/tombstone 选择，再过滤已删除结果，否则旧 active preference 会复活。legacy `UserDefaults` 迁移也必须从 logical-key LWW winner 判断 key 是否已迁移；winning tombstone 仍表示“已迁移”，必须阻止旧本机值重新导入。

`AppCloudSync.enabledKey` 是设备本地启动配置，只保存在 `UserDefaults`，修改后下次启动生效。它不属于 `AppPreferenceKey`，也不能进入 `SyncedPreference`、冲突快照或导出/恢复数据。历史 `TimeTrackerCloudSyncEnabled` 记录在这些边界统一过滤。普通 Local、Demo 和 UI Test 模式的 mutation 不生成冲突快照；CloudKit 活跃或存在待上传恢复时，`StoreDomainEvent` 只重抓受影响的 task、ledger、pomodoro、preference、countdown、checklist 或 inbox 域。仅 full sync、远程 import 和没有 baseline 的初始化需要捕获全部域。

同步文件所有权如下：

- `SyncConflictService.swift`：bootstrap 与 prompt 组装。
- `SyncConflictService+LocalMutation.swift`、`+CloudImport.swift`、`+CloudExport.swift`、`+Recovery.swift`、`+Resolution.swift`：本地变更、云事件与显式恢复流程。
- `SyncConflictService+State.swift`、`+StateWriting.swift`、`+StateLock.swift`、`+StateLocations.swift` 与 `SyncConflictState.swift`：有界本机状态读写、pending forced-upload mirror、跨进程锁、文件位置与 epoch/generation/checkpoint state。
- `SyncConflictService+Export.swift`：过滤后的 JSON export encoding。
- `SyncDataSnapshot.swift`：版本化全域快照、摘要和 fingerprint。
- `SyncDataSnapshot+Capture.swift`：按域捕获当前事实。
- `SyncDataSnapshot+Preflight.swift`、`SyncDataSnapshot+PreflightContent.swift` 与 `SyncDataSnapshot+PreflightSemantics.swift`：在恢复事务前对不可信 transport 做结构、内容和语义预检。
- `SyncDataSnapshot+Restore.swift`、`SyncDataSnapshot+RestoreTasks.swift`、`SyncDataSnapshot+RestoreLedger.swift`、`SyncDataSnapshot+RestorePlanning.swift`、`SyncDataSnapshot+RestoreChecklist.swift` 与 `SyncDataSnapshot+RestoreInbox.swift`：预检通过后，在一个原子事务中分域恢复。
- `SyncSnapshotRecords.swift`、`SyncSnapshotLedgerRecords.swift`、`SyncSnapshotPlanningRecords.swift`、`SyncSnapshotChecklistRecords.swift` 与 `SyncSnapshotInboxRecords.swift`：组织/任务基础和分域跨版本 Codable record DTO；它们不是第二套业务模型。

`SyncConflictState.json` 的每次 read-modify-write 都在 `SyncConflictService.withExclusiveStateAccess` 内完成。进程内使用递归锁，跨主应用/Shortcuts 进程使用 POSIX advisory `lockf` 文件锁；两个进程不会用各自的旧状态副本互相覆盖。状态 JSON 原子替换，forced-upload mirror 只在权威 state 缺失/损坏隔离时恢复，并在下一次 locked load 校正。权威 state 读写上限为 128 MiB，recovery mirror 为 64 MiB。读取先用 file metadata 预检，再通过 `FileHandle.read(upToCount: limit + 1)` 抵御预检后文件增长的 TOCTOU，不做无界 `Data(contentsOf:)`。写入先编码并同时验证权威 state 与所需 mirror，只有两者都在上限内才解析目标路径、建目录或原子替换；独立 mirror rewrite 在最终写边界再次验长。大小拒绝不能改写旧的有效 state 或 mirror。损坏或超限的权威 state 会隔离并进入显式恢复；损坏或超限的 pending mirror 会隔离并安全忽略，不能阻塞主库。超限隔离直接移动文件，不把整份 JSON 载入内存。

在 iOS 上，权威状态文件、pending forced-upload 恢复镜像和腐损状态隔离文件写入后都设置 `FileProtectionType.completeUntilFirstUserAuthentication`。这些文件在设备本次启动首次解锁前不可读，首次解锁后可供后台 Shortcuts/CloudKit 流程继续使用；lock 文件不是用户快照，也不能被描述为同样的受保护数据文件。macOS 不套用 iOS Data Protection 属性。

Cloud export 不以“收到任意成功回调”作为本机已同步证明。每次 local mutation 推进 `localGeneration`；import/强制恢复推进 `syncEpoch`；export start 记录 event ID、epoch、generation、fingerprint 和 startedAt。成功 finish 只确认同 epoch 且不早于已确认 generation 的 checkpoint，乱序旧回调不能回退 base 或清除较新的 pending forced upload。旧 state 清理被排除偏好时会重算 fingerprint 并同时清空清理前 payload 的在途 checkpoints，使延迟回调不能恢复旧 base。checkpoint 最多保留 16 个、最长 24 小时，不为每个事件复制整份用户 snapshot。

Snapshot restore 把历史/外部 transport 当作不可信输入。进入原子 mutation 前，纯 preflight 会拒绝：单表超过 100,000 条或总计超过 250,000 条、任一表内重复 UUID、超过字段/总文本 UTF-8 预算（标题 4 KiB、note/reason 64 KiB、紧凑字段 256 B、preference JSON 256 KiB、总文本 32 MiB）、非有限或不在 `[1900-01-01, 2201-01-01)` 的日期、非有限/无法安全加 10 的 sort order、未知 enum raw value、越界 Pomodoro 计划（时长 `1...28,800` 秒、target rounds `1...24`、completed `0...target`）、类型不匹配或非法 JSON 偏好，以及能证明的 session/task 关系矛盾。当前 payload 中缺少被引用记录允许通过，以兼容 CloudKit staged import；已同时存在但任务不一致则拒绝。任一预检失败都不能改写现有记录或生成 tombstone；不做静默去重或钳制。

这个边界覆盖显式 `SyncDataSnapshot.restoreAsLocalWinner` 恢复路径；已被 SwiftData/CloudKit 直接 materialize 进 context 的初始 import 不会倒流经该 snapshot preflight，不得用此证据宣称所有 CloudKit 输入已被同等拦截。

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

`DeviceIdentity` 是本机 `UserDefaults` 中的随机平台前缀 UUID，仅用于同步 tie-break 和 mutation metadata。读取时只复用“当前平台 `mac|ios|watch` 前缀 + 大写连字符规范 UUID”的完整值；错误平台、非规范 UUID、后缀、控制字符或超过 42 UTF-8 bytes 的值会被重新生成并回写。新 identity 不包含 Mac 主机名、账户名或其他可读设备名称。

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

`LiveActivityTimingPolicy` 是 ActivityKit `staleDate` 与 UI elapsed presentation 的共同边界：活动从 canonical `startedAt` 起最多实时增长八小时，进入 stale 后必须切换为固定的 `LiveActivityElapsedPresentation.frozen`，可见文本和 accessibility value 都使用同一个冻结秒数。不得只改状态标签而继续渲染 `Text(startedAt, style: .timer)`。锁屏内容在辅助功能字号下直接采用纵向结构，其他字号用 `ViewThatFits(in: .horizontal)` 在宽行和堆叠结构之间选择；展开 Dynamic Island 在辅助字号下保留两行任务标题和独立停止控件，普通字号也要为窄标题提供换行回退。系统强约束的 compact/minimal presentation 可以保持精简，但不能把其单行约束扩散到锁屏和 expanded surface。

### Watch

Watch target 的状态 owner 是同一个 `WatchAppStore` 类型，但职责按 extension 文件拆开：base 文件只持有 observable state、依赖和恢复；Commands 文件处理 submit/retry/discard、20 秒确认 timeout 与本机 queue persistence；Connectivity 文件处理 activation/transmit、payload/result/snapshot application 与 freshness/error；SessionDelegate 文件只负责 WCSession callbacks。新增逻辑应进入对应 owner，不能重新把 transport、delegate 与 queue lifecycle 混回 base 文件。

Watch 使用持久快照加命令队列。每个 `WatchTimerCommand.id` 是幂等键；新命令和进程恢复命令走 durable `transferUserInfo`，可达时再用 `sendMessage` 加速；单纯 reachability 变化只重发即时消息，不能重复制造 durable 副本。手机返回七态 typed terminal result（success、duplicate、missingTask、missingSegment、invalid、failed、timeout），并用 durable user-info 再投递；20 秒无 terminal result 会进入可重试失败态，retry 保留 ID、刷新 `issuedAt`，用户也可 discard。`WatchCommandProcessor` 在 receipt lookup 后、任何 mutation 前校验 DTO 和时间边界：命令最多保留 30 秒，允许最多 5 分钟的未来设备时钟偏差；过期/非法命令返回 invalid 且不写 receipt 或 ledger，因此用户仍可用同 ID 明确重试。快照反射只为旧手机兼容确认。

Watch UI 是单一 Crown-scrollable `NavigationStack/List`：Active Timer 优先；Quick Start 只显示前四项，其余最多 256 个可工作任务进入“全部任务”；行状态通过一次 Set/Dictionary index 构建，不能为每行线性扫描命令队列。主页只预览第一个失败，更多失败进入“全部问题”，每项提供 retry/discard。`WCSession.isReachable` 只表示即时消息通道，不等于后台同步离线，因此状态只描述首次等待、发送、已排队、连接错误或 stale。较旧 snapshot 不能覆盖较新的已显示状态。主 target 的 codec/state/processor 测试不能替代真机往返验证。

所有 WatchConnectivity payload 和本机恢复数据都按不可信输入处理。Codec 在构造领域 DTO 前后验证有限日期、UTF-8 byte 长度、数组数量、唯一 command/timer/task ID、summary 非负上限、active timer 年龄和未来时钟偏差。Watch state snapshot 最多包含 64 个 active timer 和 256 个 recent task。iPhone durable incoming queue 最多 64 个命令；Watch persisted pending/failed 各最多 64 项；编码队列最多 512 KiB。`WatchCommandQueueState.isSafeForRestoration` 拒绝结构非法、command/result ID 不一致或跨列表重复的状态。pending overflow 把最旧项转成 `queueOverflow` failure，failed overflow 丢弃最旧 failure；无法安全恢复的本机数据会清除，而不是解码后继续执行。字段上限的唯一常量表是 `WatchTransportLimits`，不得在 codec、store 和 UI 各写不同数值。

### Deep link 与 scene 生命周期

`AppDeepLinkRouter` 只接受 `timetracker` scheme、最长 2,048 bytes、无 user/password/port/fragment 的白名单路由；每个 host/path 还限制 query 名称、数量和 UUID 格式。`ContentView` 在 repository 尚未配置时把合法 URL 放入 scene-local `PendingDeepLinkQueue`：容量 16，按解析后的 `AppDeepLinkAction` 去重，满时丢弃最旧项，配置成功后按顺序 drain，scene 消失时清空。带 `taskID` 的停止链接与共享 system-action command 都只能停止该任务的活动 segment；目标已停止时必须成为无操作，不能回退停止另一条并行计时。只有不带 `taskID` 的通用停止动作可以选择当前最近的活动 segment。不要把未验证 URL、closure 或可无限增长的数组放入启动队列。

iOS `WindowGroup` 可以产生多个 scene，而 `WatchConnectivityBridge` 只有一个进程级 command handler。`WatchCommandRouter` 因此保存 scene registration 与弱 `TimeTrackerStore` 引用，优先最近 active scene，没有 active scene 时才回退到最近仍存活的注册；注销/释放会清理 route，最后一个 route 消失时移除 bridge closure。不得让 singleton closure 强持有 scene store，或由每个 `ContentView` 无条件覆盖全局 handler。

### Widget

Widget 从版本化共享快照读取数据，区分共享容器不可用、缺失与损坏，不把所有失败都显示成“没有计时”。`WidgetSnapshotCache.snapshot` 在 producer 边界限制 64 active/64 recent（当前 Widget recent UI 只投影前 3 项），将 summary 裁到非负上限、timer start 裁到 `generatedAt - maximumActiveTimerAge ... generatedAt`，并用 Unicode-safe prefix 将投影 title/path/style 限制为 512/1,024/128 UTF-8 bytes。所有文本共用 128 KiB 预算，从而保持 Widget JSON 不超过 256 KiB。

Widget 的容器级 `.widgetURL` 永远是 `WidgetDeepLinks.today`。启动任务是 mutation，必须由显示任务名的显式 `Link(destination: WidgetDeepLinks.startTimer(...))` 发起；不得根据 recent task 动态改写背景 URL，否则任意空白区域点击都会偷偷启动列表第一项。小型空状态只给首个 recent task 一个明确的 44 pt Quick Start 目标，中型布局的任务行各自持有链接，背景仍只负责打开应用。

`WidgetSnapshotLimits` 同时是 consumer/store 验证的唯一上限表：解码字段的 title/path/style 硬上限为 4 KiB/16 KiB/256 UTF-8 bytes，并验证有限日期、最多 5 分钟未来偏差、summary/active-age 上限和唯一 ID。`SharedWidgetSnapshotStore.save` 在写 App Group UserDefaults 前拒绝非法/超限快照；`loadResult` 在 decode 前检查字节，decode 后重新验证，失败返回 `.corrupted`。Watch producer 复用裁剪后的 active timers，并对最多 256 recent task 应用同样的 Unicode-safe 512/1,024/128-byte 投影上限和共享 128 KiB 文本预算。这些裁剪不写回任务或账本。时间线根据 snapshot freshness 和 active timer 安排刷新。主应用和扩展已启用 `group.me.mezorewww.timetracker`，Xcode 自动签名构建已生成带该 entitlement 的 profile；发行门禁仍要求真机验证共享容器 URL、读写、刷新策略、锁屏与离线状态。

## 8. AI 服务

LLMService 面向用户配置的 OpenAI-compatible endpoint。边界要求：

- 远程 endpoint 必须为 HTTPS。
- 仅 `localhost`/`.localhost` 保留域名以及经 `inet_pton` 数值解析确认的 `127.0.0.0/8` 或 `::1` 可使用 HTTP；`127.evil.com` 一类主机名不能靠字符串前缀伪装成本机。
- API key 只在请求 Authorization header 中使用。
- 带 Authorization 的 redirect 只允许保持相同 scheme、host 和有效端口；跨源、HTTPS 降级或模糊主机跳转必须拒绝，防止 credential 泄漏。
- 生产 transport 使用专用 `URLSessionConfiguration.ephemeral`：禁用 URL cache、cookie 与 cookie store，资源超时 60 秒。响应通过 `URLSession.AsyncBytes` 流式读取；HTTP 非 2xx 与声明超过 2 MiB 的 Content-Length 在 headers 阶段取消，未声明/不可信长度仍以实际读取字节硬限制 2 MiB。父 Task 取消必须取消底层 URLSession task，`URLError.timedOut` 转为可操作超时错误。
- 注入 transport 仍须在 Model/Inbox/Checklist service 层对成功响应执行 2 MiB 二次防御；响应类型和 HTTP 状态优先于 buffered-body 上限，保持真实与替代 transport 的错误语义一致。
- 发送前按功能构造最小请求，不附带无关数据。`LLMSuggestionInputPolicy` 是 Inbox/checklist 共用的 request projection 边界：候选最多 48 项/16 KiB JSON，prompt 最多 24 KiB，request body 最多 32 KiB，持久化 model ID 最多 256 bytes，字段按 UTF-8 bytes 以完整 `Character` 裁剪。model ID 上限必须与同步快照 compact-field restore 上限保持一致；这些裁剪仅用于网络 DTO，不回写 canonical facts。
- 模型 ID 是 opaque identifier，不是可安全缩写的展示文本。偏好 sanitizer 只接受最多 256 UTF-8 bytes 且不含控制字符的完整 ID；超限项从模型列表过滤、超限选择变为空配置，绝不能截断后向服务端发送另一个标识。
- Inbox 候选集先取 Quick Start 固定任务，再取高频/近期任务，最后稳定补足。候选归一化去重后再按实际 JSON 字节预算取舍；不能回退成对全库纯字母截断。
- `SymbolCatalog.symbolNames` 保留完整本机 picker 目录，`aiSuggestionSymbolNames` 是请求中的 78 项精选语义集。普通 icon sanitizer 用 `symbolNameSet` O(1) 查找；AI 返回 icon 只接受已公告精选集，Inbox task UUID 只接受实际发送候选。
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

导出边界必须 fail closed：读取、过滤或编码失败时返回错误或 `nil`，由 UI 展示错误且不打开 `fileExporter`。禁止返回 `{}`、空数组或旧缓存作为占位成功结果；否则用户无法区分“数据确实为空”和“导出已经失败”。行为测试至少覆盖有效内容、敏感字段过滤、未配置/序列化失败不产生文档，以及 UI 只在获得真实 payload 后呈现导出面板。

## 10. 测试策略

优先级从高到低：

1. 领域行为与迁移测试
2. Store/command 集成测试
3. UI 可访问性标识驱动的流程测试
4. 少量稳定截图测试
5. 源码结构契约

仍有部分测试通过读取 Swift 源文件并匹配字符串来约束 UI，这类测试会在等价重构后误报。逐步把它们替换为行为、accessibility identifier 和结构化 API 测试。

测试必须隔离 UserDefaults、Keychain、临时目录、时区与 locale。本轮已移除类别空分区测试对演示种子全局状态的依赖；新增测试仍应显式清理共享状态。

Today UI 测试以 `home.view` 判断根页面就绪，再滚动查找具体操作；不能把某个可能尚未进入 iPad Split View 可访问性快照的子按钮当作页面启动信号。测试启动环境把审计路由固定为 Today，横屏用例由 Runner 显式设置 `XCUIDevice` orientation，并必须实际打开任务选择器。截图后恢复默认字号和方向、终止 App，并关闭本轮启动的 Simulator。新增 contract 或 UI regression 只表示验收门槛已经落库，不能在对应 signed test/result bundle 成功前宣称回归通过；Xcode beta 的 testmanager/Runner 卡死属于基础设施失败，必须保留结果或诊断并报告。

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
- APS 的规范签名键是 `aps-environment`。不要写成 `com.apple.developer.aps-environment`：Automatic Signing 可能仍成功构建，却把未知键从生成 `.xcent` 与最终签名中静默移除。能力验收必须对比源 entitlement、embedded profile、`.xcent` 和 `codesign -d --entitlements` 的实际结果。
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
