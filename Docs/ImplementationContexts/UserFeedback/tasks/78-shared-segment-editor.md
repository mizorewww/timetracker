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

- [ ] 分析 Timeline 的历史 segment 可打开独立 editor，修改后 analytics snapshot
  刷新且写入只发生一次。
- [ ] 任务详情的历史 segment 可打开同一 editor，修改后详情统计与记录列表刷新。
- [ ] 两个入口都能删除允许删除的 segment，并保留取消、失败反馈和并发安全语义。
- [ ] 活动 timer、Apple Health 只读记录、重复/已删除 identity 不获得非法编辑入口。
- [ ] iPhone/iPad/macOS 正常字号定向 UI 测试与截图覆盖入口、修改、删除确认及返回。

## Checkpoint 编排

- [~] A：完成现状、Apple HIG、SwiftUI 数据流、现有依赖和测试覆盖审计。
- [ ] B：先补 command/store 边界与 UI acceptance 测试。
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

## 进度记录

- 2026-07-27：认领任务并建立 `~78` 活动实现记忆。
