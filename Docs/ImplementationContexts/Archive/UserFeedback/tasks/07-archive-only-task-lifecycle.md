# 07：任务仅归档生命周期实现记忆

Status: Complete

> 本文件只保存实现、验证和子代理编排记忆，不是任务来源。范围与完成状态必须重新读取
> [`Docs/userfeedback.md`](../../../../userfeedback.md) 中唯一的 `[~]` 项。

## 当前阶段

- 已完成领域、持久化、同步、界面、HIG、测试和依赖的静态审计。
- 已确认历史提交 `8a22f8b` 与 `bfe3756` 移除了任务删除界面和领域命令，当前没有新的
  用户任务删除入口可删。
- 已用失败测试复现菜单、设置、文案、deep link 与未来时间戳 LWW 缺口。
- 已完成归档/解除归档严格胜过跨设备未来时间戳副本的领域修复。
- 已统一产品文案、菜单和 deep link 语义，并通过 macOS 契约/领域测试与带签名 iOS 编译。
- 已完成 iPhone、iPad、macOS 归档 → Settings 解除归档 → Tasks 恢复的交互与截图矩阵。
- 已完成 Release 全设备构建、实体 iPhone/iPad 安装、macOS 安装与独立版本/签名核验。
- 当前反馈项已完成；最终 checkpoint 只包含本记忆、反馈 `[x]` 和活动软链接移除。

## 实现边界

- 用户可见的任务生命周期只保留“归档”和“解除归档”，不允许永久删除任务。
- 设置中提供“已归档任务”入口与列表，并允许从该列表解除归档。
- Task 页面左滑快捷操作由删除改为归档；归档还必须有可发现的非手势入口。
- 删除所有专为“永久删除任务”功能存在的领域命令、界面、文案、确认流程与测试。
- 区分任务硬删除与时间段、清单项等其他实体的删除；不擅自扩大范围。
- 对同步、迁移或数据修复所需的内部清理逐处举证，不能因名称相似而盲删。
- 不读取或处理 `Docs/userfeedback.md` 中后续反馈。

## 验收清单

- [x] 盘点所有任务删除、归档、解除归档调用点与数据不变量
- [x] 确认归档专用领域 API 已存在，任务硬删除功能代码已经移除
- [x] 确认设置中已有归档入口、列表与父级优先的解除归档
- [x] 确认 Task 页面左滑已是归档，详情 More 已提供非手势入口
- [x] 修正剩余归档语义、跨平台入口与分布式持久化边界
- [x] 增补领域、界面契约和跨平台回归测试
- [x] 验证 iPhone、iPad、macOS 普通路径并适当截图
- [x] 运行 `CONFIGURATION=Release scripts/build_install_all.sh`
- [x] 核验安装版本与签名，释放 owned 设备、进程和临时产物
- [x] 只在 `Docs/userfeedback.md` 标记完成并移除活动软链接

## HIG 与依赖决策

- 归档是可逆状态变更，不使用 destructive role、红色或不可逆删除确认；统一使用
  SF Symbol `archivebox`，解除归档使用清晰的动词标签与匹配的系统符号。
- 左滑遵循系统列表手势，但不能成为唯一入口；设置中的归档列表提供明确的解除归档按钮或菜单。
- 使用系统 `List`、`swipeActions`、`Menu`、`NavigationStack`/`NavigationSplitView`
  与现有数据层，不自绘系统组件。
- 任务生命周期规则放在可测试的模型或服务层；SwiftUI 视图只调用命名明确的归档动作。
- context menu 隐藏不可用动作；详情 More 这类普通菜单可以保留简短的 disabled
  `Archive`，但不把错误说明写成动作标题。
- macOS 的任务动作必须有菜单栏入口；归档命令没有默认系统快捷键，因此不擅自分配按键。
- 本项不增加第三方依赖。已核对 Apple SwiftData/SwiftUI 官方资料，以及成熟候选
  Swift Composable Architecture（约 14.7k stars）和 SwiftUIX（约 8k stars）；
  它们不能降低这个现有领域命令的同步或迁移风险，引入反而扩大架构和回归面。实现继续使用
  系统 `SwiftData`、`List.swipeActions`、`Menu`、`contextMenu`、Swift Testing/XCTest。

