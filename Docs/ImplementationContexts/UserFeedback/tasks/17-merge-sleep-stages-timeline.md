# 17：时间线睡眠阶段合并实现记忆

> 本文件仅作为主代理与子代理的实现、验证和编排记忆，不是任务来源。唯一范围与状态必须重新读取
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 条目。

## 当前阶段

- [x] 读取唯一反馈并建立 active link。
- [x] 审计 HealthKit 睡眠样本导入、领域模型去重/合并及 Timeline 映射边界。
- [x] 参考 Apple 官方语义与成熟库，确定最小、可测试的合并策略。
- [x] 确认既有产品修复完整，并补齐读取层、跨午夜 Store 贯通和 UI 唯一性回归测试。
- [x] 使用 owned 模拟器完成普通路径与截图验收并清理资源。
- [x] 执行 `CONFIGURATION=Release scripts/build_install_all.sh` 并由 Codex 标记完成。

## 唯一反馈边界

- 时间线不应因 HealthKit 的不同睡眠类型而把同一次实际睡眠拆成多段。
- 同一次实际睡眠应在 Timeline 上合并为连续区间。
- 不领取或实现其后的 workout/睡眠仅同步、AI 配置等反馈。

## 强制设计与实现约束

- 重新核对 Apple HealthKit 睡眠分析的官方阶段语义、重叠与来源规则，不凭枚举名称臆造算法。
- 优先在数据归一化或 Timeline projection 的明确边界修复，避免只在 SwiftUI 视图里遮掩重复区间。
- 现有相邻计时段自动合并语义不得无意扩展到普通用户计时；睡眠专属规则必须可隔离、可回归。
- 若原生 HealthKit/Swift 标准库已完整覆盖，不为区间合并引入第三方依赖；审计候选库时一般拒绝低于
  1k GitHub stars 的非用户指定依赖。
- UI 操作与截图只使用 owned 模拟器；物理 iPhone/iPad 只做最终 Release 安装与只读核验，不启动、
  不操作、不截图。
- 每个小 checkpoint 完成验证并提交；只暂存本任务状态差异，保护 `Docs/userfeedback.md` 中用户新增内容。

## 官方语义与库审计

- Apple 的 `HKCategoryValueSleepAnalysis` 文档说明每条样本只有一个值；In Bed 可以与 Awake、Core、Deep、
  REM 等详细阶段重叠，而详细阶段彼此不重叠。Apple Watch 的 Awake 样本也可能只出现在相邻睡眠阶段之间。
  因此不能把每个 asleep stage 直接显示为独立 Timeline 项。
