# 09：Live Activity 与灵动岛可见性实现记忆

> 本文件只保存实现、验证和子代理编排记忆，不是任务来源。范围与完成状态必须重新读取
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中唯一的 `[~]` 项。

## 当前阶段

- [x] 已按文档顺序领取 Live Activity / 灵动岛不可见反馈。
- [x] 已审计 ActivityKit 能力、系统资格条件、请求/更新/结束生命周期与展示 UI。
- [x] 已完成错误分类、可观察运行状态与保留目标重试基础 checkpoint。
- [x] 已把 ActivityKit 运行边界改造成可注入、可验证的生命周期客户端。
- [~] 正在实现 Settings 诊断状态与系统表面 UI 测试就绪门槛。
- 下一 checkpoint：显示真实注册/关闭/后台重试/配置故障状态，并让 UI 测试等待 ActivityKit 请求完成。

## 反馈边界

- 用户当前看不到 Live Activity 和灵动岛，需要判断是功能损坏还是资格条件导致失效。
- 修复必须覆盖实际请求、更新、结束和恢复链路，并清楚区分系统不支持、用户关闭与应用缺陷。
- 只处理 `Docs/userfeedback.md` 当前 `[~]` 项，不读取或领取后续反馈。

## 验收清单

- [x] 盘点 ActivityKit 配置、entitlement、Info.plist、扩展与 App Group/数据通路
- [x] 盘点请求、更新、结束、恢复和系统授权/资格判断
- [x] 用失败测试或可复现诊断锁定根因
- [~] 依照 Apple HIG 与 SwiftUI/ActivityKit 最佳实践实施最小修复
- [ ] 验证 iPhone 锁屏、支持灵动岛的机型与降级路径并适当截图
- [ ] 运行 `CONFIGURATION=Release scripts/build_install_all.sh`
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

- 领取阶段不启动模拟器、TestManager 或 Instruments。
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
- [~] 当前 checkpoint：Settings 诊断状态、可操作恢复提示与 UI 测试就绪门槛。
