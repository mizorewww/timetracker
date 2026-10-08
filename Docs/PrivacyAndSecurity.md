# TimeTracker 隐私与安全说明

状态：工程级数据流说明，非法律隐私政策

本文说明仓库当前实现如何存储和传输数据，并列出发行前安全门禁。最终上架文案仍需按实际发行地区、服务方与 App Store 隐私申报单独审核。

## 1. 数据清单

| 数据 | 本机存储 | 可能传输到 | 导出 |
| --- | --- | --- | --- |
| 任务、分类、收件箱、清单 | SwiftData | 用户的 CloudKit；启用建议时发送必要投影，明确生成任务计划时发送完整当前 Category/Task/Checklist 工作区到配置的 LLM 服务 | JSON |
| 时间片、番茄记录 | SwiftData | 用户的 CloudKit；Watch/Live Activity 使用必要状态投影 | JSON |
| 重复规则、每日生成回执、任务量目标与增量 | SwiftData | 用户的 CloudKit | JSON；旧快照缺少该表=未知，显式空数组=清空 |
| 普通设置 | SwiftData / UserDefaults | 部分偏好经 CloudKit 同步；iCloud enablement 仅限当前设备 | JSON 中的可同步偏好，不含设备本地开关 |
| 随机设备标识 | UserDefaults | 作为同步记录 metadata 进入 CloudKit | 可能随业务记录导出；不含主机名或账户名 |
| LLM API 密钥 | 本机 Keychain | 配置的 LLM endpoint 的 Authorization header | 不导出 |
| AI 自动建议同意 | 本机 UserDefaults | 不同步；开启后才允许客户端自动发送必要字段 | 不导出 |
| Widget / Watch 快照与命令 | App Group / 配对设备内存与队列 | Widget 扩展 / WatchConnectivity | 不作为独立备份 |
| 诊断与测试截图 | 开发环境文件 | 仅在维护者主动分享时 | 不属于应用 JSON |

## 2. 本机存储与秘密

业务实体存放在 SwiftData store；启用 iCloud 后同一业务模型可由 CloudKit 同步。持久容器无法建立时应用可能进入诊断或临时内存模式——内存模式的数据在进程结束后消失。当前 schema 是 V14；V9→V14 的迁移历史与“派生缓存移除但保留用户事实、旧 schema 冻结”规则见 [Architecture](Architecture.md)。Inbox identity 是随机值或 legacy record UUID，不含标题、规范化标题或哈希；recurrence/goal 的 deterministic identity 只由 UUID、规则日键和冻结时区计算，不含用户文本。

LLM API 密钥使用 Keychain generic password：AfterFirstUnlockThisDeviceOnly、明确关闭 Keychain 同步、不跟随 iCloud、不写入 SwiftData/UserDefaults/JSON 导出或普通日志。升级时若发现旧版本遗留的明文 key，只读取一次并迁移到 Keychain，之后清空 UserDefaults 值并软删除敏感 `SyncedPreference`；Keychain 与 SwiftData 不是同一事务——安全副本写入后 redaction 在原子 mutation 中提交，保存失败时 redaction 回滚而 Keychain 副本保留以便重试。新生成的 `DeviceIdentity` 仅由平台前缀 + 随机 UUID 组成，不使用主机名、账户名、硬件标识或可读设备名；Watch 在自身 defaults 持久化独立的 `watch-UUID`，它不是认证凭据，命令去重仍用随机 command UUID。

iOS 的同步权威状态、pending 恢复镜像和腐损隔离文件可能包含任务/偏好/账本快照，写入后使用 `FileProtectionType.completeUntilFirstUserAuthentication`（本次启动首次解锁前不可读，之后可后台使用）；macOS 不套用该属性，普通 file lock 不被当成用户快照。权威 state 限 128 MiB、recovery mirror/slot 限 64 MiB，读取先做 metadata 预检再只读 `limit+1` 防止 TOCTOU；损坏或超限的权威 state 隔离并要求显式恢复，损坏/超限的 pending mirror 单独隔离并忽略。精确规则见 [AgentDecisions](AgentDecisions.md) AD-023。

