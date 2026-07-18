# TimeTracker 隐私与安全说明

状态：工程级数据流说明，非法律隐私政策
校对日期：2026-07-18

本文说明仓库当前实现如何存储和传输数据，并列出发行前安全门禁。最终上架文案仍需根据实际发行地区、服务方和 App Store 隐私申报单独审核。

## 1. 数据清单

| 数据 | 本机存储 | 可能传输到 | 导出 |
| --- | --- | --- | --- |
| 任务、分类、收件箱、清单 | SwiftData | 用户的 CloudKit；启用 AI 时的部分字段发送到配置的 LLM 服务 | JSON |
| 时间片、番茄记录 | SwiftData | 用户的 CloudKit；Watch/Live Activity 使用必要状态投影 | JSON |
| 普通设置 | SwiftData / UserDefaults | 部分偏好通过 CloudKit 同步；iCloud enablement 仅限当前设备 | JSON 中的可同步偏好，不含设备本地开关 |
| 随机设备标识 | UserDefaults | 作为同步记录 metadata 进入 CloudKit | 可能随业务记录导出；不包含主机名或账户名 |
| LLM API 密钥 | 本机 Keychain | 配置的 LLM endpoint 的 Authorization header | 不导出 |
| AI 自动建议同意 | 本机 UserDefaults | 不同步；开启后才允许客户端自动向已配置 endpoint 发送必要字段 | 不导出 |
| Widget 快照 | App Group 共享容器 | 同一设备的小组件扩展 | 不作为独立备份 |
| Watch 快照和命令 | 主应用与 Watch 内存/队列 | 配对设备之间的 WatchConnectivity | 不作为独立备份 |
| 诊断与测试截图 | 开发环境文件 | 仅在维护者主动分享时 | 不属于应用 JSON |

## 2. 本机存储

业务实体存放在 SwiftData store。启用 iCloud 后，同一业务模型可由 CloudKit 同步。应用可能在持久容器无法建立时进入诊断或临时内存模式；内存模式的数据在进程结束后消失。

当前 V10 schema 不再持久化或同步 `DailySummary` 派生缓存。V8→V9 lightweight migration 会删除这份可重建 cache，但保留任务、时间账本、Pomodoro、checklist、Inbox、分类、倒计时和偏好等用户事实；分析摘要在内存中从 ledger 重建。V9→V10 为 Inbox AI dismissal 增加可同步的不透明 context/revision UUID。它们是随机值或 legacy record UUID，不包含标题、规范化标题或标题哈希；每条记录只保存固定数量字段。Legacy 类型只用于读取旧 store，不应重新进入当前导出或 CloudKit registry。

LLM API 密钥使用 Keychain generic password：

- 可访问级别为 AfterFirstUnlockThisDeviceOnly。
- 明确关闭 Keychain 同步。
- 不跟随 iCloud 到其他设备。
- 不写入 SwiftData、UserDefaults、JSON 导出或普通诊断日志。

升级时若发现旧版本遗留的明文 API key，只允许读取一次并迁移到 Keychain，之后清空 UserDefaults 值并软删除敏感 SyncedPreference。Keychain 与 SwiftData 不是同一个事务：安全副本写入后，SwiftData redaction 在原子 mutation 中提交；若保存失败，redaction 会回滚而 Keychain 副本保留，后续启动可安全重试。迁移失败应报告错误，不应继续把明文当作正常存储。

新生成的 `DeviceIdentity` 仅由平台前缀和随机 UUID 组成，不使用 Mac 主机名、账户名或用户可读设备名称。

