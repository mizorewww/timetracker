# Time Tracker

Time Tracker 是一个使用 SwiftUI、SwiftData、Swift Charts、ActivityKit 和 CloudKit/iCloud 能力构建的本地优先时间账本应用。它的核心不是“待办事项列表”，也不是“番茄钟”，而是把用户真实发生过的工作、学习、生活和琐事记录成可追溯、可修正、可分析的时间账本。

应用当前覆盖 iPhone、iPad 和 macOS，并包含 Live Activity、App Intents/Shortcuts、Widget 和 Apple Watch target。工程保持 Xcode 自动签名并使用开发团队 `LT98S43NKA`；主应用与 Widget 已配置同一 App Group。代码侧构建和模拟器验证不能替代真实设备验收，发行前仍需完成 Widget 共享容器、Watch durable command/terminal-result 往返和 Live Activity 系统行为的真机验证。项目代码已经按功能、领域和数据流拆分，后续系统入口必须复用底层时间模型。

## 设计宗旨

Time Tracker 的第一原则是：时间记录是事实，任务、番茄钟、分析和预测都只是围绕事实的不同视图。

传统待办应用关注“我要做什么”，时间追踪应用关注“我做了多久”，番茄钟应用关注“我是否保持专注”。Time Tracker 试图把这三者合并成一个稳定的系统：

```text
任务告诉用户：我要做什么。
时间账本告诉用户：我实际上做了什么。
番茄钟告诉用户：我是否以专注方式完成。
分析告诉用户：我的时间模式是否健康、有效、可持续。
```

因此，项目坚持这些原则：

- `TimeSegment` 是事实来源。任何普通计时、手动补录、番茄钟、Live Activity、Widget 或 Watch 操作，最终都必须通过共享命令落入统一的时间账本。
- 任务是时间的归属对象，不是时间本身。任务可以移动、归档、软删除，但历史时间记录不应随意消失。
- UI 可以重构，分析可以重算，原始账本数据必须尽量稳定。
- Forecast 必须可解释。用户明确填写的预计时长可以直接形成计划预测；否则必须同时有 checklist 完成证据和真实计时，近期历史只用于换算活跃日，不凭空生成剩余工时。
- 本地优先。用户数据保存在 SwiftData，本地可用；iCloud 同步是跨设备能力，不应把业务逻辑变成网络依赖。
- 多平台入口必须复用同一套命令和用例，避免 App、Live Activity、Widget 或 Watch 各写一套计时逻辑。

## 当前功能

### Today 首页

Today 是日常使用的核心入口，回答三个问题：现在正在追踪什么、今天已经发生了什么、下一步可以快速继续什么。

- 查看当前所有 Active Timers。
- 支持多个任务同时计时。
- 以原生 `List` 展示今日总时长、可选墙钟时间和时间线。
- Quick Start 支持固定任务和最近高频任务。
- 显示由任务预计时长或 checklist 证据驱动的剩余时间预测。
- iPhone、iPad 与 macOS Today 都显示用户自定义倒计时事件；日、周、月、年这类低价值通用进度不再占据 Today。
- Active Timer、Forecast 和 Timeline 行可以直接打开只读优先的任务详情。
- iPhone 使用系统原生五标签 `TabView`，Settings 从 Today 工具栏以 scene-owned sheet 进入，关闭后保留原标签与导航；iPad 在所有窗口宽度都保持同一个 `NavigationSplitView`，由系统折叠或显示侧边栏而不切换根导航；macOS 使用 `NavigationSplitView` 和独立 Settings 场景。

### 任务与任务树

任务系统用于组织时间归属，而不是替代时间账本。