## 3. iCloud 与多设备

启用 iCloud 时，任务、时间事实、番茄、收件箱、清单及非敏感偏好可能进入用户的私有 CloudKit 数据库；密钥不参与同步，每台设备需单独配置。是否启用 iCloud 是当前设备的启动配置，只存本机 `UserDefaults`、修改后下次启动生效，不跨设备传播；历史 `TimeTrackerCloudSyncEnabled` 云端记录会在 preference 读取、冲突快照和导出/恢复边界被过滤。

多设备风险包括新旧版本同时写入不同 schema、离线设备稍后上传旧状态、强制上传/下载覆盖另一侧更新、删除与维护操作同步后传播。破坏性同步工具必须带确认、显示方向与范围并在执行后提示等待同步或重启；应用不得把容器 fallback 误报为 CloudKit 成功。

## 4. AI 请求

应用向用户配置的 OpenAI-compatible endpoint 发起模型列表与聊天请求。设置采用 Test→Save 草稿：输入 endpoint/API key 不逐字持久化，“测试连接”发送带凭证的模型列表请求但不保存，选模型并“保存”后才写入偏好和 Keychain；endpoint/模型列表/已选模型/思考强度作为一次 SwiftData 偏好提交，Keychain 是独立安全存储，偏好提交失败时尽力恢复旧密钥并单独报告补偿失败。自动建议是默认关闭的本机开关，只有另行开启后才为 Inbox/checklist 自动发送内容；手动生成任务计划仍是一次明确请求。

请求内容：

- **Inbox 建议**：收件箱标题、候选任务 UUID、候选任务标题与层级路径、图标名与颜色十六进制值。包含全部可工作的 Task 和全部可见 Category，只做规范化/去重/确定性排序，不按人工数量、JSON 或字段预算静默丢弃。
- **Checklist 视觉建议**：清单标题、所属任务标题与完整任务显示路径、允许的图标名与颜色列表。连续编辑采用本机 latest-input debounce 并取消已过期的 pending/in-flight 工作，只接受仍匹配最新标题、task path 与本地 revision 的响应；取消不能撤回 endpoint 已接收的数据，也不等同远端删除。用户手动选择的图标/颜色始终优先。
- **任务计划生成**：只在用户填写需求并明确点按“生成”后发出。Request 页先显示当前 Category/Task/Checklist 数量；内容包括当次完整需求、完整的任务规划指令（可同步/导出的普通偏好，按 256 KiB 编码边界验证，不是秘密）、允许的完整规范图标名与颜色列表，以及完整的 provider-visible 当前工作区（Category、Task、Checklist 的稳定 UUID、完整标题/备注、完整父级路径、关系、预计时长、图标/颜色、排序、归档状态、任务量目标与重复设置），不按任意实体数量或路径深度静默截断；还包含同一份工作区内容的确定性 `contextFingerprint`，用于把请求与审阅绑定。

