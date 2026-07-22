# 21：Apple Health 特殊任务自动显示实现记忆

> 本文件只用于主代理与子代理的实现、验证和编排记忆，不是任务来源。唯一范围与状态必须重新读取
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 条目。

## 当前阶段

- [x] 领取反馈，审计 Apple Health catalog 创建、Tasks 查询/过滤与计时选择器排除路径。
- [x] 明确缺失发生在 bootstrap、read model 还是 UI 分组，并选择最小一致修复。
- [x] 实现 Health 特殊任务自动出现在 Tasks，同时维持仅同步、不可计时、不可被计时选择器选择。
- [~] 完成相关单元/契约回归和 owned simulator 普通路径截图验收，清理资源。
- [ ] 执行 `CONFIGURATION=Release scripts/build_install_all.sh`，标记反馈完成并移除活动链接。

## 唯一反馈边界

- Apple Health 类型任务应自动显示在 Tasks 页面。
- 这些任务仍是 Apple Health 同步管理的特殊任务，只能从 Apple Health 同步数据。
- Health 任务不允许开始计时，也不能出现在任何计时任务选择器中。
- 不领取后续 Inbox 完成态、Timeline 轨道、Live Activity、首页统计、Health 历史统计或 category 修改反馈。

## 强制约束

- 复用现有确定性 Health catalog、同步与 eligibility policy，不创建平行身份或用标题判断类型。
- 自动显示不能依赖用户先有 workout/sleep 样本；也不能把 Health 任务混入可计时候选。
- UI 与截图只使用明确登记的 owned simulator；物理设备只做最终 Release 安装和只读核验，不启动、不操作、不截图。
- 每个小 checkpoint 验证后提交；只暂存本任务状态差异，保护 `Docs/userfeedback.md` 中用户新增内容。

## Checkpoint 编排

- [x] Checkpoint A：静态审计 catalog bootstrap、Tasks read model、archive/category 过滤及所有 timer picker eligibility。
  - 根因是 catalog bootstrap 被 Timeline 偏好间接门控：冷启动只调用 `refreshAppleHealthTimelineIfEnabled`，默认关闭时在 materialize 前返回；Tasks read model 本身没有丢弃 Health task。
  - catalog 是固定 2 category / 12 task 的本地导航模板；现有 mutation event 会刷新 Tasks，`TaskTrackingAvailabilityService` 保持它们 visible 并从 trackable 集合排除，底层 Timer/Pomodoro/Ledger/Watch 仍二次校验。
  - Apple 官方将 `HKHealthStore` 定义为授权与查询 HealthKit 数据的入口；静态本地模板不需要触发授权或 sample query。参考：<https://developer.apple.com/documentation/healthkit/hkhealthstore>、<https://developer.apple.com/documentation/healthkit/hkhealthstore/ishealthdataavailable()>。
  - 不新增第三方库；系统 HealthKit、SwiftData、SwiftUI 与仓库既有 catalog/eligibility policy 已覆盖完整语义，wrapper 只会扩大权限和维护面。
- [x] Checkpoint B：实现与定向单元/契约测试。
  - 启动/foreground 共用刷新入口先 materialize catalog，再检查 Timeline enabled；Health unavailable、Timeline disabled 时也创建静态模板，但 authorization status、授权、sample query 均为 0。
  - UI 回归改为不点击“Show Apple Health in Timeline”，直接进入 Tasks 验证 Running 与 Sleep 自动可见；原 sync-only 详情、Quick Start 排除和普通 task 正控制继续保留。
  - macOS `AppleHealthTimelineTests` `29/29` 通过；catalog、Tasks、Timer picker、Ledger、Pomodoro、Watch、系统动作、quantity 与 UI contract 的 11-suite 回归 `183/183` 通过，均保留签名。
- [~] Checkpoint C：owned iPhone/iPad simulator UI/截图、精确 Release 安装、状态与资源收口。

## 资源所有权

- 尚未创建 simulator、启动设备流程或生成 trace。
