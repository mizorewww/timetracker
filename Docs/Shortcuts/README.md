# Time Tracker Shortcuts 设计

> iOS/iPadOS「快捷指令」(Shortcuts) 与 App Intents 能力的设计与使用文档。
> 实现入口:`timetracker/AppIntents/TimeTrackerAppIntents.swift`;命令层:`timetracker/Commands/SystemActionCommands.swift`。

## 能力矩阵

| 快捷指令 | Intent | 参数 | 返回 | 行为 |
|---|---|---|---|---|
| Add Inbox Item | `AddInboxItemIntent` | `Title`(文本) | 无 | 在 Inbox 捕获一个松散条目,供后续 AI 路由或手动归类 |
| Start Timer | `StartTimerIntent` | `Task`(任务实体,可搜索) | 无 | 为指定任务开始计时;遵守并行计时与准入策略 |
| Stop Timer | `StopTimerIntent` | `Timer`(运行中的计时实体) | 无 | 停止指定的一段计时 |
| Get Running Timers | `GetActiveTimersIntent` | 无 | `[Running Timer]` | 返回当前所有运行中的计时(任务名 + 路径) |
| Stop All Timers | `StopAllTimersIntent` | 无 | 无 | 停止所有运行中的计时 |

实体(Entities):

- **Task**(`TaskNodeAppEntity`):只列出「可直接计时」的任务。重复任务模板、归档任务、Apple Health 同步任务(运动/睡眠)不可选;重复任务选择其当日实例。支持按标题/路径搜索(`EntityStringQuery`),建议列表取前 12 个。
- **Running Timer**(`ActiveTimerAppEntity`):当前运行中的时间段,显示任务名与路径。

## 在快捷指令 App 中的典型用法

1. **一键捕获**:`Add Inbox Item` + 「听写文本」→ 语音快速记录想法进 Inbox。
2. **场景自动化**:到达公司 → `Start Timer`(选择 "Client Work");离开公司 → `Stop All Timers`。
3. **条件判断**:`Get Running Timers` → 「如果 计数 > 0」→ `Stop All Timers`,否则无操作。
4. **Siri**:直接说「在 Time Tracker 中开始计时」「在 Time Tracker 中停止所有计时」(已在 `TimeTrackerShortcuts` 注册 phrases)。

## 架构与设计决策

- **薄封装**:Intent 只做参数解析与结果包装,所有写入经 `SystemActionCommandHandler` → `StoreScoped*CommandCoordinator` → 与应用内操作完全相同的准入、事务与同步路径。契约测试 `CoreSystemActionCommandTests.appIntentsAreThinWrappersAroundSystemActionCommands` 锁定 Intent 不得直接触碰 SwiftData 模型。
- **跨进程锁**:快捷指令在独立进程运行,与应用、Widget 共享 `.timer-mutations.lock` 文件锁域(见 `PathFileLock`),锁获取有 5 秒超时,竞争时干净报错而非卡死。
- **提交后效果**:每个变更 Intent 在提交后统一执行 `SystemActionPostCommitEffects`(快照记录、Live Activity 调和、跨 scene 广播),与手表命令同一条路径。
- **`Stop Timer` 只停一段**:单停止语义与应用内一致(多计时并行时必须显式指定目标,避免误停)。
- **`Stop All Timers` 逐段提交**:每段计时是独立已提交事务,部分成功不会让 store 处于中间态;事件聚合后一次性执行提交后效果。
- **不需要打开 App**:所有 Intent `openAppWhenRun = false`,可在锁屏/后台执行。

## 限制

- Apple Health 管理的运动/睡眠任务只能由 Apple 健身/健康 App 产生,Shortcut 不能为其开始或停止计时。
- 番茄钟(Focus)暂不提供 Shortcut(计划选择策略待设计);Inbox AI 路由在后台按既有策略异步进行,不由 Shortcut 触发。
- 任务实体建议列表上限 12 个;更多任务请用搜索参数。

## 测试

- `CoreSystemActionCommandTests`:命令层语义(含 stop-all 全停断言)与 Intent 薄封装契约。
- 模拟器验收通过 `xcodebuild test -only-testing:timetrackerTests/CoreSystemActionCommandTests` 运行。
