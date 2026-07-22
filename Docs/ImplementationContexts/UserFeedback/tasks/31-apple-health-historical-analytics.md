# 31：Apple Health 历史统计实现记忆

> 本文件只用于主代理与子代理的实现、验证和编排记忆，不是任务来源。唯一范围与状态必须重新读取
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 条目。

## 当前阶段

- [x] 领取 Apple Health 类型任务的详情 Summary 与历史时间线缺失反馈。
- [~] 审计 HealthKit 数据投影、任务详情与统计数据流，并制定自动化验收契约。
- [ ] 实现历史时长与历史时间线，补齐定向测试和脚本化截图验收。
- [ ] 精确执行 `CONFIGURATION=Release scripts/build_install_all.sh`，标记反馈完成并移除活动链接。

## 唯一反馈边界

- Apple Health 类型任务的 task 详情 Summary 能显示过去累计时长。
- 统计视图能查看该任务过去的时间线数据。
- 不领取后续首页卡片拆分、设置页或其他反馈。

## 强制约束

- 完整遵循仓库本地 `apple-hig` 与 `swiftui-expert-skill` 规则；优先复用现有 HealthKit、SwiftUI、Swift Charts 与应用聚合服务。
- 如评估第三方库，必须先核验维护质量与 GitHub stars；除用户建议外不采用少于 1k stars 的库。
- 所有 UI 交互与截图验收写成 XCTest/XCUITest；只使用有明确所有权的模拟器，不手动调整窗口，不在物理设备启动、点击或截图。
- 每个 checkpoint 只暂存本任务变更，保护 `Docs/userfeedback.md` 中其他用户新增内容。

## Checkpoint 编排

- [~] Checkpoint A：范围领取、现状/依赖/HIG 审计与自动化验收设计。
- [ ] Checkpoint B：最小实现、定向单元/UI contract 与脚本化视觉验收。
- [ ] Checkpoint C：Release 全设备安装、签名/版本只读核验与收口。

## 资源所有权

- 当前未创建 simulator、DerivedData、测试进程或截图；主代理将在审计后登记每个批次的 owner 与清理结果。

## 审计结论

- 待补充。
