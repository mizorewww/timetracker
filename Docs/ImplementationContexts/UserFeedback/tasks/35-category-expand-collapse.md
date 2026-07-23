# 35：Category 展开与收起实现记忆

> 本文件只用于主代理与子代理的实现、验证和编排记忆，不是任务来源。唯一范围与状态必须重新读取
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 条目。

## 当前阶段

- [x] 领取“feature: category 的展开和收起”反馈。
- [x] 审计 Category 的现有层级、导航、状态持久化与跨平台交互。
- [x] 设计并实现最小的展开/收起行为，补齐自动化与脚本截图验收。
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

## Checkpoint B 实现

- 新增 `TaskCategoryExpansionState`，只记录 collapsed section ID；默认展开、按 Category 独立切换，且与已有 `TaskExpansionState` 分离，因此收起 Category 后不会丢失内部 task subtree 的展开状态。
- Tasks 主列表对有任务的 Category 使用 `Section(isExpanded:)`；header 的 leading disclosure 与 trailing Category `Menu` 是独立点击目标，复用稳定 section ID、最小交互尺寸、`chevron.forward`/`chevron.down` 和 Reduce Motion 语义。空 Category 不显示无内容的 disclosure。
- iPad/macOS Sidebar 使用独立的原生 sidebar-style collapsible Section；Tasks 主列表与 Sidebar 不共享 transient UI state。当前 task 或外部详情路由变化时，会自动展开所属 Category 与 task ancestors，避免当前选择被隐藏。
- disclosure 补齐稳定 UI-test identifier、展开/收起可访问性值；原有 forecast-disabled Category 状态继续通过 `accessibilityValue` 暴露，Category actions 不会因收起消失。
- XCUITest 覆盖 iPhone、iPad、macOS 的默认展开、收起、兄弟 Category 不受影响、内部 task 状态恢复、详情导航、Sidebar 独立状态与路由自动展开；所有截图均由测试 attachment 生成。
- macOS 测试不人工拖动窗口：XCUITest 打开 App 自己的 Window menu，按 AppKit 稳定 action identifier `_moveToDisplay:` 选择标题包含 `NSScreen.localizedName` 的主屏；单屏/菜单无 move 项时按 `_zoomCenter:` 脚本居中，随后严格断言整个 App window 位于主屏。截图使用目标 `XCUIElement` window，而非桌面 screen。
- 新增库：无。实现只使用 SwiftUI、SF Symbols、项目现有 task tree；测试辅助使用 XCTest/XCUITest 与 macOS 自带 AppKit。既无依赖缺口，也无需新增低质量 package。

## Checkpoint B 验证证据

- 聚焦模型与 UI contract：`TaskTreeReadIndexTests`、`TaskUIContractTests` 等相关套件 49/49 通过，0 failed（`/tmp/timetracker-task35-contract-suites-final.xcresult`）。
- iPhone 17 Pro owned simulator：Category 主流程与 trailing actions 共 2/2 通过，0 failed（`/tmp/timetracker-task35-iphone-ui-final.xcresult`）。
- iPad Pro 11-inch owned simulator：Tasks 主列表 1/1、Sidebar 1/1 通过，均 0 failed（`/tmp/timetracker-task35-ipad.xcresult`、`/tmp/timetracker-task35-ipad-sidebar.xcresult`）。
- macOS 最终自动化：Tasks 与 Sidebar 2/2 通过，0 failed（`/tmp/timetracker-task35-mac-portable-menu-final2.xcresult`）；日志确认 XCUITest 通过 `_moveToDisplay:` 点击目标主屏，并生成 7 张目标 App window attachment。
- 已目视核对 iPhone、iPad 与最终 macOS expanded/collapsed/restored/auto-expanded attachment：Category 与 task disclosure 层级清晰、动作菜单保留、收起后内容消失、恢复后内部层级保持；没有桌面、Codex 或其他应用混入截图。
- 一次早期“整个 test target”尝试被 Xcode 27 自动生成未授权的 implicit Clone runner，TestManager 随后崩溃并产生 0.000 秒伪失败；该运行已中断且不计作产品验证。最终所有上列 run 均显式 `-parallel-testing-enabled NO`，使用确定性 owned destination。
- `git diff --check` 通过。最终复审已消除 forecast-disabled 状态语义、Sidebar 行为覆盖和 macOS 菜单本地化匹配风险。

## Checkpoint B 资源清理

- owned iPhone UDID `7828FCB3-295E-4C37-B68D-AA97486C9D43` 与 iPad UDID `DE99CFA4-A2D0-4D65-A118-DD9E3E83785F` 已终止 App、shutdown 并 delete。
- 已确认无 `codex-task35`、implicit Clone、Booted simulator、owned `xcodebuild`、`xctest`、UI runner 或 timetracker App 进程残留；本批次未打开 Simulator 或 Problem Reporter GUI。
