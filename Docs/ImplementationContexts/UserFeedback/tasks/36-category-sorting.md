# 36：Category 排序实现记忆

> 本文件只用于主代理与子代理的实现、验证和编排记忆，不是任务来源。唯一范围与状态必须重新读取
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 条目。

## 当前阶段

- [x] 领取“feature: category 的排序”反馈并建立活动链接。
- [x] 审计 Category 现有顺序来源、持久化模型、跨平台入口与测试基线。
- [~] 设计并实现最小排序能力，补齐自动化与脚本截图验收。
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

- [x] Checkpoint A：领取任务、创建实现记忆与 active link。
- [x] Checkpoint B：审计顺序模型、交互方案、库与自动化基线。
- [~] Checkpoint C：实现、聚焦验证、脚本截图与实现提交。
- [ ] Checkpoint D：Release 全设备安装、签名/版本核验与收口。

## 审计证据与实现决定

### 现有顺序链路

- `TaskCategory.sortOrder` 已经是持久化字段；当前 Schema 与旧 Schema 都已包含，不需要 Schema、迁移或备份格式变更。
- Category repository 已按 `sortOrder → createdAt → UUID` 读取，新分类使用尾项 `sortOrder + 10`；本任务只补“重新排序”的写路径。
- Tasks、Sidebar、任务层级 Picker、Category Picker 与任务编辑器都消费同一份 `store.taskCategories` / task tree read index，因此一次排序会自然传播；Analytics 的分类榜按使用时长排序，保持原语义。
- task tree 保留输入 Category 顺序，并把虚拟“未分类”固定追加到最后；虚拟分组不进入排序页。
- sync snapshot 已保存、恢复并 preflight `sortOrder`。Apple Health 正常 catalog reconcile 不覆盖用户顺序；仅首次创建和 Clear All 恢复采用高位默认顺序，本任务不扩张该既有策略。

### 并发与持久化

- 新增整表 baseline：有序 Category IDs，以及每项 `clientMutationID`。
- 在现有 store-scoped lock 的 fresh context 中严格校验数量、成员、当前顺序和全部 mutation revisions；并发创建、删除、编辑或另一个窗口排序都必须拒绝并 refresh。
- 目标顺序在一次事务中规范化为 `10, 20, 30...`。所有受影响 Category 共用一个由 `PersistentLWWMutationDate.strictlyDominating` 生成的时间戳，并更新 device ID 与 mutation ID，只保存一次。
- 排序结果继续发布 task-domain mutation event；现有 refresh planner 负责刷新 tasks、analytics、Live Activity 与多窗口 UI。
- 不新增“顺序单记录”Schema：当前整表归一化足够覆盖本机多窗口，并显著降低逐行 CloudKit LWW 混合概率；严格跨离线设备原子顺序不在本反馈范围。

### 跨平台交互

- Tasks 的 Add 菜单新增“Sort Categories”入口，少于两个真实 Category 时禁用；Sheet 通过统一 `AppPresentationRouter` 承载，避免局部 ad-hoc presentation。
- 独立排序页使用原生 SwiftUI `NavigationStack + List + ForEach.onMove`，以 Category UUID 作为稳定 identity；iPhone/iPad 打开后进入原生 active edit mode。
- 每行同时提供 Move Up / Move Down 操作，作为拖拽的可发现替代方式及稳定自动化路径；macOS 也可用这些原生命令完成排序。
- Sheet 使用本地草稿：Cancel 丢弃，Done 才提交整表 baseline；提交失败保留现有错误/refresh 语义。Tasks 与 Sidebar 的展开状态继续按稳定 Category ID 保留。
- macOS Task 菜单同步提供排序命令，满足桌面 toolbar command 可从菜单栏访问的约定。

### 库选择

- 采用 Apple 原生 SwiftUI `List`、`onMove`、`EditMode` 与标准 Array move API，复用现有 SwiftData transaction/XCTest；不新增依赖。
- `visfitness/reorderable` 约百余 stars，低于用户给出的 1k 门槛且会引入自定义 gesture/autoscroll 风险，拒绝。
- SwiftUIX 约 8k stars，质量与采用度足够，但其广泛兼容层没有补上本任务的任何原生能力，故不为单个排序页引入。
- `Table(sortOrder:)` 表示 comparator/列排序，不适合用户自定义持久顺序；底层 drag/drop transfer API 过重；OS 27 新 reorder container API 仍是 Beta 且不满足当前 macOS 15 部署基线。

### 自动化验收

- 单元测试覆盖：有效 reorder、same-order no-op、stale edit、stale membership、直接 order mutation、metadata/单事务结果、fresh context 持久顺序、虚拟未分类仍在末尾。
- source contract 覆盖 router、稳定 identifiers、`onMove`、iOS edit mode、Move Up / Move Down 边界与三语键。
- XCUITest 只通过稳定 identifier 打开排序页、点击 Move Up / Move Down、断言 Study/Work 的 frame 顺序和 Tasks/Sidebar 同步，然后脚本截图；移动后重新查询元素，避免 SwiftUI List diff 的 stale element。
- UI 测试使用内存 container，跨进程重启会重新 seed，因此真正的持久化由 fresh `ModelContext` 单元测试验证，XCUITest 只验证当前进程传播。
- iPhone、iPad、macOS 的导航、窗口定位、操作和截图全部由 XCTest/XCUITest 驱动；不手动调试窗口，不用物理机交互。

## 权威参考

- Apple HIG — Lists and tables: <https://developer.apple.com/design/human-interface-guidelines/lists-and-tables>
- Apple HIG — Drag and drop: <https://developer.apple.com/design/human-interface-guidelines/drag-and-drop>
- SwiftUI `onMove`: <https://developer.apple.com/documentation/swiftui/dynamicviewcontent/onmove(perform:)>
- SwiftUI `EditMode`: <https://developer.apple.com/documentation/swiftui/editmode>
- XCUITest gestures/elements: <https://developer.apple.com/documentation/xcuiautomation/xcuielement>

## 资源所有权

- 审计阶段子代理只读，不编辑、不构建、不测试、不创建 simulator，也不操作任何窗口。
- UI 验收由主代理创建并登记 owned simulator；每批结束必须终止 App/runner、shutdown/delete 设备并清理临时产物。
