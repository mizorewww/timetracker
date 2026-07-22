# 18：Apple Health 任务仅同步实现记忆

> 本文件只用于主代理与子代理的实现、验证和编排记忆，不是任务来源。唯一范围与状态必须重新读取
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 条目。

## 当前阶段

- [x] 读取唯一反馈并领取任务。
- [x] 审计 workout/睡眠任务的创建、Quick Start、任务选择器、详情页和计时入口。
- [x] 参考 HealthKit、Apple Fitness 与 Apple HIG，确定仅同步产品语义及成熟库边界。
- [x] 实现并验证 workout/睡眠任务不能由 Time Tracker 启动计时，只能由 Apple Health 同步。
- [x] 使用 owned 模拟器完成普通交互与截图验收并清理资源。
- [x] 执行 `CONFIGURATION=Release scripts/build_install_all.sh` 并由 Codex 标记完成。

## 唯一反馈边界

- Quick Start 不应允许开始 workout。
- Workout 应由 Apple 的健身 App 开始，并在 Time Tracker 中只作为 Apple Health 同步数据展示。
- 睡眠同样只允许从 Apple Health 同步，不允许在 Time Tracker 内主动计时。
- 不领取或实现后续 AI 提示词、Health 任务自动展示、Inbox 等反馈。

## 强制约束

- 先审计仓库现有实现和历史提交；若产品修复已完整存在，只补真实缺失的契约与验收，不重复造逻辑。
- 仅同步约束必须位于领域能力/动作边界，并覆盖 Quick Start、任务选择器、任务详情及其他启动入口，不能只隐藏一个按钮。
- HealthKit 数据读取与普通用户计时持久化语义不得混淆；不得为完成本任务写入伪造健康样本。
- 优先系统 HealthKit、SwiftUI 与仓库现有成熟依赖；一般拒绝 GitHub 低于 1k stars 的非用户指定库。
- UI 操作与截图只使用 owned 模拟器；物理 iPhone/iPad 只做最终 Release 安装和只读核验，不启动、不操作、不截图。
- 每个小 checkpoint 验证后提交；只暂存本任务状态差异，保护 `Docs/userfeedback.md` 中用户新增内容。

## 产品与数据流审计结论

- 产品修复已由历史 checkpoint `cb9a8e4` 建立，本任务没有复制一套展示层判断：
  `AppleHealthTaskCatalog.syncOnlyTaskIDs` 用稳定保留 UUID 识别所有 workout kind 与睡眠任务，完全不依赖可编辑标题或 category。
- `TaskTrackingAvailabilityService` 保持 Apple Health 任务可见、可编辑，同时把固定节点及其所有后代从
  `trackableTaskIDs` 移除；父节点稍后才从 CloudKit 到达的 child-first 图也 fail closed。
- Quick Start 读取模型与编辑器只接收 trackable ID；历史遗留的 Apple Health pinned ID 不会显示、启动，并会在保存时清理。
- Task Detail 保留编辑能力，但显示 `Apple Health Sync`，隐藏 timer 与 manual-time 动作；任务选择器、Timer、Pomodoro、
  App Intent、深链、Watch、macOS 菜单和 quantity 入口复用领域能力或 fresh-context admission。
- 最底层计时 repository/command 在任何写入前再次拒绝 sync-only 分支，因此被拒绝的 Health 操作不会先停止另一个普通计时器。
- HealthKit 集成只有 sample query/read 路径，授权请求 `toShare: []`；没有 workout session、sample save 或其他写入路径。
  导入的 workout/sleep samples 仅保存在内存 timeline state，不进入 SwiftData 或 CloudKit。

## Apple 参考与库边界

- Apple Watch Workout 指南确认 workout 应由 Apple 的 Workout/健身体验开始：
  <https://support.apple.com/en-ca/guide/watch/apdd16e8761a/watchos>
- HealthKit `HKSampleQuery`、queries 与 `HKWorkout` 官方文档确认本 App 所需能力是读取已保存的 sample：
  <https://developer.apple.com/documentation/healthkit/hksamplequery>
  <https://developer.apple.com/documentation/healthkit/queries>
  <https://developer.apple.com/documentation/healthkit/hkworkout>
- Apple HIG HealthKit 与隐私文档用于核对用户文案、上下文授权和最小数据访问：
  <https://developer.apple.com/design/human-interface-guidelines/healthkit>
  <https://developer.apple.com/documentation/healthkit/protecting-user-privacy>
- 采用系统 HealthKit、SwiftUI、SwiftData 与仓库现有依赖；没有新增第三方库。该能力由系统 framework 完整提供，
  为包装一次 sample query 引入外部 HealthKit wrapper 会增加权限与维护面，不能提高正确性。

## 本 checkpoint 的增量

- 增加 Watch projection 回归：即使 Running、Sleep、Running 的后代和普通任务都被历史偏好置顶，Watch snapshot
  也只发布普通任务。
- 增加 iPhone UI 回归：使用明确 gated 的内存 Health fixture，验证 Running 详情只有 Apple Health 同步说明，
  首页 Quick Start 与编辑器均无 Running/Sleep 行或 timer action。
