# 29：Live Activity 时间尾部间距与排版优化实现记忆

> 本文件只用于主代理与子代理的实现、验证和编排记忆，不是任务来源。唯一范围与状态必须重新读取
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 条目。

## 当前阶段

- [x] 领取反馈，定位 Live Activity 各 family 的尾部时间布局、现有 fixture 与自动化验收入口。
- [x] 依据 Apple HIG 与 SwiftUI 布局规范确定信息层级、间距和最窄宽度契约。
- [x] 实现最小修复，补齐单元/UI contract 与完全脚本化 XCUITest 几何/截图验收。
- [~] 精确执行 `CONFIGURATION=Release scripts/build_install_all.sh`，标记反馈完成并移除活动链接。

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
- [x] Checkpoint B：实现、定向单元/UI contract 与脚本化视觉验收。
- [~] Checkpoint C：Release 全设备安装、签名/版本只读核验与收口。

## 资源所有权

- 当前静态审计子 agent：只读，无文件、build、simulator 或设备所有权。
- 主代理 Checkpoint A Dynamic Island iPhone 批次（已关闭）：`Task29-LiveActivity-iPhone17Pro`，UDID `0EB915F6-E338-4072-AA63-57C78DDF6B37`；仅运行脚本化 XCTest/XCUITest，App/runner 已终止，设备已关机并删除。
- 主代理 Checkpoint B 第一轮视觉验收批次（已关闭）：`Task29-Verify-iPhone17Pro`，UDID `0AD815A6-93DC-4AB4-9633-5E81143F71BA`；simulator-only XCUITest 成功注册 ActivityKit 并找到 compact identifiers，但 SpringBoard 为 compact Link 返回 `CGRect.null`，旧几何断言因此失败。已终止 App/runner 与诊断收集、关机删除设备，并清除 DerivedData/损坏的未封口 xcresult；无该批次进程或 Booted 设备残留。
- 主代理 Checkpoint B 第二轮 iPhone 17 Pro 批次（已关闭）：`Task29-Verify2-iPhone17Pro`，UDID `53F84305-F592-4917-91F7-6F9F4A28354A`；simulator-only XCUITest 的注册、语义、逐秒更新、通知中心手势与长按展开均通过，但 fresh simulator 的系统 Live Activities 授权提示遮住了 Lock Screen 截图，compact/expanded 截图也未显示视觉 timer，因此不作为验收结论。App/runner 已终止，设备已关机删除，DerivedData/xcresult/截图已清除且无残留进程。
- 主代理 Checkpoint B 第三轮 iPhone 17 Pro 批次（已关闭）：`Task29-Verify3-iPhone17Pro`，UDID `56E59D68-2BE6-40DE-9274-5C6ED446AB35`；第一遍测试逻辑通过，但截图证明授权提示是自定义 SpringBoard 面板而非 `XCUIElementTypeAlert`，因此改为直接查找并点击系统 `Allow` button。增量复跑在到达系统界面前失败：xcresult 无障碍树证明复用后的内存测试 store 没有重新呈现任何 active segment（`Now` 仅显示 `home.startTimer`），所以本轮不能验证授权修复或布局。该失败属于测试夹具/批次复用，不作为产品布局结论；App/runner 已终止，设备已关机删除，DerivedData、xcresult、失败附件均已清除，且无 Task29/Booted simulator 或相关进程残留。下一轮改用全新自有 simulator，从冷启动完整执行脚本。
- 主代理 Checkpoint B 第四轮 iPhone 17 Pro 批次（已通过并关闭）：`Task29-Verify4-iPhone17Pro`，UDID `08AACF5D-601B-443C-8CAF-773710314B4E`；最终 simulator-only XCUITest 1/1 通过，注册、系统授权、compact/Lock Screen/expanded 语义、逐秒更新、>=8 小时原始起点、几何和展开脚本全部通过。自动附件逐张验收：compact 为 `Read App… | 16:00:48`；Lock Screen 为 icon + 完整标题/路径 + `16:01:12` 的紧凑纵排；expanded 为 icon + `Read Apple HIG` + `16:01:30` 同一行。三者无黑框、裁切、重叠或异常尾部空白。App/runner 已终止，设备已关机删除，DerivedData/xcresult/附件已清除；无该 UDID、Runner 或诊断进程残留。
- 主代理 Checkpoint B 第一台 iPhone Air 宽尺寸批次（已关闭）：`Task29-Verify-iPhoneAir`，UDID `82AEEED2-5631-4BC9-B91C-1402786792A5`；首次启动在系统 `DAAccount.migrator` 阶段以 `Data Migration Failed` 结束，尚未安装/启动 App 或测试 Runner，因此没有产品结论。设备已立即关机删除。
- 主代理 Checkpoint B 第二台 iPhone Air 宽尺寸批次（已通过并关闭）：`Task29-Verify2-iPhoneAir`，UDID `74D5B69C-9298-4FEA-84CA-04603FA7DC16`；首启同样报告 Xcode 27 beta `Data Migration Failed`，但设备实际 Booted 且 simulator-only XCUITest 1/1 完整通过，证明该迁移状态没有污染 App 测试。自动附件逐张验收：compact 为 `Read Appl… | 16:00:48`；Lock Screen 为完整标题/路径 + `16:01:12`；expanded 为 icon + 完整标题 + `16:01:29` 同一行。无黑框、裁切、重叠或异常尾部空白。App/runner 已终止，设备已关机删除，独立 DerivedData/xcresult/附件已清除；无该 UDID、Runner 或诊断进程残留。
- 主代理 Checkpoint B 优先级分面修订最终回归批次（已通过并关闭）：`Task29-Final-iPhone17Pro`，UDID `1E1E16DF-0986-4A73-90B9-DE33745F5F4F`；simulator-only XCUITest 1/1 通过，自动完成 fixture、ActivityKit 注册、系统授权、compact/Lock Screen/expanded 语义、逐秒更新、>=8 小时原始起点及强几何契约。自动附件逐张验收：compact 为 `Read App… | 16:00:51`；Lock Screen 为完整标题/路径 + `16:01:21` 的紧凑纵排；expanded 为 icon + 完整标题 + `16:01:38` 同一行。无黑框、裁切、重叠或异常尾部空白。App/runner 已终止，设备已关机删除，独立 DerivedData/xcresult/附件已清除；无该 UDID、Runner 或诊断进程残留。
- 主代理 Checkpoint B Apple Vision 可见性门禁最终回归批次（已通过并关闭）：`Task29-OCR-iPhone17Pro`，UDID `B9B67833-14F4-4CC5-A02D-A1E7EB7D258F`；最终 simulator-only XCUITest 1/1 通过，脚本自动完成 fixture、ActivityKit 注册、系统授权、compact/Lock Screen/expanded 语义、逐秒更新、>=8 小时起点、强几何与 Apple Vision 可见性门禁。最终自动附件与 OCR 均确认：compact 为 `Read App… | 16:01:12`；Lock Screen 为完整标题/路径 + `16:01:44` 的紧凑纵排；expanded 为 icon + 完整标题 + `16:02:02` 同一行。无黑框、裁切、重叠或异常尾部空白。App/runner 已终止，设备已关机删除，独立 DerivedData/xcresult/附件已清除；无该 UDID、Runner 或诊断进程残留。
- 主代理 Checkpoint B 分 surface Vision ROI 最终回归批次（已通过并关闭）：`Task29-ROI-iPhone17Pro`，UDID `A96BF1F8-D464-4E01-B2CD-BE5BD23C120B`；最终 simulator-only XCUITest 1/1 通过，脚本自动完成 fixture、ActivityKit 注册、系统授权、compact/Lock Screen/expanded 语义、逐秒更新、>=8 小时起点、强几何与各自 ROI Vision 可见性门禁。最终自动附件与 ROI OCR 均确认：compact 为 `Read App… | 16:00:50`；Lock Screen 为完整标题/路径 + `16:01:15` 的紧凑纵排；expanded 为 icon + 完整标题 + `16:01:33` 同一行。无黑框、裁切、重叠或异常尾部空白。App/runner 已终止，设备已关机删除，独立 DerivedData/xcresult/附件已清除；无该 UDID、Runner 或诊断进程残留。
- Apple Vision 门禁首遍到达 compact 后按设计执行 OCR，并准确识别出 `16:00:49`；测试却因把所有 OCR 行去空白后拼接，导致时间后的 `Fitness` 破坏正则单词边界而红测。该结果证明视觉时间存在且 OCR 链路有效，属于新测试断言错误而非产品红灯。Xcode 27 随后再次把 owned `simctl diagnose` 卡住超过两分钟，主代理只终止该诊断子进程使 xcresult 封口；现改为逐条 OCR 行的完整 `HH:MM:SS` 匹配，并擦除同一 owned simulator 后从冷启动复跑。
- Apple Vision 门禁第二遍的 compact 与 Lock Screen OCR 已通过；expanded 的 Vision 结果把标题和时间合并为同一行 `Read Apple HIG 16:01:40`，而门禁仍要求整条 OCR 行只能是时间，故在最后一个 surface 红测。画面时间同样明确存在，仍是测试匹配过严而非产品红灯。Xcode 27 的 owned `simctl diagnose` 再次卡住超过两分钟，主代理只终止该诊断子进程使失败 xcresult 封口；现把契约修正为“任一 OCR 行包含多小时 `HH:MM:SS`”，再次擦除同一 owned simulator 后全流程冷启动复跑。
- Apple Vision 门禁第三遍尚未进入 ActivityKit/OCR：冷启动首页、唯一 running row 与 16 小时 fixture 均通过，首次自动坐标点击 `settings.open` 后 Xcode 27 却丢失合成事件，5 秒后仍在首页而红测。前两遍同一路径均已成功，故属于 XCUITest 事件投递假红；脚本现会在确认设置页未出现时自动重试一次相同中心坐标，然后仍以页面 identifier 为强断言。再次擦除同一 owned simulator 后冷启动全流程。
- 擦除后的首遍测试在进入 ActivityKit 前再次遇到 Xcode 27 `isHittable == false` 的伪阴性；AX Button 已存在，因此去掉冗余 hittable 门槛并始终通过其中心坐标点击。卸载重跑后，XCUITest 已自动完成系统授权且 compact timer 重新可见，但 `Stopwatch(maxFieldCount: 2)` 在真实 WidgetKit 外观错误显示为 `16 hours, 0…`；Lock Screen 则按 `ViewThatFits` 合理选择纵向 fallback，旧断言因只接受横排而失败。当前修订统一保留三字段 Stopwatch，用 11pt caption2 + 原生 condensed 字宽适配窄 family，并让几何验收同时接受紧凑横排或无重叠纵排。
- 三字段修订后的首次冷启动复跑在 UI 测试开始约 1.58 秒即被 Xcode 27 测试基础设施中止，xcresult 唯一失败为 `Failed to get list of active applications: Accessibility error kAXErrorIPCTimeout`，尚未进入 App fixture 或任何产品断言；其失败录屏也只有启动空白阶段，因此不作为产品红灯。Xcode 随后把 owned `simctl diagnose` 卡住超过两分钟，主代理只终止该诊断子进程使 xcresult 封口；下一遍在已完成首次启动迁移的同一 owned simulator 上重跑。
- warmed simulator 复跑完整到达全部系统表面：compact 自动截图显示 `Read App… | 16:00:56` 且无黑框/裁切，Lock Screen 显示 icon、完整标题/路径及 `16:01:20` 的紧凑纵排；expanded 截图虽有完整标题与 `16:01:37`，但 `ViewThatFits` 因动态 Stopwatch 的布局度量选择了纵排，形成过高黑框，违反已完成“expanded 三元素同一行”反馈，因此按产品红灯拒绝。修订为普通字号 dynamicIsland 始终使用可压缩 horizontalContent，只有 Lock Screen 继续使用横/纵自适应；无 fixedSize、固定 timer 宽度或低字号缩放。
- 强制 expanded 横排后的复跑再次由截图抓到真实红灯：系统已经展开，但 Stopwatch 原有 `.layoutPriority(2)` 把任务 summary 压缩到 0 宽，画面只剩 icon、`16:01:54` 和大片空黑区；XCUITest 因 `liveActivity.expanded.title` 不存在而拒绝通过。现仅对 Dynamic Island 使用 summary 2、timer 1，让标题先保留、原生 timer 接受剩余宽度 proposal；Lock Screen 保持 summary 1、timer 2，确保 `ViewThatFits` 不会误判横排可容纳。仍不引入 fixedSize 或硬编码宽度。
- 后续每个模拟器批次必须在此记录名称与 UDID；主代理负责终止 App、关机、删除，并核验无 runner/process 残留。