iOS 的 `SyncConflictState.json`、pending forced-upload 恢复镜像和腐损状态隔离文件可能包含任务、偏好或账本快照。写入后都使用 `FileProtectionType.completeUntilFirstUserAuthentication`：设备本次启动首次解锁前不可读，首次解锁后即使再次锁屏也可供后台 Shortcuts/CloudKit 协调使用。macOS 不使用这项 iOS Data Protection 属性；普通 file lock 本身不被当成用户快照。权威 state 读写限 128 MiB，recovery mirror 限 64 MiB；metadata 预检后仍只通过 `FileHandle` 读取 `limit + 1`，防止文件增长 TOCTOU 造成无界内存占用。写端在解析路径或触盘前先编码并验证 state 与 mirror；任一超限都保留旧的有效文件，独立 mirror rewrite 也会在最终写入边界复检。损坏或超限的权威 state 会隔离并要求显式恢复；损坏或超限的 pending mirror 会单独隔离并忽略，既不覆盖权威 state，也不阻塞仍可使用的主库。超限文件隔离不会整份载入内存。

## 3. iCloud 与多设备

启用 iCloud 时，任务、时间事实、番茄、收件箱、清单及非敏感偏好可能进入用户的私有 CloudKit 数据库。密钥不参与同步，因此每台设备必须单独配置。

是否启用 iCloud 是当前设备的启动配置，只保存在本机 `UserDefaults`，修改后下次启动生效。该开关不会跨设备传播；历史 `TimeTrackerCloudSyncEnabled` 云端记录会在 preference 读取、冲突快照和导出/恢复边界被过滤。

多设备风险包括：

- 新旧应用版本同时写入不同 schema。
- 离线设备稍后上传旧状态。
- 强制上传或下载覆盖另一侧的更新。
- 删除和维护操作在同步后传播。

破坏性同步工具必须带确认、显示方向和范围，并在执行后提示等待同步或重启。应用不得把容器 fallback 误报为 CloudKit 成功。

## 4. AI 请求

应用向用户配置的 OpenAI-compatible endpoint 发起模型列表和聊天请求。

设置采用 Test→Save 草稿：在配置 sheet 中输入 endpoint/API key 不会逐字持久化；“测试连接”会向该 endpoint 发送带凭证的模型列表请求，但不会保存；用户选择模型并点击“保存”后才写入偏好和 Keychain。endpoint、模型列表和已选模型作为一次 SwiftData 偏好提交，Keychain 则是独立安全存储；偏好提交失败时应用尽力恢复旧密钥，补偿失败会单独报告，因此这不是跨存储 ACID transaction。自动建议是默认关闭的本机开关，只有用户另行开启后才会为 Inbox/checklist 自动发送内容。手动点击建议或从任务页生成任务计划仍是一次明确请求。

### 收件箱任务建议

请求可能包含：

- 收件箱标题。
- 候选任务 UUID。
- 候选任务标题与层级路径。
- 候选任务图标名与颜色十六进制值。

一次最多选取 48 个可工作任务，先保留 Quick Start 固定任务，再使用已有计时索引选高频/近期任务，最后才按稳定路径顺序补足。候选 JSON 最多 16 KiB；Inbox 标题最多 512 UTF-8 bytes，单个候选标题/路径最多 256/512 bytes。候选去重和取舍是输入顺序无关的确定结果。

### 清单视觉建议

请求可能包含：

- 清单标题。
- 所属任务标题与任务路径。
- 允许选择的系统图标名和颜色列表。

Checklist 标题与所属任务标题各最多 512 UTF-8 bytes，任务显示路径最多 1,024 bytes。Inbox 与 checklist 共用 78 个常见语义 SF Symbols 的精选发送列表，不会把完整的 8,000+ 图标目录附在每个请求中；这不会缩减用户本机图标选择器。

### 任务计划生成

请求只在用户从任务页填写需求并明确点按“生成”后发出，可能包含：

- 用户当次输入的计划需求，最多 4 KiB UTF-8 bytes。
- “任务规划指令”设置，最多 4 KiB UTF-8 bytes。它是可同步、可导出的普通偏好，不是秘密；不应填写密码或 API key。
- 允许模型使用的精选系统图标名和颜色列表。

