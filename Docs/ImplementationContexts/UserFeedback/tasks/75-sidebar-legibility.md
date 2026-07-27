# 75：侧边栏分类图标与文字可读性 实现记忆

状态：2026-07-27 已完成

> 本文件是主代理与子代理的实现、验证和编排记忆；唯一任务来源仍是
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 条目。

## 认领的反馈条目

- iPad / macOS 侧边栏中的分类图标和文字过小，普通字号下扫描与辨识困难。

## 预期行为

- 侧边栏分组、目的地和任务行形成清晰且符合平台习惯的字号层级；当前目的地、
  badge、展开控件和任务身份不会互相竞争。
- 分类图标具有稳定、易辨识的视觉尺寸和对齐，不通过放大整行 hit frame 制造
  假图标尺寸，也不裁切 SF Symbol。
- iPad 与 macOS 使用同一语义组件；只有系统平台控件自身的自然差异，不复制
  两套分类 row。
- iPhone 的 tab/紧凑导航不因宽屏侧边栏修复而改变。

## UI 验收清单

- 先保留正常字号下 iPad 横屏与 macOS 的确定性侧边栏截图，并定位字号、symbol
  frame、row height 与系统 sidebar style 的实际 owner。
- 用现有可访问性标识和确定性交互保存修改前后的验收截图，不使用源码字符串
  扫描或像素颜色扫描。
- 检查长分类名、badge、展开箭头、选中态和至少一层任务树；图标与文字基线、
  行间距和点击区域保持稳定。
- iPhone 紧凑根导航回归，确保没有把 tab 图标或正文一并放大。
- SwiftFormat、相关单元/XCUITest、默认 `make test` 和 Release
  `make build-install-all` 通过，并释放所有 owned 资源。

## Checkpoint 编排

- [x] A：领取反馈、建立活动实现记忆并定位侧边栏 row owner。
- [x] B：先记录可读性基线，并确认现有行为 UI 契约覆盖侧边栏层级。
- [x] C：实现最小共享组件修复并更新相关文档。
- [x] D：完成格式、跨平台截图、全量测试、Release 全设备安装与收口。

## 库策略

- 优先使用 SwiftUI `Label`、动态系统文字样式、SF Symbols 和现有
  `TaskSummaryRow`；不为字号或 symbol frame 引入组件库。
- 参考 Apple HIG 对 sidebar hierarchy、typography、SF Symbols 与 selection 的
  规范。只有现有原生组件无法满足明确行为时，才评估维护活跃、成熟且一般不少于
  1k stars 的第三方库。

## 进度记录

- 2026-07-27：认领任务并建立 `~75` 活动实现记忆。
- 2026-07-27：定位到 `SidebarView.sidebarCategoryHeader` 把共享
  `TaskCategorySectionHeader` 强制为 compact，导致 iPad 分类标题 / SF Symbol
  使用 12 pt caption，macOS 使用 10 pt caption；同一侧边栏的目的地和任务标题
  已使用 `.body`，不需要整体放大。
- 2026-07-27：先运行现有确定性 macOS 分类展开/折叠验收并保留截图，结果包为
  `build/UITestResults/task75-baseline-macos/macOS-20260727-185638.xcresult`；
  截图确认 Work、Study、Exercise 分类 header 明显小于相邻任务和目的地。
- 2026-07-27：Apple HIG 要求 iPadOS / macOS 默认可读正文分别为 17 pt /
  13 pt，SF Symbols 应与文字 weight/size 配对；因此把共享 header 的展示意图区分为
  standard、compact picker 和 sidebar，仅 sidebar 使用 `.body.semibold`，不改变
  picker、Tasks 主列表、任务行或 iPhone tab。
- 2026-07-27：macOS 修改后 UI 用例通过；展开、折叠、恢复与从主列表导航后的
  自动展开均保持，截图结果包为
  `build/UITestResults/task75-green-macos/macOS-20260727-185845.xcresult`。
- 2026-07-27：专属 iPad Pro 13-inch 横屏运行同一用例通过，四张截图位于
  `build/UITestResults/task75-green-ipad/iOS-20260727-190100.xcresult`；
  Makefile 已关闭并删除模拟器。iPhone 17 Pro 的五 Tab → Analytics →
  Today → Settings 根导航回归也通过，结果包为
  `build/UITestResults/task75-green-iphone/iOS-20260727-190422.xcresult`。
- 2026-07-27：`make format-check`、`make localization-check`、
  `make check-hooks`、`git diff --check` 均通过；默认 `make test` 的
  1422 tests / 158 suites 全部通过。
- 2026-07-27：实现 checkpoint `835df7d2`（`Improve sidebar category
  legibility`）由 hook 升版至 1.1.258 (313)。Release
  `make build-install-all` 成功：iPad Pro M4 实际安装并由 `devicectl`
  回读为 1.1.258 (313)，嵌入 Watch companion 的 bundle ID 为
  `me.mezorewww.timetracker.watchkitapp` 且同为 1.1.258 (313)；
  `/Applications/timetracker.app` 同版，`AppBuildInfo.plist` 指向
  `835df7d27a88` 且 `GitDirty=false`。iPhone Air 当时由 CoreDevice
  报告 `unavailable`，因此没有把它误报为已安装。
- 2026-07-27：第 75 项完成；没有新增第三方库，使用 SwiftUI 动态系统文字样式
  与 SF Symbols，并按 Apple HIG 的 sidebar、typography 和 symbol 配对规则验收。
