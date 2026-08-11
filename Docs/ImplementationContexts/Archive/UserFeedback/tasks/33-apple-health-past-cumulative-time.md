# 33：Apple Health 过去累计时间与时间段实现记忆

Status: Complete

> 本文件只用于主代理与子代理的实现、验证和编排记忆，不是任务来源。唯一范围与状态必须重新读取
> [`Docs/userfeedback.md`](../../../../userfeedback.md) 中对应的 `[~]` 条目。

## 当前阶段

- [x] 领取“Apple Health 任务似乎无法查看过去累积时间和过去时间段”的反馈。
- [x] 对照上一项历史分析实现，以脚本化测试设计复现真实剩余缺口。
- [x] 审计数据查询范围、累计口径、详情/统计入口与刷新生命周期。
- [x] 复用现有周期导航实现最小修复并补齐 Core/UI contract/XCUITest。
- [x] 提交实现 checkpoint，执行 `CONFIGURATION=Release scripts/build_install_all.sh`，标记反馈完成并移除活动链接。

## 唯一反馈边界

- Apple Health 固定任务应能查看过去累计时间，以及用户选择的过去时间段。
- 不领取后续首页卡片、category 展开或其他反馈。

## 强制约束

- 完整遵循仓库本地 `apple-hig` 与 `swiftui-expert-skill`；UI 调试、导航、断言与截图全部使用 XCTest/XCUITest 脚本。
- 不手动操作调试窗口；物理设备只做最终 Release 安装和只读版本/签名核验，不启动、点击或截图。
- 优先复用现有历史分析服务和系统框架；若评估第三方库，必须核验维护质量与 GitHub stars，除用户建议外不采用少于 1k stars 的库。
- 每个 checkpoint 只暂存本任务变更，保护 `Docs/userfeedback.md` 中其余用户新增内容。

## Checkpoint 编排

- [x] Checkpoint A：范围领取、上一实现差距审计与自动化复现设计。
- [x] Checkpoint B：最小实现、聚焦测试与脚本截图验收。
- [x] Checkpoint C：Release 全设备安装、签名/版本只读核验与收口。

## Checkpoint A 审计结论

- 根因可直接复现：详情页只有 `Today / Week / Month` 粒度选择，没有历史日期状态或周期导航；`taskAnalyticsSnapshotRequest` 又把同一个 `now` 同时作为 `referenceDate` 与 `liveNow`，所以三个粒度永远锚定当前周期。
- 底层 `AppleHealthTaskAnalyticsProjectionService` 已按 request 的 `evaluationKey.interval` 裁剪当前周期，并查询上一比较周期及睡眠上下文；只要请求能够表达历史日期，所选历史周期的累计时间、图表和记录无需另造投影服务。
- “过去累积时间”按应用既有术语指所选过去周期的 Gross Time，而不是 lifetime/all-time。当前反馈没有“自始至今/全部/生命周期”语义；不擅自增加无界 HealthKit 查询或新的累计口径。
- Task31 的 XCUITest 只从 Week 切到 Month，验证的是粒度而不是历史周期，因此在完全无法查看上周/上月时仍会通过。
- 最小修复：详情页复用现有 `AnalyticsPeriodNavigator`、`AnalyticsPeriodText`、`AnalyticsRange.evaluation(referenceDate:liveNow:)` 与 `AnalyticsRefreshPlan`；请求构造明确拆分 selected reference date 和 wall-clock now，并保持现有 cancellable/newest-wins 生命周期。
- 自动化验收必须真实点击“上一周期”，断言周期标题改变、下一周期按钮启用、历史累计非零、图表/历史记录属于已加载的过去周期，并从 XCUITest 的 xcresult 附件取图审阅。
- Apple 官方 SwiftUI `DatePicker` 文档确认原生控件支持绑定绝对日期并限制选择范围；现有 navigator 已使用 `...liveNow` 阻止未来日期，不需要新增第三方依赖。

## 非本项范围

