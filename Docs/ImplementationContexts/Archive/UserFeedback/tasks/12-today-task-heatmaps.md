# 12：Today 每任务 Heatmap 实现记忆

Status: Complete

> 本文件只保存实现、验证和子代理编排记忆，不是任务来源。范围与完成状态必须重新读取
> [`Docs/userfeedback.md`](../../../../userfeedback.md) 中唯一的 `[~]` 项。

## 当前阶段

- [x] 领取 Heatmap 反馈并建立活动链接。
- [x] 审计任务模型、计时/Checklist 聚合、Today、设置、任务详情与 BlossomColor 组件。
- [x] 明确普通计时任务、Checklist 和现有任务量数据的每日强度语义与迁移默认值。
- [x] 实现持久化配置、每日聚合与任务详情默认关闭的追踪开关。
- [x] 实现并验证每任务配色与 Today 独立 Heatmap。
- [x] 完成 owned iPhone/iPad 模拟器交互、截图验收与批次资源清理。
- [x] 补齐运行中计时刷新、数量父子语义、确定性冷启动验收与最终相关回归。
- [x] 执行 Release 全设备安装并清理本任务临时产物。
- [x] 由 Codex 在唯一任务来源标记父项和全部子项完成并移除活动链接。

## 唯一反馈边界

- Today 可显示 GitHub 风格的 Heatmap；用户能从设置中选择要显示的任务。
- 每个任务拥有独立 Heatmap 与配色方案；复用仓库已有 BlossomColor 相关组件。
- 是否追踪 Heatmap 可在任务详情中开启，默认关闭。
- 强度首先按任务的真实每日数据决定：反馈明确提到 Checklist 完成数量、每日任务时长
  最大值阈值，以及任务量任务的每日任务量；实现前必须以现有模型能力确认精确定义。
- 不提前实现下一条“重复任务和简单任务量任务”；只为当前模型已经存在的数据类型提供语义，
  必要的未来兼容必须有测试且不能虚构新产品流程。
- 只处理 `Docs/userfeedback.md` 当前 `[~]` 项，不领取后续反馈。

## 设计与实现约束

- 使用 `apple-hig` 和 `swiftui-expert-skill`：图表必须有清晰标题/摘要，不能只靠颜色传达值，
  iPhone、可缩放 iPad 窗口和 macOS 都要保持可读布局。
- 优先 Apple Swift Charts 的 `RectangleMark` 或仓库已有成熟组件；不新增低质量重复实现。
- 新第三方 GitHub 依赖一般必须达到 1k stars，并在采用前核对维护状态、许可证和平台支持。
- 聚合、阈值和调色必须在模型/服务层可独立测试，不在 SwiftUI `body` 中排序或聚合。
- `ForEach`/Chart 数据必须使用持久稳定 identity；新 SwiftUI API 按部署目标正确 gate。
- 不新增 Liquid Glass。保留正式 Apple Developer 签名。
- 所有 UI 操作和截图只来自 owned 模拟器；物理设备只执行规定的 Release 安装，
  不启动、不操作 UI、不截图。

## 验收清单

- [x] 从设置选择/取消选择 Heatmap 任务，真实磁盘容器重开后保持
- [x] 任务详情开关默认关闭，并与设置选择保持单一语义
- [x] 每个已选择任务在 Today 显示独立、可辨识的 GitHub 风格年度/周期 Heatmap
- [x] 复用 BlossomColor 主题色并生成清晰的从浅到深强度层级
- [x] 普通时长、Checklist 完成数量和仓库已存在的任务量数据有确定、可测试的日聚合语义
- [x] 空数据、归档任务、删除/恢复数据、时区和跨日边界行为明确
- [x] iPhone/iPad/macOS 普通布局与深浅色不截断；清单/时长/数量均已完成 simulator-only 截图验收
- [x] 聚焦测试与相关回归已完成；全量测试中的本任务相关失败已修复并隔离复验
- [x] `CONFIGURATION=Release scripts/build_install_all.sh` 成功并核验版本/签名
- [x] 清理 owned 模拟器、进程和临时产物

## 子代理编排

- [x] 数据模型、迁移、每日聚合和阈值语义审计
- [x] Today、设置、任务详情与 BlossomColor 复用入口审计
- [x] 测试架构、Swift Charts/可复用库与模拟器验收路径审计
- [x] 数量任务父子聚合 fixture、真实 Today 卡片与 simulator-only 截图补强

