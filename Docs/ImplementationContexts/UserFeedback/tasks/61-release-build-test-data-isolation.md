# 61：Release 构建与测试数据隔离实现记忆

状态：2026-07-26 进行中

> 本文件是主代理与子代理的实现、验证和编排记忆；唯一任务来源仍是
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 条目。

## 认领的反馈条目

- 反馈第 105 条：干净的 macOS Release App 启动后测试数据覆盖 iCloud；Release 构建
  不得混入测试数据；`make build-install-all` 默认改为 Release configuration。
- 反馈第 106 条：Inbox 中反复出现莫名其妙的 `first`；排查同类测试数据；今后测试
  数据必须集中放置，不得干扰正式运行的 App。

用户在反馈中明确写了"结合下一条"，因此这两条作为一个任务一起做。

## 现场证据（2026-07-26 在用户本机采集）

1. `defaults read me.mezorewww.timetracker` 当前实际包含：
   - `TimeTrackerPendingCloudUploadReset = 1`
   - `TimeTrackerQueuedCloudReconciliation = 1`
   - `NSWindow Frame TimeTrackerUITestWindow = "600 242 720 808 …"`

   前两个键是**当前已经武装**的破坏性云恢复标志：正式 App 下次启动会执行强制
   上传/重新对账。第三个键证明 UI 测试窗口与已安装的正式 App 共用同一个
   preferences domain。

2. macOS `timetracker.entitlements` 没有 `com.apple.security.app-sandbox`，
   所以测试宿主进程与 `/Applications/timetracker.app` 共享
   `~/Library/Preferences/me.mezorewww.timetracker.plist` 与
   `~/Library/Application Support/`。

3. `~/Library/Application Support/` 当前只有 `TimeTracker.store*`，没有
   `TimeTrackerSync/`、`TimeTracker-Demo.store`、`TimeTracker-UITests.store` 残留。

## 根因（子代理 Explore 全量排查 + 本机证据交叉确认）

**根因 1 — 测试宿主与正式 App 共用 UserDefaults domain（105 与 106 的共同根因）**

- `timetracker/App/AppModelContainerFactory+Testing.swift:83-88` 的
  `isUnitTestHost()` 判定正确，`makeUnitTestHostModelContainer()` 与
  `makeUITestModelContainer()` 都只用内存/独立 store，**SwiftData store 本身是隔离的**。
- 但 `UserDefaults.standard` 完全没有隔离。测试直接写生产恢复标志：
  `timetrackerTests/Core/CoreSyncConflictTests.swift:1179,1207,1213,1224,1254,1284,
  1493,1515,1539,1557,1583,1621` 写 `TimeTrackerPendingCloudDownloadReset`、
  `TimeTrackerPendingCloudUploadReset`、`TimeTrackerActiveCloudReconciliation`、
  `TimeTrackerActiveCloudDownloadRecovery`、`TimeTrackerCloudSyncEnabled`、
  `TimeTrackerPersistenceMode`；清理只在 `defer` 作用域内。
- 测试中断/崩溃 → 标志残留 → 正式 App 下次启动在
  `AppModelContainerFactory.swift:82-127` → `AppCloudSync+Recovery.swift:22-60`
  执行破坏性的下载重置或强制上传。**这正是"干净 Release App 覆盖 iCloud"的机制，
  且本机当前就处于已武装状态。**
- `SyncConflictService` 默认状态目录同样共享：
  `SyncConflictService+StateLocations.swift:56-64` →
  `~/Library/Application Support/TimeTrackerSync`。
  `timetrackerTests/Support/TestSupport.swift:60-62` 的
  `makeTestSystemActionCommandHandler()` 没有覆盖 `stateURLOverride`。
  测试写出的快照会被
  `timetracker/Services/SystemIntegration/SyncDataSnapshot+RestoreInbox.swift:48-71`
  在正式 store 里重新插入 `InboxItem` —— **这是 `first` 删掉又回来的机制**。

**根因 2 — `make build-install-all` 默认装 Debug 包到真机**

- `Makefile:12` `CONFIGURATION ?= Debug`；
  `tools/timetracker_tools/build_install_all.py:252` `env("CONFIGURATION", "Debug")`。
- Debug 配置定义 `DEBUG`（`project.pbxproj:785`）→
  `AppDemoDataConfiguration.allowsDemoDataCreation == true`
  （`AppDemoDataConfiguration.swift:13-19`）。

**根因 3 — Debug 包里的破坏性入口直接作用于生产 CloudKit store**