## Checkpoint A 审计结论

- 根因来自 App 自己叠加的布局约束，不是 Dynamic Island 系统保留区：`LiveActivityTimerRow.horizontalContent` 的 `HStack(spacing: 10)`、可无限扩张的 `ActivityTaskSummary` 与额外 `Spacer(minLength: 6)` 让标题到时间的最低视觉断层成为 `10 + 6 + 10 = 26pt`。
- `TimerText` 再强制预留 Lock Screen `78...104pt` / Expanded `64...84pt` 的宽度，短时间字符串也携带不可见的“幽灵宽度”；compact leading/trailing/minimal 又分别硬编码 `62/50/45pt`，重复干预系统本来就会提供的 compact region。
- compact/minimal 的 `.minimumScaleFactor(0.7/0.55)` 会把默认 11pt 的 `.caption2` 最坏压到约 7.7/6.1pt，低于 Apple HIG 的 iOS 11pt 最小字号。Lock Screen 外层 `14pt` padding 正好等于 HIG 标准边距，必须保留。
- Apple Live Activities HIG 要求 compact leading/trailing 作为一个视觉单元、两侧尽量窄并贴近 TrueDepth camera，不自行增加 camera 侧 padding；空间不足应缩短信息精度并保持清晰字号。SwiftUI 原生 `SystemFormatStyle.Stopwatch` 支持用 `maxFieldCount` 在 `HH:MM:SS` 与 `HH:MM` 之间降级。
- 实现契约：删除冗余 Spacer 与固定宽度/低字号缩放；Lock Screen timer 使用 intrinsic width，并由 `ViewThatFits` 在窄 family 自动选择紧凑横排或纵排；普通字号 Expanded 强制保持单行。compact/minimal 保留原生三字段 stopwatch 与 11pt caption2，分别以系统 condensed/compressed 字宽适配而不缩小字号。视觉与 accessibility value 都保留持续更新的三字段时间。保留系统黑底、task icon、单行标题、14pt Lock Screen margin 与现有 deep link。
- 方案完全复用 ActivityKit、WidgetKit、SwiftUI `ViewThatFits`、`SystemFormatStyle.Stopwatch` 与 XCTest/XCUITest，不新增第三方依赖；这里没有成熟库能比系统 family proposal 更准确。
- 现状基线由自有 iPhone 17 Pro / iOS 27 模拟器上的 `LiveActivitySystemSurfaceUITests.testDynamicIslandPresentsTheRegisteredRunningTask` 全脚本执行：ActivityKit 注册、Home/SpringBoard 切换、Dynamic Island 长按展开及 4 张截图均自动完成，测试通过。截图证实 compact 时间使用被缩小的完整 `16:00:xx`，expanded 标题与时间之间存在明显松散空白。
- 后续自动验收会把测试限制为 simulator-only，并为 compact/expanded 元素加入稳定 identifier；断言 leading/timer 分居 camera 两侧、垂直对齐且不重叠，expanded icon/title/timer 同行且不重叠，并保留截图。Checkpoint A 的 xcresult/截图临时目录已删除，无 `xcodebuild`、`xctest`、runner、trace 进程或 Booted/Task29 simulator 残留。

