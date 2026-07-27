# 77：Apple Health 独立只读数据库与 JSON 导出 实现记忆

状态：2026-07-27 实现中

> 本文件是主代理与子代理的实现、验证和编排记忆；唯一任务来源仍是
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 条目。

## 认领的反馈条目

- App 为 Apple Health 运动/睡眠时间线维护独立数据库；用户不能在 App 内修改
  Health 事实；Settings JSON 导出包含该数据库。

## 合规范围裁决

- Apple App Review Guideline 5.1.3(ii) 当前明确禁止在 iCloud 存储个人健康信息。
  因此独立 Health replica 必须是 device-local、CloudKit-disabled 的 SwiftData
  store；“同步”定义为从本机 HealthKit 增量刷新并收敛删除/修改，不是上传到
  CloudKit。
- JSON 导出是用户明确发起的本地文件操作，可以包含独立 replica，但必须在文案和
  隐私文档中明确它含敏感健康时间范围/类型/来源信息，不是可恢复备份。
- App 继续只申请 HealthKit 读取权限，不提供 Health 记录的新增、编辑、删除、
  archive、timer、manual-time 或 AI 入口。

## 预期架构

- 新建版本化 `HealthReplicaSchemaV1`、migration plan 和独立
  `ModelConfiguration`，不修改主业务 schema V14，不把 Health sample model
  注册进主 CloudKit container。
- `HealthReplicaRepository` 是唯一 SwiftData owner；`HealthReplicaSyncService`
  接收独立 anchored-change reader 的结果并在一次 store transaction 内按稳定
  sample identity upsert、应用 HealthKit 明确给出的删除对象，并且只在记录提交成功
  后推进 workout/sleep 两个 opaque anchor。
- 持久字段按最小化原则只包含稳定 sample UUID、kind/workout activity、
  start/end、source bundle、sleep stage 与 replica metadata；不保存用户可编辑
  标题、备注、任务关系、设备名或 HealthKit 原对象。
- UI/Analytics 只消费只读 value snapshot，不持有 replica `PersistentModel`；
  现有 Health timeline projection 迁移到 repository/service 边界，macOS 无
  HealthKit 时读取本机 replica 但不伪造可刷新能力。
- 不修改 `SyncDataSnapshot`、Cloud conflict fingerprint/merge/restore 或
  `TimeTrackerModelRegistry`；新增版本化的 user-export envelope，组合已有过滤后的
  business snapshot 与独立 Health payload。合法空库明确导出空数组，任一 store
  读取或编码失败时整体 fail closed，不打开文件导出器。
- 两个 SwiftData store 不能宣称一个跨库 ACID transaction；导出按固定顺序捕获两个
  独立只读快照，并在文档中称为用户主动导出，不称为可恢复备份。

## 测试优先清单

- [x] 新独立 store 与主 store/CloudKit configuration 物理隔离；unit/UI test
  永远使用内存或显式隔离 URL。
- [x] 第一次同步、幂等重放、HealthKit 修改、撤销授权/查询失败、取消、记录删除与
  anchor 原子推进/回滚。
- [x] 任意 UI/command 不能修改 Health replica；只读投影与现有时间线/分析语义一致。
- [x] JSON 导出包含确定性 Health records，空/损坏/不可用 replica 有明确结果，
  且敏感字段与主快照边界符合文档。
- [x] 新 Health schema V1 的磁盘重开与 current compatibility fixture；首版不虚构
  V0 migration。
- [ ] 正常字号 iPhone/iPad/macOS Settings/Health timeline 定向截图；真机 HealthKit
  同步与 Release 安装是最终 gate。

## Checkpoint 编排

- [x] A：完成现状、Apple 合规、schema/container、导出和测试边界审计。
- [x] B：先写独立 store/schema/repository/sync/export 的失败行为测试。
- [x] C：分层实现本地 replica、只读投影和 JSON 导出，更新当前工程文档。
- [ ] D：完成全量/真机验证、Release 全设备安装与收口。

## 库策略

