# 06：任务选择器状态指示实现记忆

> 本文件只保存实现、验证和子代理编排记忆，不是任务来源。范围与完成状态必须重新读取
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中唯一的 `[~]` 项。

## 当前阶段

- 已按顺序领取反馈项并完成静态、HIG、测试与 iPhone 基线截图盘点，尚未修改产品代码。
- 基线证明 Stop / Start 按钮外框同尺寸、同尾列，但 `stop.fill` / `play.fill`
  被强制缩进同一方形画布后，可见包络与光学中心仍不同。
- 已实现可执行动作与被动状态两层共享样式，并通过纯契约与 iPhone 真实 UI 验证。
- 下一步补强同一 UUID 的 Stop → Start 语义测试，并完成 iPad/macOS 矩阵。

## 实现边界

- 统一任务选择器中相同状态的图标、尺寸、字重、占位和对齐。
- 正在计时状态必须同时具有清晰的符号语义，不能只依赖颜色。
- 不改变任务是否可选、启动或停止计时的业务规则。
- 不处理 `Docs/userfeedback.md` 中后续反馈。

## 验收清单

- [x] 盘点所有任务选择器及其运行状态来源
- [x] 定义并测试共享状态指示的布局与语义契约
- [x] 实现 Start Another Timer 及其他同类 picker 的统一样式
- [ ] 验证 iPhone、iPad、macOS 普通路径并截图
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
- 该设备只归本任务的基线和最终 UI 验收批次使用；完成后终止 App、关机并删除。

## Checkpoint 记录

- `d94dfed`：领取当前反馈项，建立 `[~]` 与活动实现记忆链接。
- `7636b03`：完成调用点、状态数据流、HIG、测试与 iPhone 基线截图审计。
- 共享样式 checkpoint（待提交）：
  - Red：新增共享类型契约后，测试按预期因类型尚不存在而编译失败。
  - Green：最终共享契约 21/21 通过；现有真实 UI test 1/1 通过。
  - HIG 独立复审发现 plain icon button 缺少明确按压反馈；已加入共享
    `TaskPickerIconButtonStyle`，统一 disabled/pressed opacity，不逐符号缩放或偏移。
  - macOS arm64 Debug 原生构建成功，并由付费开发者身份与 provisioning profile 签名。
  - 初版截图：
    `build/Task06PickerShots/initial-implementation-iPhone/C1A5D97A-5009-4A46-AC9A-698AA4C9F15D.png`。
  - 视觉结论：Stop / Start 使用相同圆形外包络、相同 centerX 和尾列，图形不再依赖
    方形画布的逐形状缩放。
