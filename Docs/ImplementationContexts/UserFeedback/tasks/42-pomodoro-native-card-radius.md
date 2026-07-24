# 42：番茄钟页面卡片原生圆角同步实现记忆

> 本文件只用于主代理与子代理的实现、验证和编排记忆，不是任务来源。唯一范围与状态必须重新读取
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 条目。

## 当前阶段

- [x] 领取“番茄钟页面的卡片是自己画的，要么切换成原生，要么圆角和原生同步”反馈。
- [~] 审计番茄钟页面自绘卡片与同屏/同平台原生卡片(任务39结论:iOS grouped = 26pt continuous 无描边;桌面 appCard = 8pt + 描边)的差异。
- [ ] 确定方案:复用任务39的统一卡片语言,圆角与原生同步。
- [ ] 实现并运行聚焦测试与 iPhone/iPad/macOS 模拟器截图验收。
- [ ] 执行 `CONFIGURATION=Release scripts/build_install_all.sh`(实体机安装失败不阻塞),标记完成并移除活动链接。

## 唯一反馈边界

- 只统一番茄钟(Focus/Pomodoro)页面卡片的容器风格(圆角/背景/描边)。
- 不领取 AI 提示词、子任务动画或其他反馈。
- 以普通文字大小、正常交互路径、三平台系统约定为优先。

## 强制约束

- 完整遵循仓库本地 `apple-hig` 与 `swiftui-expert-skill`;所有 UI 导航、断言与截图只用 XCTest/XCUITest 脚本。
- 实体机器不做测试;模拟器验收后 shutdown+delete 并清理 /tmp 产物。
- 优先复用 SwiftUI 与现有 DesignSystem;除用户建议外不引入 GitHub 少于 1k stars 的库。
- 每个 checkpoint 只暂存本任务的已完成变更;保留用户在反馈文件中的其他内容。

## Checkpoint 编排

- [x] Checkpoint A：领取任务、创建实现记忆与 active link。
- [ ] Checkpoint B：审计番茄钟卡片实现与平台差异。
- [ ] Checkpoint C：实现圆角同步并补齐聚焦测试。
- [ ] Checkpoint D：三平台模拟器验收与资源清理。
- [ ] Checkpoint E：Release 构建安装、核验与收口。

## 资源所有权

- [~] 主代理：任务状态、编排、集成、所有 build/simulator/XCUITest/screenshot/Release 批次与清理。
- [ ] 待分配：番茄钟页面卡片审计。

## 已提交 checkpoint

- [~] 待提交：领取任务、实现记忆与 active link。
