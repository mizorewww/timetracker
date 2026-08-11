# 80：直接拖拽排序与冗余排序模式清理实现记忆

Status: Complete

状态：2026-07-28 已完成

> 本文件是主代理与子代理的实现、验证和编排记忆；唯一任务来源仍是
> [`Docs/userfeedback.md`](../../../../userfeedback.md) 中对应的 `[~]` 条目。

## 认领的反馈条目

- 任务列表已经能直接拖拽排序，不应再要求用户先进入单独的“排序”模式；删除因此
  变得冗余的排序按钮与状态代码，并在适合的列表继续优先使用直接拖拽。

## 初始范围

- 审计 Tasks 主列表、分类/子任务菜单、Task Editor checklist、Inbox 及其它已有排序
  入口，确认哪些排序按钮只是切换冗余模式，哪些仍承担事务确认、macOS 或辅助操作
  所需的真实能力。
- 保留现有 command/repository 排序边界与稳定身份，只调整用户触发方式；不重写
  SwiftData 排序协议，不把拖拽写入散落到 View。
- 优先使用 SwiftUI 原生 `List`、`ForEach`、`onMove` 与平台菜单；
  不实现自定义横向手势或第三方拖拽框架。

## UI 验收清单（改动前）

- [x] iPhone 正常字号：Task checklist 与 Inbox 不显示 Sort/Done 模式按钮，直接长按
  拖动仍可用，移动后顺序持久化。
- [x] macOS 正常字号：Task checklist 不显示 Sort header，保留直接拖动，并让现有
  28 pt 上移/下移按钮常驻作为非拖拽替代。
- [x] Checklist 只允许在未完成组或已完成组内部移动；Inbox capture 与 completed
  section 不进入 open-item 移动作用域。
- [x] 独立的 Category 排序 sheet、Cancel/Done、并发 baseline、macOS Task 菜单，以及
  Quick Start 的移动入口保持不变。
- [x] Tasks 主树保持不变：它当前没有安全的同级 reorder facade，把扁平树直接接入
  `onMove` 会混合同级、父子与展开子树，属于另一个功能而不是本次冗余代码清理。
- [x] 删除冗余 UI 后，本地化 key、accessibility identifier、测试与文档同步收口。

## 测试优先清单

- [x] 用现有 command/service 行为测试确认 checklist 分组、Inbox open-item baseline、
  Category staged reorder 与持久化边界；新增 TaskEditorSession → save → fresh reload
  的直接排序回归。
- [x] 先补 UI 自动化，确认移除模式前会因 checklist Sort 按钮存在而失败。
- [x] 删除排序模式后复跑 iPhone/macOS UI 自动化，并保留和目检正常字号截图。
- [x] 完整测试、格式/本地化门禁、正常字号截图与 Release 全设备安装通过。

## Checkpoint 编排

- [x] A：完成排序入口、状态、command、测试、平台差异与依赖审计。
- [x] B：先补失败的行为/交互测试，锁定直接拖拽契约。
- [x] C：删除冗余模式并完成最小原生交互实现。
- [x] D：完成定向、全量、截图、Release 全设备安装与收口。

## 库策略

- 直接拖拽是 SwiftUI 原生能力，预计不新增依赖；若现有原生 API 足够，引入第三方
  reorder 库只会增加手势冲突、供应链与跨平台维护成本。

## 子代理编排

- 主代理负责范围、活动记忆、测试优先、集成、模拟器/设备批次、提交与收口。
- 子代理可并行完成排序 UI/状态代码审计、command/测试审计与 Apple HIG/平台交互审计；
  结论回写本文件，避免同时修改主代理正在处理的文件。

## 进度记录

- 2026-07-27：按反馈顺序认领任务并建立 `~80` 活动实现记忆，进入 Checkpoint A。
- 2026-07-27：三路只读审计确认全仓库只有 Checklist、Inbox、Category sorter 三处
  `.onMove`。Checklist 与 Inbox 的 EditMode/Sort 状态是冗余 chrome；Category sorter
  是有 staged Cancel/Done 和 stale baseline 的独立事务，不能删除；Tasks 主树没有
  可直接复用的 reorder command/facade，不扩入本任务。
- 2026-07-27：Apple 官方 `List`/`onMove` 说明支持长按后拖动；HIG 要求拖拽有合理
  替代路径。采用原生 API，不引入第三方库；macOS Checklist 上下移动按钮改为常驻。
- 2026-07-27：测试优先新增
  `testDirectReorderingSurfacesDoNotShowSortMode`。改动前 iPhone 运行真实失败于
  Checklist 的 Sort 按钮仍存在（1 test / 1 failure，
  `build/UITestResults/iOS-20260727-232723.xcresult`）。
- 2026-07-27：删除 Checklist 与 Inbox 的 Sort/EditMode 状态与按钮，保留两处
  `.onMove`、全部 command/service、Category sorter、Quick Start 移动入口；同步删除
  三语孤立 `common.sort`，并补充直接排序的持久化回归与产品/架构/测试文档。
- 2026-07-27：`TaskEditorSessionTests` 新增直接重排后经 production save、fresh
  `ModelContext` 重载仍保持顺序的回归（23/23）；Inbox coordinator 定向回归
  15/15；格式 0/842、本地化 9/9。
- 2026-07-27：XCTest 对原生 List row-lift 的两种合成长按拖动都发送了正确坐标，
  但 iOS 27 模拟器没有合成系统行抬升，故不保留会误报的手势断言。交互能力由未改动的
  Apple 原生 `.onMove`、production session/save/reload 行为测试和 UI 结构共同覆盖。
- 2026-07-27：最终 UI 用例在 iPhone 与 macOS 均通过；iPhone 分别验证 Task
  Checklist、Inbox 无 Sort 模式并截图，macOS 验证无 Sort 且上下移动按钮常显。证据：
  `build/UITestResults/iOS-20260727-235203.xcresult`、
  `build/UITestResults/macOS-20260727-235722.xcresult`；目检截图位于
  `build/UITestScreenshots/task80-ios-20260727-235203/` 与
  `build/UITestScreenshots/task80-macos-20260727-235722/`。首次 macOS 截图被历史
  WidgetRenderer Problem Reporter 遮挡，已关闭系统报告窗口并重拍干净证据。
- 2026-07-28：完整 `make test` 通过（1443 tests / 162 suites），`make format-check`
  通过（0/842），`make localization-check` 通过（9/9、主资源 1282 keys），
  `make check-hooks` 与 `git diff --check` 通过。
- 2026-07-28：实现提交 `405065d3`（1.1.283 / 338）完成 Release
  `make build-install-all`：安装到 iPad Pro M4、iPhone Air，iOS 包包含 Watch
  companion，并将签名验证通过的 macOS App 复制到 `/Applications/timetracker.app`。
