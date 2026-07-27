# 78：分析页与任务详情共用独立时间段编辑 UI 实现记忆

状态：2026-07-27 已完成

> 本文件是主代理与子代理的实现、验证和编排记忆；唯一任务来源仍是
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[x]` 条目。

## 认领的反馈条目

- 分析页面与任务详情必须能从历史时间段进入编辑，支持修改和删除。
- 时间段编辑应是独立、可复用的 UI，而不是把主页的整块 Timeline 视图复制到其他
  页面。

## 初始范围

- 先审计主页既有 `SegmentEditorSheet`、Timeline row actions、分析页 Timeline 和任务
  详情记录列表的读写边界，确认可复用入口与缺失行为。
- 复用同一个 editor presentation model、validation 与 command 边界；页面只负责
  选中稳定 segment identity、呈现 editor，并在成功后刷新自己的只读 snapshot。
- 修改与删除必须继续通过既有 Commands/Store facade，不让 SwiftUI View 直接写
  SwiftData；活动 timer 与已完成 segment 的能力差异维持现有业务规则。
- 本任务不顺带重做分析图表、Timeline 排版或任务详情信息架构。

## 测试优先清单

- [x] `.trackedSegment` 可按精确、带命名空间的身份解析 canonical editor draft；
  Apple Health、newer tombstone 与 busy presentation 均不会误开或替换 sheet。
- [x] 分析 Timeline 的历史 segment 可打开独立 editor，修改后 analytics snapshot
  刷新且写入只发生一次。
- [x] 任务详情的历史 segment 可打开同一 editor，修改后详情统计与记录列表刷新。
- [x] 两个入口都复用可删除 segment 的共享 editor，并保留取消、失败反馈和并发安全语义。
- [x] 活动 timer 保留既有规则；Apple Health 只读记录、重复/已删除 identity 不获得非法
  编辑入口。
- [x] iPhone/iPad 正常字号定向 UI 测试与截图已覆盖入口、修改、删除确认及返回；macOS
  signed build 通过，XCUITest 被系统 `WidgetRenderer_Activities` crash reporter 抢焦点
  阻断，保留 xcresult 作为该平台 inconclusive 证据。

## Checkpoint 编排

- [x] A：完成现状、Apple HIG、SwiftUI 数据流、现有依赖和测试覆盖审计。
- [x] B：先补 command/store 边界测试，锁定 canonical identity 与 presentation 语义。
- [x] C：复用独立 segment editor presentation，接入分析页与任务详情并补 UI
  acceptance 测试。
- [x] D：完成全量、截图、Release 全设备安装与收口。

## 库策略

- 优先复用项目已有 `SegmentEditorSheet`、SwiftUI sheet/confirmationDialog/swipeActions
  与既有 Commands；先查 Apple 官方文档和当前仓库锁定依赖，避免引入第二套表单、
  路由或状态管理框架。
- 只有现有原生/仓库组件无法满足明确行为测试时才评估第三方库；新增依赖需维护活跃、
  许可证与隐私边界合格，且一般不少于 1k GitHub stars。

## 子代理编排

- 主代理负责范围、活动任务记忆、写入边界、集成、构建与提交。
- 可并行委派现有入口/命令审计、Apple HIG 交互审计与测试缺口审计；结论回写本文件，
  子代理不同时编辑主代理正在修改的 Swift 文件。

## Checkpoint A 审计结论

### 现有实现

- 独立编辑 UI 已存在于 `Features/Ledger/SegmentEditorSheet.swift` 与
  `SegmentEditorViews.swift`。它完整拥有 draft、Form、Cancel/Save、删除确认、
  stale reload、失败反馈、iOS large-only detent 与 macOS sheet frame；不需要复制
  Home Timeline，也不需要把它和 Manual Time 合并成另一套表单。
- Home 的既有链路是 `TimelineRow` → scene-owned `AppPresentationRouter` →
  `AppPresentation.Content.segmentEditor` → 单一 `AppPresentationHost.sheet(item:)` →
  `SegmentEditorSheet`。Analytics 与 Task Detail 应只把精确记录身份接入这条链。
- Analytics `TimelineLegendRow` 和 Task Detail `TaskRecentRecordPoint` 都已经持有
  `TimelineEntryID`，但当前行是静态 presentation。`TimelineEntryID` 是带命名空间的
  enum；必须只接受 `.trackedSegment(id)`，绝不能抽出裸 UUID 后把 Apple Health
  workout/sleep 误当成 ledger segment。
- 保存/删除后的 store-scoped command 已负责 fresh context、baseline CAS、原子提交、
  ledger/rollup/analytics refresh 与 `analyticsRevision` 推进。页面不得手工修改缓存
  snapshot，也不得重新持有 SwiftData `TimeSegment`。

### 设计决定

- 两个历史记录入口使用原生 `Button(.plain)` 包装完整 tracked row，并在尾部显示
  `pencil` 编辑提示；整行是直接、可发现且可键盘/辅助技术激活的入口。Apple Health
  行保持完全静态，不显示 disabled Edit/More。
- 点击时只把稳定 `TimelineEntryID` 交给 router；router 从当前 canonical、未删除
  winner 生成 draft。找不到、关系不完整或 presentation slot 忙时不打开空 editor，
  也不替换当前 sheet。
- 修改和删除统一在独立 editor 内完成，不在 Analytics/Task Detail 复制 Home 的
  Menu、直接删除 confirmation owner 或 repository 写入。成功以 sheet 关闭及页面
  自动刷新作为反馈；失败保留 editor 与 draft。
- HIG 基线：iOS/iPadOS 入口至少 44×44 pt，macOS 使用原生控件语义；单页 sheet 保持
  Cancel leading / Save trailing，完整表单继续 large-only；删除继续使用 destructive
  role、明确影响说明和 Cancel。

### 测试审计

- 既有 command/Pomodoro 测试已覆盖 stale active、stale delete、missing target、
  exclusive admission、active Pomodoro rebind/close/delete、finished 不可 reopen、
  session bounds 与 edit 保存失败回滚；不重复复制这些夹具。
- 新增行为测试集中于：
  1. `.trackedSegment` 精确解析当前 canonical draft；
  2. 相同裸 UUID 的 workout/sleep 仍只读；
  3. missing/deleted/duplicate loser 不开 sheet，busy router 不替换当前 sheet；
  4. 普通历史 edit/delete 只作用一次并驱动 Analytics 与 Task Detail read model 刷新；
  5. Cancel 零写入，失败不 dismiss。
- 新增正常字号 XCUITest 使用稳定 namespaced identifier，覆盖 Analytics 与 Task Detail
  打开同一 `segmentEditor.view`、保存/删除后的 exact row 更新，以及 Health 行没有
  mutation action。iPhone、iPad、macOS 各留关键截图。

### 依赖与官方参考

- 锁定依赖中的 Markdown、代码高亮、颜色选择、LRU 与 collections 库均与本功能无关；
  不新增第三方路由、状态或表单库。
- 采用 Apple 官方 SwiftUI `Button`、`sheet(item:)`、`Form` 与
  `confirmationDialog`。官方文档确认 item-driven sheet 以可选 `Identifiable` 数据
  作为单一 source of truth，`Button` 会保留可访问动作语义；HIG 将 sheet 定义为紧邻
  当前上下文的短任务，并要求 iOS/iPadOS 单页 sheet 的 Cancel/完成动作位于两侧。

## 进度记录

- 2026-07-27：认领任务并建立 `~78` 活动实现记忆。
- 2026-07-27：完成主代理与三个只读子代理的代码、HIG/SwiftUI、测试覆盖审计；确认
  复用现有 editor 与 command 边界，不引入新依赖，Checkpoint B 转入测试先行。
- 2026-07-27：新增 router/store identity 边界测试并确认先红后绿；共享入口现在只接收
  `.trackedSegment`，从当前 canonical 可见记录生成 draft，Health 同 UUID、newer
  tombstone 与 busy router 均被安全拒绝。定向 17 tests 通过，Checkpoint B 完成。
- 2026-07-27：Analytics 与普通 Task Detail 的 tracked 历史行接入 scene-owned
  `AppPresentationRouter` 和现有 `SegmentEditorSheet`；整行 plain button + pencil，
  Health 行保持静态。保存/删除后复用 command/revision 自动刷新，不新增第三方依赖。
- 2026-07-27：新增 Analytics 删除、Task Detail 保存和 Health 只读 XCUITest。iPhone
  Analytics/Task Detail、iPad Analytics 与 iPhone Health 用例通过并完成视觉验收；
  `make build-macos` 通过。macOS XCUITest 多次被 Xcode 27 beta 环境的
  `WidgetRenderer_Activities quit unexpectedly` 系统弹窗抢焦点，失败证据保存在
  `build/UITestResults/macOS-20260727-220627.xcresult` 等 bundle；未把环境规避逻辑
  留进产品或测试代码。
- 2026-07-27：完整 `make test` 首轮只暴露一条遗留源码字符串扫描误报；按仓库测试
  规则将它替换为 `HourTaskActivityService` 的任务身份、颜色和时长分桶行为测试。
  最终 `make test` 通过 1438 tests / 162 suites。
- 2026-07-27：实现提交 `f9f80be2` 后运行 `make build-install-all` 成功；Release App
  已安装到实体 iPhone Air，内嵌 Watch companion 的签名与 designated requirement
  通过，macOS App 已复制并验签到 `/Applications/timetracker.app`。运行时没有可直接
  枚举的实体 Apple Watch，配对手表由 iPhone Watch App 的 Automatic App Install
  接管 companion 安装。反馈条目与子条目均标记完成，并移除 `~78` 活动链接。
