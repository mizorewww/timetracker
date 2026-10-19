# Architecture

只写从代码里不容易看出来的结构与不变量；细节以代码和测试为准。必须遵守的长期决策见 [AgentDecisions](AgentDecisions.md)。

## 分层与数据流

```text
SwiftUI View
  -> TimeTrackerStore (@MainActor @Observable facade)
  -> store-scoped command coordinator（store lock + fresh ModelContext + performAtomicMutation）
  -> SwiftData repository / model
  -> StoreDomainEvent -> StoreRefreshPlanner -> domain stores 增量刷新
  -> CommittedMutationSystemProjectionScheduler 异步投影到 Widget / Watch / Live Activity
```

- `TimeSegment` 是唯一时间事实；任务、清单、番茄、统计、预测、图表都是派生。
- View 不直接写 SwiftData，也不在 `body` 里算统计/rollup/forecast。
- 所有已记录时长经 `TrackedTimePolicy` 读取（`min(endedAt ?? now, now)` 再裁到区间）；不得在别处用 `endedAt ?? Date()` 计算已记录时长（编辑器给活跃段预填的结束时间不属于时长读取）。
- Scene、App Intent、Watch 写入共用同一套 store-scoped coordinator；提交后只投递 exact `StoreDomainEvent`，不等待投影，投影失败不影响命令结果。
- 命令失败抛给调用方，由发起的 view 经 scene 的 `AppSceneFeedbackRouter` 展示；store 没有全局错误槽。无发起 view 的生命周期、同步与提交后读模型刷新失败只写日志，下一次刷新重试。
- 任务详情没有离开确认或崩溃恢复副本：编辑 450 ms 后自动保存，失焦、进入后台、详情消失（任何导航）时同步提交；未通过校验的草稿不保存并在原处标出原因；只有保存时发现任务已被其它设备/场景改动才弹 Reload/Keep。离开详情时若编辑仍无法保存，以场景提示告知未保存的原因；归档前先同步提交打开中的编辑，若该编辑无法保存且属于被归档任务或其子任务，则不执行归档。
- CloudKit 远端变更经 notification 合并后由 `RemoteChangeHistoryCursor` 按 persistent history 决定刷新范围；没有轮询。
- 布局只按窗口宽度在 `AppRootView` 选择 compact（<720 pt，TabView）或 regular（NavigationSplitView）shell；`#if os(...)` 只用于平台独有 API。

## 目录

| 路径 | 内容 |
| --- | --- |
| `timetracker/App` | 入口、root shell、scene 级 sheet/feedback router、容器与 CloudKit 启动、deep link、Watch 路由、菜单命令、demo 数据 |
| `timetracker/Models` | SwiftData 模型、`VersionedSchema` V1…V14 与迁移计划、`TrackedTimePolicy`、`TaskEstimatePolicy` |
| `timetracker/Repositories` | SwiftData 查询/写入；`ModelContext+AtomicMutation.swift` 是事务边界 |
| `timetracker/Commands`, `Services/*/StoreScoped*` | 持久写入命令 |
| `timetracker/Stores` | facade、domain stores（Task/Ledger/Checklist/Rollup/Analytics/Preference）、刷新规划 |
| `timetracker/Services` | 纯计算（统计、时间线、预测、计时准入）、LLM、导出、系统投影 |
| `timetracker/Features`, `SharedUI` | 按功能组织的 UI；`SharedUI` 只放至少两处使用的组件 |
| `timetracker/Shared`, `SharedLiveActivity` | 跨 target 的 DTO 与 App Group 快照 |
| `timetrackerWatchApp` / `WidgetExtension` / `LiveActivityExtension` | 系统表面，只读投影 + 复用主应用命令 |

## 领域模型要点

- `TaskNode`：`parentID` 是层级权威，`depth`/`path` 可修复。任务没有产品层状态；`statusRaw` 仅为旧 schema 兼容保留。归档 = `archivedAt != nil` 或旧 raw `archived`。`deletedAt` 是同步 tombstone，生产 store 永不物理清除。
- `TimeSession` 是一次工作意图，`TimeSegment` 是实际时间。同任务、普通秒表、间隔严格小于 60 秒且间隔内无其它可见工作时，新 Start 复用原 session、墓碑旧 segment、新建 segment 并把起点延伸到原起点。
- `ChecklistItem` 是任务唯一的完成/进度信号，完成清单不锁定任务。
- `TaskRecurrenceRule` 把任务变成每日模板，只生成当天实例、不回填；模板本身不能计时。规则/回执/生成任务使用确定性 UUIDv8，避免多设备重复生成。
- 预测：显式预计时长优先；否则按 `已用时间 / 已完成清单数 × 未完成数` 推断，证据不足时显示缺失原因而不是数字。历史节奏只取最近 90 个本地日，只用来把剩余时长换算成天数。
- 并行计时合法：gross = 片段之和，wall = 区间并集，overlap = gross − wall。

## Schema 演进

1. 优先新增扩展模型 + UUID 引用，而不是给 `TaskNode`/`TimeSession`/`TimeSegment` 加列。
2. 必须加字段时：新 schema 版本、字段可选或有稳定默认、先写旧 store 兼容测试再接 UI。
3. 旧 `VersionedSchema` 保持历史形状；活模型加字段后，旧版本解析到冻结快照类型（参见 V14 背后的 V13 `ChecklistItem` 快照）。
4. 不复用版本号；同步模型的 `id`、时间戳、`deletedAt`、`deviceID`、`clientMutationID` 语义保持不变。
5. 新增同步模型要更新 `TimeTrackerModelRegistry` 与 `RemoteChangeHistoryCursor` 的模型映射。

## 同步与读侧去重

CloudKit 镜像是唯一同步机制。重复物理行按 LWW 选 winner：`updatedAt` 新者胜 → 同时刻 tombstone 胜 → `createdAt` → `deviceID` / `clientMutationID` / 稳定内容键；先选 winner 再过滤 tombstone。CloudKit 分批导入时，task/session 尚未到达的 segment 只隐藏不删除。iCloud 开关、设备 ID、密钥、自动 AI 同意只存本机，不同步、不导出。

## AI

请求经 MacPaw `OpenAI`（`LLMClient`）发往用户配置的 OpenAI-compatible endpoint；远程必须 HTTPS，HTTP 仅限 loopback，拒绝 redirect。API key 只在 Keychain（device-only）。任务规划的模型工具只修改内存 overlay，Apply 在 store lock 内重新捕获 baseline 做 CAS，有任何差异零写入（AD-132）。