- UI fixture 继续仅存在于 `DEBUG && os(iOS)`：必须同时是 `--uitesting` 启动，并有专用参数或
  `TIMETRACKER_UI_TEST_APPLE_HEALTH=1`。环境信号用于跨 XCUITest launch 边界稳定传递，普通 Debug 与全部 Release
  启动都不会启用 fixture。
- fixture gate 回归覆盖 argument、environment、缺少 `--uitesting` 的拒绝，以及偏好隔离。

## 验证证据

- macOS 定向基线：
  `build/Task18HealthSyncOnlyValidation/Baseline-20260722.xcresult`，7 个 suites，126/126 通过，Apple Development
  签名未关闭。
- iOS Health reader/fixture suite：
  `build/Task18HealthSyncOnlyValidation/FixtureSuite-20260722.xcresult`，11/11 通过；此前过窄过滤产生的 0-test
  结果明确不计入验收。
- macOS Watch suite：
  `build/Task18HealthSyncOnlyValidation/WatchSuite-Retry2-20260722.xcresult`，43/43 通过，新增测试真实执行。
  首次真实执行暴露测试错误 `.invalidMove`，原因是 repository 正确拒绝把普通 child 创建到保留 Health 节点；
  fixture 改为模拟合法同步落库的 `TaskNode` 图后通过。早先另一个 0-test 结果同样不计入验收。
- owned iPhone 17 Pro 模拟器 UI：
  `build/Task18HealthSyncOnlyValidation/SyncOnlyUI-Retry7-20260722.xcresult`，1/1 通过。
  UI 断言覆盖导入的睡眠 sample、Running 固定 ID、同步说明、无 timer/manual-time、Quick Start 普通任务正控制，
  以及 Running/Sleep 在首页与编辑器 pinned/available 中均不存在。
- 截图附件：
  `build/Task18HealthSyncOnlyValidation/Retry7Attachments-20260722-1229/2AA328CE-8084-4F6B-A157-ACD5FCAD2D58.png`
  （Running 同步详情）与
  `build/Task18HealthSyncOnlyValidation/Retry7Attachments-20260722-1229/F41C5611-4988-419C-B4AC-ACC99B500D95.png`
  （Quick Start 编辑器）。目视确认正常文字尺寸下层级、留白、系统按钮和说明清晰；没有物理设备截图。
- UI 失败尝试未被伪装为成功：先后发现通用导航/系统 SearchField 定位、系统 Health 授权页误匹配、XCUITest
  128 字符下标限制、push 后返回与滚动状态等测试问题；最终使用固定 ID、严格 label predicate、明确 fixture gate、
  系统返回及仓库现有 Today 滚动 helper 跑通完整用户路径。
- `git diff --check` 通过。

## 资源所有权

- 本任务 owned 模拟器：`Task18HealthSyncOnly-iPhone17Pro`
  （UDID `EF05A5D3-EBD0-4DFE-8798-71829301A4BC`，iOS 27.0）；只允许主代理用于本任务定向 UI 测试与截图，
  完成批次后必须终止 App、关机并删除。
- 既有 `AnalyticsReview-iPhone17Pro`（`E831B715-747C-478F-B8EE-539C48952444`）为 Shutdown 且不属于本任务，
  不得启动、关闭或删除。

## 资源清理结果

- 本任务 simulator `EF05A5D3-EBD0-4DFE-8798-71829301A4BC` 的 App/UI runner 已终止，设备已 shutdown 并删除；
  `simctl list` 中已不存在该 UDID，且没有 Booted device。
- Retry 4 失败后残留的本任务 `simctl diagnose` PID 95709 已定向终止；没有 owned `xcodebuild`、`xctest`、
  UI runner、extension、trace 或诊断进程残留。
- Simulator/Problem Reporter GUI 未由本批次打开，因此没有擅自退出用户或其他代理的 App。
- `AnalyticsReview-iPhone17Pro` 保持原有 Shutdown 状态，未操作。

## 下一步

- 无。本任务可以由 Codex 把唯一反馈 `[~]` 改为 `[x]` 并移除 active link，然后继续读取下一条未完成反馈。

## Release 全设备安装

- 已精确执行 `CONFIGURATION=Release scripts/build_install_all.sh`，exit 0；iOS/iPadOS 主 App、嵌入 Watch companion
  与 macOS Release 均使用付费 Apple Development 身份和 Team `LT98S43NKA` 构建，未关闭签名。
- iPad Pro M4 `748D0137-ADC3-58AF-855C-1E98B3125F93` 与 iPhone Air
  `FBA36694-D841-56D4-8ED6-21942873B21B` 的只读 `devicectl device info apps` 均确认安装
  `me.mezorewww.timetracker`，版本 `1.1.52 (107)`，且为 developer app。
- Release iOS 主包、嵌入 `me.mezorewww.timetracker.watchkitapp` 与 `/Applications/timetracker.app` 均为
  `1.1.52 (107)`；三者 `codesign --verify --deep --strict` 全部通过，Authority 为
  `Apple Development: ZEXUAN GAO (PX46M259V3)`，Team Identifier 为 `LT98S43NKA`。
- 物理设备只执行脚本安装和上述只读查询；没有 launch、交互或截图。
