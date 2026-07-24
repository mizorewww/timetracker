# 44：子任务勾选动画与位置恢复实现记忆

> 本文件只用于主代理与子代理的实现、验证和编排记忆，不是任务来源。唯一范围与状态必须重新读取
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 条目。

## 当前阶段

- [x] 领取“task详情子任务勾选完成后跑下去没有动画 / 取消勾选无法回到原位置”反馈。
- [~] 审计任务详情子任务列表的完成排序、动画与身份机制(对照任务11的 checklist 动画)。
- [ ] 确定最小修复:完成时子任务动画移动到底部;取消完成动画回到按原顺序的位置。
- [ ] 实现并运行聚焦测试与 iPhone/iPad/macOS 模拟器截图验收。
- [ ] 执行 `CONFIGURATION=Release scripts/build_install_all.sh`(实体机安装失败不阻塞),标记完成并移除活动链接。

## 唯一反馈边界

- 只修任务详情里“子任务”(subtask)行的勾选完成动画与位置恢复;checklist 勾选已有任务11的行为,可作对照但不在本任务重做。
- 不领取 iOS Shortcut、quickstart 排序或其他反馈。
- 以普通文字大小、正常交互路径、三平台系统约定为优先。

## 强制约束

- 完整遵循仓库本地 `apple-hig` 与 `swiftui-expert-skill`;所有 UI 导航、断言与截图只用 XCTest/XCUITest 脚本。
- 实体机器不做测试;模拟器验收后 shutdown+delete 并清理 /tmp 产物。
- 优先复用 SwiftUI 动画与现有组件;除用户建议外不引入 GitHub 少于 1k stars 的库。
- 每个 checkpoint 只暂存本任务的已完成变更;保留用户在反馈文件中的其他内容。

## Checkpoint 编排

- [x] Checkpoint A：领取任务、创建实现记忆与 active link。
- [ ] Checkpoint B：审计子任务列表排序/动画/身份。
- [ ] Checkpoint C：实现动画与位置恢复并补齐聚焦测试。
- [ ] Checkpoint D：三平台模拟器验收与资源清理。
- [ ] Checkpoint E：Release 构建安装、核验与收口。

## 资源所有权

- [~] 主代理：任务状态、编排、集成、所有 build/simulator/XCUITest/screenshot/Release 批次与清理。
- [ ] 待分配：子任务列表实现审计。

## 已提交 checkpoint

- [~] 待提交：领取任务、实现记忆与 active link。
