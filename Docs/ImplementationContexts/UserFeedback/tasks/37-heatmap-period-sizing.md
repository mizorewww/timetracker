# 37：Heatmap 默认时间段与方块尺寸实现记忆

> 本文件只用于主代理与子代理的实现、验证和编排记忆，不是任务来源。唯一范围与状态必须重新读取
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 条目。

## 当前阶段

- [x] 领取“设置中 Heatmap 默认时间段长度选择，并改善 iPhone 方块偏小”反馈并建立活动链接。
- [x] 审计现有 Heatmap 设置、持久化、布局、跨平台入口与测试基线。
- [x] 设计并实现最小能力，补齐自动化与脚本截图验收。
- [x] 提交自动化 checkpoint，执行 `CONFIGURATION=Release scripts/build_install_all.sh`，由 Codex 标记完成并移除活动链接。

## 唯一反馈边界

- 仅实现设置中 Heatmap 默认显示时间段长度的选择，并在该选择或布局策略下改善 iPhone 方块偏小。
- 不领取后续 AI、首页、分类或其他反馈；具体适用的 Heatmap、选项、默认值与平台差异必须先从现有代码和测试证据确定。

## 强制约束

- 完整遵循仓库本地 `apple-hig` 与 `swiftui-expert-skill`；所有 UI 导航、断言与截图只用 XCTest/XCUITest 脚本。
- 不手动操作调试窗口；物理设备只做最终 Release 安装和只读版本/签名核验。
- 优先复用 SwiftUI 原生控件、项目现有 preference 与 Heatmap 布局；只有明确缺口才评估新依赖，除用户建议外不采用 GitHub 少于 1k stars 的库。
- 每个 checkpoint 只暂存本任务变更；`Docs/userfeedback.md` 中用户新增内容保持未暂存。

## Checkpoint 编排

- [x] Checkpoint A：领取任务、创建实现记忆与 active link。
- [x] Checkpoint B：审计设置/布局/持久化语义、库与自动化基线。
- [x] Checkpoint C：实现、聚焦验证、脚本截图与实现提交。
- [x] Checkpoint D：Release 全设备安装、签名/版本核验与收口。

## 审计证据

- [x] `TodayActivityHeatmapSnapshotService` 与日历投影把范围写死为 53 周；设置页只有任务选择，没有范围选择。
- [x] `ActivityHeatmapChart` 把方块/间距/图高写死为 `9 / 3 / 108pt`，且宽度至少 320pt；仅减少周数不会改善小方块。
- [x] `HomeActivityHeatmapRefreshRequest` 没有周期字段，因此只修改 preference 会命中旧 request 与旧 snapshot，是必须同步修复的陈旧缓存缺口。
- [x] 通用 `SyncedPreference`、canonical JSON、同步预检、store 广播链可直接复用，不需要 SwiftData schema migration。
- [x] 现有单元测试已覆盖首周日、DST、future cells、活动聚合、容器重开；现有 XCUITest 已有 Heatmap demo seed 与三平台首页路径，可扩展为全脚本设置、重启持久化和截图验收。

## 实现决定

