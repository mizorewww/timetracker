# 47：iPad/mac Now 与 Overview 和 iPhone 同步并排实现记忆

Status: Complete

> 本文件只用于主代理与子代理的实现、验证和编排记忆，不是任务来源。唯一范围与状态必须重新读取
> [`Docs/userfeedback.md`](../../../../userfeedback.md) 中对应的 `[~]` 条目。

## 当前阶段

- [x] 领取“ipad/mac上的Now界面和overview请和iphone同步,宽屏把overview和now放在同一行”反馈。
- [x] 审计 iPhone 与桌面(iPad/macOS)的 Now、Overview 组件差异(任务03/33 的历史差异设计)。
- [x] 确定统一方案:同一套 Now/Overview 组件,宽屏 Now|overview 同行,iPhone 保持上下排。
- [x] 实现并运行聚焦测试与 iPhone/iPad/macOS 模拟器截图验收。
- [x] 执行 `CONFIGURATION=Release scripts/build_install_all.sh`(实体机安装失败不阻塞),标记完成并移除活动链接。

## 唯一反馈边界

- 统一 iPhone/iPad/mac 的 Now 与 Overview 组件与排版;宽屏 Now|overview 同行,iPhone now \n overview。
- 不领取 heatmap 进分析页、checklist 复用或其他反馈。
- 以普通文字大小、正常交互路径、三平台系统约定为优先。

## 强制约束

- 完整遵循仓库本地 `apple-hig` 与 `swiftui-expert-skill`;所有 UI 导航、断言与截图只用 XCTest/XCUITest 脚本。
- 实体机器不做测试;模拟器验收后 shutdown+delete 并清理 /tmp 产物。
- 优先复用 iPhone 版 Now/Overview 组件;除用户建议外不引入 GitHub 少于 1k stars 的库。
- 每个 checkpoint 只暂存本任务的已完成变更;保留用户在反馈文件中的其他内容。

## Checkpoint 编排

- [x] Checkpoint A：领取任务、创建实现记忆与 active link。
- [x] Checkpoint B：审计两版 Now/Overview 差异。
- [x] Checkpoint C：实现统一组件与宽屏并排。
- [x] Checkpoint D：三平台模拟器验收与资源清理。
- [x] Checkpoint E：Release 构建安装、核验与收口。

## 资源所有权

- [x] 主代理：任务状态、编排、集成、所有 build/simulator/XCUITest/screenshot/Release 批次与清理。
- [x] 主代理(直接审计,无需子代理)：Now/Overview 组件差异审计。

## 已提交 checkpoint

- [x] 统一实现提交 + `feb338fa`(1.1.134 (189));领取任务与 active link 创建时已提交。


## 实现与验收记录

- 统一方案:共享 `HomeNowActiveContent`/`HomeNowEmptyStartButton`(iPhone 宿主 grouped 行、桌面 appCard;label 保留 L31 的 iPhone iconOnly / iPad·mac titleAndIcon);Overview 统一为 `PhoneTodaySummaryRow`(放开 #if os(iOS))。桌面趋势单元格(MetricsPanel/MetricCell)、TodayTimerAction、TodayMetricTrend 全部删除。
- 宽屏 Now|overview 并排沿用既有 `DesktopTodayCurrentStateSections`。
- 契约:`nowAndOverviewShareOneComponentAcrossPlatforms` 锁共享结构与死代码移除;多个旧锁重定向。
- UI:`testDesktopTodayShowsUnifiedNowOverviewRow` 三平台通过;iPad 截图确认 Now|Overview 同行且组件与 iPhone 一致,iPhone 截图确认无变化;Gross Time 值加 lineLimit(1)+minimumScaleFactor 防窄列换行。
- [x] `CONFIGURATION=Release scripts/build_install_all.sh`:iOS/macOS BUILD SUCCEEDED,iPhone Air 已装 `1.1.134 (189)`,无设备安装失败。
- [x] 反馈已由主代理标记完成,active link 已移除;owned 模拟器与 /tmp 产物已清理。