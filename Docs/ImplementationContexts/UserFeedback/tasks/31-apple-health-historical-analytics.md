# 31：Apple Health 历史统计实现记忆

> 本文件只用于主代理与子代理的实现、验证和编排记忆，不是任务来源。唯一范围与状态必须重新读取
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 条目。

## 当前阶段

- [x] 领取 Apple Health 类型任务的详情 Summary 与历史时间线缺失反馈。
- [x] 审计 HealthKit 数据投影、任务详情与统计数据流，并制定自动化验收契约。
- [x] 实现历史时长与历史时间线，补齐定向测试和脚本化截图验收。
- [~] 提交已验证实现，随后精确执行 `CONFIGURATION=Release scripts/build_install_all.sh`。
- [ ] 标记反馈完成并移除活动链接。

## 唯一反馈边界

- Apple Health 类型任务的 task 详情 Summary 能显示过去累计时长。
- 统计视图能查看该任务过去的时间线数据。
- 不领取后续首页卡片拆分、设置页或其他反馈。

## 强制约束

- 完整遵循仓库本地 `apple-hig` 与 `swiftui-expert-skill` 规则；优先复用现有 HealthKit、SwiftUI、Swift Charts 与应用聚合服务。
- 如评估第三方库，必须先核验维护质量与 GitHub stars；除用户建议外不采用少于 1k stars 的库。
- 所有 UI 交互与截图验收写成 XCTest/XCUITest；只使用有明确所有权的模拟器，不手动调整窗口，不在物理设备启动、点击或截图。
- 每个 checkpoint 只暂存本任务变更，保护 `Docs/userfeedback.md` 中其他用户新增内容。

## Checkpoint 编排

- [x] Checkpoint A：范围领取、现状/依赖/HIG 审计与自动化验收设计。
- [x] Checkpoint B：最小实现、定向单元/UI contract 与脚本化视觉验收。
- [~] Checkpoint C：Release 全设备安装、签名/版本只读核验与收口。

## 资源所有权

- `task31_health_data_audit`、`task31_ui_test_audit` 与官方资料审计子 agent 均已完成只读审计；未编辑、构建、测试、创建 simulator 或操作窗口。
- 主代理创建并独占的 iPhone Air `7CD8F1C2-B980-4B30-956E-E5767171FCB6`、iPad Pro 13-inch (M4) `CEE748F7-C048-4740-B226-1F4BD5B52637` 已在批次结束后终止 App/runner、关机并删除；`simctl` 无 Booted 或残留 owned device。
- Task31 临时测试产物位于 `/tmp/timetracker-task31-*`。当前无 owned `xcodebuild`、`xctest`、UI runner、App、Simulator 或 Problem Reporter 进程。

## 审计结论

- 根因不是 View 布局：Apple Health 固定任务被正确排除在手动计时之外，因此永远不会产生本地 `TimeSegment`；任务详情 `taskAnalyticsSnapshot` 只聚合本地账本，而 Health 样本目前又只按“今天”加载给首页时间线，Summary、任务分析和历史记录必然为零/空。
- `AppleHealthTaskCatalog` 只有 role → 固定 task ID，需补 exact task ID → role 反查；只允许目录生成任务走 Health 读取，不能把用户子任务误判为 Health 数据源。
- 新增纯值 `AppleHealthTaskAnalyticsProjectionService`，复用 `AppleHealthTimelineProjectionService`、`AppleHealthSleepEpisodeService` 和 `TimeAggregationService`。Workout 同 ID canonicalization、睡眠跨源去重/阶段合并、awake/inBed 排除、跨边界裁剪都沿用既有语义；累计时长只来自 `durationIntervals`。
- 详情使用独立异步加载路径，不依赖首页的 `AppleHealthTimelineEnabled` 开关，不向 SwiftData、CloudKit 或 iCloud 写入任何健康样本。SwiftUI `.task(id:)` 负责范围切换取消与 newest-request-wins；显式呈现 loading/content/empty/unavailable/failed/retry，macOS 立即显示不可用而不是永久 spinner。
- Health Summary 只显示有意义的累计/实际时长；隐藏 direct/children 与贡献条等层级指标。任务分析复用现有 `DailyTimeSeriesChart` 呈现所选日/周/月历史，保留平均/最长记录；最近记录按 workout 或完整 sleep episode 展示，睡眠时长不包含 awake gap。
- DEBUG fixture 扩展为确定性多日 workout/sleep 数据，并支持 empty 与 fail-once 场景。单元测试覆盖 role 过滤、重复 ID、跨日裁剪、gross/wall、每日桶、sleep awake 排除与 store 开关解耦；XCUITest 在 owned iPhone/iPad 上脚本导航、切换范围、重试、旋转和截图，macOS 只用脚本窗口放置验证 unavailable。物理设备仅用于最终 Release 安装与只读签名/版本核验。
- 日期轴改为真实 `Date` 值，并由 `DailyTimeSeriesXAxisPolicy` 在紧凑 Month 最多选择 5 个、常规宽度最多选择 8 个均匀刻度；脚本截图确认 iPhone 与 iPad 横竖屏均无省略号、裁切或密集网格。视觉审计将左下角悬浮圆形识别为系统 `.tabBarMinimizeBehavior(.onScrollDown)`，不是产品自绘遮挡。
- 最终自动化结果：Apple Health 聚焦单测 10/10；Apple Health、Analytics、Home、Task 与本地化关联回归 163/163；iPhone 历史范围 1/1、iPad 历史范围与旋转 1/1、iPhone retry/empty/background refresh 2/2；最终 iOS build-for-testing 成功。关联回归同时修正 3 个落后于既有实现的静态源码契约断言，没有改产品行为。
- macOS XCUITest 两次都在 test runner 初始化前被系统拒绝，原因是控制台会话处于 `CGSSessionScreenIsLocked=Yes`，报 `LocalAuthentication Code=-4`；没有手动解锁、调整窗口或触碰用户会话。macOS 逻辑与 UI contract 已由上述 10/10、163/163 自动化覆盖，此项如实记为环境性未执行。
- Apple HIG 要求仅在相关上下文请求健康数据，并使用系统授权界面；HealthKit 读取授权结果不可被应用判定，空态只能表述为“没有可读取的数据”，不能声称用户拒绝。查询继续使用 overlap 语义，避免漏掉跨午夜睡眠。官方依据：<https://developer.apple.com/design/human-interface-guidelines/healthkit>、<https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data>、<https://developer.apple.com/documentation/healthkit/hkqueryoptions>、<https://developer.apple.com/documentation/healthkit/running-queries-with-swift-concurrency>。
- 依赖审计：现有第三方包不提供本缺口能力；Apple HealthKit、Swift Concurrency、SwiftUI、Swift Charts 与 XCTest/XCUITest 已覆盖需求。新增第三方依赖：无。
