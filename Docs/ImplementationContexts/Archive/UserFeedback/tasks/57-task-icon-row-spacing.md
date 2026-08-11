# 57：任务详情图标行右侧间距实现记忆

Status: Complete

> 本文件是主代理与子代理的实现、验证和编排记忆。任务内容与状态的唯一来源仍是
> [`Docs/userfeedback.md`](../../../../userfeedback.md) 中对应的 `[~]` 条目。

## 当前阶段

- [x] 按文档顺序领取“任务详情图标右侧有奇怪空间”反馈。
- [x] 审计任务详情图标入口的布局 owner、导航行为、平台差异与历史边界。
- [x] 先写普通字号 UI 验收清单和失败证据。
- [x] 做最小实现并补充稳定的自动化几何/交互断言。
- [x] 运行格式、本地化、单元测试和受影响 iPhone/iPad 截图验收；macOS 产品分支未变，
  签名构建成功，UI 启动因主机会话锁屏而无法取得新截图。
- [x] 提交小 checkpoint，执行 Release 全设备安装，标记反馈完成并移除活动链接。

## 唯一范围

- 修正任务详情中可点击图标入口右侧的异常空白，让图标、标题/提示和系统 disclosure
  行为符合当前 Form/List 的平台布局。
- 保留点击图标进入图标编辑页面的既有功能、标识、草稿状态和自动保存语义。
- 不顺带领取 Analytics 闪烁、AI、Release 测试数据或 Apple Health 后续反馈。

## 强制约束

- 主代理完整遵循仓库本地 `apple-hig` 和 `swiftui-expert-skill`。
- 优先使用 SwiftUI 原生 `NavigationLink`、`LabeledContent`、Form/List row 与系统间距；
  系统组件能覆盖时不自绘 disclosure，也不引入第三方 UI 库。
- UI 变更先建立普通字号验收清单；完成后用脚本化 XCUITest 和截图覆盖
  iPhone、iPad、macOS。
- 每个模拟器登记名称和 UDID，结束后终止 App/Runner、关机并删除。
- `Docs/userfeedback.md` 中用户并行新增或重新打开的其他条目不纳入本任务提交。

## Checkpoint 编排

- [x] Checkpoint A：领取、现状/历史/测试审计、验收契约。
- [x] Checkpoint B：测试先行、最小布局修正和文档更新。
- [x] Checkpoint C：跨平台截图、完整门禁、Release 全设备安装和反馈收口。

## 资源所有权

- Red 批次：主代理，`codex-task57-red-iPhone17Pro`
  (`D72C1448-EAC7-4418-9721-912973075C9E`，本任务创建)，App
  `me.mezorewww.timetracker`、UI runner，产物根目录
  `/private/tmp/codex-task57-red.9wApfU`；完成失败证据后必须终止、关机、删除并审计。
- Final UI 批次：主代理继续持有上述 iPhone，并创建
  `codex-task57-final-iPadPro13`
  (`E2A634BE-6078-45C3-A599-5652AFF247A1`)；App 实际 bundle
  `me.mezorewww.timetracker`、UI runner，产物根目录
  `/private/tmp/codex-task57-final.RiE6Ge`。macOS 使用本机测试目标，不打开 Simulator。
- [x] 两台自建模拟器均已终止 App/runner、shutdown、delete；审计无 task57 simulator、
  Booted device、owned `xcodebuild`/XCTest runner 或 App 进程残留。临时结果目录保留到
  Release 收口记录完成后删除。

## 审计结论

- 布局 owner 是 `TaskDetailIdentityRow.identitySummary`：44pt `TaskIcon` 与标题区本应由
  外层 `HStack(spacing: 14)` 控制。
- 回归由提交 `36d697b6` 引入：当时把固定尺寸图标包进 iOS `NavigationLink`。它位于
  `List`/`Form` 中，因此系统自动显示 disclosure indicator 并为附件保留宽度。
- Xcode 27 SwiftUI SDK 提供的原生
  `.navigationLinkIndicatorVisibility(.hidden)`（iOS 17/macOS 14 起可用）可在保留
  `NavigationLink` push 与命中语义的同时精确移除 indicator 及其占位；它比改变
  `buttonStyle` 的装饰/高亮语义更直接、更稳定。
- macOS 分支本来就是 plain `Button` + popover；修复只应在详情页 iOS 调用点隐藏
  indicator，不全局影响仍需要标准 disclosure 的共享 Form 行，也不改导航目的地、
  草稿绑定、自动保存或 macOS 呈现方式。
- 现有 XCUITest 只验证进入选择器并截取进入后的页面，未保存详情行修复前截图，也未
  约束图标点击元素的宽度和图标到标题的可见间距。

## UI 验收清单

- [x] 图标入口在普通字号下保持约 44pt 的原生最小点击尺寸，不再横向膨胀。
- [x] 图标入口右边缘到标题输入框左边缘保持设计系统 14pt 间距（自动化容差 10...18pt）。
- [x] 点击图标仍进入图标编辑页面，保留现有 push/popover 平台语义。
- [x] iPhone compact-width 与 iPad regular-width 均不出现双 disclosure、截断或
  不对称 padding。