工作区 prompt 不包含 Inbox 内容、时间历史、Pomodoro 历史、Keychain 数据、设备 ID、同步 metadata 或任何 `clientMutationID`；本地 revision map 与完整 CAS baseline 只留在内存。API key 不进入 prompt 或工具结果，但按配置作为 Authorization header 发给 endpoint。编码失败不会发出 partial context；endpoint 以 HTTP 400/413/422 拒绝完整请求时以 typed error 报告三类实体 counts 与实际 encoded bytes，客户端不发送截断版也不回退旧 create-only JSON。思考强度是可同步/导出的普通偏好，只允许 DeepSeek 官方 `high`/`max`、默认 `high`；三个生产功能在 DeepSeek V4 下都发送 `thinking.type=enabled` + 当前 effort 并省略 temperature，任务规划还省略 thinking 不支持的 `tool_choice`，工具调用后的 `reasoning_content` 在同一次会话后续请求中完整回传但只用于该次临时预览，不持久化/同步/导出/记录日志；切换 effort 会取消旧请求。模型只能通过严格结构化工具读取/修改一个本机内存 overlay，不能直接访问 SwiftData；已有 Task/Checklist 按稳定 UUID 引用，Category 名称只有唯一规范化匹配时才可复用；Finalize 只产生只读 diff，破坏性影响需再次确认，Apply 在共享 store lock 下对完整 provider-visible snapshot 与本地 revision baseline 做 CAS 后原子应用，Task removal 只 Archive，任何 stale/校验/保存失败均零写入并保留预览。完整规则见 [AgentDecisions](AgentDecisions.md) AD-132。

**凭证与传输**：API key 仅放入 Authorization header；远程地址必须 HTTPS，HTTP 仅允许 localhost / `.localhost` 保留主机及经数值解析确认的 `127.0.0.0/8`/`::1`（字符串前缀不能接受 `127.evil.com`）；带 Authorization 的重定向只允许 scheme/host/有效端口完全相同。响应经禁用缓存与 cookie 的 ephemeral 会话读取，资源超时 60 秒，Content-Length 与实际正文都限制 2 MiB，非 2xx 在 headers 后立即取消。所有 AI 流程的 model ID 为 256 bytes、endpoint/API key 分别最多 4/8 KiB；模型 reason 按 512-byte 持久化字段归一化，icon 必须属于本次已公告目录，task/category UUID 必须属于实际发送候选。请求、响应与错误日志不得输出密钥，生产诊断避免记录完整用户文本。

选择第三方 endpoint 即授权其按条款处理上述字段；应用只能控制客户端发送边界，不能保证第三方不记录或训练。发行前必须为实际默认/推荐 endpoint 确认并披露运营主体、处理目的、传输地区、日志/内容保留期、训练用途、用户删除渠道与服务条款版本；未锁定则不得以“内容不保留”等措辞发布，自定义 endpoint 也必须在 UI 提醒用户自行审查政策。

## 5. 系统扩展数据流

提交后更新由 store-scoped projection scheduler 异步追赶（见 AD-142），只改变执行时机与本机恢复 metadata，不改变任何扩展 DTO、字段、接收方、App Group、WatchConnectivity 或 ActivityKit payload；单 sink 失败不会让已提交业务动作变成可重试失败。

- **Live Activity** 接收当前计时的最小展示状态，不是事实存储；锁屏与灵动岛只展示任务身份与经过时间，点按只打开主应用“今日”，扩展没有停止按钮，也不直接执行 SwiftData/CloudKit 或其它持久 mutation。
- **Widget** 通过 `group.me.mezorewww.timetracker` 共享版本化快照（自动签名 profile 已含该能力）。Producer 用 Unicode-safe prefix、summary/start clamp、count cap 与 128 KiB 文本预算把投影整形到传输范围，不修改 canonical facts；快照在写入和读取都按不可信输入验证（256 KiB 编码上限、active/recent 各 64 项、有界 UTF-8 字段、有限日期/统计、唯一 ID），非法读取显示 corrupted 而不回退到 standard UserDefaults 或空数据。仍需真机验证共享读写与刷新；不得用临时公共文件、UserDefaults suite fallback 或关闭 sandbox 绕过。
- **Watch** 在配对设备间传输任务/计时快照与用户命令。命令队列持久保存在 Watch 本机，每个 command ID 是幂等键；命令与手机 terminal result 都走 durable `transferUserInfo`，可达消息只用于加速。20 秒超时由用户重试或丢弃，重试保留原 ID 并刷新发送时间；手机在写账本前拒绝超过 30 秒的旧命令。payload 与恢复队列是不可信边界：状态快照最多 64 active/256 recent、共用 128 KiB 文本预算，Watch 待处理/失败各 64 项、持久队列编码最大 512 KiB；非法/重复/过大的恢复状态会被清除，pending overflow 进入可见 failure。DTO 最小化，不含 API key。
- **App Intents** 把系统参数传入共享领域命令，结果不回显密钥或内部诊断。持久 mutation 提交后只 enqueue exact events，sync snapshot 与系统表面在后台从 fresh context 重放当前事实，Intent 不等待或同步生成 payload；请求来源显式区分本地提交、启动补偿与表面补投影，remote import 不得被记录成本机 mutation。
- **Deep links**：应用只接受 `timetracker` scheme、最长 2,048 bytes、无 credential/port/fragment 的白名单 host/path/query 并校验 UUID；数据库未就绪时每个 scene 最多保留 16 个按语义去重的合法动作，scene 关闭时清空。链接不能携带 API key，也不能绕过归档、历史 tombstone 或不存在任务的可工作性检查。

