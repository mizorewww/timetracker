# 92：Apple Health 加载不结束实现记忆

状态：2026-07-28 进行中

> 本文件是主代理与子代理的实现、验证和编排记忆；唯一任务来源仍是
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 条目。

## 认领范围

- 复现并定位 Apple Health 增量刷新一直停留在加载态、从不成功的问题。
- 保持 Task88 已建立的 observer query、增量 anchor、本地 replica 与后台调度架构。
- 修复状态机/命令边界，不以轮询、假成功或绕过 HealthKit 权限替代。

## 验收条件

- [ ] 先建立能复现无限加载的行为测试，并定位缺失的终止状态。
- [ ] 授权、无数据、增量成功、失败、取消和不可用状态都能确定结束加载。
- [ ] 增量 anchor 与 replica durable write 仍保持事务安全，不丢失重试机会。
- [ ] 正常字号 UI/状态文案验收通过；需要时保存 Apple Health 设置/任务详情截图。
- [ ] `make test`、格式、本地化门禁通过，实现提交后完成 `make build-install-all`。

## 子代理编排

- 子代理 A：只读追踪 HealthKit refresh/observer/anchor 状态机，给出可能无法结束的路径。
- 子代理 B：只读梳理现有 Apple Health 行为测试、UI 测试和缺口。
- 主代理：复现、测试先行、最小修复、验证、截图、提交、设备安装与关闭。

## 约束

- Apple HIG：授权、不可用、空数据、失败和加载必须是用户可区分的真实状态。
- SwiftUI skill：异步任务以单一 owner 驱动，所有成功/失败/cancellation 路径都清理
  presentation state；View 不拥有 HealthKit 持久化。
- 本任务优先复用 HealthKit、Swift Concurrency 和现有 replica 服务；除非现有能力不足，
  不新增第三方依赖。

## 进度记录

- 2026-07-28：认领用户新增的无限加载 bug，建立活动实现记忆；下一步先写失败测试并
  追踪 refresh 终止路径。
