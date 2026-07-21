# 09：Live Activity 与灵动岛可见性实现记忆

> 本文件只保存实现、验证和子代理编排记忆，不是任务来源。范围与完成状态必须重新读取
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中唯一的 `[~]` 项。

## 当前阶段

- [x] 已按文档顺序领取 Live Activity / 灵动岛不可见反馈。
- [x] 已审计 ActivityKit 能力、系统资格条件、请求/更新/结束生命周期与展示 UI。
- [x] 已完成错误分类、可观察运行状态与保留目标重试基础 checkpoint。
- [x] 已把 ActivityKit 运行边界改造成可注入、可验证的生命周期客户端。
- [x] 已实现 Settings 诊断状态与系统表面 UI 测试就绪门槛。
- [x] Settings 与恢复逻辑已跟随 ActivityKit 的真实生命周期，而非只依赖请求成功。
- [x] 已解除把内容 freshness、累计计时上限与单实例 8 小时生命周期错误绑定的问题。
- [x] 已以 simulator-only 截图验收锁屏与灵动岛的长计时持续展示。
- [~] 正在执行最终 Release 全设备安装、签名和版本验证。
- 下一 checkpoint：运行用户指定的 `CONFIGURATION=Release scripts/build_install_all.sh`，核对产物与安装版本并清理临时资源。

## 反馈边界

- 用户当前看不到 Live Activity 和灵动岛，需要判断是功能损坏还是资格条件导致失效。
- 修复必须覆盖实际请求、更新、结束和恢复链路，并清楚区分系统不支持、用户关闭与应用缺陷。
- 只处理 `Docs/userfeedback.md` 当前 `[~]` 项，不读取或领取后续反馈。

## 验收清单

- [x] 盘点 ActivityKit 配置、entitlement、Info.plist、扩展与 App Group/数据通路
- [x] 盘点请求、更新、结束、恢复和系统授权/资格判断
- [x] 用失败测试或可复现诊断锁定根因
- [x] 依照 Apple HIG 与 SwiftUI/ActivityKit 最佳实践实施最小修复
- [x] 验证 iPhone 锁屏、支持灵动岛的机型与降级路径并适当截图
- [~] 运行 `CONFIGURATION=Release scripts/build_install_all.sh`
- [ ] 核验安装版本与签名，释放 owned 设备、进程和临时产物
- [ ] 由 Codex 在 `Docs/userfeedback.md` 标记完成并移除活动软链接

## 初始实现约束

- 优先使用 ActivityKit、WidgetKit 与系统提供的状态/授权 API，不自建常驻后台或重复状态框架。
- 保留正式 Apple Developer 签名、entitlement 和 provisioning；验证不得通过关闭签名规避问题。
- 先证明失效条件和生命周期，再决定是否需要 UI、状态模型或持久化改动。

## 子代理编排

- [x] ActivityKit 配置、entitlement 与扩展静态审计：未发现本地 Live Activity 的 target、嵌入或 plist 硬错误。
- [x] 请求/更新/结束、计时状态投影与恢复链路审计：锁定 Watch 后台普通请求、静默授权失败与异步竞态。
- [x] Apple HIG、系统资格条件和跨设备验收矩阵审计：锁屏为基线，灵动岛仅在支持机型验收。

## 运行资源所有权

