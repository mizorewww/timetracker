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

实体: **Task**(`TaskNodeAppEntity`)只列出「可直接计时」的任务(模板/归档不可选,重复任务选其当日实例),支持按标题/路径搜索,建议列表取前 12 个;**Running Timer**(`ActiveTimerAppEntity`)显示当前运行时间段的任务名与路径。

## 典型用法

1. **一键捕获**:`Add Inbox Item` + 「听写文本」→ 语音记录想法进 Inbox。
2. **场景自动化**:到达公司 → `Start Timer`;离开公司 → `Stop All Timers`。
3. **条件判断**:`Get Running Timers` → 「如果 计数 > 0」→ `Stop All Timers`。
4. **Siri**:「在 Time Tracker 中开始计时」「停止所有计时」等已注册短语。

## 架构与设计边界

- **薄封装**:Intent 只做参数解析与结果包装,所有写入经 `SystemActionCommandHandler` → `StoreScoped*CommandCoordinator` → 与应用内操作完全相同的准入、事务与同步路径;验证落在 store-scoped 命令的可观察原子结果上。
- **跨进程锁**:快捷指令在独立进程运行,与应用、Widget 共享 `.timer-mutations.lock` 文件锁域(`PathFileLock`),锁获取有 5 秒超时,竞争时干净报错而非卡死。
- **提交后效果**:每个变更 Intent 在提交后统一执行 `SystemActionPostCommitEffects`(enqueue 精确事件、后台投影追赶),与手表命令同一条路径,不等待投影完成。
- **`Stop Timer` 只停一段**:多计时并行时必须显式指定目标,避免误停。
- **`Stop All Timers` 逐段提交**:每段计时是独立已提交事务,部分成功不会让 store 处于中间态。
- **不需要打开 App**:所有 Intent `openAppWhenRun = false`,可在锁屏/后台执行。

## 限制

- 番茄钟(Focus)暂不提供 Shortcut;Inbox AI 路由在后台按既有策略异步进行,不由 Shortcut 触发。
- 任务实体建议列表上限 12 个;更多任务请用搜索参数。

## 测试

自动化回归聚焦 store-scoped 命令的原子写、精确停止、陈旧调用拒绝与恢复只读边界。Shortcuts/App Intent 的参数解析、系统展示和真实调用链在受影响发布中作为设备验收项执行。
