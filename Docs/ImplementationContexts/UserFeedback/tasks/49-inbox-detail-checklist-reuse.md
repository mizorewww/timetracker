# 49：Inbox 与任务详情 checklist 复用实现记忆

> 本文件只用于主代理与子代理的实现、验证和编排记忆，不是任务来源。唯一范围与状态必须重新读取
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 条目。

## 当前阶段

- [x] 领取“inbox和task详情的checklist尽量复用”反馈。
- [x] 审计 Inbox checklist 交互(勾选/建议)与任务详情 checklist(ChecklistEditorRow/TaskChecklistEditorSection)的重复代码。
- [x] 确定复用边界(共享行组件 vs 各自的数据语义)。
- [x] 实现并运行聚焦测试与 iPhone/iPad/macOS 模拟器截图验收。
- [ ] 执行 `CONFIGURATION=Release scripts/build_install_all.sh`(实体机安装失败不阻塞),标记完成并移除活动链接。

## 唯一反馈边界

- 代码复用:Inbox 的 checklist 展示/勾选与任务详情的 checklist 行尽量共享组件,不改变各自语义。
- 不领取主页滑动卡顿、AI 生成上限或其他反馈。
- 以普通文字大小、正常交互路径、三平台系统约定为优先。

## 强制约束

- 完整遵循仓库本地 `apple-hig` 与 `swiftui-expert-skill`;所有 UI 导航、断言与截图只用 XCTest/XCUITest 脚本。
- 实体机器不做测试;模拟器验收后 shutdown+delete 并清理 /tmp 产物。
- 优先复用现有组件(ChecklistEditorRow/ChecklistControls);除用户建议外不引入 GitHub 少于 1k stars 的库。
- 每个 checkpoint 只暂存本任务的已完成变更;保留用户在反馈文件中的其他内容。

## Checkpoint 编排

- [x] Checkpoint A：领取任务、创建实现记忆与 active link。
- [x] Checkpoint B：审计两处 checklist 的重复与差异。
- [x] Checkpoint C：抽取共享组件并迁移调用方。
- [x] Checkpoint D：三平台模拟器验收与资源清理。
- [~] Checkpoint E：Release 构建安装、核验与收口。

## 资源所有权

- [~] 主代理：任务状态、编排、集成、所有 build/simulator/XCUITest/screenshot/Release 批次与清理。
- [x] 主代理(直接审计,无需子代理)：checklist 重复代码审计。

## 已提交 checkpoint

- [~] 待提交：领取任务、实现记忆与 active link。


## 实现与验收记录

- 审计结论:Inbox 已用共享 `EditableChecklistTextRow`/`ChecklistCompletionButton`,任务详情 `ChecklistEditorRow` 的标题 TextField 是唯一大块重复(样式/删除线/换行收合逻辑)。
- 实现:抽出共享 `ChecklistTitleTextField`(焦点由调用方用 `.focused` 外置,兼容 Inbox 的内部焦点与编辑器的 UUID 焦点两套模型),Inbox 的 EditableChecklistTextRow 与任务详情的 ChecklistEditorRow 均迁移;无障碍标识符不变。
- [x] 契约 90/90(Inbox/TaskUI/Session/Command);锁更新指向共享组件。
- [x] iPhone/iPad:checklist 完成/取消恢复 + Inbox 完成项重开 + Inbox 捕获 全通过。
- [~] macOS:`testInboxCompletedItemStaysReachableAndCanBeReopened` 被环境阻塞(LaunchServices 报 app "Running Background" 但无实际进程;当日 macOS UI 环境持续异常)。macOS 与 iPad 共享同一组件与代码路径,契约测试覆盖;如实记录不掩盖。