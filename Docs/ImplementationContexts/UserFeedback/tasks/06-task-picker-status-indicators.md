# 06：任务选择器状态指示实现记忆

> 本文件只保存实现、验证和子代理编排记忆，不是任务来源。范围与完成状态必须重新读取
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中唯一的 `[~]` 项。

## 当前阶段

- 产品实现已在 `563f1da` 提交：可执行动作与被动状态分别收敛到共享样式。
- UI 语义加固已在 `5d5f783` 提交：同一 UUID 的 Stop → Start、平台最小尺寸与
  trailing column 都有回归保护。
- iPhone 与 iPad 最终矩阵已经通过；Running + Selected 被动状态及 Stop / Start
  动作均已截图并人工验收。
- macOS 最终 2/2 语义路径通过；精确搜索结果、真实点击、28 pt 尺寸、trailing
  column 与 action 完全位于 sheet 可视区均已验证。
- 下一步提交最终设备矩阵 checkpoint，然后运行完整 Release 全设备安装。

## 实现边界

- 统一任务选择器中相同状态的图标、尺寸、字重、占位和对齐。
- 正在计时状态必须同时具有清晰的符号语义，不能只依赖颜色。
- 不改变任务是否可选、启动或停止计时的业务规则。
- 不处理 `Docs/userfeedback.md` 中后续反馈。

## 验收清单

- [x] 盘点所有任务选择器及其运行状态来源
- [x] 定义并测试共享状态指示的布局与语义契约
- [x] 实现 Start Another Timer 及其他同类 picker 的统一样式
- [x] 验证 iPhone、iPad 普通路径并截图，验证 macOS 语义、尺寸与可视区域
- [ ] 运行 `CONFIGURATION=Release scripts/build_install_all.sh`
- [ ] 核验安装版本与签名，释放 owned 设备、进程和临时产物
- [ ] 只在 `Docs/userfeedback.md` 标记完成并移除活动软链接

## HIG 与依赖决策

- 可执行的 Start / Switch / Stop 使用同一圆形包络 SF Symbols：
  `play.circle.fill` / `arrow.left.arrow.right.circle.fill` / `stop.circle.fill`；
  统一系统字体、字重、image scale、monochrome rendering 和尾部交互槽，不允许逐图标
  `scaleEffect`、`offset` 或自绘图形。
- 被动的 Running / Selected 使用较小但相同的紧凑指标：
  `timer.circle.fill` / `checkmark.circle.fill`，固定尺寸与排列顺序；不得伪装成按钮。
- 运行状态不能只依赖 tint，图形本身必须可区分。
- Timer picker 的 running row 已有明确 Stop，不重复添加被动 Running 标记。
- 数据源已经统一来自 `activeSegments → activeSegmentByTaskID → projection.isRunning`，
  不增加本地镜像状态。
- 优先复用 SwiftUI 和项目现有组件；如确需第三方库，先核对维护状态、许可证、
  平台兼容性和至少 1k GitHub stars。
- 本项只需 Apple SwiftUI 与 SF Symbols，不新增依赖。

## 子代理编排

- 已完成：picker 调用点与状态来源静态盘点；确认两种 timer row 已共享
  `TaskTimerActionButton`，应在共享组件收敛，不修改业务状态。
- 已完成：HIG/视觉一致性独立审查；根因是只统一布局 frame、没有统一可见光学包络。
- 已完成：现有测试与可观察 UI 契约盘点；当前 XCUITest 只比较 Button 外框、跳过
  macOS，且 Stop 后没有按同一 UUID 和精确动作语义查找。

## 基线证据

- Owned iPhone 17 Pro 上运行
  `testTimerPickerAlignsRunningAndAvailableTaskActions`：1 test、0 failures。
- xcresult：`/tmp/TimeTrackerTask06-baseline-iPhone.xcresult`
- 导出截图：
  - `build/Task06PickerShots/baseline-iPhone/BA982209-A5DE-4237-93E2-C4E34C84A175.png`
    （Running Stop 与 available Start 同屏）
  - `build/Task06PickerShots/baseline-iPhone/52ABA907-0682-4DCA-B47B-66E8ABCF60E4.png`
    （同一任务 Stop 后重新可 Start）
- 视觉结论：圆形按钮外框及 trailing column 一致，但 square / triangle 的可见尺寸和
  光学中心不一致，现有 source-string contract 还错误锁定 `.resizable().scaledToFit()`。

## 运行资源所有权