- Settings 系统表面批次 owned iPhone 17 Pro 模拟器：`EAE5FCDF-60EE-4C0F-915E-762AC1ADCC15`；验证后已关闭并删除。
- 用户已明确要求截图验收只使用 owned 模拟器；物理设备不用于截图，最终安装验证与截图验收分开处理。
- 先前物理机证据不再作为最终截图验收依据，对应临时截图会随 Task 09 构建产物清理。
- ActivityState 最终验证 owned iPhone 17 Pro 模拟器：`2424D763-9F34-4DFE-841D-5E83DC707588`；验证后已关闭并删除。
- 被 Xcode 测试基础设施污染的 owned 模拟器 `05EBE8E7-0A22-49C3-8EDD-D8AA65293B22` 及其隐式 clone 已关闭并删除。
- 长计时验证 owned iPhone 17 Pro 模拟器：`8668643E-2BB3-422F-9007-2A3653ABE790`；验证后已关闭并删除。
- 长计时系统表面截图 owned iPhone 17 Pro 模拟器：`251D2146-99C6-4C1F-9033-590D9AF58DAB`；验证后已关闭并删除。
- 后续每个设备批次记录唯一 UDID；批次结束后终止 App、关闭并删除 owned 设备，清理 Runner、构建和 trace 进程。
- 不触碰不属于 Task 09 的模拟器或进程。

## Checkpoint 记录

