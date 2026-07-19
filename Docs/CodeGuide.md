# TimeTracker 代码文档

状态：当前实现说明
校对日期：2026-07-19

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
| timetracker/App | 启动、依赖组装、平台根视图、导航与 scene 级 presentation |
| timetracker/Features | Today、Inbox、Tasks、Pomodoro、Analytics、Settings 等界面 |
| timetracker/Models | SwiftData 持久模型与 schema 版本 |
| timetracker/Commands | 可持久业务动作与 use case handler |
| timetracker/Repositories | SwiftData 查询与写入实现 |
| timetracker/Services | 分析、预测、同步、安全、维护与系统集成服务 |
| timetracker/Stores | `@Observable` UI 门面、领域快照、刷新规划和业务/页面导航状态 |
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

- Sync conflict：`SyncConflictService` 只保留 bootstrap/prompt；local mutation、Cloud import/export、recovery/resolution、manifest/slot state persistence、file lock/locations、export encoding、snapshot capture/分域 restore、snapshot state 与分域 record DTO 分文件。
- Analytics：root landing page、category-detail loading 与 category-detail content 分文件；category 使用 typed `NavigationLink(value:)` / `navigationDestination` 路由。首页顺序由 `AnalyticsCategory.reviewCategories` 和 `exploreCategories` 显式定义，两组合并必须对 `allCases` 完整、无重复；每行直接展示问题、当前答案和详情目的地，不能另加卡片手势。Tasks & Categories 详情固定先显示 Category Distribution，再显示 Task/Root Task Distribution；breakdown bucket 在没有真实详情路由前保持只读，不显示 disclosure。overview row、metric/detail list、period control 与 store 的 metrics/breakdowns/overlap/task snapshot 各有所有者。Facade 的同步 snapshot/cache 生命周期留在 `TimeTrackerStore+Analytics.swift`，async cache-miss visual loading 留在 `TimeTrackerStore+AnalyticsLoading.swift`，轻量 UI read model 留在 `TimeTrackerStore+AnalyticsReadModels.swift`；domain 层把 cache-aware daily assembly、comparison window、comparison calculation、insight narrative 与 raw metrics 分别归属 `Caching`、`ComparisonWindow`、`DecisionSupport`、`Insights`、`Metrics`，不得为方便而重新聚合。分布图切片值由 `AnalyticsDistributionSlice.swift` 持有，分组聚合与 “Other” 折叠规则由 `AnalyticsGroupBreakdownPresentation.swift` 持有，分段宽度算法由 `AnalyticsGroupBarLayout.swift` 持有；Today 小时活动的跨小时共享尺度与 task stack 守恒算法由 `HourStackLayoutEngine.swift` 持有，视图文件只保留组合与展示。
- Pomodoro presentation：`PomodoroPageLayout` 从外层 `GeometryReader` 的有限 viewport 派生唯一布局分支，负责宽屏双栏与窄屏单栏；正常字号依赖系统 safe-area/tab chrome inset，只保留内容节奏所需的滚动末端余量。禁止用嵌套 `ViewThatFits` 同时测量整棵 primary/secondary 子树。setup composition、空状态、参数控件、Plan/Task 选择、timer face、active composition、active countdown、有限 timeline schedule 和 ledger 各有所有者。计划是小型稳定 `Menu`；任务选择通过 scene-owned typed sheet，按标题/完整路径搜索并以当前 Focus 页的回调更新局部 task ID，不能启动计时或改写全局 task selection。页面容器不承担 deadline 或账本写入。
- Settings：display/timing、Pomodoro、countdown、sync、data、actions、bindings 与 support 分文件；`SharedUI/Components` 中的 foundation/value row、action/destructive label、text/number input、presentation modifier 和 sync feedback 也各有所有者。
- Task Workspace：canonical router 与 identity/checklist/overview/analytics/navigation/record/editor sections 分文件。系统 navigation title 提供导航上下文，首张 identity row 则是内容区持久可见的任务身份，必须以 primary headline 显示任务标题、以 secondary subheadline 显示父级/根路径；不能恢复旧工作流状态或已经由 Stop 动作表达的运行状态。`TaskDetailView` 在同一 navigation destination 内切换证据阅读态与 `TaskEditorPanel` 草稿态；已有任务不得再打开第二个编辑 sheet，新建任务仍使用同一 editor panel 的模态事务。request-keyed `.task(id:)` 只在阅读态载入分析快照；`loadedRequest` 必须和当前 request 相等才显示快照，避免范围、任务树或账本 revision 改变时短暂展示旧分析。iPhone `List` 为正常字号保留明确的 scroll-content bottom margin，末项不得贴入 Tab Bar glass。`AnalyticsRefreshPlan` 只在 active scene 安排下一个分钟/本地日边界，scene 回到前台、时钟或时区变化会重新取样；不得恢复整页 `TimelineView` 或让分析加载遮住计时动作。
- Task notes：详情证据态通过固定版本的 MarkdownView 渲染 Markdown，链接由 `TaskNotesMarkdownPreview` 转交系统 `openURL`；编辑态仍保存并显示原始 Markdown 文本。不要把渲染后的 attributed content 写回模型，也不要修改 MarkdownView 的全局默认 theme。
- Ledger infrastructure：Cloud startup、persistence safety、timer DTO、aggregation、formatting、device identity 与 summary 分文件。
- Facade lifecycle：`TimeTrackerStore+Configuration.swift` 只负责首次配置、repository-only 系统表面组装和 post-commit surface refresh；`TimeTrackerStore+Lifecycle.swift` 负责 refresh、mutation 边界和 throwing 恢复编排，`TimeTrackerStore+SyncObservers.swift` 额外接收已提交的 App Intent notification 并只刷新当前 scene read models。`SystemActionPostCommitEffects` 是 App Intent 唯一的后置编排点：snapshot、Widget/Watch/Live Activity 和同进程 scene broadcaster 必须使用同一 committed `StoreDomainEvent`，但 scene catch-up 不得重复记录 snapshot、重发 system surface 或启动自动 LLM。不得把启动迁移/seed/observer 安装混在同一大扩展，也不应为新恢复 API 写入全局瞬时错误。
- Widget：entry/provider/config、active-timer family layouts、supplementary/error states 与 deep-link/localization/color support 分文件。
- Watch：三页 dashboard orchestration、Active Timers page、共享 Quick Start/All Tasks 列表、失败问题页、timer/task rows、status/error/empty states、command presentation index 与 color support 分文件；`WatchAppStore.swift` 保留 observable state/安全恢复，`WatchAppStore+Commands.swift` 负责 queue/timeout/persistence，`WatchAppStore+Connectivity.swift` 负责 transport/payload/freshness，`WatchAppStore+SessionDelegate.swift` 独立承接 WCSession callbacks。
- Ledger/Rollup index：ordered flat segment array mutation 独立到 `LedgerStore+FlatSegmentIndex.swift`；增量 rollup 的 scoped mutation/replacement 独立到 `RollupIncrementalIndex+Mutation.swift`。
- Today：`HomeViews.swift` 只组合宽屏优先级，`PhoneHomeSections.swift` 组合紧凑屏顺序，各 section 文件拥有具体内容；`TodayHomeContent` 在一次组合中集中生成 active/timeline、Quick Start、forecast 和 countdown 读模型，避免各 section 重复查询与分组。Quick Start 的任务身份按钮始终路由详情；Today、Quick Start 与计时选择器的 Start/Switch/Stop 全部复用 `TaskTimerActionButton`，以 fresh `TimerPickerSelectionCommand` 显示 Start/Switch，并仅对当前 `TimeSegment` 显示精确 Stop。调用方不能复原状态相关的整行 toggle，也不能在 Stop 旁再堆一个 Running 标记。
- App presentation：`AppPresentationRouter` 由每个可呈现 UI 的 scene 自己持有，`AppPresentationHost` 是该 scene 唯一的 App 级 sheet owner；feature 只请求 typed content，不在共享 facade 中保存 sheet draft 或 `isPresented`。任务选择器转入新建任务使用 matching presentation ID 的原子替换，不经过异步 dismiss/yield 空窗。
- App feedback：每个 scene 自己持有 `AppSceneFeedbackRouter` 与唯一 `AppSceneFeedbackHost`。队列按 FIFO 呈现，dismiss 必须匹配当前 feedback UUID；不得把 macOS Settings 的用户操作错误写回共享 Store 再由主窗口弹出。

分层不等于所有文件都已完成单一职责拆分。仍较集中的大型行视图已在 [CodeRefactorPlan](CodeRefactorPlan.md) 逐项列出；不要把已经完成的 Home 组合拆分重新列为“未来工作”，也不要用机械行数替代职责审核。

## 3. 运行时数据流

持久写入的推荐路径为：

    SwiftUI View
        → feature/store action
        → domain command
        → repository
        → SwiftData model context
        → read model/service refresh

`TimeTrackerStore` 是 `@MainActor @Observable` 的 UI 门面，但不是所有业务规则的最终归属。根视图用 `@State` 持有它，注入视图以普通引用读取；scene-owned presentation/feedback router 另由对应根视图以 `@State` 持有，只有系统 presentation binding 等确实需要双向绑定的位置才建立局部 `@Bindable`。新功能应先判断规则属于：

- View：布局、可访问性、展示状态。
- Store：业务/UI 可观察状态、动作编排、页面导航、持久健康状态和精确失效；用户发起的操作优先 throwing/typed result，不保存跨 scene 的 sheet 草稿或瞬时弹窗队列。
- Command：一次明确、可测试的业务写入。
- Repository：模型查询与持久化细节。
- Service：跨实体计算、同步、导入导出或系统集成。

视图不应直接复制领域判断，也不应绕过命令与仓储执行长期写入。计时文本用 `TimelineView` 做局部刷新；不得为了时钟显示让整个 facade 每秒发布一次状态。动态数字统一交给 `AnimatedClockText` 的原生 numeric transition，周围视图继续拥有唯一时钟 schedule；Reduce Motion 时不做过渡。Today 的活动计时行只让正在运行的行按秒刷新，已结束时间线保持静态；摘要每 30 秒刷新。`TodayHomeContent` 的数组在根组合处构造一次，Quick Start 去重并保留稳定任务 ID。Today 指标先规范化一次候选 segment，再以单个循环同时裁剪今日和前一日、累加 Gross；两组区间各自合并后得到 Wall。需要重叠时间时由 Gross 与 Wall 的差得到，不再扫描 segment。不得让每张卡重新遍历完整账本。

`TimeTrackerStore.perform` 和 `SystemActionCommandHandler` 使用 `ModelContext.performAtomicMutation` 包住一个用户动作。命令/仓储内部的 `saveAfterMutationStep` 在独立调用时立即保存，在外层 transaction 中延迟到最后一次统一 `save()`；动作或最终保存抛错会 rollback 整个 unit of work。提交之后的 read-model refresh 或 sync snapshot 失败不可能撤销已保存事实，因此 `perform` 仍返回成功并展示“已保存但重新载入失败”。App Intent 还会在 commit 后发布实际 domain events，使已配置 scene 通过 read-only refresh 收敛；它不能以此重新记账、再次同步或启动自动 LLM。Feature 只能在 `perform == true` 后清理 transient success/failure 状态。Keychain 不能加入 SwiftData 的 ACID transaction：LLM 配置先记住旧密钥，将三项普通偏好批量成一次 SwiftData 保存，并在提交失败时尽力恢复旧密钥；恢复本身失败必须单独报告。任务、账本等 UI selection 也只在 `didSave` 后更新，因为它不会由 `ModelContext.rollback()` 自动恢复。

