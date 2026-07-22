# 29：Live Activity 时间尾部间距与排版优化实现记忆

> 本文件只用于主代理与子代理的实现、验证和编排记忆，不是任务来源。唯一范围与状态必须重新读取
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 条目。

## 当前阶段

- [x] 领取反馈，定位 Live Activity 各 family 的尾部时间布局、现有 fixture 与自动化验收入口。
- [x] 依据 Apple HIG 与 SwiftUI 布局规范确定信息层级、间距和最窄宽度契约。
- [~] 实现最小修复，补齐单元/UI contract 与完全脚本化 XCUITest 几何/截图验收。
- [ ] 精确执行 `CONFIGURATION=Release scripts/build_install_all.sh`，标记反馈完成并移除活动链接。

## 唯一反馈边界

- 修复 Live Activity 最右侧时间附近异常空白/间距。
- 在不改变计时语义和交互能力的前提下，提高 Lock Screen / Dynamic Island 排版质量。
- 不领取主页统计图、Apple Health 或其他后续反馈。

## 强制约束

- 开始 UI/SwiftUI 工作前完整遵循仓库本地 `apple-hig` 与 `swiftui-expert-skill`，只读取其任务相关引用。
- 优先复用 ActivityKit、WidgetKit、SwiftUI 与仓库既有组件；若原生布局足够，不为装饰引入第三方依赖。
- 所有可重复验收写成 XCTest/XCUITest；macOS 如需窗口位置，由 `XCUICoordinate` 自动完成。只在自有模拟器截图；物理机仅最终 Release 安装与签名/版本只读核验，绝不启动、点击或截图。
- 每个 checkpoint 只暂存本任务变更，保护 `Docs/userfeedback.md` 中其他用户新增内容。

## Checkpoint 编排

- [x] Checkpoint A：布局根因、HIG 约束与自动化验收设计审计。
- [~] Checkpoint B：实现、定向单元/UI contract 与脚本化视觉验收。
- [ ] Checkpoint C：Release 全设备安装、签名/版本只读核验与收口。

## 资源所有权

- 当前静态审计子 agent：只读，无文件、build、simulator 或设备所有权。
- 主代理 Checkpoint A Dynamic Island iPhone 批次（已关闭）：`Task29-LiveActivity-iPhone17Pro`，UDID `0EB915F6-E338-4072-AA63-57C78DDF6B37`；仅运行脚本化 XCTest/XCUITest，App/runner 已终止，设备已关机并删除。
- 后续每个模拟器批次必须在此记录名称与 UDID；主代理负责终止 App、关机、删除，并核验无 runner/process 残留。

## Checkpoint A 审计结论

- 根因来自 App 自己叠加的布局约束，不是 Dynamic Island 系统保留区：`LiveActivityTimerRow.horizontalContent` 的 `HStack(spacing: 10)`、可无限扩张的 `ActivityTaskSummary` 与额外 `Spacer(minLength: 6)` 让标题到时间的最低视觉断层成为 `10 + 6 + 10 = 26pt`。
- `TimerText` 再强制预留 Lock Screen `78...104pt` / Expanded `64...84pt` 的宽度，短时间字符串也携带不可见的“幽灵宽度”；compact leading/trailing/minimal 又分别硬编码 `62/50/45pt`，重复干预系统本来就会提供的 compact region。
- compact/minimal 的 `.minimumScaleFactor(0.7/0.55)` 会把默认 11pt 的 `.caption2` 最坏压到约 7.7/6.1pt，低于 Apple HIG 的 iOS 11pt 最小字号。Lock Screen 外层 `14pt` padding 正好等于 HIG 标准边距，必须保留。
- Apple Live Activities HIG 要求 compact leading/trailing 作为一个视觉单元、两侧尽量窄并贴近 TrueDepth camera，不自行增加 camera 侧 padding；空间不足应缩短信息精度并保持清晰字号。SwiftUI 原生 `SystemFormatStyle.Stopwatch` 支持用 `maxFieldCount` 在 `HH:MM:SS` 与 `HH:MM` 之间降级。
- 实现契约：删除冗余 Spacer 与固定宽度/低字号缩放；让 Lock Screen/Expanded timer 使用 intrinsic width；compact/minimal 用 `ViewThatFits` 首选三字段 stopwatch、空间不足回退两字段，同时把完整三字段时间保留为 accessibility value。保留系统黑底、task icon、单行标题、14pt Lock Screen margin 与现有 deep link。
- 方案完全复用 ActivityKit、WidgetKit、SwiftUI `ViewThatFits`、`SystemFormatStyle.Stopwatch` 与 XCTest/XCUITest，不新增第三方依赖；这里没有成熟库能比系统 family proposal 更准确。
- 现状基线由自有 iPhone 17 Pro / iOS 27 模拟器上的 `LiveActivitySystemSurfaceUITests.testDynamicIslandPresentsTheRegisteredRunningTask` 全脚本执行：ActivityKit 注册、Home/SpringBoard 切换、Dynamic Island 长按展开及 4 张截图均自动完成，测试通过。截图证实 compact 时间使用被缩小的完整 `16:00:xx`，expanded 标题与时间之间存在明显松散空白。
- 后续自动验收会把测试限制为 simulator-only，并为 compact/expanded 元素加入稳定 identifier；断言 leading/timer 分居 camera 两侧、垂直对齐且不重叠，expanded icon/title/timer 同行且不重叠，并保留截图。Checkpoint A 的 xcresult/截图临时目录已删除，无 `xcodebuild`、`xctest`、runner、trace 进程或 Booted/Task29 simulator 残留。
