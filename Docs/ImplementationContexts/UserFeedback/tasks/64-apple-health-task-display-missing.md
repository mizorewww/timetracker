# 64：任务里的 Apple Health 显示消失 实现记忆

状态：2026-07-27 进行中

> 本文件是主代理与子代理的实现、验证和编排记忆；唯一任务来源仍是
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 条目。

## 认领的反馈条目

- 反馈第 109 条：任务里的 Apple Health 显示消失了。

## 预期行为

- Apple Health 管理的任务在已支持的平台和宽度下保持可发现，不因刷新、权限状态、
  空数据或 SwiftUI 投影失效而从任务体验中消失。
- macOS 不伪造 HealthKit 数据；若反馈实际涉及跨平台任务可见性，数据与平台能力状态
  应明确分离。
- 修复不得把 UI 测试数据写入正式运行的持久化存储。

## 待验证的假设

- H1：HealthKit 权限/刷新失败把已存在的 Apple Health 管理任务错误过滤掉。
- H2：Apple Health 任务仍在 store 中，但任务列表或详情的值投影没有被 Observation
  正确失效。
- H3：宽度驱动布局改造后，入口只在某个已删除的平台分支中渲染。
- H4：任务仍可见，消失的是任务详情中的 Apple Health 专属内容。

## Checkpoint 编排

- [x] A：审计 Apple Health 数据、任务持久化和任务 UI 投影；先添加可复现行为测试。
- [~] B：按测试结果修复根因，并更新当前架构/设计文档。
- [ ] C：在受影响设备上完成正常字号 UI 截图验收与回归测试。
- [ ] D：执行 Release 全设备安装，关闭反馈并移除活动链接。

## 库策略

- 先确认问题是否能由系统 HealthKit、SwiftData 与 SwiftUI Observation 正确解决。
- 若需要外部库，先核对维护状态、许可证、平台支持和 GitHub 社区规模；除用户指定外，
  一般不采用少于 1,000 stars 的小型库。

## 进度记录

- 2026-07-27：认领第 109 条，建立实现记忆，开始从 HealthKit reader、store 投影和
  任务 UI 三层定位。
- 2026-07-27 Checkpoint A：现有
  `testAppleHealthTasksStayOutOfQuickStartAndExplainSyncOnlyDetail` 在 owned
  iPhone 17 模拟器通过，证明 fixture 首次创建目录时 UI 可见。子代理审计与新增
  `existingCatalogConvergesAStaleFacadeAfterNoOpReconciliation` 共同定位到生产竞态：
  CloudKit/其他 scene 已写入完整目录时，fresh coordinator 返回 no-op，而 facade
  因空 events 未刷新，Tasks、搜索和 timeline→task 映射继续使用旧投影。新增测试在
  修复前按预期失败；完整 `make test` 其余仅保留 4 个既有基线失败。
- 2026-07-27 Checkpoint B：catalog no-op 现在调用
  `refreshStoreScopedTaskReadModels()`，只经 `refreshReadModels` 收敛
  Task/Category/Assignment、任务树和搜索，不记录第二次 mutation、不触发自动建议/
  系统表面，也不请求或持久化 Health 样本。同步更新 Architecture 与 CodeGuide。
