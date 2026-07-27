# 78：分析页与任务详情共用独立时间段编辑 UI 实现记忆

状态：2026-07-27 实现中

> 本文件是主代理与子代理的实现、验证和编排记忆；唯一任务来源仍是
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 条目。

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

- [~] 分析 Timeline 的历史 segment 可打开独立 editor，修改后 analytics snapshot
  刷新且写入只发生一次。
- [ ] 任务详情的历史 segment 可打开同一 editor，修改后详情统计与记录列表刷新。
- [ ] 两个入口都能删除允许删除的 segment，并保留取消、失败反馈和并发安全语义。
- [ ] 活动 timer、Apple Health 只读记录、重复/已删除 identity 不获得非法编辑入口。
- [ ] iPhone/iPad/macOS 正常字号定向 UI 测试与截图覆盖入口、修改、删除确认及返回。

## Checkpoint 编排

- [x] A：完成现状、Apple HIG、SwiftUI 数据流、现有依赖和测试覆盖审计。
- [~] B：先补 command/store 边界与 UI acceptance 测试。
- [ ] C：提取/复用独立 segment editor presentation，接入分析页与任务详情。
- [ ] D：完成全量、截图、Release 全设备安装与收口。

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