`InboxCaptureCommand` 把普通用户 capture 与可重试的外部 integration 明确分开：没有 `ExternalCommandKey` 的调用每次都创建独立 Inbox 条目，标题、时间、`clientMutationID`、App Entity identity 都不得用于“猜测重复”。外部调用方若需要 at-most-once，必须自行持久并在重试时复用 `(origin, UUID)` key；`StoreScopedInboxCommandCoordinator` 会在同一 fresh store transaction 中写入 `InboxItem` 和 `InboxCaptureReceipt`，相同 canonical payload 重放只返回原 item ID/空 events，复用 key 却改变 payload 直接拒绝。若跨设备同时提交同一 key 后得到不同 item 或 payload，replay 必须显式拒绝，绝不能按时间任选回执。receipt 是 V11 CloudKit 用户事实，也进入 conflict snapshot/restore、preflight、清空数据 tombstone 与 LWW duplicate handling；旧 V10 snapshot 缺少该 optional table 时是未知状态，三方合并或 restore 都不得把它当作空表删除现有 receipt。永久清理若删除 Inbox item，也必须删除其 receipt。没有可信上游 key 的 `AddInboxItemIntent` 诚实保留 at-least-once 语义，post-commit side effect failure 也绝不伪造可安全重试的 mutation failure。

### 当前平台 UI 合同

- iPhone：五个系统 `Tab`（Today、Inbox、Tasks、Focus、Analytics）；Settings 从 Today 工具栏通过当前 scene 的 `AppPresentationRouter` 以 sheet 打开，关闭后保留原 tab、任务路由与滚动上下文，不进入 Today 的 `NavigationStack`。`nav.focus` 是 iPhone tab、iPad sidebar、macOS sidebar 与 Focus 页面标题的统一导航文案；`nav.pomodoro` 仍只描述账本来源、设置和分析中的 Pomodoro 领域，不得拿它恢复平台间不一致的导航标题。
- iPad：设备 idiom 稳定选择 `NavigationSplitView` 侧边栏与详情；分屏、Stage Manager 或旋转造成的 compact width 只由该 split view 折叠列，不切换成 iPhone 根导航，因此当前目的地、sidebar selection 和详情状态不会随窗口宽度丢失。从侧边栏或任务列表选择任务会打开同一个 `TaskDetailView`。
- macOS：单实例主 `Window` 承载 `NavigationSplitView` 工作区；独立系统 Settings scene、主窗口和 Settings 共享一个应用级 `TimeTrackerStore`，避免复制 CloudKit observers、自动 AI 建议与系统表面同步。
- Scene presentation：主窗口与 macOS Settings 各自持有 `AppPresentationRouter`，共享 Store 但不共享 sheet。每个 scene 只有一个 `AppPresentationHost.sheet(item:)`，因此同一 scene 的编辑器不会重叠或覆盖脏草稿，另一个 scene 也不会错误弹出当前动作。router 忙时不替换现有内容；matching-ID callback 才能 replace/dismiss，防止旧 sheet 回调关闭新 sheet。macOS New Task / Add Time 命令只作用于 focused 主 scene，router 忙时禁用。
- Scene feedback：主窗口与 macOS Settings 各自持有 `AppSceneFeedbackRouter`，共享 Store 但不共享 alert 队列。JSON 导出、数据库清理和同步恢复已使用 throwing 边界：成功/状态变化就地显示，失败只进入发起 scene 的队列，文件选择器取消不是错误。`ContentView` 对尚未迁移的 Store `errorMessage` 仅作临时桥接；新增用户操作不得依赖该共享槽位。
- Today：iPhone 使用 `List`，顺序为 Now、Overview、Quick Start、Timeline、Forecast、Countdown。iPad/macOS 共享 `TodayHomeContent`；详情 viewport 扣除两侧 page padding、再受 1180 pt 上限约束后才得到实际内容宽度。该宽度达到 1000 pt 且存在辅助内容时，Quick Start/Timeline 进入主栏，Forecast/Countdown 进入 360 pt 辅助栏，否则保持单栏。Today 只有一个当前计时入口：无活动计时时为 Start Timer；有活动计时时根据并行偏好显示 Start Another Timer 或 Switch Timer。这个主动作在 Now 内容流中保留可见文字。`TimerPickerCommandPolicy` 以 `.start`、`.startAnother`、`.switchTimer` 固化入口模式，并把任务选择命令限定为开始、切换或 `alreadyRunning`。计时选择器每行都由只读任务摘要与独立的尾部动作组成；Start、Switch 和 Stop 固定使用同一 icon-only 槽位。运行中任务进入独立 Running 区域，但一行只出现明确的 Stop，不再重复 Running badge；整行和选择摘要不得根据运行状态暗中改成停止命令。只有成功开始或切换后才关闭选择器，Stop 与失败都保留当前 picker 上下文。通用新建任务只存在于任务域和任务选择器，不与计时主操作竞争。
- Analytics navigation：当前范围摘要后用两个原生 `Section` 组织 Review/Explore；`AnalyticsCategoryRow` 只展示问题、当前答案和目的地，外层 typed `NavigationLink` 独占交互。Tasks & Categories 详情顺序为 Category、Task、Root Task Distribution；`AnalyticsGroupBreakdownRow` 在没有真实详情路由前是静态 read-model 展示，不能自行增加 `Button`、手势或 disclosure。
- Task identity and summary：脱离树结构的任务行或按钮统一从 `TaskTreeIndexes.taskIdentityPresentation(for:)` 取得 O(1) 投影，不在 View 中拆分路径字符串。`.hierarchical` 只显示标题，由现有树缩进/section 提供层级；`.standard` 显示标题与不含自身的父级路径，搜索结果等脱离树的表面必须使用它；`.compact` 才使用完整路径。`TaskSummaryRow` 是 Tasks、Sidebar、层级选择器和 `TaskIdentityRow` 的共享视觉语法：标题优先，正常字号最多两行；`.hierarchical` 的标题后第二行、或 `.standard` 的次级父路径之后，metadata line 按“左侧 checklist progress → flexible spacer → 被动 timer 图标 → 已工作时长 → navigation chevron/accessory”排列。辅助功能字号可纵向生长。被动 `TaskRunningIndicator` 只说明状态，不执行 Stop；选中勾选和导航符号可以是 metadata accessory，Start/Switch/Stop 命令必须是独立控件，三者都不得替换任务图标。`TaskVisualPresentation` 在进入 SwiftUI 前规范化 symbol 与颜色。
- Task timer actions：`TaskTimerActionButton` 统一 Today、Quick Start 和计时选择器全部 Start/Switch/Stop 的 bordered control、destructive role、满足 iOS/iPadOS 至少 44 pt 点击目标的尺寸、macOS 原生 28 pt 尺寸、icon-only/title-and-icon 分支及带任务名的辅助标签。计时选择器固定使用 icon-only 和固定操作槽：iOS/iPadOS 为 54×54 pt，macOS 为 28×28 pt，让三种状态共享尺寸与尾部位置。它只呈现调用方已经决定的 `TimerPickerSelectionCommand` 或精确 active segment，不拥有准入策略。选择器中的 `TaskSummaryRow` 是独立只读语义元素，动作是独立原生 Button；两者不得嵌套，也不能隐藏摘要后让 Stop 获得整行点击范围。
- Task navigation：`TasksNavigationView` 是 iPhone、iPad 与 macOS 唯一的任务导航容器，持久承载一个 `TasksView`，并通过 `navigationDestination(item:)` 把 store-owned `TasksRoute?` 推入系统 `NavigationStack`。`selectedTaskID` 表示计时器等领域使用的业务选择，`tasksRoute` 只表示当前页面；系统 Back 只把 route 写回 nil，不得清空业务选择，也不得重建列表来模拟返回。搜索与展开状态归现存的 `TasksView` 实例所有。打开详情必须先验证任务存在且未删除；删除成功、外部删除、全量维护或刷新发现 route 失效时才清路由，写入失败必须保留原详情与选择。iPad/macOS sidebar 的 selection 直接从 route/destination 派生，并在 task-tree revision 变化时重新展开当前任务的新祖先，不维护第二份镜像 `@State`。
- Task Detail：只读优先的 `List`，铅笔按钮在同一 workspace 中进入编辑态；清单完成状态可直接切换。系统 navigation title 与首张 identity row 都显示任务标题：前者属于导航 chrome，后者以标题优先、父级/根路径次级的层级承担内容身份。任务运行时，计时状态只由动作区明确的 Stop 表达，不在 identity row 重复 Running；Add Time 等其它明确动作仍按自身语义保留。核心身份/动作/清单/预测/备注不得依赖分析快照；分析尚未完成时仅在其自身 section 显示系统 `ProgressView`，不使用全页 loading replacement。返回完全交给系统导航控件，详情页不得添加自绘 Back 或额外调用 `dismiss()`；删除成功由 route 失效自然 pop，删除失败停留在原页。
- Task editors：任务、分类、checklist 与 Pomodoro 计划的符号/颜色入口共用 `SymbolColorPickerButton`。iOS 入口必须用 `NavigationLink` 推入编辑器已经拥有的 `NavigationStack`，Back 只返回同一草稿，最终 Save/Cancel 仍由外层 sheet 独占；不得在编辑 sheet 内再叠加一个带伪 Done 的 sheet。颜色由共享 `SymbolColorWell` 承担：iOS/iPadOS 在 scene-owned 的系统 SwiftUI popover 中直接复用 BlossomColorPickerCore 的默认 `ExpandedBlossomView`、`PetalLayout`、模型、色板、亮度控制与命中逻辑，并把整个上游视图按 `44 / BlossomConstants.petalSize` 等比放大；不得重新排列花瓣、重建色轮、另写亮度轨道，或在系统容器内再添加应用自有 picker 卡片。入口与放大后的可见色瓣均为 44 pt。macOS 直接使用 BlossomColorPicker 的顶层 presenter。应用适配层只负责 presentation、统一缩放、焦点和六位 sRGB binding。任意有效三位/六位 sRGB 输入都规范化为六位持久值；选中符号、Checklist 完成标记和 Timeline 色块通过 `TaskColorPalette.contrastingForegroundColor` 按实际背景选择黑/白前景。搜索键盘出现时，符号滚动区仍必须在键盘上方至少保留一个完整可点行；打开颜色、选择符号、Return/Done 或滚动会结束搜索焦点。新建任务和分类标题每个编辑会话只自动聚焦一次，从子页面返回时不能重新抢焦点。
- Task hierarchy editor：`TaskInfoEditorSection` 只组合标题、层级 rows 与符号校验；parent/category picker 和 footer hints 由 `TaskEditorHierarchyRows.swift` 接收轻量 options/hints，不直接订阅整个 Store。父任务选项使用 canonical full path 区分同名任务，不以空格模拟树层级；不可用的当前父项保留为可恢复选择，其他不可用项禁用。继承分类的任意颜色只用于图标，说明文字保持系统 secondary。
- Task stale recovery：`saveTaskDraftResult` 返回 `.saved/.stale/.failed(message:)`，不把 baseline 冲突降级为普通 Bool。旧 Bool facade 只为非 UI 调用保留兼容错误反馈；editor 收到 stale 后从已经刷新的 Store 构造 latest draft，必须先确认才用它替换当前 draft、session baseline 和 parent candidates。Keep Draft 不修改任何输入；Reload 明确丢弃未保存内容，重载后 Cancel 不得把最新 baseline 误判为脏草稿。
- Task rows：Tasks 列表不再维护普通、紧凑和 Accessibility 三套视觉 row；它把 canonical identity 与必要 metadata 交给 `TaskSummaryRow`。正常字号优先让标题最多显示两行；树内使用 `.hierarchical` 避免重复路径，搜索/平铺结果使用 `.standard` 保留父级上下文。metadata line 左侧是 checklist，右侧依次是被动 timer 图标、已工作时长和 iOS navigation chevron；Running 不是 Stop，行内不得加入停止命令。`TaskManagementRowAccessibilitySnapshot` 仍是任务详情按钮的单一 VoiceOver 投影，并继续补足视觉摘要未常驻显示的完整路径、预测与子任务数；不要用 `accessibilityRepresentation` 或忽略 children 后只补部分字段。context menu 与 swipe 的删除都只发送 `requestDelete`，由所在 row 的同一个 `confirmationDialog` 和显式 task UUID 执行；swipe modifier 不得再保存第二份确认状态。用户文案统一为 Delete/删除，不暴露 soft-delete 实现术语。
- Task availability：`TaskTrackingAvailabilityService` 一次线性扫描分别产出 `visibleTaskIDs` 与 `trackableTaskIDs`。归档兼容以 `archivedAt != nil` 或历史 `statusRaw == "archived"` 任一成立为准；归档写入继续双写两者，恢复预检从 `LegacyTaskStatusRaw` 接受 V4 的四种旧值，不迁移或批量回写 CloudKit。`planned`、`active`、`completed` raw 只做 round-trip，不能影响可见性、层级、编辑或计时。归档/删除分支不可见且不接收新工作；归档活动子树前必须先停止 timer/Pomodoro，历史 segment 编辑可保留原任务。Today、Quick Start、Pomodoro、手工记录、Inbox 建议、App Intent、任务创建/移动与任务动作共用这一归档/删除判定。
- System routing：`AppDeepLinkRouter` 严格解析 URL；`PendingDeepLinkQueue` 只缓存初始化未完成或当前 scene presentation 忙时已经通过相同验证的语义动作，按动作去重、先进先出且最多 16 项。会改变导航或打开 sheet 的 action 在取得 presentation slot 前不得先改 destination；start/stop 这类无 modal 动作可直接执行。sheet 关闭后再有界重放 deferred action。`WatchCommandRouter` 用弱 store 引用选择最近活跃 iOS scene，并在最后一个 scene 注销后移除进程级 bridge handler。
- Settings：五类导航 IA，不提供应用级 appearance override，也不放置“手动补录”等日常工作流动作。LLM 配置编辑器通过当前 Settings scene 的 presentation router 打开。`SyncSettingsSection` 只拥有开关、状态和 iCloud 账户可用性检查；CloudKit 导入/导出交给系统自动调度，不提供无法保证结果的“立即同步”按钮。`SyncRecoverySettingsSection` 空间上独立承载会覆盖一侧数据的恢复命令：无冲突时默认折叠在一个明确的恢复入口之后，真实冲突时则直接先显示本机与 iCloud 摘要、再显示两个方向。按钮与确认都必须使用破坏性语义和明确的替换方向。根 `ContentView` 对新冲突只显示 scene-local、可忽略的 `SyncConflictNotice` 并导航到 Settings，不在启动/前台刷新时自动弹出覆盖选项；token 变化后才允许再次提示。提示只在主存储可写时出现，iPhone、iPad 与 macOS 都由各自 shell 的顶部 safe-area inset 放置，禁止再用固定底部高度猜测系统 chrome，也不把完整通知卡伪装成 Tab Bar accessory。`SettingsDestructiveConfirmation` 捕获第一次选择时看到的 optional conflict ID；最终确认通过 throwing `resolveSyncConflict(expectedConflictID:resolution:)` 在同一个跨进程 state lock 内精确比较当前 optional ID。ID 或“当时无冲突”状态变化时返回 `conflictChanged`，零模型/state/reset 副作用并在恢复区要求重新核对；匹配后明确返回 `appliedImmediately` 或 `queuedForNextLaunch`，IO/restore/save 失败抛回当前 Settings scene，UI 不从 persistence mode 猜结果。所有 Settings 破坏性动作共用一个 `SettingsDestructiveConfirmation?` presentation state 和一个 `confirmationDialog`，而且 modifier 必须附着在实际承载按钮的 category `Form`；不得在根列表串联多个同类 presentation modifier，或把 modifier 放到 compact `NavigationLink` destination 之外。`CountdownTitleEditor` 持有仅属于界面的标题草稿，`CountdownTitleDraft` 负责脏状态、外部刷新合并和错误呈现；只有保存按钮、Return 或失焦会调用 `CountdownCommandHandler`。命令先规范化并验证标题，再执行 SwiftData 变更，因此逐字符输入不会产生数据库写入或半成品同步事实。日期仍通过独立动作即时保存。
- Pomodoro：下一次专注是唯一主流程，旁边或下方展示最近记录。Plan 和 Task 是两个可见的原生 `Menu`；已选任务主行显示标题，第二行显示不重复标题的父级路径，菜单项继续用完整路径区分同名任务。单一主操作紧跟选择器，计划摘要随后同时公开 focus/short break/long break/rounds，并在宽度允许时优先使用一行四项、否则回退为 2×2。section 测试标识只能属于标题或显式容器元素，不得从整张卡片覆盖 Menu/Button 自身标识；没有点击标题/计时器的隐藏选择逻辑。活动 break 在到期前提供“跳过休息”，到期后显示“开始下一轮专注”，两者都调用同一个显式 resume 命令；Task 当前不可工作时 UI 禁用入口。停止确认保存发起时的 run ID，active run 被替换后必须撤销旧确认，不能对“当前任意 run”执行破坏动作。
- iOS 不设置 `CADisableMinimumFrameDurationOnPhone`；刷新率与帧调度交给系统，流畅度用 Release 截图/trace 和真实设备观察验证，不靠 Info.plist 强制覆盖。

