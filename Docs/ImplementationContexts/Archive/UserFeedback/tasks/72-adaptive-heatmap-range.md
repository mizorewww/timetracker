# 72：热力图范围自适应尺寸 实现记忆

Status: Complete

状态：2026-07-27 已完成

> 本文件是主代理与子代理的实现、验证和编排记忆；唯一任务来源仍是
> [`Docs/userfeedback.md`](../../../../userfeedback.md) 中对应的 `[~]` 条目。

## 认领的反馈条目

- 设置 heatmap range 后，热力图没有随范围与可用空间自动放大，单个瓷砖过小。

## 预期行为

- 热力图根据所选日期范围、容器宽度和平台密度计算可读的瓷砖尺寸，充分利用当前可用空间。
- 增大 range 时完整显示目标范围，不因固定尺寸留下无意义空白；较短范围也不维持过小的固定瓷砖。
- iPhone、iPad 和 macOS 的 Home/Overview 热力图保持一致的数据语义、日期顺序、滚动和选择行为。
- 不破坏任务过滤、空数据状态、柱状图或宽屏自适应布局。

## UI 验收清单

- 用确定性 fixture 记录至少一个短范围与一个长范围的基线截图。
- 普通字号验证 iPhone、iPad 和 macOS；检查瓷砖尺寸、间距、周标签、月份标签和容器边界。
- 验证切换 range 后尺寸会重新计算，且所有目标日期仍可访问。
- SwiftFormat、相关尺寸策略/行为测试、相关 XCUITest、默认 `make test` 和 Release 全设备安装通过。
- 释放所有 owned runner、模拟器与临时构建资源。

## Checkpoint 编排

- [x] A：领取反馈、建立活动实现记忆并审计热力图 owner 与现有尺寸策略。
- [x] B：补充先失败的自适应尺寸/布局行为测试。
- [x] C：实现最小跨平台修复并更新设计文档。
- [x] D：完成格式、跨平台截图、全量测试、Release 全设备安装与收口。

## 库策略

- 优先复用现有 heatmap 组件、SwiftUI `GeometryReader`/layout proposal 与项目既有图表依赖。
- 先核对 Apple SwiftUI Layout/Charts 官方能力；只有现有组件与原生布局无法满足行为时才评估维护活跃、成熟且一般不少于 1k stars 的依赖。

## 进度记录

- 2026-07-27：认领任务并建立 `~72` 活动实现记忆。
- 2026-07-27：代码、设计和测试三个只读子审计一致定位到固定尺寸表：
  `ActivityHeatmapLayoutPolicy` 只看 size class 与周数、不接收真实容器宽度；数据范围和设置持久化链路正常。
- 2026-07-27：核对 Apple 官方 SwiftUI `onGeometryChange`、容器布局，以及
  Swift Charts `MarkDimension.fixed`/轴标签碰撞解析能力；本任务无需引入第三方依赖。
- 2026-07-27：先把固定表测试改为可用宽度行为测试；旧实现按预期因缺少
  `availableWidth` 初始化参数失败，保留了红灯证据。
- 2026-07-27：布局策略现从实际 viewport 选择最大的整数瓷砖尺寸：
  12...24 pt，按 2/3/4 pt 分级间距；短范围放大并完整适配，长范围维持
  12 pt 可读下限并水平滚动。范围变化重置滚动锚点，月份标签用原生
  greedy 碰撞解析，范围 footer 仍位于滚动区外。
- 2026-07-27：目标单元测试通过（14 tests / 1 suite / 0 failures）；
  SwiftFormat 与 lint 均为 0 问题。
- 2026-07-27：iPhone 一个月范围 UI 验收通过，结果为
  `build/UITestResults/iOS-20260727-173047.xcresult`；图表高度至少
  210 pt、宽度至少 168 pt 且不溢出卡片。macOS 首轮验收发现侧栏
  accessibility element 不是 `Button`，已将测试定位改成跨平台
  identifier 查询，待重跑。
- 2026-07-27：macOS 一个月范围与设置持久化验收通过：
  `build/UITestResults/macOS-20260727-174615.xcresult`。测试同时修正
  了多窗口定位：由应用菜单把 Settings 置前，并只滚动其
  `settings.view`，不再误滚后台 Home。
- 2026-07-27：iPad 一个月范围与设置持久化验收通过：
  `build/UITestResults/iOS-20260727-174823.xcresult`；临时模拟器
  `F29397C2-EBCD-40E3-84CD-A84D8C088215` 已由 Makefile 删除。
- 2026-07-27：一年长范围在 macOS 与 iPad 纵/横屏通过可读宽度和
  水平溢出断言；结果分别为
  `build/UITestResults/macOS-20260727-175327.xcresult` 与
  `build/UITestResults/iOS-20260727-175417.xcresult`，后者的临时
  模拟器 `3D044E40-9D53-4789-AFAF-9FEB8DCCBC6B` 已删除。
- 2026-07-27：默认 `make test` 通过（1422 tests / 158 suites /
  0 failures）；hook 状态与 `git diff --check` 通过，准备提交实现
  checkpoint。
- 2026-07-27：实现 checkpoint `c6f9f100`（`Adapt heatmaps to
  available width`）已提交，hook 将版本推进为 1.1.249 (304)。
- 2026-07-27：`make build-install-all` Release 构建、签名与安装通过：
  iPad Pro M4 `748D0137-ADC3-58AF-855C-1E98B3125F93`、iPhone Air
  `FBA36694-D841-56D4-8ED6-21942873B21B`、有效嵌入式 Watch
  companion，以及 `/Applications/timetracker.app`；安装版本确认是
  1.1.249 (304)。
