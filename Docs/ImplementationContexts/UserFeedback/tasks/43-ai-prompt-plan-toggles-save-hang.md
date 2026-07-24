# 43：AI 提示词暴露 / 计划开关 UI / 保存卡死实现记忆

> 本文件只用于主代理与子代理的实现、验证和编排记忆，不是任务来源。唯一范围与状态必须重新读取
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 条目。

## 当前阶段

- [x] 领取“AI 提示词预览/计划开关重叠/保存提示词卡死”反馈组。
- [~] 审计三条问题的现状:三个 AI 提示词的编辑/预览路径、生成计划页开关实现、提示词保存链路。
- [ ] 确定各项最小方案。
- [ ] 分 checkpoint 实现并运行聚焦测试与模拟器截图验收。
- [ ] 执行 `CONFIGURATION=Release scripts/build_install_all.sh`(实体机安装失败不阻塞),标记完成并移除活动链接。

## 唯一反馈边界(三个子项)

1. AI 的三个提示词为什么只有一个允许 MarkdownView preview:三个提示词编辑都应支持 MarkdownView 预览;提示词逻辑(输出格式、非 zero-shot、sfsymbol 全量、deepseek 思考预算/CoT)尽量暴露给用户,防止疑惑。现状已足够稳定,重点是“逻辑暴露”。
2. 生成的 plan 开关重叠在一起:复用任务详情里的开关 UI。
3. 保存 AI 提示词时卡死。

- 不领取 iOS Shortcut、quickstart 排序或其他反馈。
- 以普通文字大小、正常交互路径、三平台系统约定为优先。

## 强制约束

- 完整遵循仓库本地 `apple-hig` 与 `swiftui-expert-skill`;所有 UI 导航、断言与截图只用 XCTest/XCUITest 脚本。
- 实体机器不做测试;模拟器验收后 shutdown+delete 并清理 /tmp 产物。
- 优先复用现有组件(MarkdownView、BlossomColorPicker 等已集成库);除用户建议外不引入 GitHub 少于 1k stars 的库。
- 每个 checkpoint 只暂存本任务的已完成变更;保留用户在反馈文件中的其他内容。
- 用户提供的 deepseek API key 只用于本地功能验证,不得写入仓库或日志。

## Checkpoint 编排

- [x] Checkpoint A：领取任务、创建实现记忆与 active link。
- [ ] Checkpoint B：并行审计三条问题(提示词编辑/预览、计划开关、保存链路)。
- [ ] Checkpoint C：修复保存卡死(Bug 优先)。
- [ ] Checkpoint D：计划开关复用任务详情 UI。
- [ ] Checkpoint E：三个提示词统一 MarkdownView 预览与逻辑暴露。
- [ ] Checkpoint F：三平台模拟器验收、Release 与收口。

## 资源所有权

- [~] 主代理：任务状态、编排、集成、所有 build/simulator/XCUITest/screenshot/Release 批次与清理。
- [ ] 待分配：三条问题的代码审计。

## 已提交 checkpoint

- [~] 待提交：领取任务、实现记忆与 active link。