## Checkpoint B 实现修订记忆

- 只读复核指出 `ActivityTaskSummary` 自身仍有 `.frame(maxWidth: .infinity)`，即使移除了显式 Spacer，短标题仍会把 expanded timer 推远；已移除该弹性宽度，并只让整行占满容器且左对齐，使 icon、标题、timer 以 10pt 固定节奏紧凑成组。
- compact/minimal 的 timer 可访问性语义已上移至可点击 `Link`：外层统一提供 label、完整三字段 value、stale hint、频繁更新 trait 与唯一 identifier，内部视觉 Text 对辅助功能隐藏，避免产生无 label 的嵌套元素。
- 本机 Xcode 27 beta 对 `Stopwatch(maxFieldCount: 2)` 的直接格式化和真实 iOS WidgetKit 外观都产生长单位词组，与当前 Apple 文档的 `H:MM` 示例不一致；真实截图显示 `16 hours, 0…`，因此不能用作发布 UI。三字段格式在 formatter 契约中稳定为 `16:02:03`，且移除错误 `fixedSize` 后已重新出现；compact/minimal 现统一使用原生三字段 Stopwatch，compact 用 condensed、最窄 36.67...45pt minimal 用 compressed 系统字宽。11pt SF 系统字体的本机只读度量分别约为 40.4pt/35.5pt，没有通过缩小字号换空间。没有改回有结束边界的 `timerInterval`，也没有回退 Task 09 已完成的超过 8 小时持续计时语义。
- SpringBoard 对跨进程 compact Link 可能只发布语义而不发布有限 frame。XCUITest 因而把 label/value、逐秒更新、唯一 identifier 和全自动截图作为强系统面验收；当 compact 系统元素提供有效 frame 时再执行几何断言。每张系统截图同时由 Apple Vision OCR 在该 surface 自己的 normalized ROI 内断言画面中确实渲染多小时 `HH:MM:SS`，堵住“语义存在但视觉全黑/时间消失”以及“整屏其他时间误命中”的假绿。expanded 必须发布有效 frame，标题到 timer 的可见间距必须为 8...24pt；源码 contract 同时禁止弹性 Summary、固定 timer 宽度、低字号缩放与额外 Spacer，并以包含数值后换行边界的完整片段精确锁定 Lock Screen 1/2、Dynamic Island 2/1 的 summary/timer 优先级映射。
- Lock Screen 的 `ViewThatFits` 在窄宽度选择纵排是设计内 fallback，不是错位；脚本几何契约要求横排间距受控，或纵排 timer 位于 summary 下方且不重叠。Expanded 普通字号则必须保持单行。截图附件在几何断言前保存，任何红测也能直接审查外观。