- 参考：
  [`HKCategoryValueSleepAnalysis`](https://developer.apple.com/documentation/healthkit/hkcategoryvaluesleepanalysis)、
  [`allAsleepValues`](https://developer.apple.com/documentation/healthkit/hkcategoryvaluesleepanalysis/allasleepvalues)、
  [`sleepAnalysis`](https://developer.apple.com/documentation/healthkit/hkcategorytypeidentifier/sleepanalysis) 与
  [HealthKit queries](https://developer.apple.com/documentation/healthkit/queries)。
- 已审计仓库现有 `swift-collections`：Swift Package Index 显示约 4.4k GitHub stars、持续维护且无依赖，质量合格；
  但它只提供数据结构，不编码 HealthKit 的 Awake/In Bed/来源语义，本任务不应为使用库而误用它。
- 也审计了通用日期/时间库；它们处理历法而不是 HealthKit episode 语义。最终继续使用系统 HealthKit、Foundation
  `DateInterval`、Swift Testing 与 XCTest，不新增第三方依赖。

## 数据流审计与既有产品修复

- 产品逻辑已由提交 `048eeab fix: merge Apple Health sleep episodes` 完成；本轮审计没有发现应重复修改产品代码的证据。
- `AppleHealthDataReader` 把 HealthKit UUID、所有六种睡眠状态、起止时间、source bundle 与 product type 映射为
  内部样本；未知枚举值返回 `nil`，不臆造阶段。
- `AppleHealthTimelineProjectionService` 先按 HealthKit UUID canonicalize，再把睡眠样本交给
  `AppleHealthSleepEpisodeService`。后者按来源身份分组，将相接/重叠片段、最多 2 分钟未标注间隙、最多 30 分钟且
  被 Awake 完整覆盖的间隙、最多 10 分钟且被 In Bed 完整覆盖的间隙合并，episode 上限为 18 小时。
- episode 同时保存显示用 envelope 与真实 asleep interval 并集：Timeline 用 envelope 布局，只累加 asleep intervals
  作为时长，所以中间 Awake 不会被误算为睡眠。
- 多来源重复 episode 会在完整覆盖证据下去重并优先保留详细阶段更完整的来源；不同 source/product 不会被盲目连接。
- `TimeTrackerStore` 查询当天开始前 18 小时的上下文，先构造 episode 再裁剪到可见日期，避免跨午夜睡眠丢失前序阶段。
- 当时的实现只把 Health 样本放在内存 `appleHealthTimelineItems`。Task 77 已将其后续持久化边界迁移到独立、CloudKit-disabled 的设备本地 replica；仍不进入主 SwiftData/CloudKit 或同步偏好。
- 保留的有意边界：如果同一晚真实数据中途改变 product type，当前实现会保持不同来源分段。没有真实样本证据前不放宽，
  以免误合并 iPhone、Watch 或第三方来源。

## 本轮回归加固

- `AppleHealthDataReaderTests` 现在逐一验证 In Bed、Awake、Unspecified、Core、Deep、REM 和未知值映射，防止读取层
  丢失阶段后让上层合并测试虚假通过。
- `AppleHealthTimelineTests` 新增 Store 贯通用例：Core 23:30–23:58、Awake 23:58–00:05、REM 00:05–00:40；
  验证查询向前取得上下文、最终只有一个 Sleep、可见 envelope 为 00:00–00:40、真实时长仅为 00:05–00:40
  （2,100 秒），并验证 Timeline snapshot 仍只有一个 Sleep entry。
- `timetrackerUITests` 不再只用 `firstMatch` 掩盖重复项，明确断言包含 Core/Awake/Deep/REM 的 fixture 只产生一条
  `Sleep`。

## 定向验证

- macOS focused baseline：`build/Task17SleepMergeValidation/Focused.xcresult`，2 个 suite 共 33 个测试通过。
- 测试加固后：`build/Task17SleepMergeValidation/Focused2.xcresult`，2 个 suite 共 34 个测试通过。
- owned iOS 27.0 模拟器读取映射测试：`build/Task17SleepMergeValidation/IOSMapping.xcresult`，1 个测试通过。
- owned iOS 27.0 模拟器 UI 测试：`build/Task17SleepMergeValidation/SleepUI.xcresult`，1 个测试通过；语义查询确认
  `Sleep` 数量恰为 1。
- 截图：`build/Task17SleepMergeValidation/ExportedAttachments/9489B0DB-861A-4B3E-8F03-DB377B4F520F.png`。
  主代理目视确认 Timeline 只有一条 `Sleep`，区间 `00:00–06:30`，实际睡眠 `6 hr, 18 min`；fixture 中间
  12 分钟 Awake 未计入时长，`Running` 仍独立显示。
- 所有构建和测试均保持 Apple Development 签名，没有关闭 code signing。

## Release 全设备安装

- 精确执行 `CONFIGURATION=Release scripts/build_install_all.sh`，退出码为 0；iOS/iPadOS（含嵌入式 Watch）与
  macOS Release 构建成功，脚本完成物理 iOS/iPadOS 安装并复制 macOS App 到 `/Applications/timetracker.app`。
- 只读 `devicectl device info apps` 核验：iPad Pro M4（`748D0137-ADC3-58AF-855C-1E98B3125F93`）与
  iPhone Air（`FBA36694-D841-56D4-8ED6-21942873B21B`）均安装 `me.mezorewww.timetracker` `1.1.52 (107)`。
- 本地 Release iOS、嵌入式 Watch `me.mezorewww.timetracker.watchkitapp` 与 macOS App 均为 `1.1.52 (107)`；
  三个 bundle 均通过 `codesign --verify --deep --strict --verbose=2`。
- 物理 iPhone/iPad 全程仅安装与只读查询，未启动、操作或截图 App；配对 Watch 由系统的 Automatic App Install
  处理嵌入式 companion。

## 资源所有权

- 本任务 owned 模拟器：`Task17SleepMerge-iPhone17Pro`
  （UDID `9A34213D-2C90-46AD-8C3B-A6F0FB5FCF6C`，iOS 27.0）。UI teardown 已终止 App；随后主代理执行
  terminate（返回 nothing to terminate）、shutdown、delete，并退出 Simulator 与 Problem Reporter。
- 清理后 `simctl list devices` 已不含该 UDID；进程检查未发现本任务 `xcodebuild`、`xctest`、UI runner、App 或
  Instruments 遗留。
- 既有 `AnalyticsReview-iPhone17Pro`（`E831B715-747C-478F-B8EE-539C48952444`）为 Shutdown 且不属于本任务，
  全程未启动、关闭或删除。