- 无限嵌套任务树。
- 所有任务都可以包含子任务，也都可以被计时。
- 任务支持状态，例如未完成、计划中、已完成。
- 任务支持颜色、SF Symbol、备注、预计时间、截止时间等编辑信息。
- 任务支持归档和软删除。
- 移动任务时会防止循环。`parentID` 是层级权威；普通启动/同步刷新只在投影中安全断开暂时 orphan/cycle，不改写 CloudKit 分阶段送达的事实，显式快照恢复才执行持久规范化。持久 `path` 是稳定 `/<UUID>` locator，用户可见标题路径即时派生，避免移动根节点时重写整棵子树。
- 父任务的展示时间会递归包含自身和子任务时间。
- 根任务可以归入用户自定义 Category，用于区分工作、学习、生活、健康等不同语境。
- Category 可控制该分支是否参与预测，为后续不同预测模型和 HealthKit 等能力预留空间。
- “已完成”是可恢复的工作状态：任务与历史仍留在任务树中，但自身和后代不能接收新计时、手动记录、番茄钟或 checklist 转入，直到用户重新打开完成路径上的阻塞任务。“归档”则隐藏整个分支。
- 自身仍为进行中/计划中的子任务可以从已完成或归档父链移到根级或可用父任务，作为纠正错误归类的恢复出口；任务自身完成/归档时仍不能借移动绕过状态。
- 任务编辑草稿记录任务、checklist 外观和分类 assignment 的 mutation baseline；并发窗口或同步结果改变相关内容后，旧草稿会拒绝保存，避免覆盖、复活或误删 sibling 变更。

### Checklist

Checklist 是任务内部的执行拆分，不是子任务，也不能单独计时。计时仍绑定到任务本身。

- 每个任务可以创建 checklist。
- Checklist 项支持完成、取消完成、删除、排序。
- 未完成项优先显示，完成项置后并保留历史。
- 完成项保留是预测系统的一部分，因为它们提供了“完成一项平均需要多久”的证据。
- Checklist 项支持图标和颜色。
- 可使用 LLM 为 checklist 建议 SF Symbol 和颜色。
- 未填写任务预计时长时，Forecast 会根据 checklist 完成度和任务真实计时实时更新。

### 预测系统

预测系统优先采用用户为当前任务明确填写的预计时长；没有明确预计时长时，才使用等权 checklist 证据模型。任务编辑器中的预计时长为 15 分钟步进，`0` 表示未设置，上限为 10 小时；旧数据中的越界值在读取时会被安全限制。

```text
如果任务或全部 checklist 已完成：
  该任务自身剩余时间 = 0

如果任务填写了预计时长：
  预计总时长 = max(明确预计时长, 当前任务直接记录时间)
  剩余时间 = max(0, 明确预计时长 - 当前任务直接记录时间)

否则，如果任务没有 checklist：
  不预测，提示用户添加 checklist 或填写预计时长

如果 checklist 完成数为 0：
  不预测，提示用户至少完成一项并记录时间

如果已完成 checklist 但任务没有计时：
  不预测，提示用户需要真实计时

如果已完成数 > 0 且已计时：
  每项平均时间 = 当前任务直接记录时间 / 已完成项数量
  剩余时间 = 每项平均时间 * 未完成项数量

```

预计时长只描述当前任务自身，不会吞并子任务；父任务预测会把自身来源与子任务预测递归相加。父任务自身没有预测来源但只有一个可预测子分支时，界面会直接展示那个子任务；如果有多个可预测子分支，会展示父任务汇总并说明它来自多个来源。最近 90 个本地日的历史节奏只把已经得到的剩余秒数换算成预计活跃日，不会创造剩余工时。

### Inbox

Inbox 用于快速收集还没有整理归属的事项。

- 快速新增收集项。
- 收集项可以完成、删除、编辑。
- 配置 OpenAI API 并明确开启设备本地的“自动建议”后，可自动建议应该归类到哪个任务；失败建议可重试，当前没有独立手动请求或建议编辑器。
- 用户可以接受建议，把 Inbox 项转换为目标任务下的 checklist。
- 用户也可以丢弃建议；编辑标题后可重新触发建议。
- 新增输入只在数据库提交成功后清空；只读恢复状态或保存错误会保留原草稿，允许直接重试。
- LLM 请求最多发送 48 个任务候选，优先保留 Quick Start 固定项、高频/近期任务，再稳定补足；模型只看到 78 个精选语义 SF Symbols，用户的完整图标选择器不受影响。网络投影按 UTF-8 字节与总请求预算缩短，不回写任务/Inbox/checklist 原文；响应使用禁用缓存/cookie 的临时会话流式读取，60 秒资源超时且最多 2 MiB，非成功状态不读取正文。LLM 结果仍经任务 ID、已公告 SF Symbol、颜色和文本上限校验。