- 设置 → 维护 → "Rebuild demo data"：
  `SettingsCategorySections.swift:126` → `SettingsDataSectionsViews.swift:74-82`
  → `SettingsDestructiveConfirmation.swift:60`
  → `TimeTrackerStore+MaintenanceCommands.swift:4-12` → `SeedData.replaceWithDemoData`。
  `SeedData.swift:49-65` **只**判断 `allowsDemoDataCreation`，不判断当前打开的是哪个
  store。出厂 `TIMETRACKER_AUTOMATIC_DEMO_DATA_MODE = off`
  （`project.pbxproj:665,720`）⇒ `usesLocalDemoStore == false` ⇒ 打开的是
  `cloudKitDatabase: .private(...)` 的生产 store ⇒ 先把用户全部数据打墓碑
  （`SeedData+Cleanup.swift:117-145`）再写入 demo 行 ⇒ 同步到真实 iCloud。
- `CloudSyncSmokeTestRunner.swift:138-158` 的 `.seed` 在生产 CloudKit 容器里创建
  `Cloud Smoke <hex>` 任务；只有 `queueDownloadFromDemo` 会被
  `AppDemoDataConfiguration.swift:29-34` 转到 demo store。
- `TimeTrackerStore+UIAudit.swift:34-40` 读 `TIMETRACKER_UI_AUDIT_ROUTE` **不要求**
  `--uitesting`，其 `sync-conflict` 路由会伪造冲突提示，确认后触发真实的破坏性恢复。

**关于 `first` 本身**：全仓库 `*.swift/*.json/*.plist/*.sh/*.py/*.md/*.strings/*.pbxproj`
穷举检索，**没有任何代码用 `"first"` 构造 `InboxItem`/`TaskNode`/`Category`/
`ChecklistItem`**。小写 `first` 仅作为 `deviceID`/探针出现在单元测试里。
所以 `first` 是人工或 Shortcut 录入的，**bug 是它删不掉、反复回来**，
由根因 1 的快照恢复路径解释。次要嫌疑：`AddInboxItemIntent`
（`timetracker/AppIntents/TimeTrackerAppIntents.swift:5-28`）调用
`addInboxItem(title:container:)` 时没有传 `externalCommandKey`
（`Commands/SystemActionCommands.swift:115-127`），
`StoreScopedInboxCommandCoordinator+CaptureReceipts.swift:17-31,42-50`
的去重回执机制在 key 为 `nil` 时整段跳过 ⇒ 重复触发的 Shortcut 会无限重复插入。

## Checkpoint 编排

- [~] A：认领反馈、建立本实现记忆、采集并固化现场证据。
- [ ] B：测试宿主隔离（根因 1）。引入统一的 `AppDefaults` 与隔离的 sync 状态目录，
  把 App 内 65 处 `UserDefaults.standard`（17 个文件）改为经隔离层访问；
  加行为测试断言测试宿主写入不会落到生产 domain。
- [ ] C：Release 硬化（根因 2、3）。`build-install-all` 默认 Release；
  `replaceWithDemoData`/`CloudSyncSmokeTestRunner`/UI-audit 路由都必须拒绝在生产
  CloudKit store 上执行。
- [ ] D：现场清理与用户可见的维护入口。解除本机已武装的破坏性标志；
  提供清除 demo/smoke 测试残留行的维护动作。
- [ ] E：`make format-check` + `make test` 门禁、Release 全设备安装、反馈收口、
  逐 checkpoint 提交。

## 约束与边界

- SwiftData `@Model` 不做改动 ⇒ 本任务不需要新增 `VersionedSchema`/迁移阶段。
- 不得因为"让检查通过"而关闭签名；保持 `CODE_SIGN_STYLE=Automatic`、
  team `LT98S43NKA`。
- 清理用户 iCloud 数据属于破坏性操作：只提供显式的维护入口，不做静默自动删除。
- 已知既有失败（与本任务无关，不在本任务伪造绿色）：
  `PreferenceSyncBehaviorTests.checklistCompletionMovesOnlyTheTargetToTheDestinationGroupEnd`、
  `TaskPersistencePolicyTests.archiveCommandPreservesTheOriginalArchiveTimestamp`。

## 使用的库

- 本任务以隔离与配置修复为主，暂无新增第三方依赖。仓库既有依赖：
  `MarkdownView`、`BlossomColorPicker`、`swift-collections`(`HeapModule`)。

## 进度记录

- 2026-07-26 Checkpoint A：认领第 105/106 条，建立本文件与 active 链接；
  按用户指示从反馈第 105 行开始，任务 60 的 `[~]` 条目暂停并撤下 active 链接。
