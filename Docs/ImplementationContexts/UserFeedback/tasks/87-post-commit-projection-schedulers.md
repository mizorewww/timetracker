# 87：提交后系统投影调度器 实现记忆

状态：2026-07-28 实现中

> 本文件是主代理与子代理的实现、验证和编排记忆；唯一任务来源仍是
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 条目。

## 认领的反馈条目

- P1：把 sync snapshot、Widget、Watch、Live Activity 从同步提交后路径移出。

## 预期行为

- durable mutation 提交后，调用方只等待当前 scene 的必要读模型收敛；同步保护快照、
  Widget、Watch 与 Live Activity 不再延长命令返回路径。
- 提交后工作保留精确 `StoreDomainEvent`，按 generation 合并重复请求；新 generation
  可以取代尚未开始的旧投影，正在执行的工作不因取消而留下“已完成”的假状态。
- sync snapshot 与三个系统表面各自记录 pending、成功或失败，不再把所有投影故障
  压入共享 `errorMessage`。
- 失败不会把已经成功的业务提交伪装为失败；可重试工作在后续提交、前台恢复或启动
  配置后继续收敛。
- App Intent、Watch 与多 scene 广播继续复用同一实际 mutation outcome；接收 scene
  只刷新读模型，不重复 snapshot、系统表面或 AI 副作用。
- 不改变 SwiftData schema、CloudKit schema、Widget/Watch wire payload 或 Live
  Activity 可见设计。

## 测试优先清单

- [x] 固定命令在系统投影被挂起时仍可完成可见读模型刷新并返回。
- [x] 固定 projection failure 不反转 durable mutation outcome，并按投影分类保留状态。
- [x] 覆盖 generation 合并、精确事件并集、重复调度去重和失败后的重试。
- [ ] 覆盖启动/前台恢复 pending work，且完成后不会重复执行旧 generation。
- [ ] 覆盖普通 scene、App Intent 与 Watch 的既有 post-commit 语义和多 scene 防循环。
- [ ] 运行聚焦测试、`make test`、性能预算、格式/本地化与签名构建。
- [ ] 运行 `make build-install-all` 并清理所有 owned 进程、设备与临时产物。

## Checkpoint 编排

- [x] A：审计现有 mutation → read model → sync snapshot/system surface 调用链，补齐
  可独立阻塞/失败的测试 seam 与性能 signpost。
- [x] B1：实现可合并的 system-surface scheduler，并把普通 scene 的 Widget、
  Watch、Live Activity 移出 mutation 调用栈。
- [~] B2：以 SwiftData persistent history 提供持久恢复，把 sync snapshot 与
  materialization/Widget I/O 移出 MainActor 交互路径。
- [ ] C：统一 App Intent 与 Watch 调用方，保留精确 outcome 与多 scene 收敛语义。
- [ ] D：更新架构、代码、测试与工程地图；完成全量验证和性能证据。
- [ ] E：全设备安装、标记 `[x]`、移除 active link并提交关闭 checkpoint。

## 库策略

- 优先评估 Swift Structured Concurrency、Foundation、SwiftData persistent history 与现有
  `DurableLocalFile` 是否足以提供 generation、coalescing、retry 和 recovery。
- 第三方依赖必须证明系统 API 或既有基础设施无法满足，审查许可证、数据访问、并发
  模型、平台支持、维护活跃度、二进制成本、供应链风险与回退方式；除用户指定外，
  一般要求 GitHub 不少于 1k stars。

## 子代理编排

- 主代理：任务认领、边界设计、实现、共享 Xcode/设备资源、提交与安装。
- 代码路径审计：列出所有同步 snapshot/Widget/Watch/Live Activity 调用点及隔离约束。
- 测试审计：提出最小行为测试、故障注入、性能和回归门禁。
- 库/官方方案调研：只用官方文档与高质量仓库，给出采用或不采用的可审计理由。

## 进度记录

- 2026-07-28：认领性能审查第 1 项，建立 `~87` 活动实现记忆；三个子代理开始并行
  只读审计，主代理完成 HIG、SwiftUI 并发/性能与项目架构/测试/隐私约束阅读。
- 2026-07-28：完成未接线的 system projection scheduler core。Widget、Watch 与 Live
  Activity 各自维护 pending/in-flight/ack/failure；四个 continuation 驱动的行为测试
  覆盖 receipt 去重、generation 合并、旧完成隔离、单 sink 失败及显式/后续提交重试。
  新增 async performance-signpost seam，并把 refresh event/plan 标为值语义 `Sendable`。
  未新增第三方依赖。