## 4. 核心领域

### 时间事实

TimeSegment 是计时事实来源。它不是“写入后永不可改”的 event：用户可以更正或软删除错误记录；这里的“事实来源”指所有派生统计、当前运行状态和时间线必须从 canonical segment 与明确规则重算，缓存不能成为第二真相。

`TrackedTimePolicy` 是所有已记录时长的唯一读侧边界。对明确的 reference `now`：effective end 为 `min(endedAt ?? now, now)`，再与查询的半开 `DateInterval` 取交集；`startedAt >= now` 或无正区间的记录贡献零。统计、gross/wall/overlap、Analytics、Forecast、Pomodoro elapsed、timeline layout、repository range query、cache signature 和 rollup 都必须调用该 policy，不得在 view/formatter 中直接使用 `endedAt ?? Date()`。

`Services/TimeTracking/TimerAdmission*` 是统一计时协调器的纯值语义边界。它只消费已经 LWW/canonical 的 active snapshots，并输出稳定 start/stop plan：普通同任务 start 复用最早 survivor 并清理重复段，Pomodoro 等需要新 session 的路径显式 `replaceAll`；exclusive 停其他任务，parallel 保留；精确 segment stop 不回退，task stop 覆盖同任务全部活动段，current 取最新 startedAt 并以 UUID 决胜。该 policy 本身不解决跨 context/进程竞态；生产 writer 还必须经过 store-specific lock + fresh context，不能只调用纯 policy 后继续写 scene 持有的旧 model。

`TimerStoreScope`、`StoreScopedTimerMutationLock` 与 `StoreScopedTimerMutationTransaction` 是协调器的事务底座。持久 store 使用解析既存祖先符号链接后的 canonical 文件 URL，同一内存 container 在完整生命周期内复用一个显式 UUID；成对的 root/target 先使用同一套纯词法组件规则做边界检查，不能分别调用 `standardizedFileURL`。`realpath(3)` 返回的物理路径也不得再次经过 `standardizedFileURL`，因为 iOS 会把 `/private/var` 反向改写为 `O_NOFOLLOW_ANY` 必须拒绝的 `/var` 系统别名。锁文件与 store 同目录并使用 `.timer-mutations.lock` 后缀。锁实现复用 `PathFileLockRegistry`/`PathProcessFileLock` 的进程内递归锁与跨进程 `flock`，不得另造第二套文件锁。transaction 必须先取得 store lock，再创建新的 `ModelContext`、关闭 autosave，并用一次 `performAtomicMutation` 统一保存或回滚。锁内只做授权、fresh fetch、plan、model mutation 和 commit；网络、UI 等待及 post-commit read-model/system-surface refresh 留在锁外。Timer、Pomodoro start/break-resume 与 active Segment 编辑的 `allowParallelTimers` 都必须由 `TimerAdmissionPreferenceResolver` 在此 fresh context 内解析，Watch、App Intent 和 facade 不得传递缓存 Bool；Watch processor 同时把锁内实际 outcome 的 events 交给 post-commit surfaces/sync，不能从旧 Watch snapshot 猜测会停止哪些 segment。Timer、Pomodoro、手工时间、新建/编辑 segment、task lifecycle/draft、countdown 新建/更新/删除、同步偏好、同步快照、checklist quick commands 和 Inbox primary commands 已共用此锁域；新增写入口不得退回 scene-owned `ModelContext`。仅设备本地的 LLM Keychain 更新也要在该锁内与完整配置保存串行：读取旧 key、写 key 与 preference commit 同一临界区完成；SwiftData 失败时仍以补偿恢复 key，不能把锁误写成跨存储 ACID。

Checklist 快捷新增、完成状态与重排由 `StoreScopedChecklistCommandCoordinator` 处理。新增命令在锁内验证 canonical task、执行与 task editor 相同的 UTF-8/控制字符校验，并从 fresh checklist 计算排序；完成状态携带 item `clientMutationID`，重排携带完整 item mutation map。目标已删除或任一 baseline 变化时必须拒绝旧操作、刷新 task/checklist read model，且不得推进同步 generation。成功事件中的 ancestor IDs 必须从锁内 fresh task hierarchy 计算，不能使用 scene facade 的旧父链。

Task Category 创建、编辑和删除由 `StoreScopedTaskCategoryCommandCoordinator` 处理。`TaskCategoryEditorDraft` 在打开时固化 category ID 与 `clientMutationID`；编辑和删除必须提交这个 baseline，不能在按钮点按时从 Store 重新构造一个更新后的版本。创建在锁内从 fresh categories 计算 sortOrder；删除在同一事务内墓碑化 canonical category 与当时所有 assignment。Repository 对 missing category 必须抛出 `categoryUnavailable`，不能 silent return。由于 task draft assignment 共用同一锁，assignment-before-delete 会被删除清理，delete-before-assignment 会让 task draft 拒绝不可用分类。

