# 94：统一主页计时选择入口 实现记忆

状态：2026-07-28 已完成

> 本文件是主代理与子代理的实现、验证和编排记忆；唯一任务来源仍是
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的状态条目。

## 认领范围

- 将主页无活动计时时的“开始计时”和有活动计时时的“再开始一个计时”统一到同一个
  SwiftUI 组件和原生按钮样式。
- iPhone 紧凑列表、iPad 宽布局和 macOS 宽布局复用同一实现；标题和图标仍由当前
  `TimerPickerMode` 决定。
- 保留禁止并行计时时的“切换计时”语义，以及现有计时选择命令边界。
- 不改任务行的开始/停止按钮、菜单、滑动操作、Widget、App Intent 或 Watch 独立界面；
  它们不是主页这组“开始计时/再开始一个计时”状态变体。

## 验收条件

- [x] 先增加能够区分空闲、并行和切换三种状态的展示行为测试或 UI acceptance。
- [x] 主页三个宽度/平台入口只保留一个共享按钮实现，不再维护空闲专用组件。
- [x] 空闲状态显示“开始计时”，并行状态显示“再开始一个计时”，禁用并行时显示
  “切换计时”；三者使用“再开始一个计时”当前的原生整行样式。
- [x] 正常字号 iPhone、iPad 和 macOS 的按钮标题、图标、44 pt 触控尺寸及截图验收通过。
- [x] `make test`、格式、本地化门禁通过，实现提交后完成 `make build-install-all`。

## 子代理编排

- 子代理 A：只读盘点全平台计时入口和共享组件边界。
- 子代理 B：只读审查 Apple HIG、SwiftUI 状态与原生按钮呈现。
- 子代理 C：只读梳理行为测试、XCUITest 和截图缺口。
- 主代理：建立失败验收、最小复用、平台 UI 验收、提交和设备安装。

## 约束

- Apple HIG：主操作使用原生 `Button` / `Label`，标签直接说明结果，触控目标至少
  44 pt，不以自绘样式替代系统反馈。
- SwiftUI skill：展示由 `TimerPickerMode` 派生，保持单一事实来源；共享视图不持有
  重复状态，也不复制计时命令。
- 不引入新库；此项由 SwiftUI 系统组件和现有计时选择策略即可完整实现。

## 进度记录

- 2026-07-28：认领最后一项反馈。现状确认同一个 `home.startTimer` 入口分成
  `HomeNowEmptyStartButton` 的突出胶囊和 `HomeNowActiveContent` 内的原生整行按钮；
  下一步先锁定三个 `TimerPickerMode` 的展示契约，再合并组件。
- 2026-07-28：三个子代理只读审计确认差异集中在主 App 的 Home；Watch、Widget、
  Live Activity 只有指定任务的系统动作，不存在这组全局入口。空 Quick Start 还保留
  第三套原始按钮，纳入同一共享 Home 组件。新增纯展示契约，锁定 `.start` 与
  `.startAnother` 共用 `plus.circle` 视觉语法、`.switchTimer` 保留切换图标；
  `TimerPickerUIContractTests` 2/2 通过，SwiftFormat 0/875 待格式化。
- 2026-07-28：删除空闲专用的突出按钮，紧凑/宽布局和空 Quick Start 统一调用
  `HomeTimerPickerButton`。第一次 iPhone UI 验收先发现按钮点击框只有 22 pt；修正后又
  发现把内边距放在 `Button` 外会令 `List` 根行和嵌套行相差 24 pt。最终把内边距收进
  原生 `Button` 标签，空闲/运行态都得到同一个 60 pt 完整点击框，未增加展示状态或
  命令层。
- 2026-07-28：`testTodayPrimaryTimerActionKeepsOneStyleAcrossTimerStates` 在 iPhone 17 Pro、
  iPad Pro 13 英寸（M5）和 macOS 各 1/1 通过；每个平台都保存并目检了运行态与空闲态
  正常字号截图，按钮可点击且会打开同一个 `timer.taskPicker`。结果包：
  `iOS-20260728-225807.xcresult`、`iOS-20260728-230056.xcresult`、
  `macOS-20260728-230258.xcresult`。
- 2026-07-28：实现 checkpoint 门禁通过：SwiftFormat 0/875、本地化资源 9/9、
  `make test` 1572 tests / 176 suites。等待提交后执行全设备安装。
- 2026-07-28：实现提交 `c2c25bf0` 后，`make build-install-all` 成功构建并签名
  Release 1.1.349 (404)，安装到 iPad Pro M4、iPhone Air，复制到
  `/Applications/timetracker.app`；iOS 包确认内嵌 Watch companion。任务完成并关闭。
