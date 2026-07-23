# 39：Heatmap 与柱状图原生卡片风格实现记忆

> 本文件只用于主代理与子代理的实现、验证和编排记忆，不是任务来源。唯一范围与状态必须重新读取
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 条目。

## 当前阶段

- [x] 领取“Heatmap 和柱状图风格与原生卡片不一致”反馈。
- [x] 审计 Heatmap、柱状图与同屏原生卡片的组件、平台差异和现有自动化证据。
- [x] 确定复用 SwiftUI 原生容器/项目 DesignSystem 的最小统一方案。
- [~] 分 checkpoint 实现并运行聚焦测试与 macOS/iPhone/iPad XCUITest 截图验收。
- [ ] 执行 `CONFIGURATION=Release scripts/build_install_all.sh`，由 Codex 标记完成并移除活动链接。

## 审计结论(task39_visual_audit / task39_test_audit)

- **P0 根因**:iPhone 上 heatmap/柱状图用 `homeVisualizationListCard` 自绘浮卡(圆角 8 + 描边 + 清空行),同屏其它 section 全是 insetGrouped 原生行;Analytics 同一柱状图组件也是裸行。桌面端已是 `appCard`,只剩 padding 16 vs 兄弟卡片 14 的差异。
- **方案**:iPhone listSection 回归原生 grouped 行(删除 `homeVisualizationListCard`/`homeVisualizationListSection` 两个修饰符);桌面 padding 统一 14;weekly loading 高度与 chartHeight 对齐(210)。
- **不改**:heatmap 调色板/格子圆角(GitHub 风格本身,与 Analytics 一致)、bar 纯色 + cornerRadius 3、桌面 header(`HomeOverviewHeader` 同款 `.headline` + info 模式,`SectionTitle` 不支持 info 按钮)。
- **契约测试**:`HomeUIContractTests`/`TodayHeatmapUIContractTests` 改为反向锁定已删除修饰符,锁定原生行语义。
- **验收矩阵**(复用 fixture `--uitesting-today-heatmap` + `--uitesting-reset-demo-preferences`):macOS `testTodayWeeklyGrossTimeChartIsVisible` + `testTodayConfiguredHeatmapsStayIndependentByTaskAndMetric`;iPhone/iPad 加 `testTodayVisualizationCardsAreVisuallyIndependent`(iPad 含脚本横屏);owned 模拟器 `codex-task39-*`,产物 `/tmp/timetracker-task39-*`。

## 唯一反馈边界

- 只统一 Heatmap 与柱状图相对同屏原生卡片的视觉和容器行为。
- 不领取后续任务详情图标跳转、Analytics 闪烁、番茄钟卡片或其他反馈。
- 以普通文字大小、正常交互路径、三平台系统约定为优先；不手动操作调试窗口。

## 强制约束

- 完整遵循仓库本地 `apple-hig` 与 `swiftui-expert-skill`；所有 UI 导航、断言与截图只用 XCTest/XCUITest 脚本。
- 物理设备只做最终 Release 安装和只读签名/版本核验，不启动、不交互、不截图。
- 优先复用 SwiftUI、Swift Charts 与现有 DesignSystem；评估成熟库但不为原生容器造轮子，除用户建议外不引入 GitHub 少于 1k stars 的库。
- 每个 checkpoint 只暂存本任务的已完成变更；保留用户在反馈文件中的其他内容。

## Checkpoint 编排

- [x] Checkpoint A：领取任务、创建实现记忆与 active link。
- [x] Checkpoint B：并行审计现有卡片实现、HIG/库方案与自动化矩阵。
- [~] Checkpoint C：实现共享原生卡片样式并补齐聚焦测试。
- [ ] Checkpoint D：三平台脚本化视觉验收。
- [ ] Checkpoint E：Release 全设备安装、签名/版本核验与收口。

## 资源所有权

- [~] 主代理：任务状态、编排、集成、所有 build/TestManager/simulator/XCUITest/screenshot/Release 批次与清理。
- [x] `task39_visual_audit`：Heatmap/柱状图/原生卡片代码审计。
- [x] `task39_test_audit`：现有 UI contract/XCUITest 与截图矩阵审计。
- [x] 主代理：Apple HIG(tier-1 + charts/boxes/三平台)与 swiftui-expert-skill(latest-apis)已加载;结论是不引入新库,统一走现有 DesignSystem(`AppCardBackground`/`secondarySystemGroupedBackground`)。

## 已提交 checkpoint

- [x] `f141f00d`：领取任务、实现记忆与 active link。