## 审计结论与锁定决策

- 现有实现仍将全部选择合成一张 Heatmap，只读取 Checklist，并写死 1/2/3/4 阈值和
  `AppColors.grossTime`；它仅作为可迁移的基础，不满足本项反馈。
- 不新增 SwiftData 模型或 V14 schema。默认关闭、任务顺序、设置多选和详情 Toggle 全部继续以
  已同步的 `AppPreferences.todayHeatmapTaskIDs` 为唯一真相，并统一调用
  `setTodayHeatmapTaskIDs`，避免双数据源。
- 每个被选择任务生成独立 snapshot；该图包含任务本身和未删除后代。父子同时被选择时分别显示，
  但单张图内按持久 ID 去重。归档选择保留历史，真正删除、孤儿和未来记录不计。
- 每任务主题色直接使用已由 `BlossomColorPicker` 编辑和同步的 `TaskNode.colorHex`，四档强度色
  从该主题色派生，不另存一份会漂移的 Heatmap 色。
- 数据源自动且互斥：分支内存在有效任务量目标时使用任务量；否则存在 Checklist 时使用完成数；
  否则使用 gross 计时时长。当前项只消费已有 V13 任务量数据，不提前实现下一条任务量/重复任务 UI。
- 时长通过 `TrackedTimePolicy` 裁剪到现在和 53 周窗口，再用
  `TimeAggregationService.secondsByDay` 按 Calendar 日界线拆分；跨日和 DST 不使用固定 24 小时。
- Checklist 采用仓库现有语义：只计当前仍完成且有 `completedAt <= now` 的 canonical 可见项目；
  取消、删除或重新完成会撤销/移动历史贡献。
- 时长与 Checklist 的正值档位按窗口内最大每日值 `M` 归一化：0 为空，正值按
  `ceil(4 * value / M)` 落入四档。任务量按当日累计量 / 有效目标量落入同样四档并封顶，避免少量
  记录因自身成为观察最大值而错误显示最深色。
- 日期使用调用方当前 Calendar 和半开日区间；系统日历/时区变化时现有 Today 刷新机制会重新分桶。
- UI 使用 Apple 原生 Swift Charts `RectangleMark`，保留系统坐标与图表可访问性；不继续扩写手绘网格。
  调研到的原生 Swift Heatmap 专用包均远低于 1k stars，通用高星图表库又没有日历 Heatmap 且会
  引入 UIKit/适配成本，因此不新增第三方依赖。
- UI 复审后的收口：最多 64 个图表在宽屏卡片布局中使用 `LazyVStack`；不足一分钟的时长用秒显示，
  不再出现有颜色却显示 `0 min`；任务量总值在标题中只显示本地化数字、完整单位保留在副标题和
  可访问性摘要；简繁中文使用“累计计时时长/累計計時時長”，不泄漏英文 Gross。
- Task Detail 的默认关闭 UI 测试使用标准确定性 fixture 中未选择的第三个任务，并沿真实的
  Today -> Tasks -> 搜索 -> 详情路径验证默认关闭、开启后色阶出现、返回 Today 后立即显示。
  UI 测试专用容器按设计是内存型，不能伪装成跨进程持久化证据；真正的持久化由临时磁盘
  SwiftData store 写入后销毁并重建 `ModelContainer` 的单元测试验证。
- UI 验收只使用本任务 owned iPhone/iPad 模拟器；物理设备只执行最终 Release 安装，不启动、
  不操作、不截图。
- 运行中的未结束计时会随 `now` 增长，因此 Today 使用 60 秒 `TimelineView` 时钟；刷新 identity
  只在存在活动计时时携带分钟 bucket，空闲时不重新生成快照。行为测试同时锁定“运行中跨分钟增加
  60 秒”和“空闲跨分钟 request 不变”。
- UI 测试不再通过失败后重启掩盖 fixture 冷启动竞态；`ContentView` 在 store 完成初始配置后暴露
  确定性 ready 标识，Heatmap UI 测试必须等待它再断言数据。

## 运行资源所有权

- `Task12-Heatmap-iPhone17Pro`：`2FD5F08C-F779-49B6-854D-8B58881971C1`，
  iOS 13 个聚焦测试通过后已终止 App、shutdown 并 delete；名称/UDID 均不再存在。
- `Task12-Heatmap-UI-iPhone17Pro`：`C293811F-C2C3-4A22-B0DF-A466C66328EE`，
  3 个 simulator-only UI 测试通过并导出 10 张 XCTest PNG；已终止 App、shutdown 并 delete。
