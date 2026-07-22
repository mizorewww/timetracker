# 25：跨平台 Timeline 省略时长标注碰撞实现记忆

> 本文件只用于主代理与子代理的实现、验证和编排记忆，不是任务来源。唯一范围与状态必须重新读取
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 子条目。

## 当前阶段

- [x] 领取反馈，复现并审计 iPhone 多个 `xxx min elapsed` 标注互相遮挡的根因。
- [x] 对照 Apple HIG、SwiftUI 布局语义和成熟实现，确定跨平台标注避让策略。
- [ ] 实现纯布局修复与覆盖密集 gap 的单元/契约测试。
- [ ] 使用明确登记的 owned simulator 与本机 macOS 窗口做全平台 UI/截图验收并清理资源。
- [ ] 精确执行 `CONFIGURATION=Release scripts/build_install_all.sh`，标记反馈完成并移除活动链接。

## 唯一反馈边界

- 修复 iPhone Timeline 中多个 `xxx min elapsed` 标注彼此遮挡的问题。
- 同一修复必须覆盖 iPhone、iPad 与 macOS Timeline，并做视觉测试。
- 不领取紧随其后的彩色任务条宽度/图标反馈，也不处理版本 hook、Live Activity 或其他条目。

## 强制约束

- 优先修正共享纯布局与真实 fixture，不用截图专用硬编码坐标伪造结果。
- 先审计现有依赖与成熟实现；一般拒绝非用户指定且 GitHub 少于 1k stars 的依赖。
- UI 截图只来自 owned simulator 或本机 macOS 自动化窗口；物理设备只做最终 Release 安装和只读核验，不启动、不操作、不截图。
- 每个小 checkpoint 验证后提交；只暂存本任务状态差异，保护 `Docs/userfeedback.md` 中其余用户新增内容。

## Checkpoint 编排

- [x] Checkpoint A：静态根因审计、相关规范与依赖研究。
  - [x] 根因：compact-width 的 `verticalTimeline` 仍逐个调用 `verticalGapLabelFrame(position:axisLength:)`；该 helper 只把单个 32pt 标签 clamp 到轴内，没有 gap-to-gap 分配。两个压缩 gap 的投影中点相距小于 32pt 时，84pt gutter 中的 capsule 必然相交；`zIndex(1)` 和让 hour ticks 避让 gap 都不能解决 gap 彼此碰撞。Task 24 的 96pt footprint + 4pt 间距多行 allocator 只接入 horizontal 路径。
  - [x] 影响范围：iPhone 竖屏及 compact-width 横屏、可能进入 compact size class 的 iPad 窄窗口；regular iPad 与 macOS 已有 horizontal 多行分配，但必须回归。
  - [x] 确定性复现：09:00–12:00、14:00–14:10、16:10–18:00 三段产生两个 2 小时 gap；压缩轴把每个 gap 折成 15 分钟。在 300pt iPhone 轴上两个中点仅相距约 22.7pt，旧 32pt frame 约重叠 9.3pt；在约 702pt horizontal 轴上两个 96pt frame 也会碰撞，既有 row allocator 应分到不同标注行。
  - [x] Apple Charts 的 `AxisValueLabelCollisionResolution.greedy` 证明“无法容纳时稳定降密度”是平台认可的轴标签策略，但它不适用于这里的自定义 annotation；`AnnotationOverflowResolution.fit` 只解决边界溢出。HIG Charts 要求辅助标注不与主数据竞争，HIG Layout 要覆盖旋转和 iPad 可变窗口，SwiftUI `Layout` 适合让 compact chart 根据真实 footprint 自适应尺寸。参考：<https://developer.apple.com/documentation/charts/axisvaluelabelcollisionresolution>、<https://developer.apple.com/documentation/swiftui/layout>、<https://developer.apple.com/design/human-interface-guidelines/charts>、<https://developer.apple.com/design/human-interface-guidelines/layout>。
  - [x] 成熟实现：Apache ECharts（审计时 66,868 stars、2026-07-15 仍有提交）采用 `moveOverlap: shiftY`，先稳定前推再回收边界空间，仍无法容纳才 `hideOverlap`；这与固定矩形时间标签最匹配。`d3-force`（1,991 stars）的迭代圆形碰撞会抖动且偏离精确时间锚点；ChartsOrg/Charts（28,004 stars）是整套并行 renderer，引入只为一维布局不合比例。参考：<https://github.com/apache/echarts/blob/74e9e09a0b5687fdd34319121ac73b3022d1483c/src/label/labelLayoutHelper.ts#L305-L590>、<https://github.com/d3/d3-force>、<https://github.com/ChartsOrg/Charts>。
  - [x] 依赖决策：不新增库；继续复用仓库锁定的 Apple `swift-collections` 1.6.0（审计时 4,459 stars）。新增 vertical placement/layout 纯 helper：按理想 Y 与稳定 id 排序，前向避让并向上回收，保持顺序和 4pt 间距；compact chart 优先增高到可容纳全部 32pt 标签，硬约束 fallback 才确定性降密度，所有 gap 虚线始终保留。hour ticks 必须使用同一最终 frame 避让。
- [ ] Checkpoint B：共享标注布局、密集 gap fixture 与自动化回归。
- [ ] Checkpoint C：owned UI 设备矩阵截图、精确 Release 安装与收口。

## 资源所有权

- 当前未创建 simulator，未启动 app、测试宿主或 Instruments。