- 2026-07-28：完成普通 scene 的 system-surface checkpoint。当前 scene 只同步刷新必要
  读模型，跨 scene 广播延迟到下一次 MainActor 调度；Widget、Watch、Live Activity
  通过同一物理 store 的共享 scheduler 独立发布，使用 fresh `ModelContext` 生成纯值
  DTO，失败只留在对应 sink。已开始的副作用不取消或重放；pending/ack receipt 各自
  有界为 512，失败风暴超限安全降级为 `.fullSync`。同一持久 URL 的多个
  `ModelContainer` 共用 scheduler，错误缓存只保留字符串摘要而不间接持有 context。
  8 个 scheduler、9 个 worker、2 个 mutation boundary 与 25 个跨 scene/System
  Action 定向测试通过；随后完整 `make test` 1479 项通过。未新增第三方依赖。
  sync snapshot、persistent-history recovery、App Intent/Watch/lifecycle 入口和真正
  非 MainActor materialization 仍属于活动 checkpoint B2/C，未宣称整项完成。
- 2026-07-28：根据 B1 独立审查收紧延迟队列的内存与突发边界。共享事件批次限制器
  以事件、关联 UUID 与偏好 key 字节的饱和成本计数，超过 512 即降级为
  `.fullSync`；跨 scene 广播最多暂存 64 项，溢出后合并为一次 source-neutral
  全量追赶，并用批次交换排空取代逐项 `removeFirst()`。行为测试覆盖单个超大
  receipt、1000 次突发广播、单个超大广播，以及通知回调重入发布不递归、不丢失、
  不遗留。scheduler 9 项、mutation boundary 4 项及完整 `make test` 1482 项通过。
  未新增第三方依赖；Foundation、Swift Structured Concurrency 与现有事件模型已足够。
- 2026-07-28：完成 B2 的 persistent-history provenance 检查点。新增稳定的
  `localMutation`、`syncReconciliation`、`bootstrapMaintenance` author；普通 scene
  outer transaction 与 21 个 fresh coordinator 写入口显式标记本地写，sync restore
  在 primitive 内标记 reconciliation，四个独立启动 migration/seed 步骤在不改变其
  best-effort 事务语义的前提下标记 maintenance。author scope 在成功和抛错时都恢复
  调用方原值，内部 command/repository atomic primitive 只继承外层分类。5 个真实
  持久库/回滚行为测试及完整 `make test` 1487 项通过；测试临时 store 在 context 和
  container 释放后删除，无遗留 SQLite 句柄告警。未新增第三方依赖；采用 SwiftData
  persistent history 官方 author API。
- 2026-07-28：完成 B2 的同步快照幂等前置检查点。`recordLocalMutation` 在既有
  store/state 锁序内比较完整 postcondition；相同 snapshot 的 at-least-once 重放仍
  返回 `.recorded`，但不再推进 generation 或重写 manifest/slot。完整 state 比较保留
  pending conflict working branch 与 protected local branch 的区别，不能只看
  fingerprint。三个行为测试先证明旧实现会重复推进/写盘，再覆盖跨 service Cloud
  重放、pending conflict identity 稳定，以及关闭同步且无 recovery 时零读写。未新增
  第三方依赖；继续复用 SwiftData、Foundation 与现有 `DurableLocalFile`。
- 2026-07-28：完成 B2 的 durable lane cursor/reset-fence 前置检查点。根据 Apple
  SwiftData 官方 history API，将完整 opaque `DefaultHistoryToken` 分别持久化给 sync
  snapshot、Widget、Watch、Live Activity；cursor 支持已协调空库的 `nil` baseline、
  单调 expected-token CAS、full-reconciliation attempt lease、store/lane/format
  校验、损坏/超限隔离与原子替换。Cloud recovery reset 在 store mutation lock 内持有
  durable-root lock，先递增保留的 reset epoch，再删除 SQLite、cursor 与 attempt；
  reset 前挂起或已被新 attempt 取代的 worker 都不能回写旧 frontier；active attempt
  阻止增量确认，并允许过期 token 重建为空 baseline。注册接口不再默认 epoch 0；
  安全工厂读取当前 generation，后续 driver 必须在专用非 MainActor actor 上使用，避免
  root-lock 文件 I/O 阻塞调用 actor。17 个 cursor
  行为测试与 21 个 Cloud recovery gate 测试通过；完整 `make test` 1507 项通过，
  performance budget 全绿。未新增第三方依赖；使用 Apple 原生 SwiftData、Foundation
  和既有 `DurableLocalFile`。