### 计时账本

计时系统以 `TimeSession` 和 `TimeSegment` 为核心。

- 开始任务会创建 `TimeSession` 和 active `TimeSegment`。
- 停止任务会关闭 segment 并结束 session。
- 在不允许并行计时的设置下，开始新任务会停止其它正在运行的任务。
- 多个 `endedAt == nil` 的 segment 表示多个任务同时运行。
- 支持手动补录时间。
- 支持编辑和软删除时间记录。
- 本地补录/编辑不允许开始或结束落在未来；界面会返回明确错误，不会写入一条“未来工时”。
- 对 iCloud、导入或旧版本中因设备时钟偏差已经存在的未来值，不静默删除事实；所有统计以当前参考时间为上界裁剪，不会提前计入尚未发生的时长。
- 跨天和重叠时间会在分析中按明确规则处理。

### 番茄钟

番茄钟是专注流程，不是独立账本。

- 番茄钟必须绑定任务。
- 开始番茄钟会创建 `PomodoroRun`、`TimeSession` 和 `TimeSegment`。
- 取消和完成都会同步更新 ledger。
- 完成最终专注轮次会正确结束关联 session。
- 开始前通过明确的“计划”和“任务”菜单完成选择，不再依赖点击计时器或标题的隐藏交互。
- 专注页任务选择保持为页面本地状态，不改写任务页的全局选择；继续、完成和停止操作携带 `runID + state + clientMutationID` phase token，旧阶段操作不能命中下一轮同名状态。
- 专注计划的时长、休息和轮次可在“设置 → 专注”中管理。
- 当前阶段由持久 phase 状态和计划时长派生 deadline；后台挂起或重启后，过期专注会在同一 deadline 截断账本。休息结束后由用户明确开始下一轮，不在后台擅自创建 focus segment。
- 编辑/删除活动番茄时间片和删除任务树会同步结束或 tombstone 对应 run，防止番茄状态与账本脱节。

### Analytics

Analytics 从 `TimeSegment` 聚合，不把统计结果当成事实来源。

- Today、Week、Month 多范围统计。
- 首页先展示当前范围摘要；“复盘”优先提供决策与质量，“深入查看”再提供时间、任务、番茄钟和指标详情，不再把所有图表堆在一个滚动页面。
- Gross Time 和 Wall Time 双口径：
  - Gross Time：所有任务时间直接相加。
  - Wall Time：去重后的真实时钟时间。
- 任务分布图按任务颜色展示。
- 今日活动分布处理短任务和重叠任务，避免极短记录完全不可见。
- 时间线支持重叠任务、相邻任务、跨天任务和长空白压缩。
- Month 图表使用真实日期，不用重复 weekday 作为数据 identity。
- Overlap 分析展示多任务同时计时造成的差异。
- Analytics 使用缓存 snapshot，避免 SwiftUI view body 内做重计算。
- 辅助功能大字体下，范围选择自动从横向 segmented control 变为菜单，详情行允许纵向生长。

### Live Activity

当前包含 Live Activity 扩展，用于展示正在计时的任务。

- 新鲜状态且普通字号下，锁屏复用 Today/Now 的任务身份层级，展开灵动岛只用一行展示任务图标、任务名和持续时间；空间不足或辅助字号使用同一组件自适应，stale 时只额外显示状态 glyph。
- 整个表面点按后打开 Today，停止计时由应用内正在计时行完成，不在 Live Activity 堆叠停止控件。
- 共享 ActivityAttributes，避免主 App 和扩展模型漂移。
- 文案走本地化，不在扩展中硬编码中文。

