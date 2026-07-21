# 14：Quick Start 编辑页添加流程实现记忆

> 本文件只保存实现、验证与子代理编排记忆，不是任务来源。范围与状态必须重新读取
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的唯一 `[~]` 项。

## 当前阶段

- [x] 领取反馈、读取 Apple HIG / SwiftUI 强制技能并建立活动链接。
- [x] 审计现有 Quick Start 编辑状态、持久化命令、候选过滤、动画与测试。
- [x] 确认并定向验证仓库现有的固定列表迁移和候选区移除实现，无需重复修改产品代码。
- [x] 使用 owned iPhone / iPad 模拟器完成普通路径与截图验收。
- [~] 执行 `CONFIGURATION=Release scripts/build_install_all.sh`，清理资源并由 Codex 标记完成。

## 唯一反馈边界

- Quick Start 编辑页点击“添加”后，任务应以清晰但克制的动画进入固定列表。
- 已添加任务必须立即从下方候选区消失，不能同时出现在两个区域。
- 拖动手势只是用户给出的可选方案；若采用，仍必须保留可发现、可访问的按钮入口。
- 不领取或实现本条之后的任何反馈。

## 强制设计与实现约束

- Apple HIG：使用标准按钮与列表语义；插入/移除动画用于解释状态变化，必须简短、可打断，并在
  Reduce Motion 下退化为低运动量反馈；iOS/iPadOS 触控目标至少 44×44 pt，macOS 至少 28×28 pt。
- SwiftUI：`ForEach` 使用持久且唯一的任务 ID；动态列表不使用 index/offset identity；事件驱动修改用
  窄作用域 `withAnimation`，transition 位于被插入/移除的稳定行上；视图自有 `@State` 保持 private。
- 先复用现有 Quick Start 持久化命令和仓库组件，不创建第二套选择状态或写入路径。
- 优先原生 SwiftUI 动画与系统列表能力；只有原生能力无法满足反馈时才评估成熟依赖，不为增加库而增加库。
- 所有 UI 操作和截图只使用 owned 模拟器；物理设备仅用于最终 Release 安装，不启动、不操作、不截图。
- 每个小 checkpoint 验证并提交；只暂存本任务差异，保护 `Docs/userfeedback.md` 末尾 8 条用户新增反馈。

## 初始验收问题

- 当前“固定列表”和“候选区”是否来自同一 canonical selection，还是存在重复派生状态。
- 点击添加的持久化成功/失败边界在哪里；动画不得先于持久化成功制造虚假完成状态。
- 添加、移除、重排、搜索/筛选后是否仍保证集合互斥和稳定 identity。
- iPhone、iPad 和 macOS 是否共用同一编辑组件；动画与行操作需分别符合触控和指针/键盘输入。
- Reduce Motion、快速连点、并发刷新、空候选区及恢复/重启后持久化是否已有覆盖。

## Checkpoint 记录

- [x] 初始 checkpoint `5782175`：领取反馈、完成强制技能读取、建立实现记忆与 active link。
- [x] 现状与回归审计 checkpoint：
  - 现有产品实现来自 `dd0497d`（`fix: animate Quick Start pinning`），后续 `510618d` 把有序选择操作
    抽到共享 `OrderedTaskIDSelectionMutation`，当前 HEAD 仍完整保留目标行为。
  - 共用编辑器以私有 `selectedIDs` 作为唯一草稿；`availableTasks` 通过 `Set(selectedIDs)` 排除固定项，
    `pinnedTasks` 按同一数组顺序解析任务，所以一次点击后同一 UUID 不会同时出现在两个区域。
  - 添加与移除都通过 `withAnimation(reduceMotion ? nil : .snappy(duration: 0.28))` 修改选择；两个
    `ForEach` 均以持久任务 UUID 为 identity。Reduce Motion 下不播放自定义移动动画。
  - `OrderedTaskIDSelectionMutation.adding` 对重复点击幂等并保持追加顺序；滑动删除通过可见 UUID
    映射，不把列表 offset 错当持久 identity。
  - Save 复用既有 `setQuickStartTaskIDs` 偏好命令；store-scoped 锁和 atomic mutation 负责写入，
    只有 `onSave` 返回成功才 dismiss，失败时编辑草稿仍留在页面。
  - iPhone 入口与 iPad/macOS 入口经同一 presentation router 打开同一个编辑器，没有平台分叉实现。
  - 两个只读子代理分别审计代码/持久化链和测试矩阵，均未改文件、未启动设备；共同结论是先做
    owned 模拟器目视验收，不为了制造 diff 再实现第二套动画。
  - macOS 定向回归：选择/偏好切片 32 tests passed；随后使用包含 `()` 的完整 Swift Testing 标识
    单独运行两条 Quick Start UI 契约和保存 dismiss 契约，3 tests passed。签名保持 Apple
    Development / paid-team provisioning，没有关闭 code signing。
  - 扩大运行完整 `HomeUIContractTests` + `AppPresentationContractTests` 时，本任务 3 条契约通过，
    但另有 2 个不属于本反馈的既有 Home 契约失败：
    `quickStartUsesIndexedTaskIdentityAndSeparatesNavigationFromTimerActions` 与
    `trackingEntrypointsShareAvailabilityAndRunningStateSemantics`；不越界修改，最终报告如实保留。

