# 25：跨平台 Timeline 省略时长标注碰撞实现记忆

> 本文件只用于主代理与子代理的实现、验证和编排记忆，不是任务来源。唯一范围与状态必须重新读取
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 子条目。

## 当前阶段

- [x] 领取反馈，复现并审计 iPhone 多个 `xxx min elapsed` 标注互相遮挡的根因。
- [x] 对照 Apple HIG、SwiftUI 布局语义和成熟实现，确定跨平台标注避让策略。
- [x] 实现纯布局修复与覆盖密集 gap 的单元/契约测试。
- [~] 使用明确登记的 owned simulator 与本机 macOS 窗口做全平台 UI/截图验收并清理资源。
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
- [x] Checkpoint B：共享标注布局、密集 gap fixture 与自动化回归。
  - [x] B1：新增稳定的 vertical placement/layout：预留首尾各 18pt，保持 32pt 标签高度与 4pt 间距；按理想 Y/稳定 id 排序，用受容量上界约束的前向 placement 把尾部空间向上回收，时间顺序不反转。极端硬约束下确定性均匀降密度但保留所有 dashed gap line；正常 compact path 将 `compactHeight` 作为最小值，按完整 footprint 自动增高，因此保留全部标签。
  - [x] B1：`verticalTimeline`、capsule、短引导线和 `verticalAxisTicks` 共用最终 placement frame；标签不再各自 clamp，也不扩大 96pt gutter 挤压任务轨道。horizontal 路径继续使用 Task 24 的多行 allocator；专用测试语义提供稳定 `timeline.gap.*` identifier，生产图仍由父层保持装饰性隐藏。
  - [x] B1：2026-07-22 使用 Team `LT98S43NKA` 的签名 macOS 测试宿主两次运行完整 `AnalyticsTimelineTests`，每次均为 36 项通过、0 失败；新增用例先证明旧的两个 32pt frame 在 300pt 轴上相交，再证明最终 frame 确定、反序输入一致、完整留在首尾安全区且间距至少 4pt，并覆盖 100pt 硬约束的确定性降密度与 12 个 gap 的 compact Timeline 容量扩展。
  - [x] B1：本批次未创建 simulator。测试宿主已退出，`build/Task25Geometry*` 与全部 xcresult 已删除，确认没有引用这些路径的 `xcodebuild`、`xctest`、UI runner 或 app 进程，且没有 Booted simulator。
  - [x] B2：新增隔离的双 gap fixture：09:00–12:00、14:00–14:10、16:10–18:00 三段稳定产生两个 `2 hr skipped` 标注；专用 `--uitesting-gap-label-collision` 参数与 18:00 固定 reference date 不影响其他 demo/test 路径。
  - [x] B2：新增一条共享 iPhone/iPad/macOS UI 回归入口；它对可见 AX frame 去重，要求两个标注的横向 footprint 确实重叠、最终矩形不相交且保留至少 3pt 的像素取整后间距。iPad 同一测试覆盖 portrait 与 landscape，并分别产出截图；所有截图入口都仅面向 simulator/macOS。
  - [x] B2：2026-07-22 使用 Team `LT98S43NKA` 的签名 macOS 测试宿主运行完整 `HomeUIContractTests`。新增 `multipleGapTimelineFixtureCoversCompactAndHorizontalCollisionLayouts` 通过；测试组仍因任务开始前已存在的 `quickStartUsesIndexedTaskIdentityAndSeparatesNavigationFromTimerActions`（报告两次）与 `trackingEntrypointsShareAvailabilityAndRunningStateSemantics` 失败而以 65 退出，未把它误记为全绿。编译及本任务契约验证成功。
  - [x] B2：本批次没有创建 simulator；`build/Task25Fixture`、对应 xcresult、测试宿主及派生进程均已清理，确认没有 Booted simulator。
- [~] Checkpoint C：owned UI 设备矩阵截图、精确 Release 安装与收口。

## 资源所有权

- [x] owned iPhone batch：`Task25-iPhone-17-Pro`，UDID `D6759E45-FE6C-4BB1-8FAD-BDF341594468`，iPhone 17 Pro / iOS 27.0。顺序复跑后唯一 Task 25 用例 1/1 通过；自动断言确认两个 `2 hr skipped` 的真实 label frame 横向 footprint 重叠但最终不相交并保持间距。原始 XCTest 截图显示两个胶囊在左侧纵轴清晰分开，第二项以短 connector 保留真实时间锚点，三段任务条、图标、虚线和刻度均正常。首次双 simulator 并发只产生 CoreSimulator app launch timeout；首次顺序产品断言又暴露纯 `label` 查询会同时命中两个祖先语义 frame，最终查询收窄到生产已有的 `timeline.gap.*` identifier，避免把容器误计为标签。XCTest 已终止 app/runner，owned UDID 已 shutdown/delete，`build/Task25UIPhone*`、xcresult、失败录像与导出截图均已删除，确认没有该 UDID 或相关进程残留。
- [x] owned iPad batch：`Task25-iPad-Pro-11`，UDID `02B4E95F-C009-43B5-AA48-C96DEA0F92CD`，iPad Pro 11-inch (M5) / iOS 27.0。最终唯一 Task 25 用例 1/1 通过，portrait 与 landscape 均读取两个真实 32pt 高 gap label frame；较窄 portrait 中两个 96pt footprint 相交时被分配到独立 annotation row，landscape 宽度足够时保持同一行至少 3pt 水平间距，两个方向的矩形都不相交。两张原始 XCTest 截图均显示胶囊、三段任务条、图标、虚线、刻度和记录列表清楚正常。首轮与 iPhone 并发只产生 app launch timeout；首个顺序运行确认 iPad regular-width 的父 `home.timeline` 会覆盖子 identifier，因此最终查询使用精确文案并限制到真实 40...110pt × 16...40pt label footprint，排除大尺寸祖先语义 frame；第二轮仅因 landscape 宽度使理想标签本就不相交而调整成按 X/Y 实际分离方向断言。XCTest 已终止 app/runner，owned UDID 已 shutdown/delete，`build/Task25UIIPad*`、xcresult、失败诊断与导出截图均已删除，确认没有该 UDID 或相关进程残留。
- [x] macOS UI batch：唯一 Task 25 用例 1/1 通过。AX 几何自动证明两个 `2 hr skipped` 横向 footprint 重叠但最终 frame 不相交并保持间距；原始 XCTest attachment 是有效前台 App 截图，两个胶囊位于独立标注行且清晰可读，三段任务条、图标、刻度和记录列表正常。XCTest 已终止 app/runner；`build/Task25UIMac`、xcresult 与导出截图均已删除，确认没有相关进程。
- 全部 simulator 批次结束后必须删除以上两个 owned 设备，并确认无 Booted device、DerivedData、xcresult 或导出截图残留。