### App Intents、Shortcuts 与 Apple Watch

- App Intents 支持添加收件箱项目、开始计时和停止计时，并由系统快捷指令发现。
- Apple Watch 通过 WatchConnectivity 接收主应用快照，并持久排队用户命令；命令与 terminal result 使用 durable `transferUserInfo`，可达消息仅用于加速。
- Watch 主界面是 Active Timers、Quick Start、All Tasks 三张系统纵向页面。第一份快照通常有活动计时就落在 Active Timers，否则落在 Quick Start；若命令失败、同步发送/排队、连接错误或 stale 状态需要处理，即使没有 timer 也先落在 Active Timers。后续出现 status/failure 不抢走当前页面，而是在 Quick Start 与 All Tasks 顶部提供 44 pt “Review/查看状态”按钮跳回 Active Timers；Active Timers 内按 failure、status、timer 的顺序让恢复信息优先可见。
- Quick Start 独立使用固定任务顺序并以高频/近期任务补足至四项；All Tasks 不继承固定顺序，而按 segment count 降序、last-start 降序、UUID 稳定排序。运行任务仍留在 All Tasks，点按后回到 Active Timers；其它任务即使已有计时也可发起开始，最终并行或切换由锁内读取的全局并行偏好决定。
- Watch 上的操作以手机 typed terminal result 为主要确认；20 秒超时后可用同一 command ID 安全重试或丢弃，重试会刷新命令时间。手机拒绝超过 30 秒的旧命令，避免离线队列在很久以后意外开始或停止计时；旧手机的快照反射保留为兼容路径。
- Watch 状态快照最多包含 64 个活动计时和 256 个可工作任务，文本总预算 128 KiB。producer 按四级 membership 优先级去重选择：实际传输的 running tasks、新 Quick Start pins、旧 Watch 会显示的前四个非运行 legacy Quick rows、canonical usage remainder；集合确定后才为旧 Watch 兼容重排 wire 数组。既有 `recentTasks` key 及其 legacy pinned-first 数组顺序保持不变，只新增可选 `quickStartRank` 与 `allTasksRank`：新 Watch 用后者恢复独立的 usage 排序，旧 Watch 忽略新字段仍得到原 Quick Start，新 Watch 收到旧手机 payload 时则回退到 wire 顺序。producer 按 Unicode 字符边界缩短超长投影文本，并裁剪 summary 与异常 timer start，不修改主账本/任务事实。命令 incoming/pending/failed 队列各 64 项，本地编码队列最多 512 KiB。超限、重复 ID、异常时间或过大字段不会被接受为有效快照或可恢复队列。
- 命令失败、陈旧快照冻结和 Always On 隐私遮盖继续保留；三页重排不把失败吞掉，也不让 stale elapsed 继续增长。
- 这些入口复用领域命令，不单独维护第二套账本逻辑。
- Widget、Live Activity 和系统链接使用同一个严格 deep-link router。App 在 SwiftData 尚未准备好时只保留经验证、按动作去重且有上限的待处理链接，初始化完成后再执行；无效或超长 URL 不进入队列。
- iOS 的 Watch command handler 由进程级弱引用 router 选择最近活跃 scene；scene 消失时注销，避免单例 bridge 永久强持有旧 `TimeTrackerStore` 或把命令发给错误窗口。

### Widget

Widget extension 与快照代码已经存在，主应用和扩展已启用 `group.me.mezorewww.timetracker`，自动签名构建也生成了相应 profile。Producer 在投影时先限制数量，用 Unicode-safe prefix 压缩超长文本，裁剪 summary/timer start，并共用 128 KiB 文本预算；共享 store 再对保存和读取执行快照验证：JSON 上限 256 KiB，active/recent 数组各最多 64 项，并检查有限日期、统计范围、UTF-8 字节和唯一 ID。超限保存会明确失败，超限/非法读取会进入 corrupted 状态，不伪装成“没有计时”。完成共享容器和真机读取/刷新验证前，仍不把它列为已完成发行验证的功能。