Analytics 不能把一个历史周期压缩成单个“结束前一秒”的伪 `now`。`AnalyticsPeriodEvaluation` 显式携带三项：选中的 Calendar `interval`、用于 `TrackedTimePolicy` 裁剪的 `cutoff`、用于识别真实系统时钟回拨的 `clockReference`。当前周期的 cutoff 是真实墙钟；已完成历史周期的 cutoff 必须精确等于半开区间的 `end`，未来周期的 cutoff 是 `start`。Ledger 的 range query 分别接收 `evaluatedAt` 和 `clockReference`；只有后者早于 index evaluation date 才能触发全库回拨候选，禁止把历史 cutoff 当作时钟回拨。

`AnalyticsComparisonWindow` 是环比统计的唯一窗口定义。当前或未来周期使用 `.matchedProgress`：current 从周期开始裁到 cutoff，previous 按相同日序与本地时分秒映射，不能用固定秒数位移；DST 保留本地钟点，长月映射到短月时在 previous period end 截止。cutoff 精确等于已完成周期 end 时使用 `.completePeriods`，比较两个完整周期。gross、wall、指标脚注和 insight 必须消费同一个 window/basis，禁止 UI 自行推断“上一范围”。

Analytics 月导航先从所选月份的 `Calendar` interval start 位移到目标月，再把根页面持有的 `AnalyticsMonthNavigationAnchor` 映射回目标月。锚点保存原始本地日号和时分秒；目标月缺少该日时只对当月结果 clamp 到月末，不修改锚点，所以 Jan 31 → Feb 28/29 后仍会得到 Mar 31。该状态由 landing 与 category detail 共用，也必须跨 `ViewThatFits` 布局分支保持一致。直接选日期、切换 range、回到今天或进入当前月会清除旧锚点；目标为当前月或未来月时返回真实 `liveNow`，不得停在未来。

`AnalyticsSelectionPolicy` 固化所有会被 `.first` 或单值摘要消费的决胜规则。Task breakdown 按 gross seconds 降序、wall seconds 降序、本地化标题升序、UUID 升序；并列 peak hour 选择最早的本地小时。任务已删除时，breakdown 与 overlap 共用 session title resolver，按 `startedAt`、`updatedAt`、UUID 选择最新有效 snapshot。不得依赖 `Dictionary(grouping:)` 的遍历顺序，也不得在不同投影重新实现不同 fallback。

本地 `addManualSegment` 和 `updateSegment` 在 repository 写入前拒绝未来结束时间或未来 active start，返回 typed `TimeTrackingRepositoryError.futureTime` 与三语 `segment.error.timeNotFuture`。CloudKit、导入和旧 store 可能已含时钟偏差值；不为“修复”而删除事实，而是在每条读/聚合路径安全裁剪。DST 中的持续时长使用绝对 elapsed seconds，本地日 bucket 边界仍交给 `Calendar`。

SwiftUI 写入表面也共用这一语义：`ManualTimePanel` 和 `SegmentEditorPanel` 的开始/结束 `DatePicker` 上限为当前 `now`，时长与保存 enablement 调用 `TrackedTimePolicy`。两个表单都包含任务、两项日期时间、验证和多行备注，iOS 只使用 `.large` detent；不得把完整编辑器塞回不可完成核心流程的 `.medium` 高度。`TrackedTimeDisplaySnapshot` 是 Today timeline、Task Detail recent records 和 `DurationLabel` 的共享显示适配层；future-ended 只显示到 `now`，future-only/future-active 在开始前显示 0，已结束的固定 label 不启动每秒刷新。

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

Inbox 界面复用系统 `List` 与独立 `Section`：iOS 使用 `insetGrouped`，macOS 使用 `inset`，捕获、待整理项目和已完成项目不再嵌套自制卡片。AI 建议在接受前只显示为条目下方的 preview，并复用 `ChecklistItemIcon` 呈现生成的真实图标与颜色；接受后才成为 checklist 事实。Ready 状态固定使用三行信息结构：共享 `EditableChecklistTextRow` 承担完成圆圈与 Inbox 原文，Inbox 显式选择垂直居中而其它多行 checklist 保留默认顶部对齐；下一行的“Suggested/推荐 + 生成图标 + 目标任务”从 24 pt 可见完成圆的左缘开始，不跟随正文列缩进；最后一行使用整张卡片宽度把 Discard 与 Apply 锚定在左右两端。圆圈尺寸和由系统最小点击目标推导的视觉 inset 都由 `InboxItemLayout` 统一拥有。紧凑宽度显示 44 pt 的圆形 × / ✓；宽布局仍是同一 action row，只把内容扩展为图标加文字，不能恢复把目标与动作挤在同一行的 `ViewThatFits`。推荐目标合成为一个辅助功能元素，两个动作保持独立按钮。状态变化动画只包围用户触发的局部变更，时长保持克制并遵守 Reduce Motion。为 UI 测试添加 identifier 时，应标在可读或可操作的叶子节点；不得把同一 identifier 标到外层 row/card，否则 SwiftUI 会向下传播并覆盖按钮与标签的身份。

Inbox 的 primary command 与 suggestion writer 都由 `StoreScopedInboxCommandCoordinator` 执行。Scene 的拖拽先从完整 open item 集合建立 `InboxOrderMutationBaseline`，固化确定性原顺序和每项 `clientMutationID`；单项切换、改名、删除、丢弃建议与手工 suggestion 草稿携带 `InboxItemMutationBaseline`。协调器取得共享 store lock 后用 fresh context 重新解析逻辑 winner；任何目标缺失、revision、顺序、目标 ID 集合或数量变化都会拒绝旧操作。驳回只刷新相关 Inbox/Task/Checklist read model，不写事实或同步 generation；成功命令以锁内 outcome 的 affected IDs 发出 Inbox 事件。新增从锁内 fresh open set 计算 sort order，App Intent capture 也只能传入 container 进入同一 coordinator，提交后才创建新的 context 用于 snapshot 和系统表面投影。LLM completion 以 request title 与 `InboxSuggestionIdentity` 在锁内重新验证逻辑 winner、merged dismissal、canonical suggestion 与 fresh task eligibility；纯 reorder 不使同一 revision 的响应失效，标题/revision、dismissal、完成、删除或目标 task 失效则静默丢弃。apply 额外固定 UI 所见 item/suggestion 的 mutation baseline，并在锁内重新计算 trackable task、Checklist visible set/next sort order 和 ancestor IDs；成功必须同时产生 Inbox 与 Checklist events。

Inbox AI 状态不再只依赖物理 `InboxItem.id`。`suggestionContextID` 是逻辑条目的不透明 UUID，`suggestionRevisionID` 在真实标题修改时轮换，`dismissedSuggestionRevisionID` 只标记当前修订。`InboxSuggestionIdentityService` 用纯 resolution 分开计算内容 LWW winner 与 dismissal identities：只有 exact `(context, revision)` 的 marker 会字段级合并，不能让旧 dismissal 整行覆盖较新的 notes、completion、completedAt 或 sortOrder，也不能跨标题 revision。读取层把 winner 与合并 dismissal 放入不可持久化的 `InboxItemReadModel`；fetch、refresh、排序、索引和 UI 读取不得为投影修改 SwiftData winner。command 通过身份/文本预检后才在原子 mutation 内 materialize，保证无效 reorder 等路径零写入。command 在驳回、删除、应用、重排或标题修改时同时处理同一 context 的 sibling（包括同 UUID 的不同 SwiftData 对象）与 suggestion。异步建议成功和失败都校验请求时标题与完整 identity；apply 必须从 context 重选 canonical active/ready suggestion，不能信任 UI 缓存对象。禁止用标题、规范化标题或其哈希生成 identity；相同标题的独立条目必须保持独立。每条 item/suggestion 只增加固定数量 UUID 字段，不维护无界驳回历史。

Checklist AI visual request 也不是对 scene 缓存的写授权。请求必须固化 item 的 mutation ID、规范化标题和 logical visual 的 `(ID, clientMutationID, userEditedAt)`；completion 在共享 store lock 内 fresh context 重验 task 可追踪性、item 和 visual revision 后才写入。任何另一个 scene 的手动图标/颜色编辑、标题/完成/删除、task 不可用或 logical visual 重建都会使结果变成无副作用的 stale discard，并只刷新当前 scene 的 read model。

同一 App 进程中的多 scene 通过 `StoreMutationBroadcaster` 加速收敛：本地 durable commit 完成、当前 scene 已刷新并记录 snapshot 后，以 source store 广播 events；其它 scene 只按 event plan 刷新 read model，并在任务/ledger plan 时校正失效 selection/route，不再次记录 snapshot 或自动启动 LLM。发送者按 identity 跳过重复 refresh。该通知不是跨进程协议；Widget、Watch、Intent 和其它进程仍须依赖 durable snapshot、persistent history/CloudKit 回调与各自的 post-commit 机制。

任务没有产品层 workflow status。任务编辑器、列表、详情、菜单和辅助功能值都不提供状态选择器、状态徽章、完成或重开动作。Checklist 是任务完成/进度的唯一产品语义：完成全部 checklist 会让 checklist-derived remaining 为零，但不会锁住任务，用户仍可继续计时、编辑和添加清单项。持久化 `statusRaw` 仅为旧 schema/snapshot/CloudKit round-trip 保留；除 `archived` 兼容值外不得驱动业务。

归档与删除语义不同。删除任务树会在一个原子动作中先结束该树的活动 Pomodoro 和 timer，再软删除任务；历史 segment/session/run 继续保留。普通 Local、iCloud、local-fallback 和 emergency 生产模式没有跨设备删除确认，因此 `AppCloudSync.allowsPermanentTombstonePurge` 为 false，`DatabaseMaintenanceService` 直接返回 0。只有隔离的 Demo/UI Test store 可物理清理过期 tombstone graph。

`TaskNode.parentID` 是层级权威；`depth` 是可修复元数据；`path` 现在是稳定 canonical record locator `/<task UUID>`，不是祖先 UUID 链，也不是用户可见标题路径。显示路径由 `TaskTreeService` 根据当前标题迭代生成，并限制为最近六级。启动、任务域刷新和同步恢复都会运行 `TaskHierarchyMetadataService`：缺失父节点和循环会确定性地提升为根，随后重算 depth/canonical path。任务移动只更新真正变化的 depth/path，避免同深度跨根移动重写整棵后代。Repository 与 TaskStore scoped merge 的层级顺序都必须以持久 UUID 作为 depth/sortOrder/createdAt 完全相同时的最终 tie-break，禁止依赖 fetch 或字典输入顺序。

任务树 UI 不直接从 `body` 重建层级。`TimeTrackerStore.rebuildTaskIndexes` 在 task mutation/refresh 后建立排序后的 `TaskTreeIndexes`、可见性和显示路径；task category 或 assignment mutation 也进入同一个 `rebuildTaskTreeReadIndex` 失效边界。不可变 `TaskTreeReadIndex` 只保存稳定 task/category ID、已过滤的 child buckets、section root IDs、child count 和搜索值，不保存第二份持久事实。只有新 index 与旧 index 在语义上不同才推进 `taskTreeReadIndexRevision`。`TaskTreeProjectionCache` 以该 revision 为失效 token，为展开状态和搜索 query 各保留最多四个 ID/value projection；命中时不得再排序 category、过滤每行 children、遍历祖先标题路径或扫描全部搜索文档。timer、ledger、selection 等无关刷新不拥有这个 revision。row identity 始终是持久 `TaskNode.id`，category section identity 始终来自 category UUID（未分类使用固定 `uncategorized`）；不得把标题、数组位置或展开状态变成 identity。任何直接改变会影响层级、可见性、标题路径或搜索文本的模型写入，都必须完成既有 task/category domain refresh，使上述唯一失效 owner 能发布新 index。

