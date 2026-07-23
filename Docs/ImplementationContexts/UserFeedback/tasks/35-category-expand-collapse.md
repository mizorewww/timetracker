# 35：Category 展开与收起实现记忆

> 本文件只用于主代理与子代理的实现、验证和编排记忆，不是任务来源。唯一范围与状态必须重新读取
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 条目。

## 当前阶段

- [x] 领取“feature: category 的展开和收起”反馈。
- [x] 审计 Category 的现有层级、导航、状态持久化与跨平台交互。
- [~] 设计并实现最小的展开/收起行为，补齐自动化与脚本截图验收。
- [ ] 提交实现 checkpoint，执行 `CONFIGURATION=Release scripts/build_install_all.sh`，标记反馈完成并移除活动链接。

## 唯一反馈边界

- Category 层级需要可由用户展开与收起。
- 保留现有 Category 编辑、任务导航、排序和数据语义；不领取后续 AI、首页或其他反馈。
- 具体入口、默认状态、状态作用域和平台差异必须先从现有代码与自动化证据确定，不能凭空新增交互。

## 强制约束

- 完整遵循仓库本地 `apple-hig` 与 `swiftui-expert-skill`；UI 导航、断言与截图只使用 XCTest/XCUITest 脚本。
- 不手动操作调试窗口；物理设备只做最终 Release 安装与只读版本/签名核验。
- 优先复用 SwiftUI 原生可折叠 `Section` 与项目现有层级组件；只有明确缺口才评估成熟第三方库，除用户建议外不采用 GitHub 少于 1k stars 的依赖。
- 每个 checkpoint 只暂存本任务变更；`Docs/userfeedback.md` 的用户新增内容保持未暂存。

## Checkpoint 编排

- [x] Checkpoint A：领取范围、当前 Category 信息架构与自动化基线审计。
- [~] Checkpoint B：最小实现、聚焦测试与脚本截图验收。
- [ ] Checkpoint C：Release 全设备安装、签名/版本只读核验与收口。

## 资源所有权

- `task35_category_architecture`、`task35_hig_ux` 与 `task35_test_audit` 只读；未编辑文件、构建、测试、创建 simulator 或操作窗口。
- 主代理在审计完成后为每个 UI 批次创建显式 owned simulator 并记录 UDID；批次结束必须终止 app/runner、shutdown/delete 设备并清理所有临时产物。

## Checkpoint A 审计结论

- `TaskCategory` 是扁平分组；真实层级是 Category → root task → child task。不得擅自新增嵌套 Category、`parentCategoryID` 或 SwiftData/CloudKit schema 迁移。
- 任务节点已有 `TaskExpansionState`、稳定 disclosure 和 `TaskTreeFlattener`；缺口只在 `TasksView` 与 iPad/macOS `SidebarView` 的 Category `Section` 永远展开。
- 临时 `TaskHierarchyPicker`、Analytics、Settings 与扁平 `TaskCategoryPicker` 不属于本项最小范围；在选择器隐藏候选任务会增加未请求状态，故不修改。
- Category 状态使用独立的轻量 `TaskCategoryExpansionState`，保存稳定 `section.id` 的 collapsed set。默认空集合保持所有现有/新 Category 展开；收起 Category 不清除内部 task 展开状态，重新展开恢复子树。
- 主 Tasks 列表直接使用 Apple 原生 `Section(isExpanded:content:header:)`，不能包进 `DisclosureGroup` 或 `OutlineGroup`；后两者会重排现有 Section、行、滑动动作和独立 Category 菜单，并重复已有扁平任务树逻辑。
- `TaskCategorySectionHeader` 只为有行的 Tasks Category 增加 leading `Button` disclosure，trailing `Menu` 保持独立。按钮复用 `AppLayout.minimumInteractiveTarget`，使用 `chevron.forward`/`chevron.down`、稳定 `tasks.category.disclosure.<section-id>`，并在 Reduce Motion 下跳过显式动画。
- Sidebar 使用原生 sidebar-style collapsible `Section` 与独立 surface state；外部路由/当前任务变化时同时展开其 Category 与 task ancestors，避免选中任务被隐藏。
- 搜索结果保持扁平且无 Category disclosure；退出搜索后原本的 Category 与 task 展开状态仍在当前 view 生命周期中。状态不进入业务模型、UserDefaults、Cloud 或同步。
- 现有 `replaceOnLaunch` demo fixture 已提供稳定语义层级 `Work → Time Tracker App → Design System` 与另一个 `Study` Category；XCUITest 用 forced-English 文案和 identifier prefix，绝不硬编码随机 UUID。
- 自动验收：状态单测；扩展现有 Task UI contract；跨平台 XCUITest 验证默认展开、只收起 Work、header/menu 与 Study 保留、重新展开恢复已展开 child、详情导航仍可用，并产出 iPhone/iPad/macOS 脚本截图。
- Apple 依据：SwiftUI `Section` 可通过 `isExpanded` binding 折叠；HIG 要求 disclosure 紧邻所控制内容、收起指向 forward、展开向下，并保留用户在当前层级中的选择。参考 <https://developer.apple.com/documentation/swiftui/section>、<https://developer.apple.com/design/human-interface-guidelines/disclosure-controls>、<https://developer.apple.com/design/human-interface-guidelines/outline-views>。
- 新增库：无。SwiftUI `Section`、`Button`、SF Symbols、现有 `TaskTreeFlattener` 与 XCTest/XCUITest 已完整覆盖，第三方库只会引入不必要风险。
