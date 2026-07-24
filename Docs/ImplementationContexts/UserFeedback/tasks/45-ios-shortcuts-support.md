# 45：iOS Shortcut 支持与设计文档实现记忆

> 本文件只用于主代理与子代理的实现、验证和编排记忆，不是任务来源。唯一范围与状态必须重新读取
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 条目。

## 当前阶段

- [x] 领取“iOS shortcut支持&文档(请开一个文件夹讲shortcut设计)”反馈。
- [x] 审计现有 App Intents/Shortcuts 能力(锁域注释提到 Shortcuts 进程)与缺口。
- [x] 在 `Docs/Shortcuts/` 开文件夹写设计文档(能力矩阵、意图清单、参数、示例、限制)。
- [x] 实现缺口的 App Intents 并运行聚焦测试与模拟器验收。
- [x] 执行 `CONFIGURATION=Release scripts/build_install_all.sh`(实体机安装失败不阻塞),标记完成并移除活动链接。

## 唯一反馈边界

- iOS Shortcut(App Intents)支持 + 设计文档文件夹。
- 不领取 quickstart 排序、iPad/mac Now 同步或其他反馈。
- 以普通文字大小、正常交互路径、三平台系统约定为优先。

## 强制约束

- 完整遵循仓库本地 `apple-hig` 与 `swiftui-expert-skill`;所有 UI 导航、断言与截图只用 XCTest/XCUITest 脚本。
- 实体机器不做测试;模拟器验收后 shutdown+delete 并清理 /tmp 产物。
- 优先复用 App Intents 框架与现有命令路径;除用户建议外不引入 GitHub 少于 1k stars 的库。
- 每个 checkpoint 只暂存本任务的已完成变更;保留用户在反馈文件中的其他内容。

## Checkpoint 编排

- [x] Checkpoint A：领取任务、创建实现记忆与 active link。
- [x] Checkpoint B：审计现有 Shortcuts 能力与命令路径。
- [x] Checkpoint C：写 `Docs/Shortcuts/` 设计文档。
- [x] Checkpoint D：实现缺口 intents + 聚焦测试。
- [x] Checkpoint E：模拟器验收、Release 与收口。

## 资源所有权

- [x] 主代理：任务状态、编排、集成、所有 build/simulator/XCUITest/screenshot/Release 批次与清理。
- [x] 主代理(直接审计,无需子代理)：App Intents 现状审计。

## 已提交 checkpoint

- [x] `c07fc390` 之前的实现提交:新 intents + 命令层 + 设计文档(1.1.125 (180));领取任务与 active link 创建时已提交。


## 审计与实现记录

- 现状:`AddInboxItemIntent`/`StartTimerIntent`/`StopTimerIntent` + Task/RunningTimer 实体 + AppShortcutsProvider 已存在且走统一命令层。
- 缺口补齐:`GetActiveTimersIntent`(查询运行中计时,返回值)、`StopAllTimersIntent`(全停);命令层新增 `stopAllTimersMutation`(逐段独立提交,事件聚合一次提交后效果)。
- 设计文档:`Docs/Shortcuts/README.md`(能力矩阵、实体语义、典型用法、架构决策、限制、测试)。
- [x] `CoreSystemActionCommandTests` 全绿(含新 stop-all 单测与薄封装契约更新)。
- [x] iPhone 模拟器 launch 冒烟测试通过;owned 模拟器已删除。
- [x] `CONFIGURATION=Release scripts/build_install_all.sh`:iOS/macOS BUILD SUCCEEDED,iPhone Air 已装 `1.1.125 (180)`,无设备安装失败。
- [x] 反馈已由主代理标记完成,active link 已移除;/tmp 产物已清理。