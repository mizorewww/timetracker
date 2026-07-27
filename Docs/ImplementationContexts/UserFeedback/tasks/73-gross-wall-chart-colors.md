# 73：Gross / Wall 双系列柱状图 实现记忆

状态：2026-07-27 实现中

> 本文件是主代理与子代理的实现、验证和编排记忆；唯一任务来源仍是
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 条目。

## 认领的反馈条目

- Gross Time 柱状图配色欠佳，希望同时显示 Gross 与 Wall 两组数据。

## 预期行为

- Today 周趋势图同时、清晰地区分每天的 Gross Time 与 Wall Time。
- 配色使用语义化、跨明暗模式可读的系统颜色，不依赖仅靠色相才能理解。
- 图例、辅助功能描述与现有时间语义一致；缺失、零值和重叠时段不会误导。
- iPhone、iPad 和 macOS 在普通字号下维持清晰标签、合理密度与卡片边界。

## UI 验收清单

- 用确定性 fixture 留存改动前后的图表截图，检查两组柱、图例、轴标签与卡片边界。
- 在 iPhone、iPad 和 macOS 普通字号验证；至少检查一种较窄布局和一种宽布局。
- 用行为测试覆盖 Gross/Wall 日汇总投影、排序以及零值/重叠数据语义。
- SwiftFormat、相关单元/XCUITest、默认 `make test` 和 Release 全设备安装通过。
- 释放所有 owned runner、模拟器与临时构建资源。

## Checkpoint 编排

- [ ] A：领取反馈、建立活动实现记忆并审计图表 owner、数据语义与现有测试。
- [ ] B：补充先失败的双系列投影/可访问性行为测试。
- [ ] C：实现双系列图表、语义化配色并更新相关文档。
- [ ] D：完成格式、跨平台截图、全量测试、Release 全设备安装与收口。

## 库策略

- 优先复用项目已有的 Apple Swift Charts，以及系统 `ShapeStyle`、图例和无障碍 API。
- 核对 Apple 官方 grouped/positioned bar、图例和颜色对比能力；仅在原生 API 无法满足时才评估维护活跃、成熟且一般不少于 1k stars 的第三方库。

## 进度记录

- 2026-07-27：认领任务并建立 `~73` 活动实现记忆。
