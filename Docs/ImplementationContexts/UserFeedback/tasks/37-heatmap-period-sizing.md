# 37：Heatmap 默认时间段与方块尺寸实现记忆

> 本文件只用于主代理与子代理的实现、验证和编排记忆，不是任务来源。唯一范围与状态必须重新读取
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 条目。

## 当前阶段

- [x] 领取“设置中 Heatmap 默认时间段长度选择，并改善 iPhone 方块偏小”反馈并建立活动链接。
- [~] 审计现有 Heatmap 设置、持久化、布局、跨平台入口与测试基线。
- [ ] 设计并实现最小能力，补齐自动化与脚本截图验收。
- [ ] 提交小 checkpoint，执行 `CONFIGURATION=Release scripts/build_install_all.sh`，由 Codex 标记完成并移除活动链接。

## 唯一反馈边界

- 仅实现设置中 Heatmap 默认显示时间段长度的选择，并在该选择或布局策略下改善 iPhone 方块偏小。
- 不领取后续 AI、首页、分类或其他反馈；具体适用的 Heatmap、选项、默认值与平台差异必须先从现有代码和测试证据确定。

## 强制约束

- 完整遵循仓库本地 `apple-hig` 与 `swiftui-expert-skill`；所有 UI 导航、断言与截图只用 XCTest/XCUITest 脚本。
- 不手动操作调试窗口；物理设备只做最终 Release 安装和只读版本/签名核验。
- 优先复用 SwiftUI 原生控件、项目现有 preference 与 Heatmap 布局；只有明确缺口才评估新依赖，除用户建议外不采用 GitHub 少于 1k stars 的库。
- 每个 checkpoint 只暂存本任务变更；`Docs/userfeedback.md` 中用户新增内容保持未暂存。

## Checkpoint 编排

- [x] Checkpoint A：领取任务、创建实现记忆与 active link。
- [~] Checkpoint B：审计设置/布局/持久化语义、库与自动化基线。
- [ ] Checkpoint C：实现、聚焦验证、脚本截图与实现提交。
- [ ] Checkpoint D：Release 全设备安装、签名/版本核验与收口。

## 审计与实现决定

- [~] 待主代理与子代理从现有代码、测试和权威参考补齐。

## 资源所有权

- [~] 主代理：维护唯一任务状态、编排、集成、所有 build/TestManager/simulator/XCUITest/screenshot/Release 批次与清理。
- [ ] 子代理只在明确分配的只读审计或互不重叠实现范围内工作；不得自行构建、创建 simulator 或操作窗口。

## 已提交 checkpoint

- [~] 领取任务 checkpoint 待提交。