持久实体去重遵循确定性 last-write-wins：先比较 `updatedAt`，同一时间 tombstone 胜过 active row，再以 `createdAt`、`deviceID`、`clientMutationID` 稳定打破平局；没有 mutation ID 的 `TimeSegment` 使用稳定内容键。清理产生的 duplicate tombstone 不得反过来覆盖真正的新 canonical row。所有“只取可见记录”的查询必须先 deduplicate/LWW、再过滤 tombstone，禁止把过滤顺序颠倒。

### 番茄会话

PomodoroRun、关联 TimeSession 与运行状态通过同一命令/仓储变更。`startedAt` 表示当前 focus/break phase 的起点，`phaseDeadline` 由持久状态与计划时长派生；它不是 View 本地倒计时。启动、前台、Pomodoro 页面出现和 deadline task 都会调用幂等 reconcile：过期 focus 在业务 deadline 截断 segment/session，避免后台挂起时间被算作专注；过期 break 不会自动新建 focus，下一轮仍需用户动作。

从 break 继续下一轮 focus 是一次新的计时准入。`PomodoroCommandHandler` 必须在同一个原子 mutation 内重新读取 LWW 后的 canonical 任务树，并用 `TaskTrackingAvailabilityService` 验证 run 的任务及全部祖先仍可接收工作；归档、删除或缺失任务都返回 canonical no-op。该拒绝发生在 ledger admission 之前，不停止其他 timer、不创建 segment、不推进 run，也不发布刷新或同步事件；不能只信任 facade/UI 可能过期的 `trackableTaskIDs`。

`PomodoroCountdownSchedule` 只从当前时间产生到 `phaseDeadline` 为止的有限序列；低频模式使用 60 秒步进，deadline 已过或不存在时只产生当前 entry。`TimelineView` 只包围 `PomodoroActiveCountdownView`，不能重新包住整个页面、最近记录或停止操作。视觉 `ProgressView` 从辅助功能树隐藏，由 timer face 统一朗读阶段、完整任务路径与本地化剩余时长，避免重复语义。

通用 ledger 编辑必须保持 Pomodoro 不变量。编辑活动 Pomodoro segment 会重绑 run 的 task/start；把 segment 关闭会按 deadline 完成或取消 run；删除活动 segment 会 tombstone run/session；删除任务树会结束所有活动 timer，并保留已产生的 Pomodoro 历史。相关写入必须在同一个 `performAtomicMutation` 中提交。

### 增量读模型与缓存

- `TaskTreeReadIndex` 在 task/category/assignment refresh 边界预先保存可见 child ID buckets、分类 section roots、child count、显示路径搜索值与稳定顺序。`TaskTreeProjectionCache` 用 store-owned semantic revision 失效，并把展开树与搜索结果分别限制为四个 LRU entry；SwiftUI `body` 只消费 projection。5,000 节点 operation-count 测试要求一次 fully-expanded miss 对每个可见 task 只做一次 child bucket lookup，同一 revision/key 的重复读取 build count 不增加。缓存只持有 ID/value read model，不能持有 SwiftData 对象或无界 query/expansion 历史。
- `LedgerStore` 初次加载建立 segment ID、day、active、time-sensitive、array-index 和 session index；`LedgerStore+SegmentIndex.swift` 协调 day/change index 与 scoped replacement，`LedgerStore+FlatSegmentIndex.swift` 用稳定 start/UUID 顺序维护 UI 所需 flat array。带日期范围的 mutation 只查询/替换相交 segment 与相关 session，并输出 `LedgerSegmentChange`。range read 把统计 cutoff 与真实 wall-clock reference 分开：历史读取继续命中日期索引；active 和 future-ended closed row 在时钟向前时局部重评；只有真实 clock rewind 才全量重评，因为届时任何历史结束时间都可能重新跨过墙钟。
- `LedgerStore+RecordIndexes.swift` 为每个任务维护按 startedAt/UUID 完全决胜的最近 8 条 segment ID，并在 scoped replacement 时增量更新；删除或改期会从该任务完整 ID set 补齐被挤出的第 9 条。Task Detail 的分钟级刷新通过 `segments(overlapping:taskIDs:evaluatedAt:clockReference:)` 直接求当前/上一比较周期与任务分支的交集：planner 先用 task ID bucket 数量和 day/long-span/time-sensitive bucket 上界选择较小的一侧，只物化该侧 ID，再做精确 overlap；不得先物化全 App 周期记录或该任务全部历史。Recent records 另从有界 recent index 合并。若 CloudKit 关系隔离使有界 recent 候选不可见，facade 才为正确性回退到完整 task index，正常一致数据不走该路径。
- CloudKit 可能分批 materialize task、session 与 segment。`TimeTrackerStore+LedgerRelationshipVisibility.swift` 因此保留原始 SwiftData 行，但只发布 task 存在、session 存在且两者 task ID 一致的 segment；不完整/错配行不得进入 Home、Rollup、Analytics、Widget、Watch 或 Pomodoro elapsed。任务或会话稍后到达时，下一次一致性刷新会自动解除隔离，不做破坏性清理。
- `ChecklistStore.refreshTaskScoped` 只替换受影响 task 的 items/visuals，并同步维护 facade bucket，不在每次 toggle 后重新按全库分组。
- `RollupIncrementalIndex` 保存任务拓扑、segment delta、活动摘要、checklist 进度和近期日 bucket；base 文件负责状态与 full rebuild，`RollupIncrementalIndex+Mutation.swift` 负责 scoped delta/replacement 应用。普通 mutation 的工作量由变更记录、任务自身与祖先深度决定；完整历史 worked seconds 始终精确。
- `TaskEstimatePolicy` 统一预计时长输入与旧数据规范化：`0...600` 分钟、`0` 表示未设置、正数最多 36,000 秒。明确预计时长只属于当前任务自身，预计总时长至少等于已经记录的时间；没有明确值时才使用 checklist 证据模型，子任务始终单独递归汇总。
- Forecast pace 使用包含今天在内的最近 90 个本地日，只对有记录的活跃日求日均；它只把已有 remaining seconds 换算为预计活跃日，不生成 remaining seconds。Calendar/时区变化会重建这组有界 bucket。
- `AnalyticsEvaluationCacheKey` 是 landing/category `.task(id:)` 与 `AnalyticsStore` overview/task cache 的共同身份，包含完整 period 起止、当前本地日身份和可选 live-minute bucket，不能从 cutoff 反推 period。当前范围即使没有活动 segment，也会在本地午夜换日 key，使当前周/月的 visible days 与 matched comparison 重新求值；只有与活动 segment 相交时才额外按 `clockReference` 分钟换 key。历史/未来范围没有 live-day/live-minute 身份，因此不会随无关墙钟日变化。snapshot、daily、timeline、group breakdown 与 comparison 统一消费显式 evaluation key、period 和 cutoff；ledger 事件按相交区间失效 day bucket，跨 period 会自然 miss。缓存方法独立在 `AnalyticsStore+Caching.swift`，生成入口不重新实现 key 比较。`AnalyticsSnapshot` 与 `TaskAnalyticsSnapshot` 只缓存不可变 read models，不保存生成期间的 `[TimeSegment]`；需要重算时必须从 Ledger scoped index 重新投影，不能用缓存强引用 SwiftData 模型充当第二数据源。根页和 category 的 cache miss 必须经 async `loadAnalyticsSnapshot`：main actor 先复制 `AnalyticsVisualSnapshotInput`，唯一 owned detached task 在后台计算 Today 的小时活动、timeline 和 overlap；cancellation handler 取消该 task，取消/过期请求不得写入 cache。worker 不得接触 SwiftData model/context、Store、binding 或 lock；其余 core assembly 留在 main actor，并受 2,000 条高重叠 fixture 的 `< 175 ms` residual budget 约束。
- `LedgerBucketCache` 继续为完整 calendar period 保留稳定 daily bucket；`DailySummaryService.visibleSummaries` 只在 bucket lookup 之后按 `summary.date < clamp(cutoff, period)` 生成可见 read model。当前周/月包含正在进行的本地日但不发布未来零日，完整历史周期发布全部日，未来周期发布空数组。`DailyAnalyticsPoint` 以 `Double(seconds) / 60` 向 Chart 提供分钟值，禁止在 View 中做整数除法；Wall/Gross 必须使用显式图例、不同 mark 类型和逐点 VoiceOver 值。
- Today 小时活动图的 24 根柱必须共享 `HourActivityScale`：纵轴上限为 `max(3_600, 当日单小时 grossSeconds 最大值)`，所以普通一小时以 3,600 秒为满高，并发使单小时 gross 超过 3,600 秒时才统一扩展全日尺度。每小时目标高度按秒级 `totalSeconds / upperBoundSeconds` 计算，零值为零高，1...59 秒不得先取整为分钟；`HourStackLayoutEngine` 必须保留所有正时长 task slice，且 slice 高度之和等于该小时目标高度。层间分隔线只能用不参与布局的 overlay，不能把间距额外加到柱高或覆盖极薄的数据层。可视比例不替代语义：每小时 VoiceOver value 继续列出真实总时长与各 task 时长，图高使用 Dynamic Type-aware `@ScaledMetric`，辅助字号下横轴从五个刻度收敛到 0/12/24 三个刻度；可见刻度对辅助技术隐藏，避免在逐小时语义之后重复朗读。
- `AnalyticsRefreshPlan` 是 Analytics 页面时钟的唯一调度 owner：活动当前范围使用与 cache bucket 完全一致的绝对分钟边界，静态当前范围等待 `Calendar` 给出的下一个本地日边界，历史范围不调度。plan identity 保留生成它的 wall-clock sample，所以同一分钟内的系统时钟回拨也会取消旧 sleep 并重新安排。`AnalyticsView` 只在 active scene 用 `.task(id:)` 持有可取消 sleep，并在 scene 激活、日历日、系统时钟或时区变化时重采样；category detail 复用根页面的 `liveNow`，不得再用全页 `TimelineView` 建立第二套刷新树。用户切换日期时必须以动作发生时的 `Date()` 判断是否重新跟随当前 period。
- Analytics snapshot request 变化时，根页和 category detail 都必须先让出一次 SwiftUI 更新周期，再在 `.task(id:)` 计算快照。仅当 `range` 与日历 `interval` 都相同，才可在 revision/live bucket 刷新期间保留旧 snapshot，并在 period controls 显示轻量进度；任何 range 或 interval 改变必须只显示新周期的 loading 状态，禁止给旧指标套用新控件语义。
- Analytics 没有目标/预算模型时，tracked-time comparison 的正负 delta 都使用 `.neutral` insight severity；数值增减是事实，不是价值判断。只有未来引入显式用户目标后，目标上下文才能把某个方向标为 positive/warning，禁止仅按 delta 符号恢复绿色“更好”语义。
- Analytics range 是日、周、月三个日历单位，不得把历史 period 写成“今天/本周/本月”。`AnalyticsRange.today` 是实现名，不是面向用户的文案；只有实际处于历史 period 时才显示“回到今天”动作，当前 period 不保留禁用的重复控件。
- 月范围的前后导航只用 interval start 确定目标月份，不能把上一步被月末 clamp 的日期当成新的 day-of-month 锚点。`AnalyticsMonthNavigationAnchor` 必须由 Analytics 根状态持有并传到所有 period controls；手动日期选择和 range/Today 操作负责重置它。
- Analytics Definitions 是 `AnalyticsGlossaryList` 拥有的非交互说明：区块开场、Gross/Wall/Overlap 的含义与计算、以及一个守恒的并发示例共同组成语义。不得用 `info.circle` 等图标暗示不存在的帮助动作，也不得为静态定义另造 popover；各定义使用稳定 identifier 并保持三语结构一致。
- `CorePerformanceBudgetTests.fiftyThousandSegmentMutationUsesConstantSizedRollupDelta` 以 50,000 个 segment 约束单 segment 增量更新和 cached recent ranking；最终是否通过仍以冻结工作树的 xcresult 为准。