请求不包含现有任务库、历史时间记录、Inbox 或 checklist 内容。固定 system contract 要求模型只返回分类、任务和 checklist 的 flat JSON 草稿；响应正文在服务层再限制为 128 KiB，并校验引用、层级、字段及 8 个分类、64 个任务、每任务 32/总计 256 个 checklist 的数量上限。通过校验的结果只进入本机可编辑预览；用户点按“创建”后才在一个 SwiftData 事务中新增事实。该流程不会自动修改、删除或覆盖既有任务，任一步失败都不留下半份计划。

两类建议和任务计划生成的 user prompt 最多 24 KiB，最终 JSON request body 最多 32 KiB，model ID 256 bytes，endpoint/API key 分别最多 4/8 KiB。256-byte model ID 同时符合同步快照的 compact-field restore 上限，避免本机可写入的 AI provenance 无法恢复。用户文本只在发送副本中按完整 Unicode `Character` 边界缩短，不回写 SwiftData 事实。建议模型返回的 reason/model ID 再次有界化，icon 必须属于本次已公告的精选列表，任务 UUID 必须属于实际发送候选。

### 凭证与传输

- API key 仅放入 Authorization header。
- 远程服务地址必须使用 HTTPS。
- HTTP 仅允许 localhost、以 .localhost 结尾的保留主机，以及经数值解析确认的 ::1 和 127.0.0.0/8 回环地址；不能用字符串前缀接受 `127.evil.com` 等伪装主机。
- 携带 Authorization 的重定向只允许 scheme、host 和有效端口全部相同；跨源、端口变化和 HTTPS 降级会被拒绝。
- 响应通过禁用缓存与 cookie 的 ephemeral 会话流式读取；资源超时 60 秒，Content-Length 与实际读取正文都限制为 2 MiB。非 2xx 在 headers 后立即取消，不为错误页继续读取正文；用户取消会传递给底层网络 task。
- 选择第三方 endpoint 等同于授权该服务按其条款处理上述字段。
- 请求、响应和错误日志不得输出密钥；生产诊断应避免记录完整用户文本。

应用只能控制客户端发送边界，不能保证第三方服务不记录或训练。发行前必须为实际默认/推荐 endpoint 确认并披露：运营主体、处理目的、传输地区、日志/内容保留期、训练用途、用户删除渠道和服务条款版本。如果这些事实未锁定，AI 功能不得以“内容不保留”或类似措辞发布；自定义 endpoint 也必须在 UI 中提醒用户自行审查其政策。

应用应在发出请求前让用户理解字段范围。数据最小化要求是只发送完成当前建议必需的内容。

## 5. 系统扩展数据流

### Live Activity

Live Activity 接收当前计时的最小展示状态。它不是事实存储，系统终止活动不会删除主应用记录。锁屏和灵动岛只展示任务身份与经过时间；点按只打开主应用的“今日”，扩展没有停止按钮，也不直接执行 SwiftData、CloudKit 或其它持久 mutation。

### Widget

通过 `group.me.mezorewww.timetracker` App Group 共享版本化快照，主应用与 Widget 的自动签名 profile 已包含该能力。Producer 使用 Unicode-safe prefix、summary/start clamp、count cap 和 128 KiB 文本预算把投影整形到传输范围，不修改 canonical facts。快照在写入和读取都按不可信输入验证：256 KiB 编码上限、active/recent 各 64 项、有界 UTF-8 字段、有限日期/统计与唯一 ID；非法读取显示为 corrupted，不回退到 standard UserDefaults 或空数据。仍需真机验证共享读写与刷新；不得通过临时公共文件、UserDefaults suite fallback 或关闭 sandbox 来绕过。

### Watch

WatchConnectivity 在配对设备之间传输任务/计时快照和用户命令。命令队列持久保存在 Watch 本机，每个 command ID 是幂等键；命令和手机 terminal result 都走 durable `transferUserInfo`，可达消息只用于加速。20 秒超时后由用户重试或丢弃，重试保留原 ID 并刷新发送时间。手机在写账本前拒绝超过 30 秒的旧命令，避免长期离线消息迟到后改变当前计时；兼容快照反射也可确认旧手机已执行。DTO 应最小化，不包含 API key。