## 6. JSON 导出

用户主动发起的导出使用版本化 `timetracker.cloudSyncedData` envelope，包含过滤敏感 preference 后的可同步业务快照，不会自动上传。当前不存在 importer、校验和、签名、加密或事务恢复，所以它不是可恢复备份，可能包含任务名称与详细时间记录，应保存到用户信任的位置，不应在工单、日志或公开仓库中直接上传。未来备份格式至少需要版本、校验和、导入预检、冲突策略、staging/回滚和恢复等价性测试。

## 7. 归档、tombstone 与恢复边界

- 普通任务只提供可逆的 Archive/Restore，不提供单项 Delete；归档不擦除关联历史，也不在仍有活动 timer/Pomodoro 时静默停止工作。
- `TaskNode.deletedAt` 只作为旧客户端、CloudKit/import、权威重置/恢复与 LWW 去重的兼容 tombstone，必须继续随快照同步并保留历史账本关系。
- 普通 Local/iCloud/local-fallback/emergency 生产 store 永不物理 purge tombstone（CloudKit 没有每台离线设备的删除确认，过早清理可能让旧设备复活数据），生产 UI 因此不显示永久清理入口；只有隔离的 Demo/UI Test store 允许在测试中清理超过保留期的完整 tombstone graph。可见 orphan 可能只是分阶段 CloudKit import，不能仅因暂时缺少父记录就删除。
- 演示数据写入（seed/rebuild）必须同时满足 DEBUG 构建**和**当前打开的是隔离 demo store；出厂 `off` 时打开的是生产 CloudKit store，在那里 rebuild 会先给用户全部行打 tombstone 再写入演示行并同步到用户 iCloud。
- 测试进程不得触碰正式 App 状态：macOS target 未开启 sandbox，`xctest` 宿主与已安装 app 共用 preferences domain、Application Support 与 App Group 容器，因此 App 与测试一律通过 `AppDefaults.shared`/`AppRuntimeEnvironment` 访问，`SyncConflictService` 状态目录与 widget 快照 suite 在测试宿主下另起命名空间。
- `make build-install-all` 默认 Release；Debug 二进制定义 `DEBUG` 并解锁演示数据与冒烟入口。“清空全部数据”还会删除本机 Keychain API key 与设备本地自动建议同意，业务数据清理失败时尽力恢复；不切换设备本地 iCloud 启动开关。当前 JSON 无法恢复这些操作。

## 8. 隐私清单与平台声明