## 静态审计结论

### 产品级调用图

- 归档：Task 行/侧栏/详情菜单 → `archiveTaskProtectingUnsavedChanges` →
  `archiveSelectedTask` → `StoreScopedTaskLifecycleCommandCoordinator.archive` →
  `TaskDraftCommandHandler.archive` → `TaskRepository.archiveTask`。
- 解除归档：Settings 已归档列表 → `unarchiveTask` →
  `StoreScopedTaskLifecycleCommandCoordinator.unarchive` →
  `TaskDraftCommandHandler.unarchive` → `TaskRepository.unarchiveTask`。
- coordinator 在同一 store lock 下用 fresh context 重新读取整棵子树，同时检查普通计时和
  Pomodoro；归档只写选中节点，后代通过父级归档传递隐藏；解除归档要求父级优先。
- 当前 Task UI、repository、use case、coordinator、store facade、macOS Commands、
  App Intent 与 deep-link 命令中均不存在 `deleteTask`、`softDeleteTask`、
  `deleteSelectedTask` 或任务 trash/destructive 入口。

### 必须保留的内部墓碑

- `TaskNode.deletedAt` 与 `TaskRecord.deletedAt` 是旧 schema、CloudKit LWW 去重、快照覆盖恢复、
  Reset All、Demo 清理和 90 天后物理清理的兼容状态，不是产品生命周期动作。
- 墓碑必须先参与 UUID 去重再被可见查询过滤；提前删除字段或生产环境物理清理会让离线设备的
  旧副本复活。
- `SyncDataSnapshot+RestoreTasks` 用墓碑表达“目标快照中已不存在”的记录；全局 Reset 与
  CloudKit 灾难恢复也必须保留。
- 时间段、清单项、Inbox、倒计时、Pomodoro、Task Category、AI 未落库草稿和恢复 JSON
  的删除/移除属于其他实体或系统维护，不在当前任务范围，不能因名称相似而删除。

### 仍需修正的真实缺口

1. Task context menu 在活动计时子树上显示一条 disabled 长错误句；应在 context menu 隐藏，
   在详情 More 中保留简短 disabled `Archive`。已完成，并避免隐藏动作后留下尾部分隔线。
2. Settings 的 Unarchive 是 `arrow.uturn.backward` 纯图标按钮；应显示明确的
   `Label("Unarchive", …)` 并保留 iOS 44pt / macOS 28pt 最小目标。已完成。
3. macOS 菜单栏没有“归档所选任务”；已增加无快捷键、按选择与活动子树状态置灰的
   `Task > Archive Selected Task`。
4. 三套本地化仍把旧墓碑历史称为 Deleted Task，并把归档描述成 hidden/return；应统一为
   Archive / Unarchive / Unavailable Task。已移除旧本地化 key，并把相关代码标识也改成
   unavailable，底层 `deletedAt` 墓碑字段保持不变。
5. 归档/解除归档写入使用普通 `Date()`；面对来自其他设备的未来 `updatedAt` 或重复 UUID
   行，LWW 可能让本次动作输给旧副本。已改为从全部同 UUID 物理副本选择 winner，并使用
   现有 `PersistentLWWMutationDate.strictlyDominating`；绝不写入或清除 `deletedAt`。
6. 归档任务 deep link 目前可能返回 handled，却因任务不可见而没有打开详情；应明确拒绝，
   且不改变 destination、selection 或草稿。已改为复用可见详情路由校验并增补回归测试。
7. 现有 UI round trip 直接跳过 macOS，并把 iPad 截图写成 `iphone-*`；应改成稳定 demo
   任务和三平台独立命名。

### 明确不在本 checkpoint 扩大的事项

