# 17：时间线睡眠阶段合并实现记忆

> 本文件仅作为主代理与子代理的实现、验证和编排记忆，不是任务来源。唯一范围与状态必须重新读取
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 条目。

## 当前阶段

- [x] 读取唯一反馈并建立 active link。
- [ ] 审计 HealthKit 睡眠样本导入、领域模型去重/合并及 Timeline 映射边界。
- [ ] 参考 Apple 官方语义与成熟库，确定最小、可测试的合并策略。
- [ ] 实现睡眠不同类型在时间线上的连续区间合并与回归测试。
- [ ] 使用 owned 模拟器完成普通路径与截图验收并清理资源。
- [ ] 执行 `CONFIGURATION=Release scripts/build_install_all.sh` 并由 Codex 标记完成。

## 唯一反馈边界

- 时间线不应因 HealthKit 的不同睡眠类型而把同一次实际睡眠拆成多段。
- 同一次实际睡眠应在 Timeline 上合并为连续区间。
- 不领取或实现其后的 workout/睡眠仅同步、AI 配置等反馈。

## 强制设计与实现约束

- 重新核对 Apple HealthKit 睡眠分析的官方阶段语义、重叠与来源规则，不凭枚举名称臆造算法。
- 优先在数据归一化或 Timeline projection 的明确边界修复，避免只在 SwiftUI 视图里遮掩重复区间。
- 现有相邻计时段自动合并语义不得无意扩展到普通用户计时；睡眠专属规则必须可隔离、可回归。
- 若原生 HealthKit/Swift 标准库已完整覆盖，不为区间合并引入第三方依赖；审计候选库时一般拒绝低于
  1k GitHub stars 的非用户指定依赖。
- UI 操作与截图只使用 owned 模拟器；物理 iPhone/iPad 只做最终 Release 安装与只读核验，不启动、
  不操作、不截图。
- 每个小 checkpoint 完成验证并提交；只暂存本任务状态差异，保护 `Docs/userfeedback.md` 中用户新增内容。

## 待审计问题

- 睡眠阶段样本是在 HealthKit 查询层、同步层、`TimeEntry` 持久化层还是 Timeline 展示层拆分。
- `.asleepCore`、`.asleepDeep`、`.asleepREM`、`.asleepUnspecified` 及 `.inBed` 是否都进入同一任务；awake
  区间与样本重叠应如何处理。
- “同一次睡眠”的连续性阈值是否已有领域常量或测试语义；必须复用既有规则或从官方数据行为推导。
- 多数据源/重复样本是否需要先求区间并集，避免简单首尾扩张把真实清醒间隔吞掉。

## 资源所有权

- 尚未创建或启动本任务模拟器；后续必须记录 owned UDID、结果包、截图路径与完整清理结果。
- 既有 `AnalyticsReview-iPhone17Pro`（`E831B715-747C-478F-B8EE-539C48952444`）为 Shutdown 且不属于本任务，
  不得启动、关闭或删除。
