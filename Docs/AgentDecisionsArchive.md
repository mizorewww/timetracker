# TimeTracker Agent 决策归档

状态：历史记录，不是当前指令

本文件保留从 [活动决策文档](AgentDecisions.md) 移出的已替代决策与历史说明。实现、审核和重构必须遵循活动文档中的 Accepted 决策；这里的内容只用于追溯演进。

## 2026-07-25 测试契约迁移说明

各决策“验证”中提到的源码扫描契约（`CoreSourceLayoutTests`、UIContracts 源码扫描层、各 “source contract/源码契约” 断言）已整体删除，相关表述是历史验证记录，不再对应现存测试；当前验证以领域行为、store/command 集成、accessibility identifier UI 与截图检查为准，且不得新增源码字符串扫描。AD-014 的“源码扫描只保留少量架构护栏”由此说明替代。

## AD-049：iOS 根导航由稳定设备 idiom 选择

状态：Superseded by AD-139

背景：旧 `iOSRootView` 把 `horizontalSizeClass == .regular` 当成 iPad，其他宽度当成 iPhone。iPad 进入分屏、Stage Manager 窄窗口或中间宽度时会变为 compact，于是整个 `NavigationSplitView` 被替换成五标签 `TabView`；sidebar selection、detail navigation 和各根容器内部状态都可能被重建。大屏 iPhone 横屏也可以出现 regular width，size class 并不是设备类型。

历史决策：`RootLayoutPolicy` 曾将 interface idiom 映射为 `.phone` 或 `.pad` shell，并要求根 shell 不随宽度改变。AD-139 已删除这条设备身份规则；本段只保留演进背景，不再约束当前实现。

后果：本决策不再授权读取设备 idiom 或按设备固定根导航。当前宽度驱动 shell、状态所有权和平台 capability 边界以 AD-139 为准。

验证：纯策略测试覆盖 phone、pad 和 unsupported 映射；源码契约确认 `iOSRootView` 使用 `UIDevice.current.userInterfaceIdiom`、不再读取 `horizontalSizeClass`。付费开发者签名的 macOS 策略/契约套件 31/31 通过，截图基础设施调整后的最终契约套件 8/8 通过。iPad Pro 11-inch 的串行 UI 用例使用系统 Show Sidebar，选择合并语义后的 task row，再在同一 scene 中竖屏→横屏→竖屏；三次都保留 `ipad.splitNavigation`、同一 task detail 和只读状态，三张屏幕级截图目视通过。Stage Manager 紧凑窗口仍保留在最终人工矩阵，不以旋转测试替代。所有专用模拟器都已终止、关闭并删除，最终进程与 Booted 设备审计为空。

## AD-056：定向停止链接不得回退到其他计时

状态：Superseded by AD-080

背景：Live Activity 的停止链接携带所属任务的 `taskID`，共享 system-action command 也接受可选任务 identity。两处旧处理逻辑都把“未找到该任务的活动 segment”和“动作没有 taskID”合并成 nil-coalescing 回退；如果用户延迟点击已结束任务的陈旧系统表面，而另一任务正在计时，就会误停后者。

决策：本条首先确立“定向目标失效不得回退”的边界。AD-080 随后把目标从 task identity 收紧为 segment identity，并把无目标行为从“最近一条”改为“仅唯一活动时间片时兼容”。当前实现与新增入口必须遵守 AD-080；本条不再授权按最近顺序停止。

后果：陈旧 Live Activity、Widget 或外部定向链接不会修改无关任务。历史上的 task-ID/no-target 规则只说明演进过程，不能覆盖 AD-080 的精确 segment 与唯一候选约束。

验证：原始回归继续证明定向目标失效不修改其它时间片；当前完整矩阵和签名证据由 AD-080 与 dated Audit 记录。

## AD-079：Quick Start 整行只负责开始或打开，不按运行状态变成停止

状态：Superseded by AD-102

背景：Quick Start 的任务行原先在未运行时开始计时，却在运行中无提示地把同一整行改成停止；视觉只把播放符号换成红色停止符号。快速入口因此成为隐藏 toggle，误点会结束正在记录的上下文，并与“正在计时”区的显式停止操作重复。

