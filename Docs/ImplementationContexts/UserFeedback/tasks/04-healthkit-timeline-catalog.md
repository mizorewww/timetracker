# 04：HealthKit timeline 与自动目录

> 本文件只保存实现、验证和子代理编排记忆，不是任务来源。每次继续前必须
> 重新读取 [`Docs/userfeedback.md`](../../../userfeedback.md) 中唯一的 `[~]` 项。

## 当前阶段

- 先审计现有 HealthKit 读取、授权、timeline 投影与特殊任务目录实现，区分已完成、
  缺失和回归部分。
- 只使用 `Docs/userfeedback.md` 决定范围和完成状态；本文不得新增产品任务。
- 审计完成前不假设需要重写现有架构，也不根据后续反馈项扩展当前范围。

## 实现边界

- 运动与睡眠数据来自系统 HealthKit，只读同步到 timeline，不伪造可手动计时的数据。
- 自动目录创建必须可重复执行且不产生重复 category/task，身份需稳定。
- 授权拒绝、设备不支持、空数据、增量刷新与时间边界都要有明确行为。
- UI 遵循 Apple HIG 的隐私、授权前置说明、系统术语和平台反馈规范。
- SwiftUI 状态保持单一来源，避免在 view body 中执行 HealthKit 查询或重复写入目录。

## 审计与验收

- [ ] 盘点生产实现、entitlements、Info.plist 隐私文案与平台可用性
- [ ] 盘点 workout/sleep 读取、去重、timeline 映射与刷新路径
- [ ] 盘点自动 category/task 目录的稳定身份、幂等与只读限制
- [ ] 建立缺口对应的定向单元/契约测试
- [ ] 在适用设备上完成授权路径与 timeline 截图验收
- [ ] 运行 `CONFIGURATION=Release scripts/build_install_all.sh`
- [ ] 释放本任务拥有的设备、进程、trace、DerivedData 与临时附件
- [ ] 只在 `Docs/userfeedback.md` 标记完成并移除活动软链接

## 依赖策略

- 优先使用 Apple 原生 HealthKit 与项目现有服务；HealthKit 是系统数据源和授权边界，
  外部 wrapper 不能替代。
- 如需引入第三方库，先核对维护状态、许可证、平台兼容性与至少 1k GitHub stars；
  没有明确收益则不新增依赖。

## 子代理编排

- 待分派：HealthKit/entitlements 与授权审计。
- 待分派：timeline 投影、睡眠/运动域模型与测试审计。
- 待分派：自动任务目录、幂等和 UI/验收审计。