- 持久化、迁移、Health 读取和导出优先使用 Apple SwiftData、HealthKit 与
  Codable/FileDocument；不引入数据库 wrapper、同步 SDK 或 JSON framework。
- 只有原生组件无法满足经过测试的明确边界时才评估维护活跃且一般不少于 1k stars
  的第三方依赖；任何新 SDK 必须审计许可证、隐私清单、数据出站和可删除性。

## 子代理编排

- 主代理负责范围裁决、模型/容器边界、集成、构建/真机所有权和提交。
- 静态现状/schema 审计、导出/隐私审计和测试覆盖审计可由子代理并行完成；结论必须
  回写本文件，子代理不得同时修改主代理正在编辑的 Swift 文件。

## 进度记录

- 2026-07-27：认领任务并建立 `~77` 活动实现记忆。
- 2026-07-27：复核 Apple 官方文档；排除 Health 数据进入 CloudKit，采用独立
  device-local replica + HealthKit 增量同步 + 用户主动 JSON 导出。
- 2026-07-27：完成代码、Settings/隐私与测试审计。确定新增窄
  `AppleHealthReplicaChangeReading`，保留既有范围读取协议；HealthKit 通过
  `HKAnchoredObjectQueryDescriptor` 和可安全归档的 `HKQueryAnchor` 提供增量、
  修改与删除事件。确定独立 schema/repository/sync fixture 和 user-export v2
  行为测试顺序，禁止把 Health 并入主 V14 或 `SyncDataSnapshot`。
- 2026-07-27：完成 schema/repository 第一层：V1 workout/sleep/checkpoint 模型、
  CloudKit-disabled 独立容器、备份排除与 iOS Data Protection、唯一 SwiftData
  repository、只读值快照、幂等 upsert/修改/明确删除/双 anchor 同事务提交和
  clear。磁盘重开可继续读写；`make test` 1428 tests / 160 suites 通过。
- 2026-07-27：完成 anchored sync 第二层：workout/sleep 独立分页读取
  `HKAnchoredObjectQueryDescriptor`，安全归档 `HKQueryAnchor`，显式收敛
  `HKDeletedObject`，且只有两条 HealthKit 流均成功后才原子提交记录与双 anchor。
  查询失败、取消和过期请求均不产生半代数据；`make test` 1431 tests / 161 suites
  与签名 iOS generic-device build 均通过。
- 2026-07-27：完成只读消费接线：shipping App 共享一个 app-scoped persistent
  repository，unit/UI test 每个 store 使用独立内存容器；时间线和 Health 任务统计
  在授权后先 anchored refresh，再从 replica 的 interval snapshot 投影，旧的窄范围
  reader fake 仍可回退兼容。隐藏时间线不清库；Clear All 明确清除 records 与 anchors。
  `make test` 1433 tests / 162 suites 与签名 iOS generic-device build 均通过。
- 2026-07-27：完成 Settings 用户 JSON 导出 envelope
  `timetracker.userData` V1：分离 `businessData` 与版本化 `appleHealth`，确定性导出
  workout/sleep UUID、类型/阶段、时间范围与来源，以及 replica 最后成功同步时间；
  opaque anchors 永不出站。合法空库编码显式空数组，任一副本读取错误使整个导出
  fail closed；原 Cloud 恢复快照格式与路径保持不变。`make test` 1435 tests /
  162 suites 通过。
- 2026-07-27：完成用户可见边界与 UI fixture 收口：三语 Settings/Health 详情明确
  本机只读、不经 iCloud、JSON 含敏感健康字段；默认文件名改为
  `time-tracker-user-data.json`。UI fixture 现在实现 anchored change reader，所有
  iOS Health 截图先写隔离内存 replica 再读取；现有 failure/empty/retry/reactivation
  语义保留。当前 Architecture、CodeGuide、ProjectMap、PrivacyAndSecurity、
  Testing、UserGuide 与 UI-Design 已更新。`make test` 1434 tests / 162 suites、
  localization parity 与签名 generic iOS build 通过。
