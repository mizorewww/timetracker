# 23：Timeline 短任务轨道布局实现记忆

Status: Complete

> 本文件只用于主代理与子代理的实现、验证和编排记忆，不是任务来源。唯一范围与状态必须重新读取
> [`Docs/userfeedback.md`](../../../../userfeedback.md) 中对应的 `[~]` 条目。

## 当前阶段

- [x] 领取反馈，审计手机 Timeline 的事件几何、最小高度、图标和 elapsed 标签布局。
- [x] 对照 Apple HIG、SwiftUI 布局语义与成熟日历/时间轴实现，确定轨道分配和间距规则。
- [x] 实现短任务避让及回归测试，保持正常长度任务和跨平台行为稳定。
- [x] 使用 owned iPhone simulator 验证普通交互路径并截图；按需要补充 iPad 回归，随后清理资源。
- [x] 执行 `CONFIGURATION=Release scripts/build_install_all.sh`，标记反馈完成并移除活动链接。

## 唯一反馈边界

- 手机上的任务时间过短、无法容纳图标时，不得向上侵占相邻任务；应按屏幕几何阈值将冲突事件分配到不同轨道或向安全方向布局。
- 相邻短任务之间必须保持可辨识间距，不遮挡已有或可能出现的 `xxx min elapsed` 标签。
- 不领取后续 Live Activity、首页统计、Apple Health 历史或其他新增反馈。

## 强制约束

- 优先修正共享 Timeline layout/read model，不以某条测试数据或硬编码坐标伪造结果。
- 先审计现有依赖与成熟实现；只有质量、维护状态和收益足够时才引入库，一般拒绝非用户指定且 GitHub 少于 1k stars 的依赖。
- UI 与截图只使用明确登记的 owned simulator；物理设备只做最终 Release 安装和只读核验，不启动、不操作、不截图。
- 每个小 checkpoint 验证后提交；只暂存本任务状态差异，保护 `Docs/userfeedback.md` 中用户新增内容。

## Checkpoint 编排

- [x] Checkpoint A：静态审计与算法/依赖研究。
  - 根因是“数据时间轨道”与“屏幕视觉轨道”分离：`TimelineLayoutEngine` 只按真实时间和固定 60 秒 gap 分 lane；compact vertical chart 随后才把短条独立扩为至少 20pt。真实 gap 大于 60 秒时，两个最终矩形仍可能在压缩后的 340/520pt 轴上相撞。
  - 末尾短条的 end 同时是动态 display interval 的下界；旧 `min(y, height - barHeight)` 为防越界会把条的 origin 从真实 start 向上搬，直接复现反馈。长空档又会被 `TimelineAxisCompression` 压成 15 分钟占位，因此不能用另一个固定秒数修补。
  - 反馈中的 `xxx min elapsed` 在当前实现里最接近 omitted-gap capsule。horizontal marker 已有前景 `zIndex`，vertical marker 却先于 bars 绘制且没有层级，确实可能被盖住。
  - 采用纯 projected-mark geometry：由 compact vertical chart 的实际高度、同一 compression、最小 mark 高度与 point spacing 一次算出 `axisOrigin`、`axisExtent`、`visualEnd`、lane 和 laneCount；grid、gap marker 与 bars 共用扣除尾端 reserve 后的同一 axis length。条始终锚定 start 向下扩，视觉矩形本身参与 interval partition。
  - 视觉投影只替换 compact vertical 路径；iPad/macOS 的 horizontal 时间轨道与领域 snapshot 语义保持不变。几何是纯值且稳定排序，不存入 `@State`，避免旋转/resize 产生 stale layout 或闪烁。
  - Apple HIG 要求图表 mark、轴和说明保持清晰层级，并给重要内容足够空间；SwiftUI 专项规范要求由实际容器尺寸驱动布局、把可测试逻辑移出 View body、保持稳定 identity。参考：<https://developer.apple.com/design/human-interface-guidelines/charts>、<https://developer.apple.com/design/human-interface-guidelines/layout>、<https://developer.apple.com/documentation/swiftui/custom-layout>。
  - 依赖审计：CalendarKit（约 2.7k stars）验证了日历事件在绘制层按 frame 分组的成熟方向，但它是 UIKit/Mac Catalyst 整套 day calendar，接入会替换现有 SwiftUI、自定义压缩轴、Health 混合数据与相邻精确记录列表；HorizonCalendar（约 3.1k）和 FSCalendar（约 10.6k）是日期网格而非本时间轨道；KVKCalendar 约 801 stars，低于约束。均不采用。参考：<https://github.com/richardtop/CalendarKit>、<https://github.com/airbnb/HorizonCalendar>、<https://github.com/WenchaoD/FSCalendar>、<https://github.com/kvyatkovskys/KVKCalendar>。
  - 最终依赖决策采用 Apple 官方 `swift-collections` 1.6.0 的 `HeapModule`（审计时约 4,459 stars，持续维护）：把领域时间轨道和后续屏幕投影轨道共用的稳定 interval partition 提取为 `TimelineLaneAllocator`，同时删除项目内手写 `MinHeap`，不保留重复实现。整套 CalendarKit/HorizonCalendar/FSCalendar 仍不引入，因为它们不能替代本项目的压缩轴与混合数据语义。
