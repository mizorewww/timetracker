# 27：省略时长胶囊自适应文字宽度实现记忆

> 本文件只用于主代理与子代理的实现、验证和编排记忆，不是任务来源。唯一范围与状态必须重新读取
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 子条目。

## 当前阶段

- [x] 领取反馈，定位 `xxx min elapsed/skipped` 胶囊的固定宽度来源及所有平台复用点。
- [x] 对照 Apple HIG、SwiftUI intrinsic sizing 与现有成熟组件确定自适应宽度契约。
- [x] 实现胶囊抱住完整文字并补充布局/契约回归。
- [~] 使用 owned simulator 与 XCTest 自动化 macOS window 做跨平台截图验收并清理资源。
- [ ] 精确执行 `CONFIGURATION=Release scripts/build_install_all.sh`，标记反馈完成并移除活动链接。

## 唯一反馈边界

- Timeline 的省略时长文字胶囊不能使用无法容纳完整文案的固定宽度；背景必须随实际文字和内边距自适应。
- 修复覆盖该共享 Timeline 组件所支持的平台与布局方向。
- 不领取版本 hook、Live Activity、主页说明文字或任何后续反馈。

## 强制约束

- 先审计现有组件、局部化文案与布局算法；不能通过缩小字体、截断文字或为截图硬编码某个文案宽度掩盖问题。
- 优先使用 SwiftUI 原生 intrinsic sizing 与现有组件；如确需第三方依赖，先核验成熟度并一般拒绝 GitHub 少于 1k stars 的非用户指定库。
- UI 验收只使用 owned simulator 与 XCTest 自动化 macOS window；物理设备只做最终 Release 安装和只读核验，不启动、不操作、不截图。
- 每个小 checkpoint 验证后提交；只暂存本任务状态差异，保护 `Docs/userfeedback.md` 的其他用户新增内容。

## Checkpoint 编排

- [x] Checkpoint A：静态根因、复用点、局部化宽度与成熟方案审计。
- [x] Checkpoint B：intrinsic capsule 实现与纯布局/契约回归。
- [~] Checkpoint C：owned UI 设备矩阵与脚本截图验收。
- [ ] Checkpoint D：精确 Release 安装、状态标记与收口。

## Checkpoint A 审计结论

### 根因与复用范围

- `TimelineChartLayout.horizontalGapLabelWidth = 96` 让横向 placement 永远使用同一宽度，`TimelineChartGrid.horizontalGapLabel` 又把带 padding 的胶囊压回该固定 frame。
- 紧凑 iPhone 纵向布局同样把胶囊压进 `verticalAxisLabelWidth - 12 = 84pt`；所以 Home 与 Analytics 共用的 `TimelineChart` 在所有布局方向都受影响。
- `DurationFormatter.compact` 与 `analytics.timeline.gap.omitted` 能生成完整本地化文案；数据和翻译没有丢失，问题只在固定显示框。
- 旧 fixture 只有两个 `2 hr skipped`，旧 XCUITest 还允许 `40...110pt`，因此固定 96pt 会被误判通过。

### HIG 与原生实现决定

- Apple HIG 要求布局适配窗口、方向、Dynamic Type 和不同长度的本地化文本；不能以固定文案宽度、缩字或截断代替自适应布局。
- 使用统一的单行 `TimelineGapLabel`，让 SwiftUI 以 `.fixedSize(horizontal: true, vertical: true)` 保留包含文字与 padding 的理想尺寸。
- 使用 SwiftUI `Layout` 和 `LayoutSubview.sizeThatFits(.unspecified)` 在布局周期内取得真实尺寸；横向用实测宽度分行，纵向用最长实测宽度扩展 gutter，并让 grid、connector、lane 与可滚动最小宽度共享同一 gutter。
- 不使用 GeometryReader/状态回传尺寸；Apple 的自定义 Layout 指南明确警告该做法可能形成布局反馈循环。
- 不新增第三方库。该问题由 SwiftUI 原生 layout engine 最准确地处理；额外文字测量/图表库既重复造轮子，也无法比系统更可靠地覆盖本地化字体和 Dynamic Type。现有 `swift-collections` 与本修复无关。

### Checkpoint B 验收契约

- fixture 必须经真实 `DurationFormatter` 产生一短一长两种文案，击穿旧 96pt 假设。
- 纯布局回归覆盖：每个 label 的实测 extent、横向碰撞分行与输入反序确定性、纵向 gutter 随最长胶囊增长、最小滚动宽度保留 bar footprint。
- 仅在 UI-test 标记开启时暴露成对的 `timeline.gapText.<id>` / `timeline.gapCapsule.<id>` 几何 probe；生产 VoiceOver 仍保持一个 gap 语义元素。
- XCUITest 按 ID 配对后直接断言胶囊包含完整文字、两侧 padding 对称、长胶囊比短胶囊宽、宽度差跟随文字宽度差、无省略且标签互不相交。
- iPhone portrait、iPad portrait/landscape、macOS 自动坐标放窗全部由 XCTest/XCUITest 完成；物理机不启动、不交互、不截图。

### 只读子代理结论