Watch payload 与 UserDefaults 恢复队列是不可信边界。Producer 对 state snapshot 使用 Unicode-safe 字段上限和 128 KiB 总文本预算。Codec 再验证有限时间、UTF-8 byte 长度、唯一 ID、非负 summary 和 active timer 年龄；state snapshot 最多 64 active/256 recent，incoming/pending/failed 各有 64 项容量，持久队列编码最大 512 KiB。非法、重复或过大的恢复状态会被清除，pending overflow 进入可见 failure，不会把任意大小的数据继续留在内存或迟后执行。

### App Intents

App Intents 把系统提供的用户参数传入共享领域命令。Intent 结果不得回显密钥或内部诊断详情。持久 mutation 提交后才生成同步/Widget/Watch/Live Activity 投影；投影刷新失败不会撤销事实，也不能把已提交动作伪装为失败并诱导系统重复执行。

### Deep links

Widget、Live Activity 和系统使用 `timetracker` URL 打开主应用。应用只接受最长 2,048 bytes、无 credential/port/fragment 的白名单 host/path/query，并校验 UUID；无效 URL 在执行或排队前即被拒绝。数据库尚未准备好时，每个 scene 最多保留 16 个按语义去重的合法动作，scene 关闭时清空。链接不能携带 API key，也不能绕过归档、删除或不存在任务的可工作性检查；Checklist 完成不构成工作阻止。

## 6. JSON 导出

JSON 导出包含可同步业务数据的快照，并过滤敏感 preference。当前不存在 importer、校验和、签名、加密或事务恢复，所以它：

- 不是可恢复备份。
- 可能包含任务名称和详细时间记录等个人信息。
- 应保存到用户信任的位置。
- 不应在工单、日志或公开仓库中直接上传。

未来备份格式至少需要版本、校验和、导入预检、冲突策略、staging/回滚和恢复等价性测试。

## 7. 删除与恢复边界

- 删除任务不等同于立即擦除全部关联历史。
- 普通 Local、iCloud、local-fallback 和 emergency 生产 store 永不物理 purge tombstone。CloudKit 没有每台离线设备的删除确认，过早清理可能让旧设备复活数据；生产 UI 因此不显示永久清理入口。
- 只有隔离的 Demo/UI Test store 允许在测试中物理清理超过保留期的完整 tombstone graph。可见 orphan 可能只是分阶段 CloudKit import，不能仅因暂时缺少父记录就删除。
- 清空、替换、重置演示数据和强制 iCloud 操作都可能造成不可逆变化。
- “清空全部数据”还会删除本机 Keychain API key 和设备本地的自动建议同意；若业务数据清理失败，应用会尽力恢复之前的外部存储值。该动作不会切换设备本地的 iCloud 启动开关。
- 当前 JSON 无法恢复这些操作。

所有永久性操作都应显示对象范围、设备/云端影响和不可恢复警告。

## 8. 隐私清单与平台声明

主应用、Widget 和 Watch 目录当前各自包含 `PrivacyInfo.xcprivacy`，并由各 target 的 Xcode file-system-synchronized group 纳入。当前 UserDefaults Required Reason 声明为：主 App `1C8F.1` 与 `CA92.1`，Widget `1C8F.1`，Watch `CA92.1`。Live Activity extension 当前没有独立 manifest；发行审核必须确认它没有需要声明的 Required Reason API，或在需要时补自己的 manifest。主应用、Widget 与 Live Activity 的手写 `Info.plist` 都是对应 synchronized group 的显式 membership exception；Watch 使用生成的 Info.plist。最终 Archive 必须检查每个产物的 manifest/合并结果与实际 API/SDK 一致。Privacy manifest 不能替代 App Store 隐私标签、AI/CloudKit 数据流披露或法律政策。