### 设置与维护

设置按“通用、专注、数据与同步、AI 助手、高级”分类，避免把普通偏好、危险维护操作与开发诊断混在一页。应用外观跟随系统，不提供与系统偏好冲突的独立亮色/深色开关。

- 并行计时、总时长/墙钟时间显示和倒计时事件。
- Pomodoro 专注计划。
- iCloud 同步开关和同步状态反馈。开关仅保存在当前设备，并在下次启动时决定是否创建 CloudKit 容器；它不会跨设备同步。
- 同步状态只把 CloudKit 明确结束、且本机刷新与冲突处理均成功的 import、export 或 setup 显示为最近成功活动。remote-store 通知只触发刷新；CloudKit 事件或本机后处理失败显示原因，账户检查不会伪造同步成功。
- OpenAI-compatible endpoint、API key 和模型选择使用 Test→Save 草稿：键入不持久化，测试只加载模型，用户明确保存后才写入偏好/Keychain。API key 仅存于本机不同步的 Keychain，每台设备需单独设置。
- 可同步偏好在写入前按 key 完成整批类型检查、规范化与 256 KiB JSON 上限验证；任一值为 `null`、畸形、类型错误或超限时整批不变，保存失败会回滚。
- 自动 AI 建议是默认关闭、设备本地的第二个明确开关；配置成功不会自动开启内容发送。
- JSON 数据导出。当前没有 importer、校验和或事务恢复，因此导出不是可恢复备份。
- “清空全部数据”会逻辑删除业务数据，并同时清除本机 Keychain 中的 LLM API key 和设备本地的自动建议同意；当前设备的 iCloud 启动开关不会被这个动作悄悄改写。
- Debug 与 Release 的自动演示模式都默认为关闭；Debug/内部明确启用后使用独立、无 CloudKit 的 `TimeTracker-Demo.store`，不会把 demo 写入用户 store。
- 普通生产 Local/iCloud/local-fallback/emergency store 永不物理 purge tombstone，避免离线设备复活旧数据；永久优化入口只在隔离 Demo/UI Test store 可用。
- About 页面展示 app 图标、版本号、build number、branch、commit hash 和构建时间。
- 只读恢复页可复制包含状态、错误、存储模式和 store 路径的诊断；Mac 还可打开数据目录并完整退出。诊断含本机路径，分享前必须检查和脱敏。
- 共享设置行在辅助功能字号下会纵向换行，VoiceOver 直接读出标题/当前值/同步状态。破坏性动作同时使用系统 destructive 语义和红色文字/图标，不只依赖图标或颜色暗示风险。

## 数据模型

核心模型如下：

| Model | 作用 |
| --- | --- |
| `TaskNode` | 任务树节点。所有任务可计时、可嵌套、可归类。 |
| `TaskCategory` | 用户自定义根语境，例如工作、学习、生活。可影响预测策略。 |
| `ChecklistItem` | 任务内部 checklist 项，用于执行拆分和预测证据。 |
| `InboxItem` | 未整理的收集项，可由 LLM 建议归类。 |
| `TimeSession` | 一次工作意图，例如“写报告”。 |
| `TimeSegment` | 真实发生的一段时间，是时间账本事实来源。 |
| `PomodoroRun` | 番茄钟流程状态，最终生成或更新 TimeSegment。 |
| `CountdownEvent` | 用户自定义倒计时事件。 |
| `SyncedPreference` | 非敏感用户设置，以 JSON 存入 SwiftData 并可通过 iCloud 同步；API key 等秘密明确排除。 |

核心数据普遍包含 `id`、`createdAt`、`updatedAt`、`deletedAt`、`deviceID` 和 `clientMutationID`，用于软删除、同步、冲突处理和幂等操作。`deviceID` 仅接受当前平台前缀加规范 UUID；旧的畸形、跨平台、含控制字符或超限值会被随机身份替换，不包含主机名或账户名。

