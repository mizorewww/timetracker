# 74：Overview 指标卡异常留白 实现记忆

状态：2026-07-27 实现中

> 本文件是主代理与子代理的实现、验证和编排记忆；唯一任务来源仍是
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 条目。

## 认领的反馈条目

- Today 的 Overview 中，Gross Time 与 Wall Time 下方存在不符合内容高度的
  异常留白。

## 预期行为

- Overview 容器高度由可见指标内容和平台规范间距决定，不保留无语义空白。
- Gross / Wall 两行在 iPhone、iPad 与 macOS 普通字号下保持清晰、均衡，
  不截断图标、分隔线、文字或触控区域。
- 修复不改变 Gross / Wall 的计算、颜色、交互或可访问性语义。
- 宽屏 Today 的 Now / Overview 起始对齐与自适应网格保持稳定。

## UI 验收清单

- 先用现有确定性 Today fixture 留存三端改动前截图，定位空白来自行、卡片、
  section 还是宽屏 grid。
- 用布局策略或 UI 行为断言锁定正常内容高度，避免像素扫描与源码字符串扫描。
- iPhone、iPad、macOS 普通字号截图检查卡片底边、分隔线、相邻 section 间距；
  iPad 同时检查横屏。
- SwiftFormat、相关单元/XCUITest、默认 `make test` 和 Release
  `make build-install-all` 通过。
- 释放所有 owned runner、模拟器与临时构建资源。

## Checkpoint 编排

- [x] A：领取反馈、建立活动实现记忆并定位 Overview 布局 owner。
- [x] B：补充先失败的布局契约或 UI 行为测试。
- [x] C：实现最小布局修复并更新相关文档。
- [ ] D：完成格式、跨平台截图、全量测试、Release 全设备安装与收口。

## 库策略

- 优先使用 SwiftUI 原生自适应布局、系统间距和现有 Home 组件，不为单一卡片
  引入布局依赖。
- 参考 Apple HIG 的 grouped content、spacing 与触控目标；仅在系统布局无法满足
  时才评估维护活跃、成熟且一般不少于 1k stars 的第三方库。

## 进度记录

- 2026-07-27：认领任务并建立 `~74` 活动实现记忆。
- 2026-07-27：根因定位为宽屏 `DesktopTodayCurrentStateSections` 的 Now
  较高并决定 `HStack` 行高，但较短的 Overview card 没有填满该行，因此其底部
  留出 24 pt 页面背景；指标行自身没有多余 padding。
- 2026-07-27：先在 macOS UI 测试中增加双卡底边 2 pt 契约，红测结果包
  `build/UITestResults/task74-red-macos/macOS-20260727-183648.xcresult`
  精确记录 Now bottom 285.5、Overview bottom 261.5。
- 2026-07-27：使用 SwiftUI 原生 ideal-size 协商修复：宽屏 row 固定为内容理想
  高度，两列与 Overview section/card 接受该行最大高度，Gross/Wall 在同一卡片
  边界内自然居中；未读取屏幕宽度、未测量并回填高度、未增加 magic padding。
- 2026-07-27：macOS 绿测
  `build/UITestResults/task74-green-macos/macOS-20260727-183808.xcresult`
  与 iPad 横屏绿测
  `build/UITestResults/task74-ipad/iOS-20260727-183900.xcresult` 通过，截图人工
  确认标题、首卡顶部和底部对齐。iPhone 首次紧凑回归在应用启动前遇到
  Simulator `No such process` 基础设施失败，结果包保存在
  `build/UITestResults/task74-iphone/iOS-20260727-184232.xcresult`，随后以全新
  owned simulator 重跑。
- 2026-07-27：iPhone 紧凑回归重跑
  `build/UITestResults/task74-iphone-retry/iOS-20260727-184418.xcresult`
  通过；截图确认 Overview 指标卡仍按内容高度结束、Weekly Time 可正常滚动
  到达，单列 section 没有被宽屏等高契约拉伸。
- 2026-07-27：`make format-check`（831 个 Swift 文件）、`git diff --check`、
  `make localization-check`（9/9 resources）、`make check-hooks` 通过；
  `make test` 通过 1422 tests / 158 suites。
