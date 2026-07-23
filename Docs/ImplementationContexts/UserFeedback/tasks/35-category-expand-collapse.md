# 35：Category 展开与收起实现记忆

> 本文件只用于主代理与子代理的实现、验证和编排记忆，不是任务来源。唯一范围与状态必须重新读取
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 条目。

## 当前阶段

- [x] 领取“feature: category 的展开和收起”反馈。
- [~] 审计 Category 的现有层级、导航、状态持久化与跨平台交互。
- [ ] 设计并实现最小的展开/收起行为，补齐自动化与脚本截图验收。
- [ ] 提交实现 checkpoint，执行 `CONFIGURATION=Release scripts/build_install_all.sh`，标记反馈完成并移除活动链接。

## 唯一反馈边界

- Category 层级需要可由用户展开与收起。
- 保留现有 Category 编辑、任务导航、排序和数据语义；不领取后续 AI、首页或其他反馈。
- 具体入口、默认状态、状态作用域和平台差异必须先从现有代码与自动化证据确定，不能凭空新增交互。

## 强制约束

- 完整遵循仓库本地 `apple-hig` 与 `swiftui-expert-skill`；UI 导航、断言与截图只使用 XCTest/XCUITest 脚本。
- 不手动操作调试窗口；物理设备只做最终 Release 安装与只读版本/签名核验。
- 优先复用 SwiftUI 原生 DisclosureGroup/OutlineGroup 或项目现有层级组件；只有明确缺口才评估成熟第三方库，除用户建议外不采用 GitHub 少于 1k stars 的依赖。
- 每个 checkpoint 只暂存本任务变更；`Docs/userfeedback.md` 的用户新增内容保持未暂存。

## Checkpoint 编排

- [~] Checkpoint A：领取范围、当前 Category 信息架构与自动化基线审计。
- [ ] Checkpoint B：最小实现、聚焦测试与脚本截图验收。
- [ ] Checkpoint C：Release 全设备安装、签名/版本只读核验与收口。

## 资源所有权

- 审计代理只读，不编辑文件、不创建 simulator、不运行并发 Xcode/TestManager 批次。
- 主代理在审计完成后为每个 UI 批次创建显式 owned simulator 并记录 UDID；批次结束必须终止 app/runner、shutdown/delete 设备并清理所有临时产物。

## ~ 当前编排问题

- Category 当前在哪些界面展示父子层级，哪些路径已经支持展开/收起？
- 展开状态应是当前界面瞬时状态、场景状态还是用户偏好，现有产品语义提供了什么证据？
- iPhone、iPad、macOS 的原生交互应如何保持一致，同时尊重 sidebar/list 的平台惯例？
- 哪个 fixture 能稳定生成至少两级 Category，并让 XCUITest 同屏验证收起后子项消失、展开后恢复？