## 架构概览

项目采用本地优先的模块化单体结构。UI 不直接写 SwiftData，持久化和业务动作通过 command、repository、domain store 和 service 分层。`TimeTrackerStore` 是 `@MainActor @Observable` 门面；SwiftUI 使用 `@State` 持有它。每个可呈现 UI 的 scene 另持有自己的 typed `AppPresentationRouter` 和 `AppSceneFeedbackRouter`，共享 Store 但不共享 sheet 草稿或瞬时 alert 队列；只在系统 binding 确实需要时建立局部 `@Bindable`。

```text
SwiftUI Feature
  -> TimeTrackerStore facade
  -> Command handler
  -> Repository protocol
  -> SwiftData repository
  -> SwiftData model
  -> Domain store snapshot
  -> Pure services derive secondary state
```

主要边界：

- `Features`：SwiftUI 页面和局部组件。
- `SharedUI`：跨功能复用的原生风格控件、布局策略和视觉 token。
- `App`：启动与 scene 根视图，以及每个 scene 唯一的 App 级 presentation router/host 和 feedback router/host。
- `Stores/Facade`：`TimeTrackerStore` 的 UI-facing 适配层。
- `Stores/Domains`：Task、Ledger、Checklist、Rollup、Analytics、Preference 等领域状态。
- `Commands`：持久写入动作，例如开始计时、移动任务、切换 checklist、应用 Inbox 建议。
- `Repositories`：SwiftData 查询与写入实现。
- `Services`：可测试算法，例如时间聚合、forecast、timeline layout 和 database maintenance。
- `Models`：SwiftData 模型、schema、迁移计划、read models。
- `SharedLiveActivity` / `timetrackerLiveActivityExtension`：Live Activity 共享模型和扩展 UI。

本轮结构拆分已经落到文件系统，而不是只停留在计划：Analytics landing page/typed category detail/store、Pomodoro setup composition/empty/focus/selection/timer face、Settings sections 与共享 row foundation/action/input/presentation/sync-feedback、Task Detail sections、ledger infrastructure、facade configuration、Widget provider/view/support、Watch 三页 dashboard/active timers/task list/timer/status/color 与 base/commands/connectivity/session-delegate store family，以及 SyncConflict 的 bootstrap、本地变更、云导入/导出、恢复、状态锁、snapshot restore 预检/分域写入和 record DTO 都已分离。当前仍超出或接近结构预算的 facade lifecycle/preference/sync observer、任务行动作和 Analytics period selection 等真实文件记录在 [Docs/CodeRefactorPlan.md](Docs/CodeRefactorPlan.md)，不再引用已经删除的旧聚合文件，也不以“所有文件都已单一职责”作泛化承诺。

CloudKit 刷新由持久存储远程变更和 CloudKit import/export 事件驱动，并做短暂合并；前台激活仍会进行一次一致性刷新。没有常驻的 5 秒全量轮询。

正常 mutation 使用增量 read model：Ledger 按相交日期范围更新 segment/session index，Checklist 按 task 更新，Rollup 消费 segment delta 并只重算任务与祖先；活动和未来结束的时间片被标记为 time-sensitive，时间前进时局部重算，系统时钟回拨时才全量重评。完整历史 worked seconds 保持精确，预测 pace 只使用最近 90 个本地日的活跃日平均。Analytics overview/task snapshot 按 range、真实 period start 和活动计时的分钟 bucket 缓存，不在 SwiftUI `body` 或历史视图时钟 tick 中重算。性能套件包含 50,000 segment 的单记录增量等价性与预算测试。

同步冲突状态的 read-modify-write 由进程内递归锁和跨进程 POSIX file lock 串行化。Cloud export 使用 epoch、generation、fingerprint 与 bounded event checkpoint，乱序旧回调不能把较新的本机变更误标为已同步。

