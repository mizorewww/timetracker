# 30：主页统计图与说明层级实现记忆

> 本文件只用于主代理与子代理的实现、验证和编排记忆，不是任务来源。唯一范围与状态必须重新读取
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 条目。

## 当前阶段

- [x] 领取反馈，审计主页统计图、渐变、标题位置与全部说明文字入口。
- [x] 依据 Apple HIG、SwiftUI 规范与成熟系统组件制定信息层级和自动化验收契约。
- [x] 实现统计卡片与 info 二级菜单，补齐定向测试和完全脚本化截图验收。
- [x] 精确执行 `CONFIGURATION=Release scripts/build_install_all.sh`，标记反馈完成并移除活动链接。

## 唯一反馈边界

- 主页统计图避免滥用渐变色。
- 把统计图标题移到卡片外。
- 将说明文字改得清楚，并把主页的各类说明统一放到 info 二级菜单。
- 不领取 Apple Health、首页 heatmap/柱状图拆卡或其他后续反馈。

## 强制约束

- 完整遵循仓库本地 `apple-hig` 与 `swiftui-expert-skill` 已读取规则；优先使用 Apple SwiftUI、Swift Charts 与系统菜单/弹出层。
- 如评估第三方库，必须先核验维护质量与 GitHub stars；除用户建议外不采用少于 1k stars 的库。
- 所有交互与截图验收写成 XCTest/XCUITest；只使用有明确所有权的模拟器，不手动调整窗口，不在物理设备启动、点击或截图。
- 每个 checkpoint 只暂存本任务变更，保护 `Docs/userfeedback.md` 中其他用户新增内容。

## Checkpoint 编排

- [x] Checkpoint A：范围领取、现状/依赖/HIG 审计与自动化验收设计。
- [x] Checkpoint B：最小实现、定向单元/UI contract 与脚本化视觉验收。
- [x] Checkpoint C：Release 全设备安装、签名/版本只读核验与收口。

## 资源所有权

- `task30_code_audit` 与 `task30_test_audit` 子 agent 已完成纯只读审计；未编辑、build/test、创建 simulator 或操作窗口。
- 两个子 agent 的实施回合分别只修改四个 UI contract 文件与 `timetrackerUITests.swift`，未 commit、build/test、创建 simulator 或操作窗口；主代理已逐项复核并与产品实现合流。
- 主代理 Checkpoint B macOS contract 批次已完成：独立 DerivedData `/tmp/timetracker-task30-contracts-dd`；完整四套源码契约运行 65 项，其中本任务新增/受影响契约全部通过。完整套件暴露 4 个与本任务无关的既有陈旧断言（Quick Start 按钮旧实现形态、timeline 旧函数名与全仓调用次数），不越界修改；唯一由标题组件移动引起的概览顺序断言已同步。
- 随后用包含 Swift Testing `()` 标识符的聚焦过滤器复跑 5/5 个受影响契约，并单独复跑 Today Heatmap 6/6，全部通过。结果分别位于 `/tmp/timetracker-task30-contracts-focused.xcresult` 与 `/tmp/timetracker-task30-contracts-targeted.xcresult`；批次收尾时与原始失败结果、DerivedData 一并删除并核验无 owned 测试进程。
- 主代理 iPhone 自动化批次已完成：自有模拟器 `codex-task30-iPhone17Pro`，UDID `49F3EBDD-7506-4317-9BFA-B8B1D6397D37`；只由 XCUITest 启动、滚动、点击 Info、断言布局与截图。最终确定性复跑补上显式 demo preference reset 后，Heatmap 1/1 通过（此前三条完整主页流程 3/3 已通过），结果为 `/tmp/timetracker-task30-iphone-rerun.xcresult`；主代理已用 `view_image` 检查最新主界面与 Info sheet 截图。
- iPhone 首轮脚本完成 0/2：Heatmap 的第三张图已存在且尺寸/数据断言通过，但 hittable 滚动未保证整张图避开底栏；周统计的 header/card 修饰符未在 iPhone `Section` 可访问性树中生成可查询容器。修正为先执行既有“完全显示”滚动，并给 header/card 明确 `.contain` 语义容器。iOS 27 测试在用例结束后卡在覆盖率/日志收尾，主代理只终止自有 `xcodebuild`；首轮 result 因中断未封装完成，复跑关闭 coverage 并使用新 result bundle。
- 主代理随后修正 weekly/heatmap 祖先 accessibility identifier 覆盖、整卡滚动与 `-collect-test-diagnostics never` 收尾；最终 iPhone 聚焦批次执行 3/3 通过（主页 Overview/Quick Start/Forecast info、Weekly Gross、三张 Heatmap + 动态 `45 reps` 峰值说明），结果 `/tmp/timetracker-task30-iphone-all.xcresult`。每个测试使用 runner Documents 下独立、启动前清空的截图子目录；主代理已用 `view_image` 检查 Overview、Quick Start、Forecast、Weekly 与 Heatmap info 截图，系统 sheet、纯色柱图、标题/卡片层级与正文均通过。
- 二次聚焦 macOS 合同批次使用 `/tmp/timetracker-task30-contract-dd` 与 `/tmp/timetracker-task30-contract.xcresult`，4/4 受影响契约通过；三套 `.strings` 通过 `plutil -lint`，`git diff --check` 通过。
- 主代理 iPad 自动化批次已完成：自有模拟器 `codex-task30-iPadPro11`，UDID `97884021-98D5-4107-92DF-991F173F58CE`（iPad Pro 11-inch M5 12GB，iOS 27.0）；三条主页流程中 Overview/Quick Start/Forecast 与 Weekly（含脚本横屏）通过，Heatmap 聚焦复跑 1/1 通过。主代理已检查 popover、横屏周统计与动态 `peak 45 reps` 截图。
- macOS 全程使用 XCUITest 的 `XCUICoordinate` 自动放置窗口和目标滚动，无手动窗口操作。Weekly 1/1 与 Heatmap 1/1 最终通过，后者结果为 `/tmp/timetracker-task30-mac-heatmap-rerun.xcresult`；主代理导出并检查了系统 popover 截图。跨平台语义读取兼容 `label`/`value`，Info 列表直接由脚本滚动。
- 最终源码合同累计 6/6 通过：首轮 5 项通过，唯一失败是测试对 Swift 源码换行的过度精确匹配；改为匹配组件调用后聚焦复跑 1/1 通过。三套本地化 `plutil -lint` 与 `git diff --check` 均通过。
- 清理完成：终止本批 app/runner，关闭并删除上述两个 owned 模拟器，核验无 `codex-task30`、Booted device、owned `xcodebuild`、`xctest`、runner 或 `/tmp/timetracker-task30` 进程残留；临时 xcresult/DerivedData/截图在记录结果后删除。
- Checkpoint C 精确执行 `CONFIGURATION=Release scripts/build_install_all.sh` 成功：iOS 与 macOS Release 均构建成功，iOS 主应用、内嵌 watchOS companion 与 `/Applications/timetracker.app` 均通过签名验证，TeamIdentifier 为 `LT98S43NKA`；macOS 可执行文件为 arm64 + x86_64 Universal。版本 `1.1.61 (116)` 已只读核验，并安装到物理 iPad Pro M4 `748D0137-ADC3-58AF-855C-1E98B3125F93` 与 iPhone Air `FBA36694-D841-56D4-8ED6-21942873B21B`，两台设备查询到的已安装版本均为 `1.1.61 (116)`；未在物理设备启动、交互或截图。当前无可见物理 Apple Watch，因此脚本无法核验 embedded profile 对实体手表的覆盖范围，但内嵌 Watch app 本身签名有效；该限制如实保留且不影响本反馈交付。