- 不重构整个 macOS Settings 信息架构；这不是当前 archive-only 功能的阻断项。
- 不新增 schema 或删除 `deletedAt`。
- 不给归档命令自创键盘快捷键。
- 不处理 `Docs/userfeedback.md` 中当前 `[~]` 之后的任务。

## 子代理编排

- [x] 领域与持久化审计：确认产品删除管线已移除，枚举墓碑/CloudKit/恢复的保留边界，并发现
  archive/unarchive 的未来时间戳 LWW 风险。
- [x] UI/HIG 审计：确认左滑、详情与 Settings 已有主链路，发现 context menu、可见
  Unarchive、macOS 菜单和历史文案缺口。
- [x] 测试/迁移/依赖复审：确认不需要 schema bump 或第三方库，发现 deep link、
  maintenance 不变量与跨平台 UI 覆盖缺口。
- 三个子代理均只读，未编辑、构建、占用模拟器或提交。

## 运行资源所有权

- iPhone 端到端批次专属设备：`TimeTracker-Task07-iPhone17Pro`
  (`D2A5E5B9-C28E-4BB6-8EB3-956A29AAAAD6`)，iOS 27.0。
- iPad 端到端批次专属设备：`TimeTracker-Task07-iPadPro11`
  (`592369B4-6E4F-4550-AD20-F54AB21ECC8B`)，iOS 27.0。
- 两台设备只归当前 primary agent 所有；批次结束后已分别 terminate app、shutdown、delete，
  并确认没有对应 TestManager、UI runner、应用进程或 Booted 设备残留。
- 批次打开的 Simulator 与 Problem Reporter 已退出；未终止其他 agent 所有的设备或进程。
- 基线 macOS 测试使用独立 `/tmp/TimeTrackerTask07*` DerivedData/result bundle；测试完成后无
  残留 `xcodebuild`/`xctest`，保留本任务 result bundle 与截图作为验收证据。

## 基线验证

- `StoreScopedTaskLifecycleCommandCoordinatorTests` + `LocalizationContractTests`：
  17 passed，0 failed。
- 完整 `TaskUIContractTests`：40 passed，0 failed。
- 两次均使用 Apple Development 签名，没有关闭 code signing。
- 基线证明历史实现可编译、现有归档链路成立；它不覆盖上面列出的剩余语义缺口。

## 红绿测试记录

- 红测：`TaskUIContractTests`、`LocalizationContractTests`、
  `PlatformShellContractTests` 与 `CoreDeepLinkRoutingTests` 按预期在菜单、Unarchive、
  macOS 命令、Unavailable 文案和 archived deep link 上失败；其他同批测试通过。
- 领域红测：旧实现下，archive 与 unarchive 都会输给未来 7 天的同 UUID 副本。
- 领域绿测：完整 `StoreScopedTaskLifecycleCommandCoordinatorTests` 12 passed、0 failed；
  新增测试同时验证严格占优时间、archive 状态和 `deletedAt == nil`。
- 产品绿测：Task UI、Localization、Platform Shell、Deep Link、Core Task、Analytics Timeline
  与 Task Lifecycle 共 134 passed、0 failed；修正菜单分隔线后完整 `TaskUIContractTests`
  再次 40 passed、0 failed；补充归档父级的后代路由用例后完整
  `CoreDeepLinkRoutingTests` 29 passed、0 failed。
- 带 Apple Development 签名的 generic iOS Debug build 成功；bundle id
  `me.mezorewww.timetracker`，签名者 `ZEXUAN GAO`，使用
  `TimeTracker HealthKit Development` provisioning profile。

## 三平台 UI 验收

- iPhone：左滑展示蓝色系统 Archive 动作；归档后任务从列表消失；Settings 的归档列表展示
  `archivebox` 与可见的 `Unarchive` 按钮；解除归档后任务恢复。结果：
  `/tmp/TimeTrackerTask07UI-iPhone.xcresult`。
- iPad：同一普通路径通过，Settings 使用 split navigation 返回而不是不存在的 Done；截图
  前缀正确为 `ipad`。结果：`/tmp/TimeTrackerTask07UI-iPad-Final.xcresult`。