一次用户写入由 store/system command 包在单个 `ModelContext` 原子 mutation 中；嵌套仓储步骤延迟到最后统一保存，失败会 rollback。保存完成后的界面刷新或同步快照失败会明确提示“更改已保存但刷新失败”，不会把已经提交的事实误报成回滚。

Mac 只创建一个主 `Window`；系统 Settings 是独立场景，但与主窗口共享同一个应用级 store，避免重复安装同步 observers、自动 AI 工作和系统表面同步。

详细文件定位请看 [Docs/ProjectMap.md](Docs/ProjectMap.md)。架构规则请看 [Docs/Architecture.md](Docs/Architecture.md) 和 [Docs/CodeRefactorPlan.md](Docs/CodeRefactorPlan.md)。

## 目录结构

```text
timetracker/
  App/                 App entry, scenes, root views, build metadata, demo data
  AppIntents/          Shortcuts and system intent entry points
  Commands/            Durable write actions and use-case-style handlers
  Features/            Home, Inbox, Tasks, Ledger, Pomodoro, Analytics, Settings, Sidebar
  Models/              SwiftData models, schema versions, migration, read models
  Repositories/        SwiftData-backed repository implementations
  Services/            Analytics, forecasting, checklist, ledger, LLM, maintenance, tasks
  Stores/              Domain stores, facade, refresh planner, selection/navigation
  Shared/              Strings and extension-safe shared helpers
  SharedUI/            Native-styled shared components and layout policies

timetrackerLiveActivityExtension/
timetrackerWidgetExtension/
timetrackerWatchApp/
SharedLiveActivity/
timetrackerTests/
timetrackerUITests/
Docs/
scripts/
BuildSupport/
DesignAssets/
```

## 本地开发

### 准备

1. 使用 Xcode 打开 `timetracker.xcodeproj`。
2. 确认 shared scheme 中存在 `timetracker`。
3. 建议启用仓库自带 git hook，让每次 commit 自动递增 patch version 和 build number：

```sh
git config core.hooksPath .githooks
```

工程使用 `CODE_SIGN_STYLE = Automatic` 和开发团队 `LT98S43NKA`。不要用 `CODE_SIGNING_ALLOWED=NO` 或清空团队配置绕过能力问题；需要 CloudKit、App Group、Widget、Watch 或 Live Activity 时，应保留真实 entitlement/profile 并修复签名原因。