- [x] Checkpoint B：实现轨道几何与单元/契约回归。
  - [x] B1：主 target 显式链接 `HeapModule`；共享分配器接受时间或投影 point interval，按 start/end/stable ID 稳定排序，使用两个最小堆以 `O(n log k)` 复用编号最小的可用轨道；`TimelineLayoutEngine` 已迁移且保留严格 `> 60s` 的原领域行为。
  - [x] B1 验证：`plutil` 通过；macOS arm64、付费开发签名下运行 `AnalyticsTimelineTests` 与 `CorePerformanceBudgetTests`，33/33 通过、0 failure、0 skip；50,000 段性能预算与大规模 Timeline 布局预算均通过。该批次没有 simulator，测试 app/runner 已退出，临时 DerivedData 在提交前删除。
  - [x] B2：compact vertical 先以实际容器高度和同一 compression 投影 mark footprint，再按 20pt 最小高度与 6pt 视觉间距分轨；时间轴统一预留一个最小 mark 尾部空间，短条锚定 projected start 向下扩展，不再使用 `min(y, height - barHeight)` 向上挪动。iPad/macOS horizontal 路径继续使用领域 lane/full-width axis，未改变。
  - [x] B2：vertical grid、omitted-gap marker 与 bars 共用 `barLayout.axisLength`；gap capsule 被约束在专用 axis annotation gutter 内，不再与 plot 中 bar 几何相交。视觉阈值按反馈的“小于”语义处理：恰好 6pt 可复用轨道，领域时间分配器原有严格边界保持不变；0 高度不创建不可见轨道。
  - [x] B2 验证：macOS arm64、付费开发签名下精确运行 `AnalyticsTimelineTests`、Task 23 的 `HomeUIContractTests/todayAndAnalyticsShareOneGraphicalTimelineComponent` 与 `CorePerformanceBudgetTests`，38/38 通过、0 failure、0 skip；覆盖投影碰撞换轨、逆序稳定、末端向下生长、恰好阈值、0 高度、gutter 边界、50,000 段与大规模 Timeline 性能预算。一次扩大到整个 `HomeUIContractTests` 的诊断运行额外暴露 Quick Start/Tracking entrypoint 的反馈范围外既有契约失败；Task 23 自身契约通过，本任务未越界修改那些代码。
  - [x] B2.1 HIG 复审：将 vertical annotation gutter 扩为 96pt，英文省略时长保持系统 `caption2` 11pt、允许两行，不再用 `minimumScaleFactor(0.7)` 压成约 7.7pt；与 capsule frame 相撞的内部 hour ticks 会被纯布局过滤，start/end 边界仍保留。gap 虚线在数据 marks 后绘制，仅 gutter label 位于前景，避免辅助线穿过彩色条和图标。
  - [x] B2.1 验证：新增真实 omitted-gap 压缩回归，证明 pixel lane 依据压缩后距离换轨，并验证 gap 边界 tick 让位；Timeline/Task 23 contract 30/30 通过、0 failure、0 skip。该批次未创建 simulator。
