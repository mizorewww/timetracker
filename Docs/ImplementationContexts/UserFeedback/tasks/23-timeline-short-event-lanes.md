# 23：Timeline 短任务轨道布局实现记忆

> 本文件只用于主代理与子代理的实现、验证和编排记忆，不是任务来源。唯一范围与状态必须重新读取
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 条目。

## 当前阶段

- [x] 领取反馈，审计手机 Timeline 的事件几何、最小高度、图标和 elapsed 标签布局。
- [x] 对照 Apple HIG、SwiftUI 布局语义与成熟日历/时间轴实现，确定轨道分配和间距规则。
- [~] 实现短任务避让及回归测试，保持正常长度任务和跨平台行为稳定。
- [ ] 使用 owned iPhone simulator 验证普通交互路径并截图；按需要补充 iPad 回归，随后清理资源。
- [ ] 执行 `CONFIGURATION=Release scripts/build_install_all.sh`，标记反馈完成并移除活动链接。

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
  - 不新增第三方库：复用 SwiftUI、现有 Timeline compression/read model 和已有 heap-backed lane allocator；为几十行投影引入整套日历框架会扩大包体、桥接与回归面且不能解决自定义语义。Apple 官方 `swift-collections` Heap（约 4.4k stars）只在未来替换现有私有 heap 时才有收益，本 checkpoint 不复制第二套 heap。
- [~] Checkpoint B：实现轨道几何与单元/契约回归。
- [ ] Checkpoint C：owned simulator 截图验收与精确 Release 安装收口。

## 资源所有权

- 尚未创建 simulator、测试 runner、截图或 trace 资源。