- 静态审计与 UI 策略代理均未编辑文件、构建、启动设备或占用 simulator。
- 两者一致建议使用 SwiftUI `Layout` 的真实 subview 测量；UI 策略额外指出必须分别暴露文字和胶囊 frame，否则旧测试无法证明“抱住文字”。

## Checkpoint B 实现与验证

- 统一的 omitted-gap label 改为单行 intrinsic size：文字本身与包含 6pt 水平、3pt 垂直 padding 的材质 `Capsule` 都使用 SwiftUI 理想尺寸，不再把文案压入固定 96pt/84pt frame。
- 横向布局由自定义 `Layout` 实测每个本地化胶囊宽高，再以每个 gap 的真实宽度确定碰撞分行和 annotation band 高度；纵向布局用最长胶囊宽度扩展 gutter，并同步 grid、connector、lane 与最小滚动宽度。
- demo fixture 通过真实 `DurationFormatter` 产生 65 分钟与 155 分钟两个不同长度的英文文案，避免旧的两个同宽 `2 hr skipped` fixture 掩盖固定宽度问题。
- 纯回归覆盖每个 ID 的不同实测宽度、输入反序确定性、实测 label 高度驱动 timeline 高度，以及纵向 gutter/最小滚动宽度随最长胶囊增长。
- 定向验证通过：macOS arm64 Debug 签名构建；`AnalyticsTimelineTests` 的两项新增布局测试；`HomeUIContractTests` 的两项本任务共享组件/fixture 契约，共 4/4 通过。
- 更宽的既有 `HomeUIContractTests` 另有 3 项与本反馈无关的 Quick Start/入口旧契约失败；未将其误报为本任务回归，也未越界修改。
- 未新增第三方库；继续使用系统 SwiftUI `Layout`、XCTest 与 XCUITest。

### 自动化前静态复核加固

- 只读复核发现窄窗口/超长本地化边界：旧算法会把用于碰撞计算的 label width 截成 axis length，却仍按真实 intrinsic width 放置。现已让碰撞 placement 始终保留实测宽度，并让横向内容最小宽度至少容纳最长胶囊与终点 mark；超出 viewport 时由原生水平 `ScrollView` 承载。
- 新增 `labelWidth > axisLength` 的纯回归，证明 placement 不会伪装成较窄宽度；同时验证最小内容宽度会增长。
- UI-test 增加独立的 intrinsic Text reference probe；实际 Text frame 必须与系统 intrinsic reference 相等，查询范围限定在 `home.timeline`，截图前先保证整个 Timeline 位于可见区域。
- 第一轮移动端冷构建在用例执行前主动中止；owned iPhone `B335D372-1EB5-4C68-85AE-04A6A290657D` 与 iPad `1696AE29-B41F-4326-A6BA-9C1545583268` 已终止 App、关机、删除，未留下 Booted device/TestManager/xcodebuild。
- 加固后 macOS arm64 Debug 签名构建通过，本任务 4/4 定向纯测试再次通过；下一步从头执行脚本化 UI 矩阵。
- 复核另指出极端 Dynamic Type 下纵向 32pt 高度模型可进一步扩展；按仓库明确的普通字号验收优先级，本项只处理用户反馈中的胶囊宽度，不扩张为极端字号专项。

### Checkpoint C 自动化稳定性修复与 macOS 验收

- 全程使用 XCTest/XCUITest 自动运行，没有手动移动窗口、操作物理设备或截图。macOS 窗口由既有坐标脚本放置，测试结束自动终止 App。
- 跨午夜运行首先得到三类 probe 均为 0；测试自动导出的 accessibility tree 证明 Timeline 处于空状态，而不是 predicate 失败。根因是 fixture 在当天 09:00—18:00，00:xx 启动时主页数据读取层已按真实时间过滤掉这些记录。
- `TodayHomeContent`、macOS/iPadOS `TimelineSection`、iPhone `PhoneTimelineSection` 与 `TodayTimelineChart` 现仅在 DEBUG 且指定 overlap/gap fixture 参数时共享当天 18:00 参考时间；正常构建和其他启动路径继续使用原有实时数据。
- 图表加入原生横向 `ScrollView` 后，旧 macOS 自动滚动器一度选中屏幕外的内层横向容器。滚动选择器现只接受窗口内、可命中的候选，并按高度选择纵向外层容器，避免任何手动滚动补救。
- 三类 probe 改为应用级唯一前缀查询；iPhone 的 `home.timeline` 是 Section 标题而非图表祖先，因此可见性使用 app window 相交，核心正确性继续由 actual Text 等于独立 intrinsic Text、Capsule 包含全文、padding 正且对称、长文案带来等量增宽来证明。
- macOS 脚本验收通过：2 个 actual Text、2 个独立 intrinsic Text 与 2 个 Capsule probe 全部配对通过；自动截图清楚显示 `1 hr, 5 min skipped` 与 `2 hr, 35 min skipped` 均完整、胶囊宽度不同且互不覆盖。
- macOS arm64 Debug 签名构建与本任务 4/4 定向纯测试在上述修复后再次通过。下一步只使用新建 owned iPhone/iPad simulator 执行 portrait/landscape 脚本矩阵。