## 依赖与互联网库审计

- 原生 SwiftUI `List`、稳定 identity 和 `withAnimation` 已覆盖跨 Section 插入/移除；Apple 官方
  文档也将事件驱动状态变化和稳定 identity 作为这类列表动画的直接能力。继续使用系统实现最符合
  HIG 的可预期交互与 Reduce Motion 行为。
- 审阅了成熟候选 `SwiftUIX`（约 8k stars）和 `SwiftUIKit`（约 1.7k stars）；两者都是广泛 UI
  工具箱，没有为这一处标准列表 diff 提供值得引入整包的新边界，因此不新增依赖。
- `visfitness/reorderable` 只有约 112 stars，低于用户要求的一般 1k stars 门槛，且拖动只是反馈中的
  备选方案，明确拒绝引入。
- 本 checkpoint 使用的库：仅 Apple SwiftUI（现有依赖不变）。

## 模拟器验收计划

- 已完成并删除的 owned batch（只由 Task 14 操作）：
  - iPhone 17 Pro / iOS 27.0：`1AEFADFB-21A9-4417-9A59-FDB23C925068`
  - iPad Pro 13-inch (M5, 16GB) / iOS 27.0：`FA6B27A1-DA49-4675-9588-E70FC3489AF6`
- 在 fresh owned iPhone 17 Pro 与 iPad Pro 13-inch 上各运行
  `testQuickStartEditorMovesAddedTaskOutOfAvailableTasks`；每台使用显式 UDID、关闭并行测试、独立
  xcresult 和截图目录。
- 目视核对点击前后：候选行消失、同一任务出现在上方固定区、顺序标签正确、固定区与候选区层级清晰；
  UI 测试同时验证反向取消后任务回到候选区。
- E2E 只断言最终状态，具体动画轨迹需结合运行时目视；若原生 List 动画符合反馈，就不添加
  `matchedGeometryEffect`、自制 drag/drop 或第三方重排库。
- 每批完成后终止 App/runner，shutdown + delete 两个 owned 模拟器，并确认未触碰既存的
  `AnalyticsReview-iPhone17Pro`。

## 模拟器验收结果

- iPhone 17 Pro：精确 E2E 1 test passed、0 failure（测试体 56.182 秒）。断言同一任务 UUID 从
  Available 消失、进入 Pinned 第 3 位并位于 Available header 上方，取消固定后又返回 Available。
- iPad Pro 13-inch：同一精确 E2E 1 test passed、0 failure（测试体 61.062 秒），验证宽屏 sheet 与
  iPhone 使用同一互斥迁移语义。
- 两个平台各导出点击前/后 2 张 simulator-only 截图并以原始分辨率逐张检查：添加后
  `Design macOS UI` 明确出现在上方 `Pinned Tasks 3`，下方候选区不再含该行；列表层级、加减按钮、
  标题和 sheet 尺寸均无截断或重复。
- 最终证据保存在 `build/Task14SimulatorValidation/iPhone.xcresult`、`iPad.xcresult` 以及
  `build/Task14SimulatorValidation/FinalScreenshots/`；对应日志和 attachment manifest 同目录保留。
- XCTest tearDown 已终止 App；随后显式 terminate App/runner、shutdown + delete 两个 owned UDID。
  复核 simulator 列表只剩既存且仍为 Shutdown 的 `AnalyticsReview-iPhone17Pro`，没有 owned
  `xcodebuild`、`xctest`、UI runner、Simulator、Problem Reporter 或 Booted 设备残留。
- 目视结果支持继续使用原生 SwiftUI List 动画；没有理由引入 `matchedGeometryEffect`、拖动重排或
  第三方依赖。物理设备在此阶段完全未启动、未操作、未截图。
