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
