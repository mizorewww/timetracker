# 30：主页统计图与说明层级实现记忆

> 本文件只用于主代理与子代理的实现、验证和编排记忆，不是任务来源。唯一范围与状态必须重新读取
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 条目。

## 当前阶段

- [x] 领取反馈，审计主页统计图、渐变、标题位置与全部说明文字入口。
- [x] 依据 Apple HIG、SwiftUI 规范与成熟系统组件制定信息层级和自动化验收契约。
- [~] 实现统计卡片与 info 二级菜单，补齐定向测试和完全脚本化截图验收。
- [ ] 精确执行 `CONFIGURATION=Release scripts/build_install_all.sh`，标记反馈完成并移除活动链接。

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
- [~] Checkpoint B：最小实现、定向单元/UI contract 与脚本化视觉验收。
- [ ] Checkpoint C：Release 全设备安装、签名/版本只读核验与收口。

## 资源所有权

- `task30_code_audit` 与 `task30_test_audit` 子 agent 已完成纯只读审计；未编辑、build/test、创建 simulator 或操作窗口。
- 当前无 simulator、build、TestManager 或 Instruments 批次；后续每个批次在此记录名称和 UDID，并在 checkpoint 前完成终止、关机、删除与进程核验。

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