## Checkpoint A 审计结论

- 唯一真实渐变是 `DailyTimeSeriesChart` 的主页 `.grossBars` 分支使用 `AppColors.grossTime.gradient`；Analytics 使用另一个 `.wallBarsAndGrossLine` 分支。最小修复是把主页柱形改为语义纯色 `AppColors.grossTime`，不波及 Analytics。Heatmap 的 `ActivityHeatmapPalette` 是同一任务色的离散透明度强度编码，不是装饰渐变，必须保留。
- 周统计标题当前在 card 模式位于 `.appCard` 外，在 iPhone 则位于原生 `Section` header；Heatmap 总标题也已在卡片外。实现补充稳定 header/card identifier，源码 contract 锁定容器关系，XCUITest 再断言 `header.frame.maxY <= card.frame.minY + 2` 且不相交。
- 应从主页常驻层移走的说明：desktop `home.subtitle`、Quick Start `quickStart.defaultHint`、周统计 footer、Heatmap section footer 与每任务动态说明。空状态中的下一步指导、图表轴/值/范围、任务身份、状态和预测结果仍属于关键上下文，继续内联。
- 信息正文不使用 SwiftUI `Menu`：Apple HIG 把 Menu 定义为命令、选项或状态入口；使用仓库现有 Forecast 范式，抽取可复用的原生 `info.circle` Button + `popover`，并在紧凑宽度交由 SwiftUI 适配为 sheet。每个相关 section header 提供自己的二级信息面，loading/loaded 状态入口一致，按钮不被 header 的 combined accessibility element 吞掉。
- 周统计说明改成可验证的具体语义：每根柱按天相加每个任务计时器的完整时长；例如两个计时器重叠 30 分钟会增加 60 分钟累计时间。Heatmap 二级面分别解释格子、计时、清单和任务量的计算；Quick Start 与 Overview 的常驻提示也进入各自二级面。
- 自动 contract：禁止主页 Gross Bar 使用 `.gradient`，要求纯色；主页统计源无 `LinearGradient`/`RadialGradient`/`AngularGradient`；要求 section info identifiers、三套本地化与常驻说明不再出现在主页 body。
- 脚本化验收复用现有 `launchApp`、`--uitesting-today-heatmap` fixture、滚动和 `capture`；改造周统计与三种 Heatmap 测试，点击 info 后验证清晰正文和 Done。矩阵为自有 iPhone 17 Pro 竖屏、iPad Pro 11 英寸竖/横屏；如需要 macOS 外观证据，只使用现成 `XCUICoordinate` 自动窗口定位，不手动操作。
- 参考：Apple Charts HIG 要求让数据最突出、说明与坐标提供清晰上下文且颜色服务于含义；Swift Charts 自带跨平台、localization 与 accessibility；Popover 适合少量临时信息且 compact 环境应适配为 sheet。官方资料：<https://developer.apple.com/design/human-interface-guidelines/charts>、<https://developer.apple.com/documentation/Charts>、<https://developer.apple.com/design/human-interface-guidelines/popovers/>、<https://developer.apple.com/design/human-interface-guidelines/menus>。
- 库：Apple SwiftUI、Swift Charts、SF Symbols 与 XCTest/XCUITest 已覆盖全部需求；没有值得引入的第三方依赖，也无需做 GitHub stars 例外。