## 5. 持久化、CloudKit 与迁移

当前 schema 为 V11（版本标识 `1.10.0`），迁移计划覆盖 V1 至 V11。V9 通过 V8→V9 lightweight migration 移除持久化 `DailySummary` 派生缓存；V10 通过 V9→V10 custom migration 为 Inbox item/suggestion 初始化不透明 context/revision UUID，并把旧版“已有 generatedAt 且没有 active suggestion”转换为该修订的显式 dismissal；V11 通过 V10→V11 lightweight migration 加入 durable Inbox capture receipt。任务、segment、session、Pomodoro、checklist、Inbox、倒计时、分类和偏好等用户事实仍保留。`DailySummary` 类型只留给 V1...V8 schema 读取与迁移，V9 Inbox 类型保留冻结旧形状；当前 registry 不包含 `DailySummary`。`TaskNode.statusRaw` 继续按 V4 兼容合同 round-trip，不为移除 UI 状态机新增 schema migration。版本升级时：

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

同步刷新是事件驱动的：`NSPersistentStoreRemoteChange` 和 `NSPersistentCloudKitContainer.eventChangedNotification` 进入 `TimeTrackerStore+SyncObservers`。首个通知建立固定 350 ms 截止时间，后续通知只合并进常量空间的 batch，不取消并后推计时器；否则持续导入会让刷新饥饿并让原因队列无界增长。窗口保留最高优先级活动、最新 import 结果与是否需要冲突处理，再由 refresh planner 执行一次一致性刷新。启动与 scene 回到 active 时仍会刷新；不要重新引入常驻 5 秒轮询。`SyncedPreferenceService.latestByKey` 必须先完成 LWW/tombstone 选择，再过滤已删除结果，否则旧 active preference 会复活。legacy `UserDefaults` 迁移也必须从 logical-key LWW winner 判断 key 是否已迁移；winning tombstone 仍表示“已迁移”，必须阻止旧本机值重新导入。

Settings 的同步状态使用 typed `SyncActivityOutcome`，不能从“本机执行过 refresh”反推 CloudKit 成功。只有带结束时间且 `event.succeeded == true` 的 import/export/setup event，在本机 read-model refresh 与冲突状态处理都成功后，才能记录 `.succeeded`；单独的 `NSPersistentStoreRemoteChange` 只触发刷新，不生成绿色活动。CloudKit error、export checkpoint 状态写入失败或本机后处理失败记录 `.failed(message:)`，并由状态卡呈现，不写共享 `errorMessage`。最近成功只在完成时间不晚于当前时间且 120 秒内成立；账户检查独立更新 `CloudAccountCheckOutcome`，不得伪造或清除同步活动。

`AppCloudSync.enabledKey` 是设备本地启动配置，只保存在 `UserDefaults`，修改后下次启动生效。它不属于 `AppPreferenceKey`，也不能进入 `SyncedPreference`、冲突快照或导出/恢复数据。历史 `TimeTrackerCloudSyncEnabled` 记录在这些边界统一过滤。普通 Local、Demo 和 UI Test 模式的 mutation 不生成冲突快照；CloudKit 活跃或存在待上传恢复时，`StoreDomainEvent` 只重抓受影响的 task、ledger、pomodoro、preference、countdown、checklist 或 inbox 域。仅 full sync、远程 import 和没有 baseline 的初始化需要捕获全部域。

启动期 CloudKit reset 由 `CloudRecoveryGate` 严格门控。factory 必须先退出 demo 与用户禁用分支，再处理 pending reset；缺失/不可读的受保护上传快照为 deferred，store 或同步状态删除失败为 failed，均保留 pending 并停在本地恢复路径。只有 completed 返回的 `CompletedCloudRecovery` token 能传给 `recordCloudKitEnabled(after:)`；而且必须等 CloudKit container 真实创建成功后才能消费 token、清 pending/error。不得恢复无参 acknowledgement、Bool 门控或失败后继续尝试云容器。

Local fallback 的 SwiftData commit 与 post-commit sync snapshot 不是同一文件事务；进程可在两者之间退出。再次尝试 CloudKit 时，`performPendingCloudRecoveryResetAfterProtectingLocalFallback` 必须用一个外层 `StoreScopedTimerMutationLock` 连续覆盖：重开仍完整的 local store、fresh context 全域 capture、权威 state 与 forced-upload mirror 落盘、恢复意图准备、destructive store reset。内部 snapshot/reset 可以递归取得同一路径锁，但外层锁在 reset 完成前不能释放；临时 `ModelContainer`/`ModelContext` 必须在删除 SQLite 前结束生命周期。Capture/state/mirror 任一步失败都回到原 local fallback，不删 store。`.downloadCloud` 是用户明确放弃本机分支，禁止 preflight recapture 把它反转成 reconciliation；upload/reconciliation 则必须保护最新 commit。这个保证只覆盖遵守共享 store lock 的 writer，任何新 writer 绕过该锁都会重新打开 snapshot/delete 竞态。

恢复意图必须区分 `.reconcileWithCloud` 与 `.explicitlyReplaceCloud`。自动 fallback/重新启用只排队 reconciliation：保护本机快照、建立 fresh CloudKit cache、等完整首次导入，再比较 fingerprint；相同则收敛，不同则生成两侧冲突，比较前不得恢复本机快照或制造 export。只有用户明确选择本机赢家才保存 explicit intent，并在恢复 bootstrap 中把受保护快照恢复为本地赢家一次。legacy/missing intent 和独立 mirror 在没有不含糊的 upload marker 时一律按 conservative reconciliation 推断。

upload、download 与 reconciliation 请求在 `AppCloudSync+RecoveryIntent` 中互斥；新选择清除相反 pending/active marker。若旧版本留下同时 upload+download 的矛盾标记，gate 返回 `.conflictingRecoveryRequests`，不得删除 store。CloudKit recovery container 已经附着后，Settings 旧 scene 发起的 stage/upload/download/resolution 通过 `requireNoAttachedCloudRecovery()` 拒绝，防止中途改变方向。

fresh-store hydration 以持久 `CloudRecoveryImportSession` 为屏障，而不是 setup、remote change 或任意 import。会话记录 UUID、kind、startedAt、storeIdentifier、成功 setup 完成时间和其后的成功 initial import 完成时间；只接受 `endDate != nil`、`event.succeeded`、event start 不早于 epoch、setup 先完成、同一 storeIdentifier 且 import start 不早于 setup completion 的事件。`CloudRecoveryImportBuffer` 在 ModelContainer 创建前先收集可能过早到达的完成事件，observer 安装后再 drain。下载/reconciliation 只在会话 kind 与当前 gate 一致且 initial import 完成时解除；错误 kind、旧 epoch、失败、乱序或其它 store 的事件都不能解锁写入。

崩溃重启只复用完整的 setup+import 会话；未完成会话重新排队 fresh-store reset，避免半次导入被误判成功，也避免永远等待已丢失的通知。恢复期 `TimeTrackerStore` 只安装 read-side repositories/observers 并刷新读模型，推迟偏好迁移、seed、Pomodoro reconciliation、LLM/system side effects 和账户检查。恢复完成通知会更新每个已配置 scene；同一 store 的启动配置用 single-flight + 一次合并重试防止同步通知造成 reentrant bootstrap 和重复恢复。

同步文件所有权如下：

- `SyncConflictService.swift`：bootstrap 与 prompt 组装。
- `SyncConflictService+LocalMutation.swift`、`+CloudImport.swift`、`+CloudExport.swift`、`+CloudRecoveryEvents.swift`、`+Recovery.swift`、`+Resolution.swift`：本地变更、云事件/恢复回执与显式恢复流程。
- `SyncConflictService+State.swift`、`+StateWriting.swift`、`+StateLock.swift`、`+StateLocations.swift`、`+SnapshotSlots.swift`、`+SnapshotSlotLocations.swift` 与 `SyncConflictStateManifest.swift`：有界本机 manifest/slot state 读写、pending forced-upload mirror、跨进程锁、文件位置与 epoch/generation/checkpoint state；`SyncConflictState.swift` 仍是运行时读模型，不是新的磁盘格式。
- `SyncConflictService+Export.swift`：过滤后的 JSON export encoding。
- `SyncDataSnapshot.swift`：版本化全域快照、摘要和 fingerprint。
- `SyncDataSnapshot+Capture.swift`：按域捕获当前事实。
- `SyncDataSnapshot+Preflight.swift`、`SyncDataSnapshot+PreflightContent.swift` 与 `SyncDataSnapshot+PreflightSemantics.swift`：在恢复事务前对不可信 transport 做结构、内容和语义预检。
- `SyncDataSnapshot+Restore.swift`、`SyncDataSnapshot+RestoreTasks.swift`、`SyncDataSnapshot+RestoreLedger.swift`、`SyncDataSnapshot+RestorePlanning.swift`、`SyncDataSnapshot+RestoreChecklist.swift` 与 `SyncDataSnapshot+RestoreInbox.swift`：预检通过后，在一个原子事务中分域恢复。
- `SyncSnapshotRecords.swift`、`SyncSnapshotLedgerRecords.swift`、`SyncSnapshotPlanningRecords.swift`、`SyncSnapshotChecklistRecords.swift` 与 `SyncSnapshotInboxRecords.swift`：组织/任务基础和分域跨版本 Codable record DTO；它们不是第二套业务模型。

通用的本机恢复文件基础设施位于 `Services/SystemIntegration/DurableLocalFile*` 与 `PathFileLock.swift`。它只负责文件系统提交，不负责 JSON schema、幂等 identity、重试状态机或业务合并：调用方必须先完成 payload 大小、版本、时间范围和语义预检。恢复关键路径必须传入同一状态家族的稳定、已存在 `durableRootURL`；兼容 overload 只适用于调用开始时最近既存祖先已经是可靠根目录的简单文件。对同一 canonical 文件混用不同 durable root 会产生不同锁，属于调用方错误。

