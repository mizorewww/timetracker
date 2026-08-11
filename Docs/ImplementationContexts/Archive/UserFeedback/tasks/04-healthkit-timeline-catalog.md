# 04：HealthKit timeline 与自动目录

Status: Complete

> 本文件只保存实现、验证和子代理编排记忆，不是任务来源。每次继续前必须
> 重新读取 [`Docs/userfeedback.md`](../../../../userfeedback.md) 中唯一的 `[~]` 项。

## 完成状态

- 已完成当前反馈项；完成状态只写回 `Docs/userfeedback.md`，本文仅保留实现记忆。
- 保留原生只读 HealthKit 架构，补齐授权状态刷新、并发读取取消与跨 actor 的睡眠
  timeline 投影，不扩展到 `Docs/userfeedback.md` 中后续的睡眠去重反馈项。
- iPhone 与 iPad 的 Today timeline 均已验收运动、睡眠、时间范围、时长和省略区间；
  正常字号下没有截断或重叠。

## 实现边界

- 运动与睡眠数据来自系统 HealthKit，只读同步到 timeline，不伪造可手动计时的数据。
- 自动目录创建必须可重复执行且不产生重复 category/task，身份需稳定。
- 授权拒绝、设备不支持、空数据、增量刷新与时间边界都要有明确行为。
- UI 遵循 Apple HIG 的隐私、授权前置说明、系统术语和平台反馈规范。
- SwiftUI 状态保持单一来源，避免在 view body 中执行 HealthKit 查询或重复写入目录。

## 审计与验收

- [x] 盘点生产实现、entitlements、Info.plist 隐私文案与平台可用性
- [x] 盘点 workout/sleep 读取、timeline 映射与刷新路径
- [x] 盘点自动 category/task 目录的稳定身份、幂等与只读限制
- [x] 建立授权 gate、偏好隔离、时间边界、timeline、目录与 Home 集成测试
- [x] 在 iPhone 与 iPad 完成授权入口和 timeline UI 测试及截图验收
- [x] 运行 `CONFIGURATION=Release scripts/build_install_all.sh`
- [x] 核验两台实体设备与 macOS 安装版本均为 `1.1.52 (107)`
- [x] 核验 Release 签名含 HealthKit entitlement，且 UI 测试 fixture 未进入 Release
- [x] 释放本任务拥有的模拟器、进程、测试产物与临时附件
- [x] 只在 `Docs/userfeedback.md` 标记完成并移除活动软链接

## 验证记录

- 相关 Health、Analytics、目录与 Home 测试：71/71 通过。
- Apple Health Today timeline UI 测试：iPhone 1/1、iPad 1/1 通过。
- Release：iOS 与 macOS 构建成功；iPad Pro M4、iPhone Air 安装成功；
  `/Applications/timetracker.app` 深度签名验证成功。
- 当前没有可见的实体 Apple Watch，因此脚本只完成 Watch companion 的嵌入与签名验证，
  未验证实体 Watch 安装。
- 独立发现的 `HomeUIContractTests.swift:968` 数量断言在纯 HEAD 同样失败，且不属于
  本反馈项修改范围；未借当前任务处理后续反馈。

## Checkpoint

- `7b9ff04` — 建立 HealthKit 实现审计记忆。
- `bddabe8` — 保持睡眠 timeline 投影可跨 actor 调用。
- `66837be` — 安全刷新 Apple Health 授权状态。
- `89d987d` — 取消过期的 Apple Health 读取。
- `0f52ed2` — 验证 iPhone/iPad Health timeline 布局和 Release fixture 隔离。

## 依赖策略

- 优先使用 Apple 原生 HealthKit 与项目现有服务；HealthKit 是系统数据源和授权边界，
  外部 wrapper 不能替代。
- 如需引入第三方库，先核对维护状态、许可证、平台兼容性与至少 1k GitHub stars；
  没有明确收益则不新增依赖。

## 子代理编排

- 已完成独立审查：HealthKit entitlement、授权、timeline 投影、自动目录与 UI 验收；
  收到的并发审查结论无阻塞项。
