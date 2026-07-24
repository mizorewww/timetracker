# 41：Analytics 切换 Day/Week/Month 闪烁实现记忆

> 本文件只用于主代理与子代理的实现、验证和编排记忆，不是任务来源。唯一范围与状态必须重新读取
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 条目。

## 当前阶段

- [x] 领取“Analytics 界面，切换 Day/Week/Month 的时候会闪烁”反馈。
- [x] 审计 Analytics 周期切换的数据加载、视图身份与动画链，定位闪烁根因。
- [x] 确定最小修复(稳定视图身份/避免重复加载/合理动画)。
- [x] 实现并运行聚焦测试与 iPhone/iPad/macOS 模拟器截图(或录屏)验收。
- [x] 执行 `CONFIGURATION=Release scripts/build_install_all.sh`(实体机安装失败不阻塞),标记完成并移除活动链接。

## 唯一反馈边界

- 只修 Analytics Day/Week/Month 切换时的闪烁(内容闪空/重排/重复动画)。
- 不领取番茄钟卡片、AI 提示词或其他反馈。
- 以普通文字大小、正常交互路径、三平台系统约定为优先。

## 强制约束

- 完整遵循仓库本地 `apple-hig` 与 `swiftui-expert-skill`;所有 UI 导航、断言与截图只用 XCTest/XCUITest 脚本。
- 实体机器不做测试;模拟器验收后 shutdown+delete 并清理 /tmp 产物。
- 优先复用 SwiftUI/Swift Charts 与现有组件;除用户建议外不引入 GitHub 少于 1k stars 的库。
- 每个 checkpoint 只暂存本任务的已完成变更;保留用户在反馈文件中的其他内容。

## Checkpoint 编排

- [x] Checkpoint A：领取任务、创建实现记忆与 active link。
- [x] Checkpoint B：审计闪烁根因(数据链 + 视图身份 + 动画)。
- [x] Checkpoint C：实现修复并补齐聚焦测试。
- [x] Checkpoint D：三平台模拟器验收与资源清理。
- [x] Checkpoint E：Release 构建安装、核验与收口。

## 资源所有权

- [x] 主代理：任务状态、编排、集成、所有 build/simulator/XCUITest/screenshot/Release 批次与清理。
- [x] 主代理(直接审计,无需子代理)：Analytics 周期切换链路审计。

## 已提交 checkpoint

- [x] `e36807df`:修复 + 契约/UI 回归 + 三平台验收(1.1.110 (165))。
- [x] 领取任务、实现记忆与 active link(创建即提交)。


## 实现与验收记录

- 根因:切换 Day/Week/Month 时 `canRemainVisible` 为 false,`AnalyticsView` 用全屏 `ProgressView` 整体替换 `AnalyticsContent` —— 周期选择器(picker)和数据一起卸载,滚动位置丢失,造成闪烁。
- 修复:`AnalyticsContent` 改为接收可选 snapshot,`AnalyticsPeriodSection` 常驻,仅数据区原地显示 `ProgressView`(minHeight 240)—— 与 `AnalyticsCategoryDetailView` 既有模式一致;仍然不会在新选周期下展示旧数据。
- 契约测试 `analyticsHomeKeepsPeriodControlsMountedWhileSwitchingRanges` 锁定结构。
- XCUITest `testAnalyticsRangeSwitchKeepsPeriodControlsMounted`:Day→Week→Month→Day 循环,每次切换后立即断言 `analytics.periodFilter` 存在、数据 section 10s 内恢复;macOS 段控件为 RadioButton(平台分支)。
- [x] iPhone(owned `codex-task41-iPhone17Pro`)、iPad(`codex-task41-iPadPro11`)、macOS 均通过;截图确认控件稳定、数据恢复。
- [x] `CONFIGURATION=Release scripts/build_install_all.sh`:iOS/macOS BUILD SUCCEEDED,iPhone Air 已装 `1.1.110 (165)`,无设备安装失败。
- [x] 反馈已由主代理标记完成,active link 已移除;owned 模拟器与 /tmp 产物已清理。