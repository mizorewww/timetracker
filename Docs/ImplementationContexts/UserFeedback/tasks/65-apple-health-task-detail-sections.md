# 65：Apple Health 任务详情仅保留分析内容 实现记忆

状态：2026-07-27 进行中

> 本文件是主代理与子代理的实现、验证和编排记忆；唯一任务来源仍是
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 条目。

## 认领的反馈条目

- 反馈第 110 条：Apple Health 任务在任务详情只留下摘要、任务分析和最近记录；
  其他普通任务专用内容不显示。

## 预期行为

- Apple Health 管理任务的详情直接聚焦只读分析：摘要、任务分析、最近记录。
- 隐藏普通任务专用的身份编辑、同步说明、范围选择、计时/手动时间、热力图追踪、
  数量录入和其他编辑入口。
- 普通任务详情保持现有行为；Health 数据继续只读、按需读取且不持久化原始样本。
- iPhone/iPad/macOS 由宽度与共享内容决定布局，不新增平台特判。

## Checkpoint 编排

- [~] A：审计 Task Detail 组合边界与现有测试，先写 Apple Health 精简详情验收断言。
- [ ] B：实现共享的 Health 分支并更新 UI/架构文档。
- [ ] C：完成格式、行为测试、正常字号 XCUITest 与截图检查。
- [ ] D：执行 Release 全设备安装，关闭反馈并移除活动链接。

## 库策略

- 优先复用现有 SwiftUI Task Detail 组件和 HealthKit 只读投影。
- 若外部库没有提供不可替代的成熟能力，则不增加依赖；纯信息架构裁剪不应引入
  新 UI 框架。

## 进度记录

- 2026-07-27：认领第 110 条；从 `TaskDetailContentView`、workspace 分支与
  Apple Health XCUITest 开始审计，准备以现有 fixture 对保留/隐藏区块做行为断言。