每个显式 root 使用保留的 `.TimeTrackerDurable.lock`。进程内递归锁与跨进程 `flock` 共用该 inode；写入、删除和隔离必须持有同一 root 锁，且 API 拒绝把锁文件本身当成 payload。目标只允许普通文件；符号链接、目录与特殊文件全部 fail closed，删除使用 `unlink`，不会递归删除目录。路径校验使用组件边界与 `O_NOFOLLOW_ANY`，防止词法 `..`、既存目录符号链接和 Foundation 根目录父路径表示差异把操作带出 root。由于 iOS/macOS 的合法容器路径可能位于 `/var` 这类系统符号链接之后，primitive 会先用 `realpath(3)` 固定已存在 root 的物理路径，再把 root 内的相对后缀映射到该路径；调用方选择的 root 是信任边界，因此 root 之上的祖先别名（包括平台提供的路径别名）会被解析，而 root 自身、其子目录和 payload 仍然拒绝符号链接。该边界面向 App 自有容器内的协作进程，不是抵御能在检查与 rename 之间任意改写目录的敌对进程的完整 sandbox。

写入在目标同目录创建权限为 `0600` 的随机临时文件，完整写入后先附加 iOS `completeUntilFirstUserAuthentication` 与可选 backup exclusion，再执行 `fsync`、`F_FULLFSYNC` 和原子 `rename`，最后同步父目录。发布前失败保留旧 canonical；发布后目录同步失败会明确抛错，调用方应按“新内容可能已发布”恢复。下一次同目录写入会在 root 锁内清理严格 `.TimeTrackerWrite-*.tmp` 命名的普通文件/符号链接并同步目录，因此进程死亡最多留下一个等待下次写入回收的临时文件，不会随重试无界增长。

损坏文件隔离统一进入同级 `.TimeTrackerQuarantine`，整个目录而不是单个 prefix 共享上限：最多 8 个普通文件、总计 16 MiB、最长 14 天；过期、明显未来时间、超数量和超字节的条目在 root 锁内修剪并同步目录。超出单文件预算的 canonical 会被耐久删除但不保留诊断副本。隔离移动失败会回滚；若 canonical 已被其他内容占据或回滚本身失败，错误同时报告 canonical 与 quarantine 路径，调用方不得把它降级成普通 decode failure。

这组 primitive 是后续 durable queue、outbox 和恢复 artifact 的共享底座；既有 `SyncConflictService` 私有状态文件仍保持自己的边界，迁移时必须在一个小任务里替换读写、故障恢复与测试，不能仅把写调用机械改名后宣称获得相同保证。

`SyncConflictState.json` 的每次 read-modify-write 都在 `SyncConflictService.withExclusiveStateAccess` 内完成。进程内使用递归锁，跨主应用/Shortcuts 进程使用 POSIX advisory `lockf` 文件锁；两个进程不会用各自的旧状态副本互相覆盖。磁盘 authority 是 V1 小型 manifest：它只存版本、epoch/generation/checkpoint 等标量和至多四个快照引用；`SyncConflictState` 的完整 snapshot 不再内联复制。每个引用指定八个受控 A/B slot 中的位置、generation、byte count 和 SHA-256；slot payload 先经 `DurableLocalFile` 写入并完整同步，最后才发布 manifest。因而中断在 manifest 前仍由旧 manifest 指向完整旧 slot；发布后才清理无引用 slot。首次读取旧的内联 JSON 会在同一锁内升级到 manifest，运行时调用方继续只处理 `SyncConflictState`。这只是设备本地恢复格式变更，不是 SwiftData/CloudKit schema。

manifest、slot、forced-upload mirror、默认删除和损坏隔离都经注入的 `DurableLocalFile`：生产环境以稳定的 Application Support 父目录为 root，测试/诊断 override 只拥有显式 state directory。文件保护在 publish 前设置，随后执行 file 与 parent-directory full sync；损坏小文件进入有界 quarantine，超出诊断预算的文件只耐久删除而不保留副本。manifest 上限为 128 MiB，每个 slot 和 recovery mirror 上限为 64 MiB；读取先用 file metadata 预检，再通过 `FileHandle.read(upToCount: limit + 1)` 抵御预检后文件增长的 TOCTOU，不做无界 `Data(contentsOf:)`。slot writer/reader 已持有 canonical sorted JSON 时直接散列该字节，不得为同一 SHA-256 再编码整份快照。写入在解析路径或替换 authority 前验证所有新 slot、manifest 和所需 mirror 的上限。若任一 manifest 引用的 slot 缺失、超限、无法解码、长度不符或 hash 不符，slot 与 manifest 都视为损坏并隔离，禁止把残缺 state 当作“没有冲突”。损坏/超限的独立 pending mirror 仍会安全忽略，不能阻塞主库；镜像只在 manifest 缺失时作为恢复来源。大小拒绝不能改写旧 manifest 或 mirror。

`pendingConflictID` 同时是用户确认的版本 token，不只是一次冲突的标签。本机 branch 或待接受云 branch 的 resolution-relevant snapshot 发生实质变化时必须在上述锁内旋转 ID，并从保存后的 state 重建 prompt；不得继续返回变化前的摘要。恢复入口也必须在 locked `loadState()` 后、任何 epoch 推进、snapshot restore、reset flag、clear/save 之前比较 expected optional ID。旧 token 和“原来没有冲突、确认前出现冲突”都返回 `conflictChanged`，不能把检查放到锁外。

`SyncConflictService.prompt()` 是 throwing read boundary：只有合法 state 中确实没有完整 pending conflict 才返回 `nil`。损坏、超限、权限和文件系统错误必须传播给 Store；禁止用 `try?` 把它们转换成“无冲突”。已经写入 local snapshot 的 `recordLocalMutation` 会在同一 state lock 内返回 `.recorded(prompt:)`，调用方不得为同一次 mutation 再读一次 `prompt()`；`.notRecorded` 则保留原本的 throwing read 边界。Watch 等已经提交业务 mutation 的入口把真正随后发生的 prompt 读取失败报告为 post-commit refresh failure，不能把 terminal command 结果倒写成未提交。

在 iOS 上，manifest、其快照 slot、pending forced-upload 恢复镜像和腐损状态隔离文件写入后都设置 `FileProtectionType.completeUntilFirstUserAuthentication`。这些文件在设备本次启动首次解锁前不可读，首次解锁后可供后台 Shortcuts/CloudKit 流程继续使用；lock 文件不是用户快照，也不能被描述为同样的受保护数据文件。macOS 不套用 iOS Data Protection 属性。

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

当前 Intent 与应用进程复用 `timetrackerApp.applicationModelContainer`，不为每次查询/动作重新创建容器。Start Timer 会读取同步偏好中的 `allowParallelTimers`，不得硬编码与主应用不同的并行规则；实体查询排除 tombstone 与归档任务。系统动作同样检查 recovery 只读状态；任何写入都必须调用所属的 store-scoped coordinator 并在共享 lock 的 fresh context 内原子提交，不能把 App Intent 的 scene-less `ModelContext` 当作并发边界。

Intent durable mutation 提交后，`CommittedMutationSnapshotRecorder` 更新同步恢复状态，`CommittedMutationSurfaceSynchronizer` 用窄依赖配置刷新 task/ledger/preference read models，再投影到 Widget、Watch 和 Live Activity。它不会启动完整应用 lifecycle 或自动 LLM 工作。post-commit 失败只记录/呈现“已保存但投影刷新失败”，不得把已提交的非幂等动作返回为失败并诱发系统重试。

### Live Activity

Live Activity 是只读状态投影。Activity attributes 应保持小而稳定，不保存唯一业务事实；extension 不直接写 SwiftData 或 iCloud。锁屏与展开 Dynamic Island 必须复用同一个 `LiveActivityTimerRow`：锁屏采用与 Today/Now 相同的“34 pt 图标 / headline 标题与 caption 路径 / title3 等宽时间”层级，展开 Dynamic Island 在普通字号只保留“图标 / 标题 / 时间”单行，不显示路径、附加计时数量或停止控件。点按任意 Live Activity 表面只打开 Today，停止操作由 Today 的可见计时行完成。Widget 的显式停止入口仍携带当前可见 segment ID，不受本规则影响。更新失败应重试或降级显示，但不应阻断主应用写入。扩展对任务文本使用隐私处理，并明确表达 stale 状态。

`LiveActivityTimingPolicy` 是 ActivityKit `staleDate` 与 UI elapsed presentation 的共同边界：活动从 canonical `startedAt` 起最多实时增长八小时，进入 stale 后必须切换为固定的 `LiveActivityElapsedPresentation.frozen`，可见文本和 accessibility value 都使用同一个冻结秒数。不得只改状态标签而继续渲染 `Text(startedAt, style: .timer)`；Dynamic Island compact trailing 与 minimal 也必须复用该 policy，不能成为继续增长的例外。任务身份由现有 `TaskIdentityPresentation` 生成，完整/缩写 breadcrumb 都按 Unicode 边界投影到受限字段，不能在 Live Activity 内另建一套 parent-path 算法。锁屏内容在辅助功能字号下直接采用纵向结构，其他字号用 `ViewThatFits(in: .horizontal)` 在宽行和堆叠结构之间选择；expanded 普通字号优先单行，空间确实不足或辅助功能字号才使用同一组件的纵向回退。compact 可截断任务名，minimal 只显示 frozen-aware elapsed，因为系统宽度无法容纳完整身份。

### Watch

Watch target 的状态 owner 是同一个 `WatchAppStore` 类型，但职责按 extension 文件拆开：base 文件只持有 observable state、依赖和恢复；Commands 文件处理 submit/retry/discard、20 秒确认 timeout 与本机 queue persistence；Connectivity 文件处理 activation/transmit、payload/result/snapshot application 与 freshness/error；SessionDelegate 文件只负责 WCSession callbacks。手机 facade 同样分工：`TimeTrackerStore+WatchSnapshot.swift` 只构造投影、预算与兼容 membership，`TimeTrackerStore+WatchCommands.swift` 只处理 Watch 命令并在需要时刷新相关 read models。新增逻辑应进入对应 owner，不能重新把 transport、delegate、queue lifecycle、快照和命令处理混回同一文件。

Watch 使用持久快照加命令队列。每个 `WatchTimerCommand.id` 是幂等键；新命令和进程恢复命令走 durable `transferUserInfo`，可达时再用 `sendMessage` 加速；单纯 reachability 变化只重发即时消息，不能重复制造 durable 副本。手机返回七态 typed terminal result（success、duplicate、missingTask、missingSegment、invalid、failed、timeout），并用 durable user-info 再投递；20 秒无 terminal result 会进入可重试失败态，retry 保留 ID、刷新 `issuedAt`，用户也可 discard。`WatchCommandProcessor` 在 receipt lookup 后、任何 mutation 前校验 DTO 和时间边界：命令最多保留 30 秒，允许最多 5 分钟的未来设备时钟偏差；过期/非法命令返回 invalid 且不写 receipt 或 ledger，因此用户仍可用同 ID 明确重试。快照反射只为旧手机兼容确认。

Watch UI 在一个 `NavigationStack` 内使用 `.verticalPage` `TabView`，依次承载 `WatchActiveTimersPage`、Quick Start `WatchTaskListView` 和 All Tasks `WatchTaskListView`。第一份已接收 snapshot 只做一次默认页选择：通常有 active timer 时进入 Active Timers，否则进入 Quick Start；但只要 `status != nil` 或存在 command failure，即使 timers 为空也进入 Active Timers，让 sending/queued、connectivity error、stale 和 retry/discard 恢复路径可见。`hasSelectedInitialPage` 建立后，后续 snapshot、命令确认、status/failure 或 stale 刷新不得改写用户当前页；Quick Start 与 All Tasks 改以 `.safeAreaInset(edge: .top)` 显示 `attentionButton`，其 label `minHeight` 为 44 pt，点按显式切到 Active Timers。数码表冠和系统纵向分页是页面导航 owner，不得恢复深层“所有任务” push 或把三个目的重新塞回单一长列表。

