# 88：Apple Health 事件驱动增量刷新 实现记忆

状态：2026-07-28 进行中

> 本文件是主代理与子代理的实现、验证和编排记忆；唯一任务来源仍是
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 条目。

## 认领范围

- 审计 Apple Health 刷新触发链，消除定时轮询或同一生命周期内的重复读取。
- 继续复用任务 77 已交付的独立 SwiftData replica、双 anchor 增量读取和用户 JSON
  导出，不重建数据库层。
- 保持已接受的隐私边界：Health replica 只留在本机且不进入 CloudKit；这里的同步是
  HealthKit 到本机 replica 的增量收敛。

## 验收条件

- [x] 没有计时器驱动的 HealthKit 轮询。
- [x] 首次需要数据时刷新一次；后续由明确的生命周期/用户动作或 HealthKit 变更事件触发。
- [x] 并发或短时间重复触发合并为一次增量同步，旧请求不能覆盖新结果。
- [ ] 锚点、修改、删除、失败回滚与 JSON 导出行为测试继续通过。
- [ ] 完成性能相关测试、`make test`、格式检查和全设备安装。

## 子代理编排

- 子代理 A：只读审计 HealthKit 查询触发链与潜在轮询点。
- 子代理 B：只读审计 replica/sync 行为测试与缺口。
- 子代理 C：只读审计 Apple 官方事件驱动能力和当前隐私决策边界。
- 主代理：测试、实现、集成、构建、提交和资源清理。

## 库策略

- 优先使用 Apple HealthKit anchored/observer/background-delivery API、SwiftData 和
  Swift Concurrency；不引入重复封装原生能力的第三方依赖。

## 进度记录

- 2026-07-28：认领任务，确认复用任务 77 的本地 replica 与 JSON 导出，不恢复或处理
  用户已通过 `.gitignore` 排除的范围外文件。
- 2026-07-28：checkpoint A 完成。`AppleHealthReplicaSyncService` 现在区分 dirty 与
  clean generation；普通分析/范围投影命中 clean replica 时不再查询 HealthKit，
  前台、显式刷新、授权重试和清库才使其失效。并发消费者共享同一个 anchored query，
  单个 waiter 取消不影响其余消费者，最后一个 waiter 取消仍回滚。新增 3 个行为测试；
  SyncService 7/7、ReplicaFacade 3/3、Health Task Analytics 11/11 通过。
- 2026-07-28：checkpoint B 实现完成。iOS reader 使用两个 `HKObserverQuery` 观察 workout
  与 sleep，并启用 HealthKit immediate background delivery；事件回调以保存的双 anchor
  完成一次共享增量同步，随后推进 store revision，从本机 replica 重投影视图。授权用途
  文案已如实说明本机加密只读 cache 与 JSON 导出；签名 generic iOS build 已确认同时包含
  HealthKit 和 background-delivery entitlement。待本 checkpoint 格式、本地化与回归门禁
  完成后提交。
- 2026-07-28：checkpoint B 已提交为 `962e64ad`。
- 2026-07-28：checkpoint C 实现完成。SwiftData replica 的增量 apply 改为仅查询变更/
  删除 UUID，并用 400 项 predicate chunk 避免 SQLite 参数上限；区间 snapshot 把 overlap
  条件下推给 SwiftData，不再全表 materialize 后过滤。apply/snapshot 增加原生 OS signpost。
  新的边界行为测试先证明旧实现会解码区间外损坏行，并覆盖 825 项跨 chunk 收敛；优化后
  Repository 9/9、CorePerformanceBudget 11/11 通过。
