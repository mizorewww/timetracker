# 86：Apple Health 记录无法安全保存 实现记忆

状态：2026-07-28 实现中

> 本文件是主代理与子代理的实现、验证和编排记忆；唯一任务来源仍是
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 条目。

## 认领的反馈条目

- App 总是提示 “Apple Health returned a record that could not be stored safely.”

## 预期行为

- 系统 HealthKit 返回的合法 workout 和 sleep 样本能够进入独立、只读、
  device-local replica，不因真实世界的边界值被误判为不安全。
- 不可表示或确实不安全的单条记录不能污染 replica，也不能推进到一个无法重放的
  anchor；错误必须保持可诊断，不能靠隐藏提示掩盖。
- 两条 anchored stream、records/deletions 和双 anchor 仍在同一个 replica
  transaction 中提交；任一查询或持久化失败保持零写入。
- 不修改主业务 V14 schema，不把 Health 数据加入 CloudKit、业务快照、AI、
  Widget 或 Watch 传输。
- UI 只在出现需要用户处理的失败时给出清晰反馈；普通合法样本不应反复产生启动或
  刷新警报。

## 首轮根因假设

- `AppleHealthReplicaRecordDraft` 或 persisted model 的安全校验范围比 HealthKit
  真实样本域更窄，例如睡眠阶段、workout activity raw value、source bundle/product
  type、日期上下界或极短/零时长样本。
- HealthKit reader 可能把合法的“删除/修改/未知新枚举”投影成当前 V1 无法表达的
  draft，导致每次 anchored replay 都在同一条记录上失败且 anchor 永不推进。
- 旧 replica 可能包含现行读取器无法解码的记录；读取失败被误报成新 HealthKit
  样本无法保存。
- 同一 sample UUID 跨 workout/sleep kind、分页内重复或 source 字段边界可能触发
  repository 的 fail-closed 检查。

## 测试优先清单

- [ ] 用最小 command/repository/sync 行为测试复现真实边界样本的稳定失败。
- [ ] 覆盖首次 anchored import、重放、修改、显式删除和双 anchor 原子推进。
- [ ] 覆盖非法记录、重复 UUID、未知枚举、日期/时长和有界文本输入。
- [ ] 覆盖旧磁盘 replica 重开与读取，确认不是 schema 兼容问题。
- [ ] 验证 Timeline 与 Apple Health Task Detail 不再重复显示该错误。
- [ ] 运行聚焦测试、`make test`、格式/本地化、签名 iOS/macOS 构建及相关正常字号
  UI 截图。
- [ ] 运行 `make build-install-all`，核验 iPhone、iPad、嵌入 Watch companion 与
  `/Applications/timetracker.app`。

## Checkpoint 编排

- [~] A：审计 HealthKit reader → draft → repository → sync → facade/UI 错误链，
  先固定可复现行为测试。
- [ ] B：实现最小数据安全修复，保留 replica/anchor 原子边界。
- [ ] C：更新当前架构、隐私、代码与测试文档；完成视觉/行为验收。
- [ ] D：全量验证、全设备安装、标记 `[x]` 并移除 active link。

## 库策略

- HealthKit 样本语义、anchored query 和本地持久化由 Apple HealthKit、SwiftData
  与 Foundation 原生支持；第三方 Health wrapper 无法替代系统授权或提升样本
  正确性，并会扩大敏感健康数据的供应链边界。
- 先复用系统框架与仓库既有 replica 服务。只有发现原生 API 无法覆盖的明确缺口时，
  才评估维护活跃、许可证合适且一般不少于 1k stars 的库。

## 子代理编排

- 主代理：任务认领、复现、实现、共享 Xcode/模拟器资源、提交与安装。
- 根因审计：追踪真实样本在 reader/model/repository/sync/facade 的失败位置。
- 数据安全审计：校验 sanitize/skip/fail-closed、旧库兼容及 anchor 语义。
- 测试审计：确定失败 fixture、聚焦套件、UI 截图与资源清理范围。

## 进度记录

- 2026-07-28：认领最后一条反馈，建立 `~86` 活动实现记忆并开始并行只读审计。