- [x] 保留既有 accessibility identifier/label、键盘/指针行为和任务详情草稿语义。

## 测试先行契约

- 扩充 `testTaskDetailIconOpensSymbolColorPicker`，先等待标题输入框并截取详情 identity
  行，再断言图标入口宽度保持 42...48pt、图标与标题间距在 10...18pt，最后继续验证进入
  共享图标选择器。
- 修复前 iOS 运行必须以几何断言失败并留下截图；修复后三平台复用同一交互测试。

## Red 证据

- iPhone 17 Pro 普通字号聚焦 XCUITest 按预期失败：44pt 可见图标外层的
  `task.detail.icon.edit` 实际 frame 为
  `(x: 32, y: 170, width: 125.67, height: 44)`，标题 field 从 `x: 174` 开始。
- 修复前截图 `iphone-task-detail-icon-row` 清楚显示系统 chevron 位于图标与标题之间；
  这证明 81.67pt 的额外宽度属于默认 `NavigationLink` indicator/附件槽，而不是外层
  14pt `HStack` 间距。
- 结果包：
  `/private/tmp/codex-task57-red.9wApfU/task57-red.xcresult`。

## iPhone Green 证据

- 仅在详情页 iOS 调用点加入
  `.navigationLinkIndicatorVisibility(.hidden)`；共享 Form 行保持系统 disclosure，
  macOS plain Button + popover 不变。
- 同一 iPhone 17 Pro 聚焦 XCUITest 通过：图标 frame 落入 42...48pt，图标到标题间距
  落入 10...18pt，点击后仍出现 `symbol.picker.view` 与搜索框。
- `iphone-task-detail-icon-row` 截图确认 chevron 与异常附件槽消失，标题从图标后的正常
  间距开始；`iphone-task-detail-icon-editor` 确认 push 目的地不变。
- 结果包：
  `/private/tmp/codex-task57-red.9wApfU/task57-green-iphone.xcresult`。
- 最终 checkpoint 源状态复跑
  `/private/tmp/codex-task57-red.9wApfU/task57-checkpoint-iphone.xcresult` 仍为
  1 test / 0 failures；`make format-check` 与 `make localization-check` 通过。

## Final UI / 单元门禁

- iPad Pro 13-inch M5：
  `/private/tmp/codex-task57-final.RiE6Ge/task57-final-ipad.xcresult`，
  1 test / 0 failures；`ipad-task-detail-icon-row` 与 picker 截图人工检查通过。
- macOS：同一聚焦 XCUITest 先完成 Apple Development 签名产品与测试宿主构建；启动
  阶段因当前控制台处于锁屏登录界面，应用状态停留 `Running Background`，未进入产品
  断言。录像确认是锁屏环境阻塞，不是 App 崩溃或布局失败。本次唯一产品 modifier 在
  `#if os(iOS)` 内，macOS plain Button + popover 分支未变化。
- `make test`：1433 tests / 1431 pass / 2 fail。失败仍是上个任务已记录且与本任务无关的
  `PreferenceSyncBehaviorTests.checklistCompletionMovesOnlyTheTargetToTheDestinationGroupEnd`
  和
  `TaskPersistencePolicyTests.archiveCommandPreservesTheOriginalArchiveTimestamp`；
  本任务不修改偏好同步、清单排序、归档命令或时间戳。
- 新增库：无。实现只使用 SwiftUI 原生
  `navigationLinkIndicatorVisibility` 与项目既有 DesignSystem/XCTest。

## Release 全设备门禁

- `CONFIGURATION=Release make build-install-all` 成功；Apple Development 自动签名保持
  开启，iOS/iPadOS 产品包含 Watch companion
  `me.mezorewww.timetracker.watchkitapp`，macOS 产品签名深度校验通过。
- Time Tracker 1.1.174 (229) 已安装到 iPad Pro M4
  (`748D0137-ADC3-58AF-855C-1E98B3125F93`)、iPhone Air
  (`FBA36694-D841-56D4-8ED6-21942873B21B`) 与
  `/Applications/timetracker.app`；设备安装后查询和 macOS Info.plist 均返回完全一致的
  版本号。
- iPad 实机启动成功。iPhone 安装与版本查询成功，但启动请求被 SpringBoard 以设备锁屏
  拒绝；错误明确为 `Unable to launch ... because the device ... could not be unlocked`，
  不是产品崩溃或签名失败。
- 收口提交会由版本 hook 前进版本号；提交后再执行一次增量 Release 全设备安装，使实体
  设备和 `/Applications` 与最终收口提交一致。

## 库策略

- 首选 Apple SwiftUI 与项目现有 DesignSystem；目前没有引入第三方库的理由。
- 若审计发现系统组件无法覆盖，再先核查候选库的维护状态、许可证、近期发布和至少
  1k GitHub stars。