每次添加 SDK、持久标识符、分析、网络服务或新的 Required Reason API 时，重新审核所有 target 和扩展，不只审核主应用。

## 9. 威胁边界与工程规则

当前重点威胁：

- 密钥被普通偏好、同步、导出或日志泄露。
- 用户数据被不安全 endpoint 窃听。
- CloudKit 或 breaking migration 静默丢失数据。
- Widget/Watch 共享格式无版本导致错误解释。
- 测试 fixture 或截图进入版本库并携带真实数据。
- 大量第三方依赖扩大供应链和隐私申报面。

工程规则：

1. 默认不记录 secret 和完整用户内容。
2. 新 secret 默认进入 device-only Keychain。
3. 新网络字段必须更新本文并有用户可理解的披露。
4. 新依赖必须评估许可证、维护、安全、隐私清单和可删除性。
5. destructive migration 必须有 fixture、验证和明确回滚边界。
6. 安全失败应 fail closed；不能以便利为由退回明文或任意 HTTP。
7. 本机 `DeviceIdentity` 只能是当前平台前缀与随机规范 UUID；不采集主机名、账户名或硬件标识，持久值异常时重新生成。

## 10. 发行前检查

- [ ] Keychain、遗留迁移、清空全部数据的本机秘密/同意清理与失败补偿、导出过滤测试通过。
- [ ] 搜索日志、fixture 和示例代码，确认没有真实 secret。
- [ ] 远程 HTTP endpoint、伪装 loopback、跨源 redirect 和 HTTPS 降级被拒绝，合法 loopback 与同源 redirect 按预期允许。
- [ ] PrivacyInfo 文件已加入正确 target 并通过归档验证。
- [ ] 主 App `1C8F.1`/`CA92.1`、Widget `1C8F.1`、Watch `CA92.1` 与各 target 的实际 UserDefaults/App Group 用途一致。
- [ ] iOS 同步权威状态、恢复镜像和腐损隔离文件的 protection attribute 为 `completeUntilFirstUserAuthentication`，且首次解锁前/后的后台行为符合预期。
- [ ] App Store 隐私标签与 AI/CloudKit 实际数据流一致。
- [ ] AI 默认/推荐 endpoint 的运营方、用途、保留期、训练用途、跨境处理与删除渠道已确认并写入发行披露；未确认时不作“零保留”承诺。
- [ ] AI 配置 Test→Save、自动建议默认关闭和用户显式开启行为通过测试/人工检查。
- [ ] Inbox/checklist 请求的候选数、字段/prompt/body UTF-8 预算、精选图标列表、非候选 UUID 拒绝和结果字段归一化通过回归。
- [ ] 任务计划的显式生成、可编辑预览、同步指令、字段/数量/层级上限、原子创建回滚和幂等重放通过回归。
- [ ] Widget App Group 在真机和发行 profile 上验证。
- [ ] Watch DTO 不包含 secret；codec/queue 的字段、数量、唯一 ID、时间和 512 KiB 恢复边界通过自动测试；持久离线队列、typed terminal result、20 秒 timeout、30 秒旧命令拒绝、retry/discard 和同 ID 幂等通过配对真机验证。
- [ ] V8→V9 `DailySummary` cache 移除与 V9→V10 Inbox suggestion identity/dismissal 迁移都在真实磁盘 fixture 上保留用户事实；旧 JSON 快照缺少新 UUID 字段时也能兼容恢复。
- [ ] 导出文案明确“不是备份”。

## 11. 用户建议

- 只配置可信的 AI 服务，并阅读其隐私政策。
- 不要把 JSON 导出发布到公共位置。
- 每台设备单独设置 API key。
- 执行强制同步或清理前先确认其他设备已完成同步。
- 若应用显示临时内存模式，停止录入重要数据并先排查。

相关资料：[用户操作手册](UserGuide.md)、[Agent 决策](AgentDecisions.md)、[版本与迁移](Versioning.md)。