- macOS：右键菜单展示 Archive，菜单栏 `Task > Archive Selected Task` 可用；Settings
  展示可见 Unarchive；解除归档后主窗口任务恢复。结果：
  `/tmp/TimeTrackerTask07UI-Mac.xcresult`。
- 已逐张目视检查三平台关键截图：滑动动作、context menu、菜单栏命令、归档列表空/非空及
  恢复状态均符合 HIG；iOS 交互目标至少 44pt，macOS 至少 28pt。
- macOS 首次回归暴露 UI test fallback 主窗口与 Settings 使用不同 Store/container，导致
  归档状态不一致。已让正常窗口、Settings 与 fallback 共享唯一的
  `applicationStore`/`applicationModelContainer`。不在 Settings scene 额外执行全量刷新，
  以免绕过 Cloud recovery 的只读刷新安全边界。
- 最终相关源码契约 51 passed、0 failed。包含共享 Store/container、Settings 不执行
  `refreshQuietly()`、可见 Unarchive 与三平台归档 UI 契约。
- 扩大运行三组契约时为 57 passed、1 failed；唯一失败是既有
  `cloudActivityIsRecordedOnlyAfterConflictProcessingAndFinalRefresh` 对
  `errorMessage =` 的源码字符串断言，与本次归档代码及新增安全断言无关，未擅自修改。

## Release 安装与签名

- 按用户指定原样运行 `CONFIGURATION=Release scripts/build_install_all.sh`，iOS/Watch 与
  universal macOS 两次 Release build 均 `BUILD SUCCEEDED`，没有关闭 code signing。
- iOS 主应用和内嵌 Watch companion 均通过 `codesign --verify --deep --strict`；companion
  bundle id 为 `me.mezorewww.timetracker.watchkitapp`，并正确声明依赖 iPhone companion。
- Release 已安装到实体 `iPad Pro M4` 与 `iPhone Air`。随后分别用 `devicectl device info
  apps` 查询，两台设备均报告 bundle id `me.mezorewww.timetracker`、版本 `1.1.52`
  (`107`) 且为 Developer App。
- macOS Release 已替换 `/Applications/timetracker.app`；独立严格签名复核通过，Identifier
  为 `me.mezorewww.timetracker`，TeamIdentifier 为 `LT98S43NKA`，签名者为
  `Apple Development: ZEXUAN GAO (PX46M259V3)`，版本同为 `1.1.52` (`107`)。
- iOS 与 macOS 的 `AppBuildInfo.plist` 都指向应用代码 checkpoint
  `d7cfe9cc90a473fb4c4844ad0b4fb3fe73b1d278`。构建时 dirty 仅因用户尚未提交的
  `Docs/userfeedback.md` 内容，不影响应用源码。
- 没有可见的实体 Apple Watch，因此脚本无法现场核对 Watch provisioning profile 的设备
  覆盖；内嵌 companion 的结构与签名均已验证，配对 Watch 可在 Automatic App Install 开启
  后随 iPhone 安装。
- 收尾检查确认没有 owned `xcodebuild`、`xctest`、UI runner、应用测试进程或 Booted
  simulator 残留。

## Checkpoint 记录

- `55cc610`：领取当前反馈项，建立 `[~]`、独立实现记忆与活动软链接。
- `ab5af0d`：完成 archive-only 全面静态审计、基线验证、HIG/依赖决策与实现边界。
- `4b4785c`：修复 archive/unarchive 在未来时间戳重复副本下的 LWW 不变量。
- `42b326e`：统一任务归档菜单、Settings 恢复、macOS 命令、Unavailable 文案与
  deep-link 语义，并锁定领域/界面/本地化契约。
- `d7cfe9c`：完成三平台端到端 UI 回归、截图验收、macOS 共享状态修复与资源清理。
- [x] 最终 checkpoint：记录 Release 安装证据、标记反馈完成并移除活动软链接。
