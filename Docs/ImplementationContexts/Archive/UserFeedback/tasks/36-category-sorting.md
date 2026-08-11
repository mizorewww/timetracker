# 36：Category 排序实现记忆

Status: Complete

> 本文件只用于主代理与子代理的实现、验证和编排记忆，不是任务来源。唯一范围与状态必须重新读取
> [`Docs/userfeedback.md`](../../../../userfeedback.md) 中对应的 `[~]` 条目。

## 当前阶段

- [x] 领取“feature: category 的排序”反馈并建立活动链接。
- [x] 审计 Category 现有顺序来源、持久化模型、跨平台入口与测试基线。
- [x] 设计并实现最小排序能力，补齐自动化与脚本截图验收。
- [x] 提交小 checkpoint，执行 `CONFIGURATION=Release scripts/build_install_all.sh`，由 Codex 标记完成并移除活动链接。

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
- [x] Checkpoint C：实现、聚焦验证、脚本截图与实现提交。
- [x] Checkpoint D：Release 全设备安装、签名/版本核验与收口。

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
- [x] `/root/task36_persistence`：已交付 Category order models、repository、store-scoped coordinator、facade 与 core unit tests；全程未构建、未创建设备。
- [x] `/root/task36_ui`：已交付排序 Sheet、统一路由/host、Tasks 与 macOS command 入口、三语本地化和 source contract tests；全程未构建、未创建设备。
- [x] `/root/task36_uitest`：已交付 `timetrackerUITests.swift` 的语义化三平台自动化路径与截图；全程未构建、未创建设备、未操作窗口。
- [x] 主代理：已审核并分文件提交实现；独占完成 build/test/XCUITest/owned simulator 与截图，未与其他 agent 共享 TestManager 或窗口资源。
- UI 验收由主代理创建并登记 owned simulator；每批结束必须终止 App/runner、shutdown/delete 设备并清理临时产物。
- [x] Owned iPhone batch：`TimeTracker Task36 iPhone` / `350C4037-235B-4B88-9CAC-CBB6E9322036`（iPhone 17 Pro，iOS 27.0）。XCUITest 通过；脚本成功打开排序页、以语义 Move Up 将 Study 移到 Work 前、提交并验证 Tasks 顺序。两张 1206×2622 XCTest 截图经主代理原分辨率检查：原生 Sheet、44pt 操作、禁用边界、拖动柄和最终层级均清晰，无裁切/重叠。App/runner 已终止，device 已 shutdown/delete，derived data、xcresult 与导出附件已清理，无 Booted device。
- [x] Owned iPad batch：`TimeTracker Task36 iPad` / `593D0433-916B-4E63-A791-55AAB687DC6D`（iPad Pro 11-inch M5，iOS 27.0）。首跑定位到测试只查询自定义 Sidebar toggle，补齐项目既有的系统 `Show Sidebar` 语义 fallback 后复跑 1/1 通过；排序、Tasks 与 persistent Sidebar 的 Study→Work 顺序均由脚本断言。两张 1668×2420 XCTest 横屏截图经主代理原分辨率检查：居中 Sheet、双栏布局、Sidebar 同步顺序无裁切/重叠。App/runner 已终止，device 已 shutdown/delete，derived data、两次 xcresult 与导出附件已清理，无 Booted device。
- [x] Owned macOS batch：host `My Mac`。同一 Task36 XCUITest 1/1 通过；窗口可见性只由 XCTest 通过现有 Window menu semantic identifiers 处理。两张 1440×1720 窗口截图经主代理原分辨率检查：深色模式 Sheet、Move Up/Down、Study→Work 的主列表与 Sidebar 顺序清晰，无裁切/重叠。测试 App/runner 已终止，derived data、xcresult 与导出附件已清理，无 owned process。

## 已提交实现 checkpoint

- `a14900c`：持久化整表 Category 顺序与并发安全测试。
- `d7702f2`：三平台排序 Sheet、入口、路由和本地化。
- `123d39a`：语义化三平台 XCUITest 与截图路径。
- `ddbda8e`：折叠 Sidebar 的系统语义 toggle fallback。

## 聚焦验证结果

- macOS：`StoreScopedTaskCategoryCommandCoordinatorTests` 与完整 `TaskUIContractTests` 通过。
- iPhone 17 Pro / iOS 27：Task36 XCUITest 1/1 通过，Tasks 顺序与两张截图通过验收。
- iPad Pro 11-inch / iOS 27：fallback 修正后 Task36 XCUITest 1/1 通过，Tasks + persistent Sidebar 与两张截图通过验收。
- macOS 27：Task36 XCUITest 1/1 通过，Tasks + Sidebar 与两张窗口截图通过验收。
- 三个平台的 UI 导航、排序、Sidebar 展开、窗口定位与截图均由 XCTest/XCUITest 完成；没有物理机交互或手动窗口调试。

## Release 全设备安装与收口

- 精确执行 `CONFIGURATION=Release scripts/build_install_all.sh`，退出码 0；iOS、内嵌 watchOS companion 与 macOS Release 构建均成功，macOS App 已复制到 `/Applications/timetracker.app`。
- iOS、Watch 与 macOS 产物版本一致为 `1.1.88 (143)`；bundle IDs 分别为 `me.mezorewww.timetracker`、`me.mezorewww.timetracker.watchkitapp`、`me.mezorewww.timetracker`。
- 三份产物均通过 `codesign --verify --deep --strict`，TeamIdentifier 为 `LT98S43NKA`；macOS 可执行文件由 `lipo` 确认为 `x86_64 arm64` universal binary。
- 可用物理设备 `iPad Pro M4` 已由脚本完成安装；随后仅以 `devicectl device info apps` 只读确认安装版本为 `1.1.88 (143)`。`iPhone Air` 当时不可用；没有启动、交互或截图任何物理设备 App。
- 已移入废纸篓 `build/Install`，确认无 Booted simulator，且无残留 `xcodebuild`、`xctest`、UI runner 或 Watch extension 进程；根目录不存在 `README.md`/`readme.md`。
