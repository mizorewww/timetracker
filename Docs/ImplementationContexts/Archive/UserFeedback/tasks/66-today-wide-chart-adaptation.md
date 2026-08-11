# 66：Today 宽屏 Heatmap 与柱状图自适应 实现记忆

Status: Complete

状态：2026-07-27 已完成

> 本文件是主代理与子代理的实现、验证和编排记忆；唯一任务来源仍是
> [`Docs/userfeedback.md`](../../../../userfeedback.md) 中对应的 `[~]` 条目。

## 认领的反馈条目

- iPad 和 macOS 的 Today 顶部 heatmap 与柱状图在宽内容区不能合理自适应。

## 预期行为

- Today 顶部图表在 iPad/macOS 常见宽度下使用清晰、有限且协调的图表宽度，
  不把单个可视元素横向拉伸到难以阅读。
- 窄宽度继续单列；足够宽时遵循系统内容布局与现有 Today 信息层级，不增加
  仅按平台判断的分支。
- Heatmap 单元、周柱状图、标题、图例和交互目标在普通字号下均不重叠、不截断。
- iPhone 既有布局与语义保持不变。

## UI 验收清单

- iPad 全屏横/竖屏及一个较窄窗口宽度下，Heatmap 与柱状图都不出现过度拉伸、
  空洞留白、裁切或标题/图例重叠。
- macOS 默认窗口与较宽窗口下，两个图表的可读密度一致，卡片起始边缘和间距协调。
- iPhone 普通字号仍为既有单列，图表内容完整。
- 布局只依据可用宽度与系统 size class，不以设备型号或 `os(...)` 决定视觉结构。
- XCTest 以稳定 identifier 与截图覆盖 iPhone、iPad 和 macOS；批次结束清理 owned
  模拟器和测试进程。

## Checkpoint 编排

- [x] A：领取反馈并建立活动实现记忆。
- [x] B：审计 Today 顶部图表组合、尺寸策略、测试夹具与 HIG 约束。
- [x] C：先补布局/验收测试，再实现宽度自适应并更新当前文档。
- [x] D：完成单测、三平台 XCUITest/截图、Release 全设备安装与收口。

## 子 Agent 分工

- 代码审计：定位 Today Heatmap/柱状图组合与尺寸计算，提出最小共享宽度策略。
- 设计审计：按 Apple HIG 审查宽屏信息密度、对齐、分栏与普通字号验收。
- 测试审计：寻找已有 fixture、窗口 resize/XCUITest 和截图复用路径。

## 库策略

- 优先复用 SwiftUI 自适应布局、现有 Heatmap/Chart 组件与 Apple Charts。
- 仅当成熟外部库提供不可替代能力时才引入；本任务不为简单布局重复造组件。

## 进度记录

- 2026-07-27：认领任务，创建实现记忆和 `~66` 活动链接，开始三路只读审计。
- 2026-07-27：代码审计确认外层 Section/Card 曾占满宽度，而周柱状图内部固定
  `720 pt`、Heatmap 内容约 `667 pt`；设计审计建议两类可视化独立位于可选下部
  分栏之前，避免 Forecast/Countdown 出现时触发宽度突变；测试审计确认可复用
  `--uitesting-today-heatmap` fixture 与现有稳定 identifier。
- 2026-07-27：新增共享宽度策略：窄内容区自然填充，宽内容区的可视化 Section
  上限为 `720 pt` 内容加两侧各 `14 pt` 卡片内边距；Weekly Gross 与 Activity
  Heatmaps 保持同宽、左对齐，并移到可选 Today 下部双栏之前。短 Heatmap 改为
  左对齐，溢出内容初始仍显示最新日期。同步更新 Architecture、CodeGuide 和
  UI-Design。
- 2026-07-27：测试先行补充布局策略单测，以及宽屏 iPad/macOS 的真实几何断言与
  截图测试。macOS 通过
  `build/UITestResults/macOS-20260727-130940.xcresult`；iPad Pro 13-inch 竖屏与
  横屏通过 `build/UITestResults/iOS-20260727-131054.xcresult`；iPhone 既有卡片
  分离回归通过 `build/UITestResults/iOS-20260727-131430.xcresult`。三组截图均已
  导出并目检，无裁切、重叠或超宽拉伸；两台 owned iOS 模拟器均已关闭并删除。
- 2026-07-27：未新增第三方库；使用 SwiftUI、Apple Charts 和现有 Heatmap
  组件完成。Apple HIG/SwiftUI 指引落实为基于可用宽度的单一布局策略、稳定的
  leading alignment、可读内容上限和 iPhone 紧凑布局回归。
- 2026-07-27：最终门禁通过：`CoreArchitectureBehaviorTests` 4 项、
  `TodayActivityHeatmapTests` 12 项、完整 `make test` 1420 项/157 suites、
  SwiftFormat 830 个 Swift 文件、本地化 parity 9/9。`make build-install-all`
  成功构建 Release 1.1.231 (286)，安装到 iPad Pro M4、iPhone Air，并将签名
  有效的 macOS App 复制到 `/Applications/timetracker.app`。Watch companion
  已嵌入并通过签名验证；本次没有可见的物理 Apple Watch。