- iPhone 17 Pro（iOS 27.0）：`722B6461-AA16-4F3A-8604-54B80725EF31`
- iPad Pro 11-inch (M4) 8GB（iOS 27.0）：`D8327867-13CF-4842-B56C-543833B272BA`
- 两台设备只归本任务的基线和最终 UI 验收批次使用；完成后终止 App、关机并删除。

## Checkpoint 记录

- `d94dfed`：领取当前反馈项，建立 `[~]` 与活动实现记忆链接。
- `7636b03`：完成调用点、状态数据流、HIG、测试与 iPhone 基线截图审计。
- `563f1da`：统一任务选择器可执行动作与被动状态指示样式。
  - Red：新增共享类型契约后，测试按预期因类型尚不存在而编译失败。
  - Green：最终共享契约 21/21 通过；现有真实 UI test 1/1 通过。
  - HIG 独立复审发现 plain icon button 缺少明确按压反馈；已加入共享
    `TaskPickerIconButtonStyle`，统一 disabled/pressed opacity，不逐符号缩放或偏移。
  - macOS arm64 Debug 原生构建成功，并由付费开发者身份与 provisioning profile 签名。
  - 初版截图：
    `build/Task06PickerShots/initial-implementation-iPhone/C1A5D97A-5009-4A46-AC9A-698AA4C9F15D.png`。
  - 视觉结论：Stop / Start 使用相同圆形外包络、相同 centerX 和尾列，图形不再依赖
    方形画布的逐形状缩放。
- `5d5f783`：UI 语义加固 checkpoint。
  - 移除 macOS 跳过，统一验证 iOS 至少 44×44 pt、macOS 至少 28×28 pt。
  - 从 Stop accessibility identifier 提取任务 UUID，停止后精确查找同一 UUID 的
    Start action，并验证标签为 `Start Read Apple HIG`。
  - Owned iPhone 17 Pro 上 1/1 通过：
    `/tmp/TimeTrackerTask06-ui-hardened-iPhone.xcresult`。
  - 人工验收截图：
    - `build/Task06PickerShots/hardened-iPhone/11862468-4AEA-4B4F-A7EC-091C45DB9A17.png`
    - `build/Task06PickerShots/hardened-iPhone/20C7017C-977A-4D0F-B1B6-A7D765D49887.png`
  - 视觉结论：Running Stop 与 available Start 圆形可见包络、尺寸、中心和尾列一致；
    Stop 后同一行恢复为相同尺寸和位置的 Start。
- 最终设备矩阵 checkpoint（本提交）：
  - iPhone 17 Pro 被动状态路径 1/1 通过：
    `/tmp/TimeTrackerTask06-ui-iPhone-passive.xcresult`。
  - iPhone 被动状态截图：
    `build/Task06PickerShots/final-iPhone-passive/B1BFF283-974E-4E70-BCA4-60FDEDB02855.png`。
  - iPad Pro 11-inch 两条路径 2/2 通过：
    `/tmp/TimeTrackerTask06-ui-iPad-final.xcresult`。
  - iPad 人工验收截图：
    - `build/Task06PickerShots/final-iPad/C8E3BF44-47E5-4D4A-A0CA-440C75E82074.png`
      （Running + Selected）。
    - `build/Task06PickerShots/final-iPad/5CB96C88-4688-4DEF-979D-4E15FAC46560.png`
      （Running Stop 与 available Start 同屏）。
    - `build/Task06PickerShots/final-iPad/B28AC215-C83F-4B6D-BA1E-49DE4F6BEEC7.png`
      （同一任务 Stop 后恢复为 Start）。
  - 首轮 iPhone/iPad 并行批次分别暴露了错误的 search-field 查询作用域与新建 iPad
    SpringBoard `Host is down`；已改为全 App 搜索字段查询、单设备串行和关闭 coverage，
    上述最终结果均正常退出且不是掩盖产品断言。
  - macOS 最终语义与可视区域矩阵 2/2 通过：
    `/tmp/TimeTrackerTask06-ui-mac-visible-final.xcresult`；搜索精确命中
    `Start Study`，Stop / Start action 均完全位于同一 sheet frame 内。
  - macOS 桌面存在不属于 App 的 `UserNotificationCenter` 浮层，且 Xcode 27 对
    `settingsWindow` / picker / sheet 的 element screenshot 返回
    `Image creation failed`，`app.screenshot()` 又错误捕获 Codex；因此未伪造 macOS
    截图，也未擅自操作系统浮层。macOS 以真实点击、accessibility 语义、28 pt 尺寸、
    trailing column 与 sheet 可视区域断言验收；视觉证据由 iPhone/iPad 承担。
