# 24：iPad Timeline 重叠与省略时长标注实现记忆

> 本文件只用于主代理与子代理的实现、验证和编排记忆，不是任务来源。唯一范围与状态必须重新读取
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 子条目。

## 当前阶段

- [x] 领取反馈，审计 iPad/macOS horizontal Timeline 的重叠轨道、短任务几何与 omitted-gap 标注层级。
- [x] 对照 Apple HIG、SwiftUI 布局语义及成熟时间轴实现，确定跨平台修复与依赖策略。
- [ ] 构造大量重叠、短任务的隔离 fixture，完成纯布局、契约和性能回归。
- [ ] 使用明确登记的 owned iPhone/iPad simulator 与本机 macOS 测试窗口进行 UI 验收并截图，随后清理资源。
- [ ] 精确执行 `CONFIGURATION=Release scripts/build_install_all.sh`，标记反馈完成并移除活动链接。

## 唯一反馈边界

- iPad Timeline 中任务条不得遮挡 `xxx min elapsed` 省略时长标注。
- 用大量时间重叠且持续时间短的任务验证 iPhone、iPad 与 macOS Timeline 的轨道、间距、标注层级和可读性。
- 不领取后续 Live Activity、首页统计或其他反馈。

## 强制约束

- 优先修正共享 Timeline 纯布局，不以某张截图或单一 fixture 的硬编码坐标伪造结果。
- 先审计现有依赖与成熟实现；只有质量、维护状态和收益足够时才引入库，一般拒绝非用户指定且 GitHub 少于 1k stars 的依赖。
- UI 截图只来自 owned simulator 或本机 macOS 自动化窗口；物理设备只做最终 Release 安装和只读核验，不启动、不操作、不截图。
- 每个小 checkpoint 验证后提交；只暂存本任务状态差异，保护 `Docs/userfeedback.md` 中其余用户新增内容。

## Checkpoint 编排

- [x] Checkpoint A：静态审计、任务相关规范与依赖研究。
  - [x] 根因一：horizontal bar 在绘制时才以 `max(18pt, naturalWidth)` 扩大短任务，但继续使用按真实时间与 60 秒间隔生成的 domain lane。现有短任务 fixture 在 720pt/压缩轴约 5430 秒时，30 秒自然宽约 3.98pt，第二条起点仅移动约 15.91pt，最终 18pt 矩形在同一 domain lane 重叠约 2.09pt。
  - [x] 根因二：`horizontalGapMarker` 把虚线与 label 绑定后整体置于 bars 前景；horizontal lanes 只预留 24pt tick 区，label 从底部向上侵入最后一条任务轨道。material 只能遮盖任务条，不能消除几何冲突，label 在首尾也没有水平 clamp。
  - [x] 根因三：horizontal 高度按 domain `timeline.laneCount` 计算；视觉投影增加 lane 后会把 lane extent 压到 1pt 并让图标溢出。末端短任务还可能从 `x == width` 开始向右超出容器。
  - [x] 方案：将 Task 23 的 projected-footprint 分配抽为方向无关的纯 helper，新增 horizontal wrapper；grid、gap 和 bars 共用扣除 18pt 尾部 reserve 后的 `axisLength`，视觉矩形按 6pt 阈值交给同一稳定 allocator。横向 label 使用独立 annotation band，虚线留在背景、label 单独置于前景；高度由实际宽度下的 projected laneCount 决定，保持 24pt lane 与 10pt spacing。
  - [x] Apple HIG 要求 marks 在 plot area 中保持主导，网格与说明不得掩盖数据；iPadOS 要适应全屏、窗口与多任务宽度，macOS 要适应可调整窗口。SwiftUI 官方 `Layout`/几何 API 支持根据父容器 proposal 决定组合尺寸，纯布局计算保持在 View body 之外。参考：<https://developer.apple.com/design/human-interface-guidelines/charts>、<https://developer.apple.com/design/human-interface-guidelines/layout>、<https://developer.apple.com/documentation/swiftui/layout>。
  - [x] 依赖决策：继续复用已锁定的 Apple `swift-collections` 1.6.0 `HeapModule`（审计时 4,459 stars，2026-07-20 仍有推送），不新增依赖。CalendarKit（2,706 stars）可借鉴视觉事件分组与 overlay 分层，但它是 UIKit/Mac Catalyst 整套 day calendar，不能保留本项目的 SwiftUI 混合数据、压缩轴和 omitted-gap 语义；HorizonCalendar（3,148）、FSCalendar（10,647）与 JTAppleCalendar（7,655）是日期/月网格；JZCalendarWeekView 仅 474 stars 且长期未维护，明确拒绝。参考：<https://github.com/apple/swift-collections>、<https://github.com/richardtop/CalendarKit>、<https://github.com/airbnb/HorizonCalendar>、<https://github.com/WenchaoD/FSCalendar>。
- [ ] Checkpoint B：跨平台布局修复、fixture、回归与性能测试。
- [ ] Checkpoint C：owned UI 设备矩阵截图验收、精确 Release 安装与收口。

## 资源所有权

- 尚未创建 simulator、启动 UI runner 或生成临时构建产物。
