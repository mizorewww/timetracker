# 32：Apple Health 分类锁定实现记忆

> 本文件只用于主代理与子代理的实现、验证和编排记忆，不是任务来源。唯一范围与状态必须重新读取
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 条目。

## 当前阶段

- [x] 领取 Apple Health 固定任务仍可修改 category 的反馈。
- [x] 审计任务分类编辑入口、持久化命令与固定 Health catalog 不变量。
- [~] 实现最小修复并补齐自动化测试与必要的脚本化截图验收。
- [ ] 精确执行 `CONFIGURATION=Release scripts/build_install_all.sh`，标记反馈完成并移除活动链接。

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
- [~] Checkpoint B：最小实现、单元/UI contract 与脚本化验收。
- [ ] Checkpoint C：Release 全设备安装、签名/版本只读核验与收口。

## 资源所有权

- 当前没有 owned simulator、测试 runner 或 Instruments 批次。

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