- [x] Checkpoint C：专用短任务 fixture、owned simulator 截图验收与精确 Release 安装收口。
  - [x] C1：新增仅在 `--uitesting-short-timeline` 下生效的隔离 fixture；它以 replace-on-launch 模式创建两条相隔 90 秒的 30 秒短任务、一条靠近显示区末端的 30 秒短任务，以及一条制造长空档压缩的上下文记录，正常 Demo 与用户数据路径不受影响。
  - [x] C1：新增 iPhone-only UI 验收入口与源码契约，明确要求加载专用 fixture、定位 Today Timeline 并导出 `iphone-home-short-timeline-lanes` 截图。macOS arm64、付费开发签名下精确运行共享图表契约、fixture 契约和非 Debug Demo 隔离契约，3/3 通过、0 failure、0 skip。首次不带 Swift Testing 枚举中的 `()` 过滤只加载 suite 而执行 0 项，未计为验证；随后按枚举出的完整测试标识重新执行并得到上述 3/3 结果。
  - [x] C2：在 owned iPhone 17 Pro / iOS 27.0 上运行专用 UI 测试。第一次运行因测试直接查询图表下方尚未惰性加载的记录行而失败；失败 hierarchy 同时证明 fixture 与 chart marks 已加载。修正为直接检查图表 mark 后，同一设备重跑 1/1 通过、0 failure、0 skip：蓝/橙短 mark 的投影矩形确实相交，横向 lane 间距至少 6pt；末端绿色短 mark 位于两者之后并保持向下锚定。
  - [x] C2 截图验收：`iphone-home-short-timeline-lanes`（iPhone 17 Pro，1206×2622）显示蓝/橙 30 秒 mark 在相邻轨道而非向上侵占，绿色末端 mark 向下生长；`2 hr skipped` capsule 与虚线清晰可读、未被彩色 mark 或图标遮挡，普通字号下记录列表也没有重叠。截图检查后已删除。
  - [x] C3：精确执行 `CONFIGURATION=Release scripts/build_install_all.sh` 成功；Release `1.1.52 (107)` 使用 Apple Development `ZEXUAN GAO (PX46M259V3)` / Team `LT98S43NKA` 签名，iOS 主应用和 embedded Watch companion 均通过严格 codesign 验证，并安装到 iPad Pro M4 与 iPhone Air；macOS 通用应用构建成功、复制到 `/Applications/timetracker.app` 并通过严格 codesign 验证。脚本保持默认 `LAUNCH_AFTER_INSTALL=0`，未启动、操作或截图任何物理设备；没有可见物理 Apple Watch，因此仅验证了 embedded companion，配对手表后续由系统 Automatic App Install 负责。

## 资源所有权

- C1 的 macOS app/test runner 已退出，临时 `build/Task23FixtureContracts` 已删除。
- C2 owned simulator：`TT-Task23-Timeline-iPhone17Pro-20260722-1817`，iPhone 17 Pro / iOS 27.0，UDID `4CFD5544-D462-4654-B41F-77C160B38E91`。创建前没有 Booted device，Simulator.app 也未运行；验收后已终止 app/runner、关机并删除该设备，当前没有本批次 Booted device，Simulator.app 已退出。
- C2 owned artifacts：`build/Task23SimulatorValidation` 中的 DerivedData、两次 xcresult、失败诊断、截图和导出附件均已删除；没有遗留 owned `xcodebuild`、`xctest`、UI runner、app extension 或 trace 进程。
- C3 Release 构建产物在读取版本与签名结果后删除；没有 Booted simulator，也没有遗留本任务 owned `xcodebuild`、`xctest`、UI runner、app extension、trace 或 timetracker 进程。