- `Task12-Heatmap-UI-iPadPro13`：`AFF6A870-C4D2-40A8-B257-0BBC0975A7C0`，
  同组 3 个 simulator-only UI 测试通过并导出 10 张 XCTest PNG；已终止 App、shutdown 并 delete。
- `Task12-Final-Heatmap-iPhone17Pro`：`EC28B07C-E1F2-4588-BFF0-4C3B3B4B17E5`，
  最终 3 个 simulator-only UI 场景全部通过并导出 11 张 XCTest PNG；逐张原始分辨率检查后已终止
  App、shutdown 并 delete。首次详情测试遇到 Xcode 启动超时，重启该 owned 模拟器后隔离复跑通过。
- `Task12-Final-Heatmap-iPadPro13`：`4CD94C78-938E-491F-BA5A-30A28EA86EF9`，
  最终 3/3 simulator-only UI 测试通过并导出 11 张 XCTest PNG；逐张原始分辨率检查后已终止 App、
  shutdown 并 delete。
- 不触碰 `AnalyticsReview-iPhone17Pro` 或其他非本任务资源。

## Checkpoint 记录

- [x] `82b9bb3`：领取反馈、建立实现记忆与活动链接。
- [x] `5568ab8`：记录模型、UI、依赖与测试审计结论。
- [x] `8c7485b`：实现并验证每任务聚合模型、动态阈值和详情开关。
- [x] `0ddec3f`：Swift Charts 每任务卡片、Blossom 主题色、详情预览、本地化及确定性 UI fixture；
  owned iPhone 模拟器 13 个聚焦测试通过；UI 复审收口后 macOS 13 个聚焦测试再次通过，
  模拟器批次已完整清理。
- [x] owned iPhone/iPad 模拟器交互与截图验收：两个平台各 3/3 UI 测试通过；逐张检查默认关闭、
  开启色阶、Today 同步、清单/时长独立蓝橙色板、层级选择器和选择摘要；两个 owned 模拟器及
  相关进程均已清理。持久化另以真实磁盘 SwiftData 容器重开测试通过；最终 macOS 聚焦批次
  14/14 通过。
- [x] `2d30d30`：服务/UI 已按职责预算拆分；运行中计时只在活动时按分钟刷新；数量任务按父任务
  及同单位后代聚合，真实 Today fixture 同时覆盖 Checklist、时长和数量三张独立卡片；UI 测试通过
  `ContentView` ready 标识等待确定性冷启动。macOS 最终聚焦测试 19/19 通过，相关隔离复验 2/2 通过。
  受限并发的 macOS 全量回归执行 1458 个测试，11 个失败中与本任务相关的 `ContentView` 行数预算已
  修复并隔离通过；归档时间戳失败隔离通过，另 9 个为设置同步或既有源码预算/契约失败，均不在当前
  唯一反馈范围。最终 owned iPhone 三个 UI 场景合计 3/3、iPad 3/3 通过，共 22 张 simulator-only
  截图完成原始分辨率验收；两个模拟器已删除，未残留 owned app、xcodebuild、xctest 或 Booted 设备。
- [x] 最终 Release 安装：精确执行 `CONFIGURATION=Release scripts/build_install_all.sh` 并以退出码 0
  完成。iOS/iPadOS Release 构建、嵌入 Watch companion、codesign 与 Designated Requirement 验证
  通过，应用在不启动的前提下安装到 iPad Pro M4 `748D0137-ADC3-58AF-855C-1E98B3125F93` 和
  iPhone Air `FBA36694-D841-56D4-8ED6-21942873B21B`；macOS Release 已复制到
  `/Applications/timetracker.app` 并验签通过。iOS 与 macOS 均核验为 `1.1.52 (107)`、bundle ID
  `me.mezorewww.timetracker`、Team `LT98S43NKA`。没有可见物理 Apple Watch，因此脚本按设计只验证
  embedded companion，实际 Watch 安装交由配对设备的 Automatic App Install。
- [x] 已删除本任务全部 `/private/tmp` xcresult、截图导出、失败诊断、sample，以及 2.1GB
  `build/Install/DerivedData`；再次核验无 Task12 owned 模拟器、Booted 设备或相关测试/构建进程。
  `Docs/userfeedback.md` 末尾三条 Apple Health 用户追加反馈保持未改内容，未混入实现 checkpoint。
