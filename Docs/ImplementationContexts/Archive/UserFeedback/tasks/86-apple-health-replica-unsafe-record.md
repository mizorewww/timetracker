# 86：Apple Health 记录无法安全保存 实现记忆

Status: Complete

状态：2026-07-28 已完成

> 本文件是主代理与子代理的实现、验证和编排记忆；唯一任务来源仍是
> [`Docs/userfeedback.md`](../../../../userfeedback.md) 中对应的 `[x]` 条目。

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

## 已确认根因

- Apple 的 `HKSample` 合同允许 `startDate == endDate`，真实 workout/sleep 中可以出现
  这种 point sample。
- `SwiftDataAppleHealthReplicaRepository.validate` 错误地要求
  `startedAt < endedAt`。point sample 因而抛出 `.invalidSample`，records 与双 anchor
  一起回滚；下一次刷新仍从旧 anchor 读取同一条记录，于是提示永久重现。
- 既有 Timeline 与 Sleep projection 已安全忽略零宽区间。正确边界是把 point
  sample 作为 HealthKit 来源事实保存并推进 anchor，仅拒绝反向区间。
- 这是校验策略修正，不改变任何字段或持久格式；V1 旧库无需 migration。升级后旧
  anchor 会重放该记录并自行收敛。

## 测试优先清单

- [x] repository 测试在旧实现上复现 point sample 稳定失败。
- [x] 覆盖 point sample 保存、双 anchor 推进及下一轮不从空 anchor 重放。
- [x] 覆盖反向区间整批回滚，确保旧 records 与双 anchor 不变。
- [x] 验证 Timeline facade 不再进入 `.failed`，而是正常得到无正时长数据状态。
- [x] 运行聚焦测试、`make test`、格式/本地化及相关正常字号 UI 截图。
- [x] 运行 `make build-install-all`，核验可用 iOS/iPadOS 设备、嵌入 Watch companion 与
  `/Applications/timetracker.app`。

## Checkpoint 编排

- [x] A：审计 HealthKit reader → draft → repository → sync → facade/UI 错误链，
  先固定可复现行为测试。
- [x] B：实现最小数据安全修复，保留 replica/anchor 原子边界。
- [x] C：更新当前架构、隐私、代码与测试文档；完成视觉/行为验收。
- [x] D：全量验证、全设备安装、标记 `[x]` 并移除 active link。

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
- 2026-07-28：确认 HealthKit point sample 合法域；旧实现的 repository 聚焦测试
  仅在新增 point sample 用例失败（`invalidSample`）。
- 2026-07-28：把 repository 时间边界从严格小于修正为小于或等于；repository
  7 tests、sync service 4 tests、facade 3 tests 全绿。未增加第三方依赖。
- 2026-07-28：`make test` 通过 1460 tests / 163 suites；现有正常字号 Apple
  Health UI fixture 加入一个零宽 workout，使行为断言与截图都经过本次修复边界，
  但 projection 仍只显示正常 workout 与合并后的 sleep episode。
- 2026-07-28：iPhone UI test
  `testAppleHealthWorkoutAndSleepAppearInTodayTimeline` 通过；目视检查
  `iphone-home-apple-health-workout-sleep` 截图，正常 Running/Sleep rows 与图表
  保持可读，没有 unsafe-record 失败状态。临时模拟器
  `C9D32760-97EB-48F5-9AB8-8EB2F225C0C1` 已由 Make target 关闭并删除，结果保存在
  `build/UITestResults/iOS-20260728-093053.xcresult`。
- 2026-07-28：Release `make build-install-all` 成功。版本 `1.1.305 (360)` 安装到
  当前 connected 的 iPad Pro M4；iOS App 已确认嵌入签名 Watch companion；
  `/Applications/timetracker.app` 已替换并通过 designated-requirement 校验。iPhone
  Air 当时由 CoreDevice 报告为 `unavailable`，未被 Make target 视为可安装设备。
  关闭任务提交后再次运行同一 target，保证最终 HEAD 在所有当时可用设备上安装。