Quick Start 与 All Tasks 是两个不同投影。Quick Start 排除当前运行任务，先按可选 `quickStartRank` 放入固定项，再从 legacy wire 顺序补足，UI 最多四项。All Tasks 不按 pin 重排：producer 按 segment count 降序、last-start 降序、UUID 字符串升序计算 canonical rank，并写入可选 `allTasksRank`；无历史任务以 `.distantPast` 参与稳定尾部排序。新 Watch 的 `allTasksByUsage` 按该 metadata 还原顺序，缺失 metadata 时保持 `recentTasks` 原始顺序作为兼容回退。运行任务必须仍在 All Tasks，行尾以绿色 timer 图标表达状态，Running 文案只进入辅助功能标签；点按只把 `selectedPage` 切到 Active Timers，只有 Active Timers row 可以发送精确 segment stop。非运行任务在已有 timer 时仍可发送 start，最终 parallel/switch 继续由手机 store lock 内的 `allowParallelTimers` 决定，Watch view 不预判或复制准入规则。

行状态通过一次 Set/Dictionary index 构建，不能为每行线性扫描命令队列。`WatchActiveTimersPage` 的 List 固定按 failure section、status section、timer section 排列：只预览第一个失败，更多失败进入“全部问题”，每项提供 retry/discard；等待、发送、已排队、连接错误和 stale 状态紧随失败，不能被 timer rows 压到后面。`WCSession.isReachable` 只表示即时消息通道，不等于后台同步离线。较旧 snapshot 不能覆盖较新的已显示状态；任务、计时和失败标题在 luminance-reduced/Always On 状态继续使用 privacy redaction。主 target 的 codec/state/processor 测试不能替代真机往返验证。

Watch 的 activity elapsed 只能在快照 current 时由 `Text(startedAt, style: .timer)` 实时增长。超过 `WatchStateSnapshot.staleAfter` 时，row 必须冻结在 `generatedAt - startedAt`，并由顶部/状态行明确说明数据陈旧；不能一边标记 stale、一边继续显示计时仍在增长。任何 `refreshPreferences` 都要重新投影 Watch 快照，因为 `quickStartTaskIDs` 是 Watch 首页的直接输入。

所有 WatchConnectivity payload 和本机恢复数据都按不可信输入处理。Codec 在构造领域 DTO 前后验证有限日期、UTF-8 byte 长度、数组数量、唯一 command/timer/task ID、唯一且有界的 Quick Start/All Tasks rank、summary 非负上限、active timer 年龄和未来时钟偏差。Watch state snapshot 最多包含 64 个 active timer 和 256 个 `recentTasks` wire items；该 key 与数组的 legacy pinned-first 顺序都为旧 Watch 保持不变。新增的 `quickStartRank` 与 `allTasksRank` 必须可选，旧 payload 缺少它们时解码为 `nil`。producer 先在 256 项与 active timers 共用的 128 KiB 文本预算内按四级优先级去重决定 membership：第一，已实际进入 `activeTimers` 且仍有 task projection 的 running tasks；第二，当前 `quickStartRank` pins；第三，`legacyWatchTaskOrder()` 中旧 Watch 会显示的前 `legacyQuickStartTaskLimit == 4` 个非运行 rows；第四，`rankedTrackableTasks()` 的 canonical usage remainder。只有入选集合固定后，才把入选项按 legacy order 重排为 wire array，并写入连续 `allTasksRank` 供新 Watch 恢复 All Tasks 顺序；最终 wire reorder 不得改变 membership。这样旧 Watch 忽略字段后仍保留既有前四项 Quick Start，新 Watch 连接旧手机时也能按原数组稳定回退；running/pin/legacy reservation 只影响上限内保留资格，不得改变带 metadata 的 All Tasks 排序。iPhone durable incoming queue 最多 64 个命令；Watch persisted pending/failed 各最多 64 项；编码队列最多 512 KiB。`WatchCommandQueueState.isSafeForRestoration` 拒绝结构非法、command/result ID 不一致或跨列表重复的状态。pending overflow 把最旧项转成 `queueOverflow` failure，failed overflow 丢弃最旧 failure；无法安全恢复的本机数据会清除，而不是解码后继续执行。字段上限的唯一常量表是 `WatchTransportLimits`，不得在 codec、store 和 UI 各写不同数值。

### Deep link 与 scene 生命周期

`AppDeepLinkRouter` 只接受 `timetracker` scheme、最长 2,048 bytes、无 user/password/port/fragment 的白名单路由；每个 host/path 还限制 query 名称、数量和 UUID 格式。`ContentView` 在 repository 尚未配置时把合法 URL 放入 scene-local `PendingDeepLinkQueue`：容量 16，按解析后的 `AppDeepLinkAction` 去重，满时丢弃最旧项，配置成功后按顺序 drain，scene 消失时清空。带 `taskID` 的停止链接与共享 system-action command 都只能停止该任务的活动 segment；目标已停止时必须成为无操作，不能回退停止另一条并行计时。只有不带 `taskID` 的通用停止动作可以选择当前最近的活动 segment。不要把未验证 URL、closure 或可无限增长的数组放入启动队列。

iOS `WindowGroup` 可以产生多个 scene，而 `WatchConnectivityBridge` 只有一个进程级 command handler。`WatchCommandRouter` 因此保存 scene registration 与弱 `TimeTrackerStore` 引用，优先最近 active scene，没有 active scene 时才回退到最近仍存活的注册；注销/释放会清理 route，最后一个 route 消失时移除 bridge closure。不得让 singleton closure 强持有 scene store，或由每个 `ContentView` 无条件覆盖全局 handler。

### Widget

Widget 从版本化共享快照读取数据，区分共享容器不可用、缺失与损坏，不把所有失败都显示成“没有计时”。`WidgetSnapshotCache.snapshot` 在 producer 边界限制 64 active/64 recent（当前 Widget recent UI 只投影前 3 项），将 summary 裁到非负上限、timer start 裁到 `generatedAt - maximumActiveTimerAge ... generatedAt`，并用 Unicode-safe prefix 将投影 title/path/style 限制为 512/1,024/128 UTF-8 bytes。所有文本共用 128 KiB 预算，从而保持 Widget JSON 不超过 256 KiB。

Widget 的容器级 `.widgetURL` 永远是 `WidgetDeepLinks.today`。启动任务是 mutation，必须由显示任务名的显式 `Link(destination: WidgetDeepLinks.startTimer(...))` 发起；不得根据 recent task 动态改写背景 URL，否则任意空白区域点击都会偷偷启动列表第一项。小型空状态只给首个 recent task 一个明确的 44 pt Quick Start 目标，中型布局的任务行各自持有链接，背景仍只负责打开应用。

`WidgetSnapshotLimits` 同时是 consumer/store 验证的唯一上限表：解码字段的 title/path/style 硬上限为 4 KiB/16 KiB/256 UTF-8 bytes，并验证有限日期、最多 5 分钟未来偏差、summary/active-age 上限和唯一 ID。`SharedWidgetSnapshotStore.save` 在写 App Group UserDefaults 前拒绝非法/超限快照；`loadResult` 在 decode 前检查字节，decode 后重新验证，失败返回 `.corrupted`。Watch producer 复用裁剪后的 active timers，并对最多 256 recent task 应用同样的 Unicode-safe 512/1,024/128-byte 投影上限和共享 128 KiB 文本预算。这些裁剪不写回任务或账本。时间线根据 snapshot freshness 和 active timer 安排刷新。主应用和扩展已启用 `group.me.mezorewww.timetracker`，Xcode 自动签名构建已生成带该 entitlement 的 profile；发行门禁仍要求真机验证共享容器 URL、读写、刷新策略、锁屏与离线状态。

Widget 的 elapsed 也以快照可信度为准：只有 `.current` 可使用 system timer text；`.stale` 与 `.clockAdjusted` 都冻结在 snapshot 的 `generatedAt`，并保留已有 stale/clock-adjusted 说明。WidgetKit 的时间线重载不会保证主应用事实仍然有效，因此不能借自动计时文本把陈旧 projection 伪装为实时状态。

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
- 模型发现不得先把服务端 `data` 全量物化为数组或无界 Set。`LLMModelListResponse` 逐项解码到 `LLMModelIDAccumulator`，只保留与偏好 sanitizer 相同的升序前 256 个唯一有效完整 ID；总响应仍同时受 transport 的 2 MiB 上限约束。
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
3. 默认先验证正常字号下的系统导航、控件、键盘、窗口尺寸与平台 HIG；保留 Dynamic Type/VoiceOver 基础语义，只在文本重排、语义或既有回归风险触发时增加对应专项。
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

导出边界必须 fail closed：读取、过滤或编码失败时抛出错误，由发起 scene 展示且不打开 `fileExporter`。禁止返回 `{}`、空数组、`nil` 或旧缓存作为占位成功结果；否则用户无法区分“数据确实为空”和“导出已经失败”。行为测试至少覆盖有效内容、敏感字段过滤、未配置/序列化失败不产生文档，以及 UI 只在获得真实 payload 后呈现导出面板。系统文件导出器的用户取消不进入错误队列。

## 10. 测试策略

优先级从高到低：

1. 领域行为与迁移测试
2. Store/command 集成测试
3. 正常字号下以稳定界面标识驱动的核心流程测试
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

本轮参考的 [Lakr233/FlowDown](https://github.com/Lakr233/FlowDown) 固定快照为 commit `694ba5d`。RecoveryMode、版本化 importer/checksum/staging 和多 target 测试组织只作模式参考；没有复制 UIKit 组件，也没有引入 SnapKit、ColorfulX、SPIndicator 或其传递依赖。

两个经过定向审查的 Swift Package 是明确例外：

- MarkdownView 固定为 `4.1.7`，只在任务备注证据态渲染 Markdown。
- [BlossomColorPicker](https://github.com/Lakr233/BlossomColorPicker/) 固定为官方 revision `9a1ee3df309e37ae271362818dcdfdb072ea9611`。它是 MIT 许可、无传递依赖、无网络和数据访问的本地 UI 包；iOS 适配层直接复用其公开 Core，macOS 使用其顶层 presenter。

依赖 revision/version、`Package.resolved` 和 [AD-117](AgentDecisions.md) 必须同步。移除 BlossomColorPicker 时只删除 package 引用与 `SymbolColorWell` 适配，已保存的六位 sRGB 数据不需要迁移。其它依赖仍必须先满足 [AD-011](AgentDecisions.md) 的许可证、供应链、体积、性能、隐私与回退证据要求，不能从这两个例外推导出整套 FlowDown 依赖获批。

## 13. 相关文档

- [用户操作手册](UserGuide.md)
- [Agent 决策文档](AgentDecisions.md)
- [隐私与安全](PrivacyAndSecurity.md)
- [项目地图](ProjectMap.md)
- [本地化](Localization.md)
- [测试](Testing.md)
