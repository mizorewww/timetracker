# 58：Analytics 周期切换闪烁实现记忆

> 本文件是主代理与子代理的实现、验证和编排记忆。任务内容与状态的唯一来源仍是
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 条目。

## 当前阶段

- [x] 按文档顺序领取“Analytics 切换 Day/Week/Month 闪烁”反馈。
- [x] 审计闪烁的状态流、视图身份、动画/transition、异步加载与历史回归边界。
- [x] 先写普通字号 UI 验收清单、稳定行为测试和修复前失败/录屏证据。
- [x] 做最小分层修复，保留图表计算、交互、缓存与跨平台语义。
- [~] 运行格式、本地化、单元测试和受影响 iPhone/iPad/macOS 截图/录屏验收。
- [ ] 提交小 checkpoint，执行 Release 全设备安装，标记反馈完成并移除活动链接。

## 唯一范围

- 消除 Analytics 页面在 Day、Week、Month 间切换时的可见闪烁。
- 保留周期选择、数据聚合、图表内容、空状态、滚动位置和现有导航行为。
- 不顺带领取 AI CRUD、Release 测试数据、平台 UI 全量审查或 Apple Health 后续反馈。

## 强制约束

- 主代理完整遵循仓库本地 `apple-hig` 和 `swiftui-expert-skill`。
- 优先修正 SwiftUI 状态、视图身份、事务或数据加载根因；不以延时、遮罩或固定快照掩盖
  闪烁。
- UI 变更先建立普通字号验收清单；完成后用脚本化 XCUITest 与截图/录屏覆盖受影响平台。
- 每个模拟器登记名称和 UDID，结束后终止 App/Runner、关机并删除。
- `Docs/userfeedback.md` 中用户并行新增的其他条目不纳入本任务提交。

## Checkpoint 编排

- [x] Checkpoint A：领取、现状/历史/测试审计、验收契约。
- [~] Checkpoint B：测试先行、最小根因修正和文档更新。
- [ ] Checkpoint C：跨平台截图/录屏、完整门禁、Release 全设备安装和反馈收口。

## 子代理编排

- [x] 状态/布局审计：定位视图 owner、状态更新顺序、动画和可能的重建边界。
- [x] 测试/历史审计：定位回归提交、现有测试缺口与稳定的闪烁验收方法。
- [x] 库/平台方案审计：核查 Apple 原生 API 与成熟库是否有适用方案，记录为何选用或不选。

## 资源所有权

- Red 批次：主代理，`codex-task58-red-iPhone17Pro`
  (`0C76DF8C-112D-4F12-B9FC-0F9F537CC902`，本任务创建)，App
  `me.mezorewww.timetracker`、UI runner，产物根目录
  `/private/tmp/codex-task58-red.GO0Iut`；本批次不开 Simulator/Xcode/DeviceHub UI。
- 完成失败证据后必须终止 App/runner、shutdown、delete，并审计无 owned
  `xcodebuild`/XCTest/Booted device 残留。

## 初始验收方向

- 单次周期点击只产生一次可预测的内容更新，不出现整页空白、白闪或旧/新内容交替。
- 周期控件保持稳定位置与选中态；图表卡片身份、标题和外框不因切换瞬间消失。
- 快速连续 Day/Week/Month 切换时，最终内容与最终选择一致，不被较早异步结果覆盖。
- iPhone、iPad、macOS 普通窗口宽度下行为一致；无意外整页 transition 或布局跳变。

## 审计结论

- 根回归始于 `f922bfe7`：Analytics 从同步常驻内容改为
  `snapshot/loadedRequest + .task(id:)`，跨 range 时完整内容先进入 loading replacement。
  `4f81577e` 又加入 `Task.yield()`，保证这一空载帧会先被 SwiftUI 提交。
- 上一轮修复 `e36807df` 只让 period controls 常驻；当前
  `AnalyticsViews.swift` 跨 range 仍向 `AnalyticsContent` 传 `nil`，
  `AnalyticsHomeContent.swift` 仍把 Summary/Review/Explore 七行整体换成 240pt spinner。
- `51bfc3f8` 后加入的独立 heatmap 位于可选数据块之后；数据块折叠时 heatmap 上跳，恢复时
  下跳，进一步放大闪烁。
- period control 的 refresh spinner 目前条件插入 `ViewThatFits` 候选 HStack/VStack。
  它改变固有宽度，在 iPad 分栏/macOS 临界宽度可能让布局横排→竖排→横排。
- `snapshot` 与 `loadedRequest` 分两次发布；快速切换任务在异步返回后先写 snapshot、再检查
  cancellation，存在过期结果造成额外中间态的窄窗口。应以单个 loaded presentation 原子发布。
- Store 已有完整 `AnalyticsEvaluationCacheKey` 的安全缓存，但视图在检查缓存前先 yield 并
  清空。仅按 range 的旧 facade cache helper 不足以区分历史周/月，不得用于直接呈现。
- 根页面没有 `.id(range)`、transition 或显式 animation；现有 transaction 已禁用隐式动画。
  根因是条件结构卸载和尺寸突变，不是动画本身，也不是外层 Tab/SplitView 重建。

## 既有测试为何漏检

- 当前 `testAnalyticsRangeSwitchKeepsPeriodControlsMounted` 在本任务基线源通过
  （1 test / 0 failures，结果包 `task58-baseline.xcresult`），但 XCUITest 每次 tap 后先等待
  App idle，只检查 period controls 仍存在、数据最终回来；最后 settled 状态才截图。
- 测试从不观察 mid-refresh，也不要求 Summary/Review 的 section shell 或 frame 在 loading
  中持续存在。因此当前确定性空载帧仍能保持全绿。
