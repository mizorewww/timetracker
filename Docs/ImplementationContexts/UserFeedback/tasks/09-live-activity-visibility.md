# 09：Live Activity 与灵动岛可见性实现记忆

> 本文件只保存实现、验证和子代理编排记忆，不是任务来源。范围与完成状态必须重新读取
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中唯一的 `[~]` 项。

## 当前阶段

- [x] 已按文档顺序领取 Live Activity / 灵动岛不可见反馈。
- [~] 正在审计 ActivityKit 能力、系统资格条件、请求/更新/结束生命周期与展示 UI。
- 下一 checkpoint：形成可复现边界与失败测试，再提交第一项最小修复。

## 反馈边界

- 用户当前看不到 Live Activity 和灵动岛，需要判断是功能损坏还是资格条件导致失效。
- 修复必须覆盖实际请求、更新、结束和恢复链路，并清楚区分系统不支持、用户关闭与应用缺陷。
- 只处理 `Docs/userfeedback.md` 当前 `[~]` 项，不读取或领取后续反馈。

## 验收清单

- [~] 盘点 ActivityKit 配置、entitlement、Info.plist、扩展与 App Group/数据通路
- [ ] 盘点请求、更新、结束、恢复和系统授权/资格判断
- [ ] 用失败测试或可复现诊断锁定根因
- [ ] 依照 Apple HIG 与 SwiftUI/ActivityKit 最佳实践实施最小修复
- [ ] 验证 iPhone 锁屏、支持灵动岛的机型与降级路径并适当截图
- [ ] 运行 `CONFIGURATION=Release scripts/build_install_all.sh`
- [ ] 核验安装版本与签名，释放 owned 设备、进程和临时产物
- [ ] 由 Codex 在 `Docs/userfeedback.md` 标记完成并移除活动软链接

## 初始实现约束

- 优先使用 ActivityKit、WidgetKit 与系统提供的状态/授权 API，不自建常驻后台或重复状态框架。
- 保留正式 Apple Developer 签名、entitlement 和 provisioning；验证不得通过关闭签名规避问题。
- 先证明失效条件和生命周期，再决定是否需要 UI、状态模型或持久化改动。

## 子代理编排

- [~] ActivityKit 配置、entitlement 与扩展静态审计。
- [ ] 请求/更新/结束、计时状态投影与恢复链路审计。
- [ ] Apple HIG、系统资格条件和跨设备验收矩阵审计。

## 运行资源所有权

- 领取阶段不启动模拟器、TestManager 或 Instruments。
- 后续每个设备批次记录唯一 UDID；批次结束后终止 App、关闭并删除 owned 设备，清理 Runner、构建和 trace 进程。
- 不触碰不属于 Task 09 的模拟器或进程。

## Checkpoint 记录

- [~] 当前 checkpoint：领取反馈、建立实现记忆与活动链接。