主应用、Widget 和 Watch 目录各含 `PrivacyInfo.xcprivacy`，由各 target 的 file-system-synchronized group 纳入。当前 UserDefaults Required Reason 声明为主 App `1C8F.1` 与 `CA92.1`、Widget `1C8F.1`、Watch `CA92.1`；Live Activity extension 当前没有独立 manifest，发行审核必须确认它没有需要声明的 Required Reason API，或在需要时补自己的 manifest。主应用、Widget 与 Live Activity 的手写 `Info.plist` 是对应 synchronized group 的显式 membership exception；Watch 用生成的 Info.plist。最终 Archive 必须检查每个产物的 manifest/合并结果与实际 API/SDK 一致。隐私清单不能替代 App Store 隐私标签、AI/CloudKit 数据流披露或法律政策。每次新增 SDK、持久标识符、分析、网络服务或 Required Reason API 时重新审核所有 target 和扩展。

## 9. 威胁边界与工程规则

重点威胁：密钥被普通偏好/同步/导出/日志泄露；用户数据被不安全 endpoint 窃听；CloudKit 或 breaking migration 静默丢失数据；Widget/Watch 共享格式无版本导致错误解释；测试 fixture/截图进入版本库并携带真实数据；大量第三方依赖扩大供应链与隐私申报面。

1. 默认不记录 secret 和完整用户内容。
2. 新 secret 默认进入 device-only Keychain。
3. 新网络字段必须更新本文并有用户可理解的披露。
4. 新依赖必须评估许可证、维护、安全、隐私清单与可删除性。
5. destructive migration 必须有 fixture、验证和明确回滚边界。
6. 安全失败应 fail closed；不能以便利为由退回明文或任意 HTTP。
7. 本机 `DeviceIdentity` 只能是当前平台前缀与随机规范 UUID，不采集主机名/账户名/硬件标识，持久值异常时重新生成。

## 10. 发行前检查

- [ ] Keychain round-trip、遗留迁移、清空全部数据的秘密/同意清理与失败补偿、导出过滤测试通过；搜索日志/fixture/示例确认无真实 secret。
- [ ] 远程 HTTP endpoint、伪装 loopback、跨源 redirect 和 HTTPS 降级被拒绝；合法 loopback 与同源 redirect 按预期允许。
- [ ] PrivacyInfo 已加入正确 target 并通过归档验证；`1C8F.1`/`CA92.1` 与各 target 实际 UserDefaults/App Group 用途一致；iOS 同步权威状态/恢复镜像/腐损隔离文件的 protection attribute 为 `completeUntilFirstUserAuthentication`。
- [ ] App Store 隐私标签与 AI/CloudKit 实际数据流一致；AI 默认/推荐 endpoint 的运营方、用途、保留期、训练用途、跨境处理与删除渠道已确认并写入披露（未确认不作“零保留”承诺）；配置 Test→Save、自动建议默认关闭通过测试。
- [ ] Inbox/checklist 完整序列化全部候选/Unicode 字段/完整 SF Symbols 目录、非候选 UUID 拒绝、opaque model ID 与结果持久化边界通过回归；任务计划的 counts 披露、完整 workspace/fingerprint、counts+bytes typed failure、严格工具协议、只读 diff、破坏性确认、完整 CAS、stale 预览保留与原子回滚通过回归。
- [ ] Widget App Group 在真机/发行 profile 验证；Watch DTO 无 secret，codec/queue 边界通过自动测试，持久离线队列、typed terminal result、20 秒 timeout、30 秒旧命令拒绝、retry/discard 与同 ID 幂等在配对真机通过。
- [ ] V8→V9 `DailySummary` 移除与 V9→V10 Inbox identity/dismissal 迁移在真实磁盘 fixture 保留用户事实，旧快照缺新字段时可兼容恢复；导出文案明确“不是备份”。

## 11. 用户建议

- 只配置可信的 AI 服务并阅读其隐私政策；不要把 JSON 导出发布到公共位置；每台设备单独设置 API key。
- 执行强制同步或清理前先确认其它设备已完成同步；若显示临时内存模式，停止录入重要数据并先排查。

相关资料：[用户操作手册](UserGuide.md)、[Agent 决策](AgentDecisions.md)、[架构](Architecture.md)、[Versioning](Versioning.md)。