本轮只定向参考了 [Lakr233/FlowDown](https://github.com/Lakr233/FlowDown) commit `694ba5d` 的恢复、备份格式和测试组织模式，没有把它的第三方依赖栈带入工程；当前工程没有因该参考新增 Swift Package 依赖。取舍与未来触发条件见 [Agent 决策 AD-011](Docs/AgentDecisions.md)。

### 运行测试

macOS 单元测试：

```sh
xcodebuild test -project timetracker.xcodeproj -scheme timetracker -destination 'platform=macOS' -only-testing:timetrackerTests
```

iOS generic build：

```sh
xcodebuild build -project timetracker.xcodeproj -scheme timetracker -destination 'generic/platform=iOS'
```

检查 scheme：

```sh
xcodebuild -list -project timetracker.xcodeproj
```

导出签名产物：

```sh
./scripts/export_signed_artifacts.sh
```

更多测试要求见 [Docs/Testing.md](Docs/Testing.md)。

### 当前验证状态

本轮重构代码已由 `55f19ae` 收口并停止主动扩张。最终取得的 R1 定向测试、性能预算、签名 Release archive 与资源清理证据，以及没有执行因而不作通过声明的完整 unit/UI/设备/trace 矩阵，统一记录在 [Docs/Audit-2026-07-14.md](Docs/Audit-2026-07-14.md)。历史批次不能机械相加成“当前工作树全套通过”；未执行项是明确的声明边界，不表示 Agent 会继续无限重构或后台补跑。

## 版本与构建信息

版本号由仓库管理，而不是靠聊天上下文记忆。

- `MARKETING_VERSION` 是用户可见版本号。
- `CURRENT_PROJECT_VERSION` 是 build number。
- `.githooks/pre-commit` 会在普通 commit 时自动把 patch version 增加 `0.0.1`，并把 build number 增加 `1`。
- `scripts/write_build_info_plist.sh` 会在 build phase 中写入 `AppBuildInfo.plist`，包含 branch、commit hash、dirty flag 和构建时间。

详见 [Docs/Versioning.md](Docs/Versioning.md)。

构建、安装、签名导出和版本维护脚本的完整说明见 [Docs/Scripts.md](Docs/Scripts.md)。

## 开发规则

为了避免项目重新变成难以维护的大文件，后续开发应遵守：

1. 功能先写预期和测试，再写 UI。
2. SwiftUI view 只负责展示和收集输入。
3. 持久写入必须经过 command handler。
4. SwiftData 查询和写入只放在 repository。
5. 复杂计算必须放在 service，并有单元测试。
6. 新增用户可见字符串必须补 English、简体中文、繁体中文。
7. Schema 变化必须考虑旧 iCloud store 的兼容性。
8. 新增系统入口必须复用同一套 command/use-case，不复制 ledger 逻辑。
9. 自定义 UI/动画要谨慎，优先使用系统组件和原生交互。
10. 性能问题先用测试或 Instruments 定位，再改架构。

## 相关文档

| 文档 | 内容 |
| --- | --- |
| [Docs/ProjectMap.md](Docs/ProjectMap.md) | 新人定位文件夹和模块的入口。 |
| [Docs/UserGuide.md](Docs/UserGuide.md) | 当前用户操作、同步、导出和系统入口说明。 |
| [Docs/CodeGuide.md](Docs/CodeGuide.md) | 当前代码地图、数据流、迁移和扩展方式。 |
| [Docs/AgentDecisions.md](Docs/AgentDecisions.md) | Agent 与维护者必须遵守的架构和安全决策。 |
| [Docs/PrivacyAndSecurity.md](Docs/PrivacyAndSecurity.md) | 数据存储、CloudKit、AI、Keychain 和扩展的数据边界。 |
| [Docs/Audit-2026-07-14.md](Docs/Audit-2026-07-14.md) | 本轮全面审核的红色基线、重构结果、验证证据和真机门禁。 |
| [Docs/Architecture.md](Docs/Architecture.md) | 领域模型、ledger 原则、forecast 规则和数据流。 |
| [Docs/CodeRefactorPlan.md](Docs/CodeRefactorPlan.md) | 已完成的结构拆分、当前集中点和重构护栏。 |
| [Docs/NativeUIPlan.md](Docs/NativeUIPlan.md) | 原生优先 UI 规则和未来截图/设备验收清单。 |
| [Docs/NextDevelopmentPlan.md](Docs/NextDevelopmentPlan.md) | 后续产品方向和验收标准。 |
| [Docs/Testing.md](Docs/Testing.md) | 测试命令、覆盖要求、性能验证和设备验证。 |
| [Docs/Scripts.md](Docs/Scripts.md) | 版本递增、构建信息、签名导出和多平台安装脚本。 |
| [Docs/Localization.md](Docs/Localization.md) | 多语言和文案治理。 |
| [Docs/Versioning.md](Docs/Versioning.md) | 版本号、build number 和构建信息写入。 |

## 后续方向

下一阶段重点不是增加更多孤立页面，而是继续强化“统一时间账本”：

- 打磨 Inbox 和 LLM 归类体验。
- 改进 checklist forecast 的解释和可信度。
- 继续优化 Analytics 的可读性和性能。
- 稳定 App Intents、Shortcuts 和 Apple Watch 的测试；完成 Widget App Group 真机读写与刷新验证。
- 为不同 TaskCategory 引入更合理的预测策略，例如工作线性外推、生活/健康更偏习惯统计。
- 加强 iCloud schema 兼容测试，避免旧设备数据被新版本破坏。

只要 `TimeSegment` 事实层保持稳定，未来系统入口、分析维度、AI 辅助和跨设备能力都可以在同一套账本上扩展。
