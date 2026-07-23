# 36：Category 排序实现记忆

> 本文件只用于主代理与子代理的实现、验证和编排记忆，不是任务来源。唯一范围与状态必须重新读取
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 条目。

## 当前阶段

- [~] 领取“feature: category 的排序”反馈并建立活动链接。
- [ ] 审计 Category 现有顺序来源、持久化模型、跨平台入口与测试基线。
- [ ] 设计并实现最小排序能力，补齐自动化与脚本截图验收。
- [ ] 提交小 checkpoint，执行 `CONFIGURATION=Release scripts/build_install_all.sh`，由 Codex 标记完成并移除活动链接。

## 唯一反馈边界

- 只实现 Category 的排序。
- 不领取后续 AI、首页、设置或其他反馈；具体排序入口、作用域、持久化和平台差异必须先从现有代码与证据确定。

## 强制约束

- 完整遵循仓库本地 `apple-hig` 与 `swiftui-expert-skill`；所有 UI 导航、断言与截图只用 XCTest/XCUITest 脚本。
- 不手动操作调试窗口；物理设备只做最终 Release 安装和只读版本/签名核验。
- 优先复用 SwiftUI 原生排序、项目现有模型与成熟库；只有明确缺口才评估新依赖，除用户建议外不采用 GitHub 少于 1k stars 的库。
- 每个 checkpoint 只暂存本任务变更；`Docs/userfeedback.md` 中用户新增内容保持未暂存。

## Checkpoint 编排

- [~] Checkpoint A：领取任务、创建实现记忆与 active link。
- [ ] Checkpoint B：审计顺序模型、交互方案、库与自动化基线。
- [ ] Checkpoint C：实现、聚焦验证、脚本截图与实现提交。
- [ ] Checkpoint D：Release 全设备安装、签名/版本核验与收口。

## 资源所有权

- 审计阶段子代理只读，不编辑、不构建、不测试、不创建 simulator，也不操作任何窗口。
- UI 验收由主代理创建并登记 owned simulator；每批结束必须终止 App/runner、shutdown/delete 设备并清理临时产物。