- [x] 增加稳定、可同步的 `ActivityHeatmapPeriod` raw-value 枚举：1 个月 / 3 个月 / 6 个月 / 1 年，对应 5 / 14 / 27 / 53 周；缺失 preference 保持原有 1 年行为，非法值回退到该默认值。
- [x] 设置使用原生 SwiftUI `Picker`；周期进入 snapshot service、store facade 与 `HomeActivityHeatmapRefreshRequest`，保证即时重算且不会复用旧缓存。
- [x] 方块使用独立、可单测的布局策略：短周期显著大于现有 9pt，长周期也提高基础尺寸；图宽和图高由周数、方块及间距推导，保留横向滚动。
- [x] 继续使用项目已有 Apple Swift Charts、SwiftUI、SwiftData。官方能力已覆盖标准 Picker、矩形 mark 与滚动容器；不新增依赖。
- [x] 库质量审计：`ChartsOrg/Charts` 约 28k stars，但引入 UIKit bridge 与现有 Swift Charts 重复；`willdale/SwiftUICharts` 约 963 stars、`DPCharts` 约 17 stars、`HeatmapKit` 约 3 stars，均低于用户要求或不值得替换原生实现，全部拒绝。
- [x] 权威参考：[Apple Swift Charts](https://developer.apple.com/documentation/charts)、[Creating a chart using Swift Charts](https://developer.apple.com/documentation/charts/creating-a-chart-using-swift-charts)、[SwiftUI Picker](https://developer.apple.com/documentation/swiftui/picker)、[XCUIAutomation](https://developer.apple.com/documentation/xcuiautomation)。
- [x] UI 验收只由 XCUITest 自动导航、断言与截图；物理机只做最终 Release 安装、签名与版本读取，不启动 App。

## 资源所有权

- [x] 主代理：完成唯一任务状态、编排、集成、所有 build/TestManager/simulator/XCUITest/screenshot/Release 批次与清理。
- [x] Task 37 iPhone 17 Pro 模拟器 `1387CFF7-4B3E-4523-8718-656D3ABCCE11` 已终止 App/runner、关机并删除。
- [x] Task 37 iPad Pro 11-inch (M5) 模拟器 `7E6465AD-8A47-4778-95C6-D08E69A67A58` 已终止 App/runner、关机并删除。
- [x] 三个子代理完成持久化、布局与自动化基线的只读审计；均未编辑、构建、创建设备或操作窗口。
- [x] 后续没有子代理编辑、构建、创建 simulator 或操作窗口。

## 已提交 checkpoint

- [x] `482e9dff`：领取任务、建立实现记忆与 active link。
- [x] `5bb75a6b`：完成设置、持久化、布局、库与自动化基线审计。
- [x] `e681cdf9`：增加可同步、可规范化且默认兼容 1 年的 Heatmap 周期 preference。
- [x] `0c4ac14f`：让 snapshot、refresh request 与 Swift Charts 布局随周期变化并提高短周期方块尺寸。
- [x] `f2ef2cc0`：在 General 设置中增加原生周期 Picker 与三平台 UI contract。
- [x] `91dab4ef`：增加独立持久化 UI-test store，以及 iPhone、iPad、macOS 三段进程持久化与脚本截图验收；版本 1.1.95 (150)。

## 聚焦验证证据

- [x] macOS 聚焦单元测试通过：`TodayActivityHeatmapTests`、`TodayActivityHeatmapRefreshTests`、`PreferencesChecklistForecastTests`、`PreferenceCommandValidationTests`、`CoreSyncSnapshotPreflightTests`、`TodayHeatmapUIContractTests`。
- [x] XCUITest 使用独立 `TimeTracker-UITests.store`，首次启动重置并写入，第二进程读取 `1 Month`，第三进程从 Today 路由验证相同 task UUID、范围和图表尺寸，最后由脚本删除该测试 store；普通 UI test 继续使用内存容器。
- [x] 当前代码 iPhone 17 Pro：1/1 通过、0 失败，123.743 秒；截图为设置、首次 Today、持久化 Today 三张。
- [x] 当前代码 iPad Pro 11-inch (M5)：1/1 通过、0 失败，128.589 秒；复用同一构建，截图为设置、首次 Today、持久化 Today 三张。
- [x] 当前代码 macOS arm64：1/1 通过、0 失败，111.494 秒；所有窗口定位、设置操作、进程重启、断言与截图均由 XCUITest 完成，没有手动调试窗口。
- [x] 九张截图逐张检查：三平台均显示 `Default Range = 1 Month`；5 周 Heatmap 方块、日期范围与图例无裁切、横向溢出或相互遮挡，首次与持久化尺寸一致；iPhone 方块明显大于原 9pt 基线。
- [x] 子代理最终只读审查未发现阻塞问题；持久化 store 仅供该串行验收用例使用，不与普通内存 UI test 共用。

## Release 与清理证据

- [x] 精确执行 `CONFIGURATION=Release scripts/build_install_all.sh`，命令退出 0；iOS/iPadOS、嵌入 Watch companion、两个扩展和 macOS Release 均构建成功，未关闭签名。
- [x] 物理 `iPad Pro M4`（`748D0137-ADC3-58AF-855C-1E98B3125F93`）安装成功；`devicectl` 只读核验已安装 `me.mezorewww.timetracker` 为 1.1.95 (150)，没有启动、交互或截图。
- [x] iOS App 与 `me.mezorewww.timetracker.watchkitapp` 均为 1.1.95 (150)，TeamIdentifier `LT98S43NKA`，`codesign --verify --deep --strict` 通过；Watch companion 的 `WKCompanionAppBundleIdentifier` 为 `me.mezorewww.timetracker`。
- [x] 当前没有可见物理 Apple Watch，因此脚本如实提示未验证 embedded profile 的手表设备覆盖；嵌入 companion 本身通过 on-disk、Designated Requirement 与 Xcode embedded binary validation。
- [x] `/Applications/timetracker.app` 为 1.1.95 (150)，TeamIdentifier `LT98S43NKA`，严格签名验证通过，主二进制同时包含 `x86_64 arm64`。
- [x] Release 后删除 `build/Install`；当前无 Booted simulator、无本任务 xcodebuild/xctest/UI runner/App 进程，两个独占 simulator 已删除，根目录无 README/readme，工作树只保留用户自己的 `Docs/userfeedback.md` 状态变更等待收口提交。
