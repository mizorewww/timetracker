# 76：macOS 全局字体可读性 实现记忆

状态：2026-07-27 实现中

> 本文件是主代理与子代理的实现、验证和编排记忆；唯一任务来源仍是
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 条目。

## 认领的反馈条目

- macOS App 各主要页面的文字整体偏小，需要在普通字号和日常窗口宽度下提升
  阅读、扫描与操作辨识度。

## 范围

- 先审计 macOS 主窗口的 Today、Inbox、Tasks、Focus、Analytics、Task Detail
  与 Settings，区分正文、导航、section/card 标题、指标、metadata、caption 和
  控件标签的真实语义 owner。
- 优先修复被错误降级为 caption/footnote 或硬编码小字号的共享组件，不把合法的
  辅助 metadata、图例或次级说明机械放大成正文。
- 保持 iPhone/iPad、Watch、Widget、Live Activity 的字号和布局不变；跨平台共享
  组件需要显式、可测试的平台展示策略。
- 不借此重做颜色、间距、信息架构或业务行为。

## UI 验收清单

- 保存正常字号、日常窗口尺寸下的 macOS 修改前后截图，至少覆盖 Today、Tasks、
  Analytics、Task Detail 与 Settings，并检查 Inbox/Focus 的共享组件。
- 核对正文与操作标签不低于平台默认 body 语义，section/card 标题保持明确层级；
  metadata 与 caption 只在确属辅助内容时使用。
- 长本地化文本、搜索、侧边栏、列表滚动、窗口缩放和主要导航仍可用；不通过固定
  point size、全局 environment 强制字号或逐页面 magic scale 实现。
- iPhone/iPad 的根导航与共享组件做定向回归。
- SwiftFormat、相关 XCUITest、默认 `make test` 与 Release
  `make build-install-all` 通过，并释放所有 owned 资源。

## Checkpoint 编排

- [x] A：领取反馈、建立活动实现记忆并生成 macOS 主要页面字体清单。
- [x] B：保存修改前截图，按 HIG 将问题收敛到明确的共享 owner。
- [ ] C：分小 checkpoint 实现、验证并更新工程文档。
- [ ] D：完成跨页面/跨平台 UI、全量测试、Release 全设备安装与收口。

## 库策略

- 优先使用 SwiftUI 动态系统文字样式、原生 control/list/sidebar 以及 SF Symbols，
  不引入全局字体缩放库或自建 typography framework。
- 参考 Apple HIG 的 Typography、Sidebars、Lists and Tables、Buttons、
  Text Fields 与 Settings 规则；只有成熟原生/现有组件无法满足明确行为时才评估
  维护活跃且一般不少于 1k stars 的第三方库。

## 子代理编排

- 主代理负责范围裁决、共享 typography owner、实现、构建/模拟器所有权和提交。
- 可并行的静态页面清单、HIG 复核与测试覆盖审计由子代理完成；所有结论回写本文件，
  子代理不得并发修改同一 Swift 文件。

## 审计结论

- 代码审计确认不存在根视图字体 environment、全局 font scale 或全局 small control；
  根因是多个正文、状态、指标标签和操作提示被降成 macOS 下仅 10–11pt 的
  `caption`、`footnote`、`subheadline`。
- Apple HIG 的 macOS 原生语义基线为 `body/headline` 13pt、`callout` 12pt、
  `subheadline` 11pt、`caption/footnote/caption2` 10pt。macOS 没有 Dynamic
  Type，本任务应继续使用系统语义样式，并在语义 owner 局部做平台映射。
- 优先 owner 为 Analytics 的 detail section、glossary/insight/overview rows，
  其次为 Inbox suggestion、Focus setup/active/recent rows、Task Detail 的状态/
  record/breakdown rows，以及 Today forecast、Settings sync/error helper。
- `TaskCategorySectionHeaderStyle.standard` 与既有 UI 规范的持久 macOS
  `.body.semibold` 冲突；`.compact` 及 sidebar count/path 等合法 metadata
  不应被机械放大。
- 必须保留 10pt 的类别包括图表 axis/legend、task parent path、时间戳、badge、
  count pill、build/debug/provider ID 等可忽略 metadata。任何影响用户决策的
  forecast reason、insight explanation、sync/error/warning 不属于 metadata。
- 不采用根级 `.environment(\.font, ...)`、固定 point size、`minimumScaleFactor`
  挤压或第三方/自研字体缩放框架；不逐页散落大量平台条件。

## 修改前证据

- Today：
  `build/UITestResults/task76-baseline-today/macOS-20260727-191625.xcresult`
- Focus：
  `build/UITestResults/task76-baseline-focus/macOS-20260727-191743.xcresult`
- Analytics：
  `build/UITestResults/task76-baseline-analytics/macOS-20260727-191842.xcresult`
- Settings：
  `build/UITestResults/task76-baseline-settings/macOS-20260727-191922.xcresult`
- Task Detail identity：
  `build/UITestResults/task76-baseline-detail-identity/macOS-20260727-192000.xcresult`
- `testTaskDetailPromotesTimerAndManualTimeActions` 在任何实现前暴露既有验收失败：
  timer button accessibility frame 高度为 24pt，低于已有 28pt 下限。此项纳入
  自绘操作标签可读性修正，不以字体变大伪造 hit target。
- 单页截图与静态审计均显示：导航标题、标准 row label 和原生 Settings controls
  多数已经符合 13pt 基线；集中问题是解释正文、主 row identity、重要状态仍停在
  10–11pt。
- 测试审计选择强化既有 `testUIRefactorBaselineScreenshots()`，用确定性 demo data
  覆盖 Today、Inbox、Tasks、Task Detail、Focus、Analytics、Settings。macOS
  Settings 必须截图真实 settings window，不能继续由“最大窗口”启发式误拍主窗口。
- 强化后的七页矩阵已在实现前通过：
  `build/UITestResults/task76-baseline-matrix/macOS-20260727-192340.xcresult`；
  附件使用 `mac-typography-*` 命名，主窗口被放置到主显示器，Settings 使用真实
  独立窗口。

## 进度记录

- 2026-07-27：认领任务并建立 `~76` 活动实现记忆。
- 2026-07-27：完成 Apple HIG、代码 owner、测试覆盖与修改前视觉层级并行审计；
  确认采用局部系统语义字体修正而非全局缩放。
- 2026-07-27：确定性 macOS 七页字体截图矩阵通过（1 test / 7 screenshots），
  checkpoint B 完成。
