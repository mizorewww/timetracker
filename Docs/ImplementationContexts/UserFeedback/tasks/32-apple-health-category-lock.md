# 32：Apple Health 分类锁定实现记忆

> 本文件只用于主代理与子代理的实现、验证和编排记忆，不是任务来源。唯一范围与状态必须重新读取
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 条目。

## 当前阶段

- [x] 领取 Apple Health 固定任务仍可修改 category 的反馈。
- [x] 审计任务分类编辑入口、持久化命令与固定 Health catalog 不变量。
- [x] 实现最小修复并补齐 Core/UI contract 自动化测试。
- [x] 在脚本创建的 owned iPhone/iPad simulator 上执行 XCUITest 与截图验收，并释放全部 owned 资源。
- [x] 提交实现 checkpoint，精确执行 `CONFIGURATION=Release scripts/build_install_all.sh`，标记反馈完成并移除活动链接。

## 唯一反馈边界

- Apple Health catalog 生成的固定任务不能被用户改到其他 category。
- 不领取后续统计、首页、设置或其他反馈。

## 强制约束

- 完整遵循仓库本地 `apple-hig` 与 `swiftui-expert-skill` 规则；优先复用现有 SwiftUI、任务 catalog 与命令层约束。
- 如评估第三方库，必须先核验维护质量与 GitHub stars；除用户建议外不采用少于 1k stars 的库。
- UI 验收全部写成 XCTest/XCUITest；只使用明确 owned simulator，不手动调整窗口，不在物理设备启动、点击或截图。
- 每个 checkpoint 只暂存本任务变更，保护 `Docs/userfeedback.md` 中其余用户新增内容。

## Checkpoint 编排

- [x] Checkpoint A：范围领取、现状/依赖/HIG 审计与自动化验收设计。
- [x] Checkpoint B：最小实现、单元/UI contract 与脚本化验收。
- [x] Checkpoint C：Release 全设备安装、签名/版本只读核验与收口。

## 资源所有权

- owned iPhone Air：`EA6EB1ED-7BDB-4150-BA39-0A8F5C368053`（已 shutdown/delete）。
- owned iPad Pro 13-inch：`E53D2E4B-EBD1-4415-AE67-BB3F887390E7`（已 shutdown/delete）。
- 最终可靠性修正复测 owned iPhone Air：`873E1122-0AD7-4935-A3C8-200B1BC0944C`（已 shutdown/delete）。
- 三台设备均仅用于本任务脚本化 XCUITest；App/runner 已终止，Simulator/Problem Reporter 已退出，最终核验无 Booted device 或 owned 测试进程残留。

## 初始假设

- UI 隐藏或禁用分类控件只能改善入口，仍需确认 mutation 层是否拒绝对固定 Health catalog task 的分类变更，避免深链、恢复草稿或未来入口绕过。
- 优先使用项目现有类型和系统框架；预计不需要新增第三方依赖。

## 审计结论

- 精确身份以 `AppleHealthTaskCatalog` 的固定 task UUID 判定，不依赖当前已可能损坏的 assignment。
- 编辑器当前对所有根任务显示可编辑 category Picker，且 parent Picker 可通过分类继承间接改变分类。Apple Health 任务需同时保持根层级与 catalog 规范分类。
- 按 Apple HIG 使用原生 `LabeledContent` 只读行显示规范分类和锁定原因；不使用仍呈现可选择外观的 disabled Picker，也不隐藏分类上下文。
- 持久化边界需规范化 `updateTask`/`moveTask` 的 parent 与 category；catalog 普通 apply 还需修复同步、备份或历史版本绕过本地 UI 后导入的错误层级/assignment。
- 现有 catalog replay 测试中“保留用户自定义 category”的旧预期与本反馈冲突，应改为保留标题、备注、图标、颜色和归档状态，但自愈规范分类与根层级。

## 验收设计

- Core：验证本地 draft/repository 写入不能把固定 Health 任务改到其他 parent/category，普通 catalog replay 会修复已导入的错误 assignment。
- UI contract：验证固定任务分支使用稳定只读标识，普通任务仍保留原 Picker。
- XCUITest：复用确定性 Apple Health Running fixture，脚本断言只读 Exercise 分类存在、parent/category Picker 不存在，并在 owned iPhone/iPad simulator 自动滚动与截图。
- 依赖：只使用 SwiftUI、SwiftData、XCTest/Swift Testing 等系统能力，不新增第三方库。

## 已完成实现与验证

- 编辑器对精确 catalog task 显示原生 `LabeledContent` 只读规范分类与锁定原因，同时隐藏 parent/category Picker；普通任务入口不变。
- facade draft 与 repository mutation 均在首次写入前拒绝错误 parent/category；删除仍被活跃固定任务占用的规范分类也会被拒绝。
- catalog 普通 replay 以严格 LWW 修复同步、备份或旧版本带来的错误层级及 assignment，同时保留可编辑元数据。
- 最终静态审查补齐三类边界：交叉错绑的多个 canonical assignment 单轮收敛、规范分类缺失/墓碑时 mutation 前原子拒绝，以及简繁中文统一使用“Apple 健康”。
- 最新聚焦 macOS 测试：61/61 通过（catalog coordinator、Task UI contract、Apple Health reader、repository source layout）。
- iOS Apple Health reader/fixture 测试：12/12 通过，覆盖调用时选择 UI fixture，避免延迟出现真实 HealthKit 授权窗口。
- 全部 UI 验收由 XCUITest 完成：iPhone Air 与 iPad Pro 13-inch 各 1/1 通过；脚本断言只读 Exercise 分类存在、可编辑 parent/category 不存在、锁定说明紧邻分类行且 `HealthPrivacyService` 授权窗口不存在。两张 xcresult 截图附件均已人工只读检查，布局紧凑且未被系统窗口遮挡。
- 最终独立复核后，同一启动配置会复用长生命周期 UI fixture，保留 fail-once/empty-once 等一次性状态；授权窗口断言会在有界窗口内轮询 App，并仅在 `HealthPrivacyService` 前台时检查其元素。最终 iOS 组合复测 14/14 通过（12 项 reader + 分类锁定 + fail-once→Retry），优化后的分类锁定 UI 单测再跑 1/1 通过并重新检查截图。
- 全量 macOS 回归：1594 项中 1583 通过；本任务曾触发的 repository 文件行数预算已修复并单独复测通过。其余 10 个既有 source-contract/layout 失败不属于本反馈；另 1 个 archive 时间精度偶发失败单独重跑通过。
- `plutil -lint` 三套本地化通过，`git diff --check` 通过；repository 拆分文件分别为 167/179 行，符合 180 行预算。
- 未新增第三方依赖；实现只使用现有 SwiftUI/SwiftData、系统 HealthKit 与 XCTest/Swift Testing。
- 实现 checkpoint：`a1db343`（`fix: lock Apple Health task categories`），版本提升至 1.1.69 (124)。
- 精确执行 `CONFIGURATION=Release scripts/build_install_all.sh` 成功：iPhone Air 与 iPad Pro M4 均只安装未启动 1.1.69 (124)，macOS `/Applications/timetracker.app` 同版本；iOS、内嵌 Watch 与 macOS 包的严格签名验证均通过，Team Identifier 为 `LT98S43NKA`。
