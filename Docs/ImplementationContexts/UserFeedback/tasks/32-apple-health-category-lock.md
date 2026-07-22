# 32：Apple Health 分类锁定实现记忆

> 本文件只用于主代理与子代理的实现、验证和编排记忆，不是任务来源。唯一范围与状态必须重新读取
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 条目。

## 当前阶段

- [x] 领取 Apple Health 固定任务仍可修改 category 的反馈。
- [~] 审计任务分类编辑入口、持久化命令与固定 Health catalog 不变量。
- [ ] 实现最小修复并补齐自动化测试与必要的脚本化截图验收。
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

- [~] Checkpoint A：范围领取、现状/依赖/HIG 审计与自动化验收设计。
- [ ] Checkpoint B：最小实现、单元/UI contract 与脚本化验收。
- [ ] Checkpoint C：Release 全设备安装、签名/版本只读核验与收口。

## 资源所有权

- 当前没有 owned simulator、测试 runner 或 Instruments 批次。

## 初始假设

- UI 隐藏或禁用分类控件只能改善入口，仍需确认 mutation 层是否拒绝对固定 Health catalog task 的分类变更，避免深链、恢复草稿或未来入口绕过。
- 优先使用项目现有类型和系统框架；预计不需要新增第三方依赖。
