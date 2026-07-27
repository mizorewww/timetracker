# 65：Apple Health 任务详情仅保留分析内容 实现记忆

状态：2026-07-27 已完成

> 本文件是主代理与子代理的实现、验证和编排记忆；唯一任务来源仍是
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 条目。

## 认领的反馈条目

- Apple Health 管理任务的详情只保留摘要、任务分析和最近记录。

## 预期行为

- Apple Health 管理任务的详情直接聚焦只读分析：摘要、任务分析、最近记录。
- 时间范围和历史周期控件收进“任务分析”区块，不再独占第四个区块。
- 隐藏普通任务专用的身份编辑、同步说明、计时/手动时间、热力图追踪、
  数量录入和其他编辑入口。
- 普通任务详情保持现有行为；Health 数据继续只读、按需读取且不持久化原始样本。
- iPhone、iPad 和 macOS 共享同一语义分支，不新增平台特判。

## UI 验收清单

- Apple Health 有数据时，列表只有“摘要 → 任务分析 → 最近记录”三个内容区块。
- “任务分析”内仍可切换日/周/月、前后移动周期并回到今天；区间标题仍可见。
- Apple Health 详情不存在 `task.detail.identity`、`task.detail.trackingUnavailable`、
  数量记录、热力图追踪、任务编辑器与预测区块。
- Apple Health 加载、空、失败、不可用状态不回退显示普通任务内容；重试仍为原生按钮。
- 普通任务保留身份、可用性、编辑、预测、分析和最近记录的既有组成。
- iPhone、iPad 与 macOS 普通字号截图中，三个区块顺序一致，内容不被系统栏遮挡。

## Checkpoint 编排

- [x] A：审计 Task Detail 组合边界与现有测试，先写 Apple Health 精简详情验收断言。
- [x] B：实现共享的 Health 分支并更新 UI/架构文档。
- [x] C：完成格式、行为测试、正常字号 XCUITest 与截图检查。
- [x] D：执行 Release 全设备安装，关闭反馈并移除活动链接。

## 子 Agent 分工

- 代码审计：定位 Apple Health 详情的组合边界、现有保护逻辑和最小改动面。
- 测试审计：定位可复用的 fixture、UI contract/XCUITest 与截图入口。
- 设计审计：核对三个保留区块的顺序、普通任务回归面与跨宽度验收点。

## 库策略

- 优先复用现有 SwiftUI Task Detail 组件和 HealthKit 只读投影。
- 本任务是信息架构裁剪；若成熟外部库没有提供不可替代能力，则不增加依赖。

## 进度记录

- 2026-07-27：重新认领并恢复任务记忆；开始读取约束文档和并行静态审计。
- 2026-07-27：完成 UI 验收清单；决定把既有时间范围控件并入“任务分析”，保留分析能力同时消除额外区块。
- 2026-07-27：三个只读子审计一致定位 List composition、More/Archive 与 recovery 泄露；完成 canonical Health 专用组合、分析内周期控件、内联状态和普通任务回归断言。
- 2026-07-27：`make format` 无改写；首轮 `make test` 完成 1419 个测试，Apple Health 相关全绿，但 3 个非本任务用例失败，待最终闸门重跑确认。
- 2026-07-27：iPhone 17 Pro analytics-only XCUITest 通过；逐一扫描 21 个 lazy List 视口后验证三段顺序与分析内周期控件。证据：`build/UITestResults/iOS-20260727-122244.xcresult`。
- 2026-07-27：iPad Pro 13-inch (M5) 周/月/历史周期与横竖屏 XCUITest 通过并人工检查 5 张截图；macOS HealthKit unavailable 状态测试及深色截图通过。证据：`build/UITestResults/iOS-20260727-122654.xcresult`、`build/UITestResults/macOS-20260727-123329.xcresult`。
- 2026-07-27：截图符合 HIG 的原生 List/Section 层级、普通字号无截断，未见编辑/More/Archive；本任务不新增第三方依赖，复用 SwiftUI、Apple Charts 与现有 HealthKit 投影。
- 2026-07-27：修复默认门禁暴露的两个独立确定性缺陷（HTTP 非成功状态优先级、首次归档时间戳）并纠正一条已被任务 44 取代的 checklist 旧断言，checkpoint `b73f9f9d`；三个聚焦套件全绿，随后完整 `make test` 以 1419/1419 通过。
- 2026-07-27：`make build-install-all` 全绿；Release 1.1.229 (284) 已安装到 iPad Pro M4 与 iPhone Air，macOS App 已复制到 `/Applications`。iOS 主应用、嵌入 Watch companion 与 macOS App 版本一致，Apple Development 签名、Team `LT98S43NKA` 和 `codesign --deep --strict` 通过；无可见实体 Apple Watch，因此手表实际安装未验证。
- 2026-07-27：唯一反馈条目由主代理标记 `[x]`，活动链接已移除。