- 2026-07-28：完成 B2 的 persistent-history driver 检查点。专用 actor 使用独立
  `@ModelActor` 按 256 条分页读取 chronological transaction；持久库从 Core Data
  metadata 取得真实 store UUID，并且仅在 reset epoch 前后读一致时把 UUID/epoch
  一起缓存。full reconciliation 在 effect 前固定 history tail，incremental 与 full
  都只在 effect 成功后确认 lane cursor；sync lane 只由精确 `localMutation` 触发，
  但所有 author 仍推进同一 unfiltered frontier。真实过期 token 自动转为 full，
  in-memory store 使用 driver 生命周期内的 volatile baseline。11 项真实 history
  测试覆盖真空 store、并发 tail、失败重放、独立 lane、过期恢复、内存库、MainActor
  heartbeat、256/257 分页、epoch 变化后丢弃旧注册和跨 driver 重启。实现接线时 driver 必须按一次 work
  短生命周期创建，或在 container 更新时显式替换，不能让 `@ModelActor` 强引用破坏
  现有 weak-container registry 的清理语义。未新增第三方依赖；使用 SwiftData、
  Core Data metadata、Foundation、Structured Concurrency 与既有 `DurableLocalFile`。
- 2026-07-28：在 driver 接线前补齐 persistent-history impact 映射。每笔 history
  change 的 entity name 被折叠成不携带陈旧 ID/range 的保守 `StoreDomainEvent`；
  sync lane 只合并 `localMutation` 的领域，三个系统表面合并所有 author 的领域，
  未知未来实体安全降级为 `.fullSync`。因此一次 history scan 即使跨过多个并发
  receipt，也不会用首个 receipt 的局部领域错误确认更远 frontier；当前 V14 的
  17 个实体都有显式映射。driver 聚焦测试现为 13 项。未新增第三方依赖。
- 2026-07-28：把 sync snapshot 加入现有 coalescing scheduler，成为与 Widget、
  Watch、Live Activity 对等且独立确认/失败/重试的第四条 lane。所有本地领域事件都
  进入 sync lane，三个系统表面继续按自身领域过滤；sync effect 不参与也不阻塞三表面
  共用一次 committed-fact materialization，materialization 失败只等待实际表面 lane
  都观察后释放缓存供显式重试。scheduler 9 项、worker 10 项聚焦测试通过。未新增
  第三方依赖；使用 Swift Structured Concurrency、SwiftData 与既有同步服务。
- 2026-07-28：将 store-scoped scheduler 的每条 work 接到短生命周期
  `PersistentHistoryProjectionDriver`。真实持久库首次触发为四 lane 建立 full
  baseline，之后无新 transaction 不再重复 effect；本地 author 驱动四 lane，远端
  reconciliation 只驱动三个系统表面但仍推进 sync cursor；单 lane 失败不确认自身
  frontier，siblings 独立推进，显式 retry 只重放失败 lane；registry 重建后复用 durable
  cursor。driver 不被 registry 长期持有，继续保持 weak-container 清理语义；effect
  前后以 container revision fence 拒绝替换期间的陈旧确认；同 store URL 双容器竞态
  验证被替换且阻塞中的四条旧 lane 均不能确认 generation/frontier，retry 改由新容器
  完成。5 项真实 SQLite 集成测试通过；该检查点的隔离 worktree 全量门禁为
  1525/1525。未新增第三方依赖；复用 SwiftData persistent history、Structured
  Concurrency 与既有 `DurableLocalFile`。
- 2026-07-28：完成 sync snapshot 后台 worker 检查点。专用 actor 在 store
  mutation lock 内创建 fresh `ModelContext`，再进入既有 state lock 捕获与持久化
  snapshot；每次持久写入前后都重新读取实时同步策略，策略在锁等待、写入前或 durable
  write 期间变化时均拒绝确认 history，后续重放依靠完整 postcondition 幂等收敛。
  Cloud reconciliation reset 先写 queued intent 再写 pending upload，state mirror
  也在同一 state lock 内推导，避免把 torn state 误判为显式 replace。关闭同步且无
  recovery 时保持零 store/sidecar 读取，reset hook 延迟期间仍不阻塞 MainActor。
  9 个 worker、3 个 replay 聚焦测试通过；隔离 worktree 完整 `make test` 为
  1535/1535。未新增第三方依赖；复用 SwiftData、Foundation、Structured
  Concurrency 与现有 `DurableLocalFile`。
