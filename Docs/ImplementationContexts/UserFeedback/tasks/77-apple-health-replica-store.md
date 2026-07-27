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
  接收 HealthKit 查询投影并在一次 store transaction 内按稳定 sample identity
  upsert、删除不再存在的本机 HealthKit 记录。
- 持久字段按最小化原则只包含稳定 sample UUID、kind/workout activity、
  start/end、source bundle、sleep stage 与 replica metadata；不保存用户可编辑
  标题、备注、任务关系、设备名或 HealthKit 原对象。
- UI/Analytics 只消费只读 value snapshot，不持有 replica `PersistentModel`；
  现有 Health timeline projection 迁移到 repository/service 边界，macOS 无
  HealthKit 时读取本机 replica 但不伪造可刷新能力。
- JSON snapshot 增加明确版本化的 `healthRecords` 数组；导出捕获主 store 与
  Health replica 的一致只读快照，不为 importer 暗示恢复能力。

## 测试优先清单

- [ ] 新独立 store 与主 store/CloudKit configuration 物理隔离。
- [ ] 第一次同步、幂等重放、HealthKit 修改、撤销授权/查询失败和记录删除收敛。
- [ ] 任意 UI/command 不能修改 Health replica；只读投影与现有时间线/分析语义一致。
- [ ] JSON 导出包含确定性 Health records，空/损坏/不可用 replica 有明确结果，
  且敏感字段与主快照边界符合文档。
- [ ] 新 Health schema 的磁盘重开与版本兼容 fixture。
- [ ] 正常字号 iPhone/iPad/macOS Settings/Health timeline 定向截图；真机 HealthKit
  同步与 Release 安装是最终 gate。

## Checkpoint 编排

- [ ] A：完成现状、Apple 合规、schema/container、导出和测试边界审计。
- [ ] B：先写独立 store/schema/repository/sync/export 的失败行为测试。
- [ ] C：分层实现本地 replica、只读投影和 JSON 导出，更新当前工程文档。
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