## Checkpoint B 完成结论

- 实现：移除造成尾部幽灵空白与黑框的 Spacer、弹性 summary、timer 固定宽度、横向 fixedSize 和低字号缩放；Lock Screen 由 `ViewThatFits` 自适应并保留 summary/timer 优先级 1/2，普通字号 expanded 固定为可压缩单行并使用优先级 2/1，确保 icon、标题、时间都可见且相邻。
- compact/minimal：继续使用 Task 09 的原生、无结束边界三字段 Stopwatch；compact 使用 11pt condensed、minimal 使用 11pt compressed 系统字宽，AX 始终提供完整且逐秒更新的 `HH:MM:SS`。没有引入手写 formatter、8 小时结束日期或 stale 冻结。
- 自动测试：`AccessibilitySurfaceContractTests` + `SystemSurfaceInteractionContractTests` 最终 16/16 通过；分 surface Apple Vision ROI 门禁版 iPhone 17 Pro `LiveActivitySystemSurfaceUITests` 最终 1/1 通过，修订前 iPhone 17 Pro 与 iPhone Air 也各 1/1 通过。系统表面均额外断言唯一 identifier、完整三字段、小时数 >=8、逐秒推进和受控几何；expanded 缺失有限 frame 会直接红测，compact/Lock Screen/expanded 各自截图 ROI 缺失可见多小时时间也会由 Apple Vision OCR 直接红测。
- 自动截图：两种尺寸上的 compact、Lock Screen、expanded 共六张最终附件逐张检查；时间持续显示到 `16:01:xx`，没有全黑空框、内容消失、裁切、重叠或异常尾部间距，expanded 均保持 icon + 完整标题 + 时间同一行。
- 失败分流：Xcode 27 beta 的 `maxFieldCount: 2` 长单位输出、一次 AX IPC timeout、两次 Air 首启迁移状态与两次诊断收集卡顿均保留在上方记忆；只有截图确认的 timer 裁切/纵排/标题消失被当作产品红灯并完成修复。
- 资源清理：所有 Task29 模拟器均已关机删除；App、extension、Runner、xcodebuild、xctest 与 owned diagnose 均已退出；iPhone 17 Pro/Air 的 DerivedData、xcresult 和附件已删除。Checkpoint B 没有使用物理设备或手动窗口。
- 库：仅复用 Apple ActivityKit、WidgetKit、SwiftUI、Vision、SF 系统字体与 XCTest/XCUITest；没有新增第三方依赖。ActivityKit family proposal 与无边界 Stopwatch 比通用 UI 库更准确，Vision 则复用系统级 OCR 做截图可见性门禁。