- lifetime/all-time Health 总计需要独立 read model 与受控/增量 HealthKit 查询，不能把 sample query 起点粗暴改成 `distantPast`；当前反馈不授权扩项。
- 当前周期内永久前台时监听外部 Health 新样本、历史列表分页/“查看全部”都不是本次“无法选择过去周期”的根因，留给明确反馈处理。

## Checkpoint B 结果

- 详情请求明确拆分所选 `referenceDate` 与真实 `liveNow`，历史周期使用完整闭合区间，当前周期仍只统计到当前时刻；历史视图停止不必要的实时刷新计划。
- Apple Health 详情复用现有 `AnalyticsPeriodNavigator`、`AnalyticsPeriodText`、原生 segmented picker 与 `DatePicker`，支持上一/下一周期、日期选择和 Today 返回；Summary 同步显示所选周期，HealthKit 不可用时不展示无效控件。
- 没有新增第三方依赖或网络实现；继续复用 SwiftUI、HealthKit 与项目既有 Analytics 服务。
- 最终 Core + UI contract 聚焦批次 54/54 通过（`AppleHealthTaskAnalyticsTests` 11、`TaskUIContractTests` 43）；新增投影测试验证历史周 Gross 4h、Wall 3h、上一比较周期 1h、完整周期 query plan 及当前记录隔离。
- 最终脚本化 XCUITest：iPhone 17 Pro 1/1 通过（196.370 秒），iPad Pro 11-inch M4 1/1 通过（213.632 秒）；真实点击上一周、断言周期标题变化/下一周期可用/Today 返回、历史累计非零、当前记录排除、历史记录存在，并覆盖 iPad 月视图横竖屏。
- 已从最终 xcresult 导出并用 `view_image` 检查 iPhone/iPad `historical-period`、历史图表及 iPad 横竖屏截图；周期控件、`Week of Jul 13, 2026`、Gross/Wall 1h10m 和图表层级均正常。
- macOS 签名 Debug 构建通过；补充的 macOS XCUITest 连续两次在执行任何用例断言前因 XCTest `Timed out while enabling automation mode` 失败，诚实记为基础设施 inconclusive。`.unavailable` 隐藏控件由已通过的精确 UI contract 覆盖。
- 最终只读审查覆盖 SwiftUI 状态流、周期导航、HealthKit 历史区间、加载状态及 XCUITest，修正了 unavailable 状态控件与重复进度提示后未发现剩余可操作问题。

## 资源所有权

- Task33 iPhone 17 Pro（iOS 27.0）：`024C0073-7B1C-47AE-86EB-77F17663CAD4`，已 terminate、shutdown 并删除。
- Task33 iPad Pro 11-inch M4（iOS 27.0）：`BFABF2B1-9CD0-444F-BC72-18A1FD2645A2`，已 terminate、shutdown 并删除。
- 已删除本任务 xcresult、截图导出目录和 DerivedData；确认没有 owned runner、xcodebuild、xctest、App 进程、设备条目或 Booted device 残留。

## Checkpoint C 结果

- 精确执行 `CONFIGURATION=Release scripts/build_install_all.sh` 并以 0 退出；iOS/iPadOS 主 App、嵌入 Watch companion、Widget、Live Activity 与 universal macOS App 均完成 Release 构建，macOS App 已复制到 `/Applications/timetracker.app`。
- `devicectl device info apps` 只读确认 iPad Pro M4（`748D0137-ADC3-58AF-855C-1E98B3125F93`）与 iPhone Air（`FBA36694-D841-56D4-8ED6-21942873B21B`）均安装 `me.mezorewww.timetracker` `1.1.73 (128)`；没有启动、点击或截图物理设备。
- iOS、嵌入 Watch 与 macOS 产物的 `codesign --verify --deep --strict` 均通过，Team Identifier 均为 `LT98S43NKA`；macOS 主二进制为 `x86_64 arm64`。当前无可见物理 Apple Watch，配对设备继续通过 Automatic App Install 管理已签名的嵌入 companion。
- Release 核验后已删除 `build/Install`，确认没有 owned `xcodebuild`、`xctest`、UI runner、Task33 App/临时路径、Booted simulator 或活动链接残留；根目录 `README.md`/`readme.md` 不存在。