决策：未运行的 Quick Start 任务行执行开始/切换；运行中的任务行显示 `RunningStatusBadge`，再次点击打开该任务详情。整行不得按隐藏运行状态调用 `store.stop`，也不得用红色停止 glyph 暗示 toggle。停止只存在于“正在计时”、任务详情、任务选择器运行区和携带明确目标的系统表面。iPhone 通过 scene 导航闭包打开任务，iPad/macOS 通过 canonical task-detail router 打开同一详情。

后果：Quick Start 的主语义稳定为“进入这项工作”：未运行时开始，已运行时查看；停止始终是单独、可发现且带目标的操作。新增 Quick Start 布局必须复用该语义，不得重新把整行写成 start/stop toggle。

验证：本条的历史回归保留为“运行态不把整行变为停止”的边界。当前独立任务内容与计时命令的合同、平台一致性和更新后的正常字号回归由 AD-102 负责。

## AD-097：Task Detail 标题只在系统导航栏出现一次

状态：Superseded by AD-124

替代关系：AD-124 替代“系统 navigation title 是任务标题唯一 owner”及 identity row 不显示标题的条款；本决策关于系统返回、正常字号底部余量和不重复运行状态的其余边界继续有效。

背景：任务详情的 inline navigation title 已显示任务名称，但首个 identity card 又以更大的文字重复同一名称。运行中的任务首屏因此把垂直空间花在重复信息上，真正可执行的 Stop / Add Time 及 Forecast 被推低；长标题还会和状态 badge 竞争一行。

决策：系统 navigation title 是任务标题唯一 owner。`TaskDetailIdentityRow` 只呈现任务图标、父级 path（根任务明确显示 root）与运行/业务状态；不得在 row 中恢复 `Text(task.title)`。iPhone inset list 为正常字号保留 16 pt 的显式 `scrollContent` bottom margin，让最后一个 section 不紧贴系统 Tab Bar glass。

后果：首屏更快建立“这里是哪一个任务”的层级上下文，同时把直接操作与 Forecast 提前；同名子任务仍以父级路径区分，根任务不会留下空白 identity 文本。这个决定不改变 task route、计时命令、分析 request 或同步数据。

验证：付费自动签名 macOS Task UI/Core architecture/refresh/source-layout 定向回归通过；generic iOS Debug 自动签名构建通过。iPhone 17 Pro / iOS 27 的 UI TestManager 在测试 host 构建后空转，直接 seeded launch 又显示空白系统画布，二者均未计为视觉通过；两次专属 UDID、App、DerivedData、result/screenshot 目录均已删除。

## AD-113：Analytics 仅在同一日历周期内保留刷新中的快照

状态：Superseded by AD-131

背景：Analytics request identity 同时包含 range、calendar period、revision、live day 和分钟 bucket。旧页面在任何 identity 变化时立即把整个 landing/category list 换成 spinner；一次普通的 minute refresh 或本机 mutation 因而产生明显闪烁。若反过来无条件保留旧 snapshot，又会在用户切换日期、周或月时把旧指标显示在新控制器下，造成更严重的统计语义错误。

决策：`AnalyticsSnapshotRequest.canRemainVisible(whileLoading:)` 只在 `range` 和 cache key 的 calendar `interval` 同时相等时返回真。此时可以在 revision、live day 或 live bucket 刷新期间继续显示已有快照，并在 shared period controls 旁显示一个非交互的系统小型 progress indicator。range 或 interval 一旦变化，landing 仍使用全页 loading，category detail 仍只显示其 loading row；不得用旧 snapshot 充当新周期 placeholder。两个 snapshot task 都先 `Task.yield()`，让新的 loading/refresh UI 有机会提交，再进行保持在既有 main-actor 边界的有界计算。

后果：活动当前 period 的读取更平稳，本机 mutation 不再打断用户正在看的相同 period；历史 navigation 和 day/week/month 切换始终保持内容与控件一致。此决定不声称把 analytics 计算移到后台；若 profile 证明它本身造成卡顿，必须以新的可取消 read-model 设计处理，不能扩大 stale-snapshot 规则。

验证：纯 request 行为测试覆盖同日 revision/bucket 保留、跨日和跨 range 拒绝；架构/UI contract 固定 root/detail 的 request gate、yield 与 shared refresh indicator。付费签名定向 XCTest 结果和资源清理记录写入 dated Audit。