- [x] 领取反馈、建立实现记忆与活动链接：`1038b6c`。
- [x] 失败证据：新增恢复策略测试首次构建因缺少 `LiveActivityFailure` / `retryDesiredState()` 失败；在途重试测试首次以 exit 65 失败。
- [x] 恢复基础：新增平台中立的失败/恢复/状态模型；监听 ActivityKit 授权变化；保留失败目标并支持强制重放；多次在途重试合并为一次，更新目标优先。
- [x] 生命周期防护：无活动计时器时把保留的 `.active` 视作待清理工作，避免授权恢复后复活已停止计时；发布 `.active` 前重新检查授权。
- [x] 验证：macOS focused `LiveActivityRecoveryTests` 4/4 通过；正式签名配置下 generic iOS Debug build 通过；未启动模拟器。
- [x] 注入边界失败证据：iOS build-for-testing 首次因缺少 `LiveActivitySystemClient` / `LiveActivityRegistration` 以 exit 65 失败。
- [x] ActivityKit 客户端：原生 adapter 独占 `ActivityAuthorizationInfo`、注册列表与 request/update/end；Coordinator 可注入 fake，释放时取消授权观察。
- [x] 生命周期测试：物理 iPhone Air 上 10/10 通过，覆盖 12 类授权错误、关闭→恢复一次重试、后台失败显式重试、停止不复活、授权/停止与暂停 update 竞态、匹配快路和观察取消。
- [x] 资源清理：测试宿主已终止；无 owned `xcodebuild`、`xctest`、App Runner 或 Booted 模拟器残留。
- [x] Settings 诊断：General 显示 ready/synchronizing/registered 与 denied/unsupported/background/capacity/configuration/payload/system 分类；提供系统设置或显式重试操作，并明确注册不等于系统保证展示。
- [x] 失败证据：旧系统表面测试在物理 iPhone Air 通过 ActivityKit 注册门禁后，因找不到 compact 标题失败；录屏证明设备已有另一条 Live Activity，iOS 把 Time Tracker 降级为右侧 minimal 计时胶囊，计时从 `32:15` 增长到 `32:17`，属于测试假阴性而非未显示。
- [x] 系统表面测试：关闭 Settings 后重新确认计时器仍运行，等待主屏转场，保存 compact/minimal 截图；依次尝试可用岛区域并展开 Time Tracker，失败时先保留截图与 SpringBoard 层级。
- [x] 截图验证：owned iPhone 17 Pro 模拟器上注册状态、App 恢复、compact 与 expanded 四张截图目视通过；expanded 显示 `Read Apple HIG` 与持续计时。
- [x] 验证：iPhone 17 Pro 模拟器系统表面 UI 测试通过；`SystemSurfaceInteractionContractTests` 8/8、`LocalizationContractTests` 8/8 通过；曾由 macOS 门禁发现 iOS-only helper 条件编译遗漏，修复后复测通过。
- [x] 资源清理：owned 模拟器已关闭删除；物理测试 App/appex 与所有 owned `xcodebuild`、`xctest`、Runner 已释放，未触碰 AnalyticsReview 模拟器或设备上的其他活动。
- [x] ActivityState 适配：逐项映射 pending/active/stale/ended/dismissed；生产 client 缓存同一 `Activity` 实例后订阅状态流，避免按 ID 二次查找把移除误判为结束。
- [x] Coordinator 生命周期：只有真实 `.active` 才发布 registered；pending 保持同步；stale 串行更新；系统 ended 在计时仍运行时重建；用户 dismissed 等待 Settings 显式重试。
- [x] 竞态防护：停止计时立即取消 observer；挂起 update、授权切换和迟到 terminal 事件不能复活计时；自动授权恢复不会越过用户移除抑制。
- [x] Pending 内容修复：区分已实际应用与最新期望 request；pending 期间标题、路径或颜色变化会在 Activity 变为 active 后重放，不再永久显示旧内容。
- [x] Settings 新增三语“实时活动已被移除”诊断与重试恢复；计时器本身继续运行。
- [x] 验证：fresh owned iPhone 17 Pro 模拟器上生命周期/恢复 28/28、系统表面/本地化契约 16/16 通过；generic iOS Debug build-for-testing 通过（仅有仓库既有 Swift 6 警告）。
- [x] 资源清理：两台 owned 生命周期模拟器及隐式 clone 均已删除；无 owned `xcodebuild`、`xctest`、Runner、diagnostics 或 Booted 设备残留。
- [x] 长计时根因：删除把 `startedAt + 8h` 同时当作 freshness 与累计时长上限的策略；本地时钟派生内容不再设置 `staleDate`。
- [x] 计时呈现：锁屏、compact/minimal 与 expanded 改用 SwiftUI `SystemFormatStyle.Stopwatch`，保留原始 segment `startedAt`，秒级刷新且不在 8 小时冻结。
- [x] 兼容与文案：未改变 Activity attributes/content 编码结构；旧 stale activity 仍显示警示，但三语提示改为累计时间继续从原始开始时间计算。
- [x] 失败证据：反转后的 unbounded Stopwatch 源契约在旧实现上失败；单方法过滤 0 项与两次 TestManager 启动故障均未冒充产品红灯。
- [x] 验证：16 小时行为与生命周期/系统表面 33/33、Deep Link/本地化 36/36、macOS 源契约 8/8 通过；generic iOS Debug build-for-testing 通过。
- [x] 资源清理：owned 长计时模拟器、App/Widget、TestManager diagnostics、Runner 与构建进程均已释放；没有 Booted owned 设备。
- [x] 截图夹具：仅在专用 UI 测试参数下把 `Read Apple HIG` 计时起点设为 16 小时前，并先断言 App 内计时已超过 8 小时；普通 demo 与 Release 不受影响。
- [x] Simulator-only UI 验证：同一 owned iPhone 17 Pro 上系统表面测试连续 3 次 1/1 通过；最终稳定批次显示 App `16:00:18`、Dynamic Island compact `16:00:24`、expanded `16:00:30`。
- [x] 锁屏验证：Device Hub 选择同一显式 simulator UDID，完成系统两阶段 Live Activities 授权后重新注册；锁屏显示 `Read Apple HIG`、完整路径与 `16:01` 小时级累计时间。`simctl io screenshot` 在该 Xcode 27 beta 未合成系统活动层，最终使用 Device Hub 自带 Screenshot 保存完整锁屏证据。
- [x] 截图证据：`build/Task09SimulatorScreenshot/FinalScreenshots/`；对应 `Test3.xcresult` 附件均记录设备名与 UDID，四张最终图片已目视检查，无裁切、重叠或 stale 标记。
- [x] 资源清理：owned 模拟器已关闭删除，Device Hub 已退出；无 owned `xcodebuild`、`xctest`、UI Runner、App、诊断或 Booted 设备残留，未触碰 AnalyticsReview 模拟器。
- [~] 当前 checkpoint：执行 Release 全设备安装、签名与版本验证。