- 结果包：
  `/private/tmp/codex-task58-red.GO0Iut/task58-baseline.xcresult`。

## 收敛后的 UI 验收清单

- [x] 已经显示过 Analytics 后，Day/Week/Month 冷缓存切换不得卸载整组数据 section；旧指标
  不能冒充新周期，loading 中以禁用、redacted 的稳定原生 section 内容表达占位。
- [x] 精确命中目标 evaluation cache 时直接显示目标快照，不为了 loading UI 先强制空一帧。
- [x] 同一 period 的 revision/live-minute refresh 继续显示真实当前快照；跨 range/interval
  placeholder 不暴露旧数值、旧可访问性值或旧导航交互。
- [x] snapshot 与 request 原子发布；快速 Day→Week→Month 时过期 Week 结果不得覆盖最终 Month。
- [x] period controls 和 Summary/Review 首屏壳保持稳定；refresh indicator 永久预留固定尺寸槽，
  不能改变 `ViewThatFits` 的 fit 结果。
- [x] heatmap 保持自己的数据链与稳定位置，不因 Analytics range loading 整段上下跳。
- [x] Category Detail 采用同一呈现边界；Today 专属小时/时间线与 Week/Month daily trend 不显示
  错误周期的真实值。

## 测试先行契约

- 为 Analytics range reload 增加仅在 `--uitesting` 且专用参数存在时启用的可控短延迟；首屏
  initial load 不延迟，生产/Release 默认路径完全不受影响。
- 给轻量刷新指示器稳定 identifier。增强现有三平台 XCUITest：进入 ready 状态后记录 period
  control 与首屏 Review frame；切换后先等待刷新指示器，在 loading 窗口断言 Review section
  仍存在、frame 无大幅跳变并截取 mid-refresh；再等待目标数据 settled。
- 小屏 `List` 的 Explore 可能因 lazy materialization 不在首屏，不把它作为跨设备 mid-refresh
  硬断言；完整 section shell/过期结果规则由纯 presentation-state 行为测试覆盖。
- 不恢复 2026-07-25 已移除的 source-string scan；自动门禁使用状态、identifier、frame 与最终
  选择，截图/录屏用于人工视觉检查。

## 库策略

- 先核查 SwiftUI 原生状态/事务/Chart 更新是否完整覆盖；若不覆盖，再查成熟、维护活跃、
  许可合适且通常不少于 1k GitHub stars 的候选库。
- 不为单个状态更新闪烁引入新的渲染框架或图表栈。
- 已核查 DGCharts、SwiftUIX、Pow 与 Swift Async Algorithms；它们都达到质量门槛，但分别会
  引入不相关的图表栈、通用 UI 扩展、动画层或异步序列抽象，不能修复本次 SwiftUI
  conditional composition 与 state publication 根因。
- 本任务不新增第三方库，使用系统 `redacted(reason:)`、`accessibilityHidden(_:)`、
  `.task(id:)`、固定 frame 与既有 Swift Charts。适用的 Apple 官方参考包括
  `ViewThatFits`、SwiftUI performance、SwiftUI update tracing 与 task lifecycle。

## Red / Green 证据

- 修复前增强后的测试结果：
  `/private/tmp/codex-task58-red.GO0Iut/task58-red2.xcresult`。受控 Week 冷加载时刷新标识存在，
  但 `analytics.section.review` 消失，测试在
  `testAnalyticsRangeSwitchKeepsPeriodControlsMounted` 明确失败。
- 修复前录屏附件：
  `/private/tmp/codex-task58-red.GO0Iut/red2-attachments/0FC78F65-E7BC-4E86-B9C7-9D20A54E8FF.mp4`；
  contact sheet 为 `/private/tmp/codex-task58-red.GO0Iut/red2-contact.png`，可见整块数据区被
  空白 rounded card 与中央 spinner 替换。
- 聚焦 presentation-phase 单元套件：9 tests / 0 failures。
- 修复后 iPhone UI 结果：
  `/private/tmp/codex-task58-red.GO0Iut/task58-green3-iphone.xcresult`，1 test / 0 failures。
  Week 与 Month 的刷新中途都保持 period controls 和 Review，两个 frame 的纵向变化均不超过
  2pt；返回精确缓存 Day 不出现 refresh identifier。
- 已逐张检查修复后的三个 iPhone 附件：Week/Month 中途画面为稳定的系统 redacted section，
  无整块白屏或位置坍缩；Day settled 画面恢复真实值与交互。
- `make format-check`：817 个 Swift 文件均无需格式修正；`make localization-check`：
  9/9 资源、三语 key parity 通过。
- `make test`：1433 tests / 1431 passed；仅保留任务开始前已经复现的两个无关失败：
  `PreferenceSyncBehaviorTests.checklistCompletionMovesOnlyTheTargetToTheDestinationGroupEnd()`
  与
  `TaskPersistencePolicyTests.archiveCommandPreservesTheOriginalArchiveTimestamp()`。

## 实现结论

- `AnalyticsView` 与 `AnalyticsCategoryDetailView` 以单个 loaded presentation 原子持有
  snapshot/request，并先消费精确 evaluation cache。
- `AnalyticsSnapshotPresentationPhase` 区分首屏、跨周期遮蔽、同周期刷新与 current；
  landing/detail 共享策略。
- 跨周期使用原有 section/card 的系统 redaction，占位数据禁止 hit testing 并从辅助功能树
  隐藏；分支语义继续读取 loaded request。
- refresh spinner 永久占用 20×20 槽，只有真实刷新时暴露动态 identifier，因此不会改变
  adaptive period-control 布局。
- AD-113 已由 AD-131 取代；Architecture、CodeGuide、UI-Design 与 Testing 同步记录新契约。
