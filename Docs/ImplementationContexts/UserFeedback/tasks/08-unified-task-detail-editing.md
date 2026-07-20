# 08：统一任务详情与编辑实现记忆

> 本文件只保存实现、验证和子代理编排记忆，不是任务来源。范围与完成状态必须重新读取
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中唯一的 `[~]` 项。

## 当前阶段

- [x] 已领取当前反馈，并完成快速操作、任务详情/编辑状态、Markdown 备注和保存链路审计。
- [x] 已用失败测试锁定自动保存、导航前落盘、验证/冲突恢复和 baseline 重建语义。
- [x] 已把已验证的自动保存核心接入 canonical task detail，并稳定工具栏。
- [x] 已让 autosave rebase 原位推进 baseline/持久 ID，并在 checklist 身份不完整时失败为冲突，避免覆盖聚焦输入或漂移身份。
- [~] 正在迁移受自动保存语义影响的 4 条跨平台 UI 测试。
- 下一 checkpoint：Mac 解锁后，用显式 owned 设备验证聚焦输入、导航 flush 与稳定工具栏。

## 反馈边界

- 移除快速操作中的 Edit 入口。
- 合并任务详情与编辑页面，重新审视普通尺寸下的信息与编辑排版。
- 任务备注使用用户指定的 `https://github.com/Lakr233/MarkdownView`。
- 合并后的编辑自动保存，不再要求用户手动点击 Save。
- 不读取或处理当前 `[~]` 之后的反馈。

## 验收清单

- [x] 盘点所有任务详情、编辑、快速操作和保存入口
- [x] 核对 MarkdownView 当前依赖、API、平台支持和许可证
- [x] 形成 iPhone、iPad、macOS 的 HIG 布局与编辑交互决策
- [x] 用失败测试锁定入口、统一页面、Markdown 与自动保存语义
- [ ] 实现并分小 checkpoint 提交
- [ ] 验证 iPhone、iPad、macOS 普通路径并适当截图
- [ ] 运行 `CONFIGURATION=Release scripts/build_install_all.sh`
- [ ] 核验安装版本与签名，释放 owned 设备、进程和临时产物
- [ ] 由 Codex 在 `Docs/userfeedback.md` 标记完成并移除活动软链接

## 实现约束

- 必须遵循仓库内 Apple HIG 与 SwiftUI 专家技能；优先原生导航、表单、焦点与保存反馈。
- 自动保存必须定义明确的提交时机、失败反馈、并发/草稿恢复与离开页面语义，不能静默丢失。
- 复用现有领域命令和已引入的 MarkdownView，不自绘 Markdown 渲染器或新增重复依赖。
- 保持任务层级、计时可用性、归档、清单、计划和草稿恢复等现有不变量。

## 子代理编排

- [x] UI/HIG 与跨平台入口审计：详情/编辑已统一；日常编辑应移除 Save/Cancel，保持 Add Time/More 稳定。
- [x] 状态、持久化、自动保存与草稿恢复审计：复用原子保存、baseline 冲突检测和恢复稿；已有任务防抖保存，离开前同步 flush。
- [x] MarkdownView API、依赖质量和测试覆盖审计：4.1.7 精确锁定、MIT、平台兼容；保留链接/高度薄适配层。
- [x] 独立复核自动保存 UI 接线中的生命周期、导航与恢复竞态。
- [x] 盘点并规划需要迁移到自动保存语义的跨平台 UI 测试。

## 已确认的实现决策

- 反馈中的独立任务 Edit 入口和详情/编辑合并已由现有 canonical `TaskDetailWorkspace` 覆盖；不改 Home 的“快速开始”固定任务配置。
- 自动保存仅适用于已有 canonical task。新建任务继续显式 Create；恢复副本继续显式 Save as New，避免生成空任务或重复副本。
- 使用原生 Observation、Swift Concurrency 和 SwiftData；不新增自动保存依赖。
- 有效修改防抖 450ms 保存；受控导航、应用失活和页面退出前同步 flush。验证失败、持久化失败或 stale 时保留草稿并阻止静默离开。
- 成功与短暂保存过程保持静默，失败提供 Retry。Add Time 与 More 不因编辑状态换位。
- MarkdownView 保持 4.1.7（revision `84381f59cc52606ffc198fb2fdac8e6a44abe528`）。它虽低于 1k stars，但为用户点名依赖；维护活跃且精确锁定。
- 不删除 `TaskNotesMarkdownRepresentable`：上游 SwiftUI `MarkdownView` 没有公开 `linkHandler`，该薄适配层负责链接交给 `openURL` 与 List 内自然高度，未自建解析器或渲染器。

## 失败测试边界

- 快速连续输入只提交最后版本；取消的旧防抖不能晚到覆盖。
- 无效草稿不写库；恢复有效后自动排程。
- 导航前先 flush；成功继续，失败/冲突/无效时留在详情并保留恢复稿。
- 保存成功推进 mutation baseline，不重置焦点；失败与 stale 不丢当前草稿。
- 已有任务详情不再出现手动 Save/Cancel，Add Time/More 始终可用；新建和恢复流程仍保留各自显式提交动作。
- Markdown source/preview、链接桥接、精确依赖 pin 与三平台布局保持。

## 运行资源所有权

- 静态审计阶段不启动模拟器、TestManager 或 Instruments。
- 后续设备矩阵由 primary agent 分配唯一 UDID 并记录；每个批次完成后清理 owned 资源。

## Checkpoint 记录

- [x] 领取反馈、建立实现记忆和活动链接：`564dce9`。
- [x] 完成 UI/HIG、自动保存链路与 MarkdownView 4.1.7 只读审计。
- [x] 自动保存核心红灯转绿：快速输入合并、导航 flush、验证阻断、失败重试、冲突保留，以及 checklist identity/baseline 重建；macOS 目标 34 项测试通过。
- [x] 自动保存 UI 接入：已有任务移除 Save/Cancel；450ms 防抖、失焦/失活/退出/导航 flush、失败 Retry、冲突恢复、原生返回保护和 checklist 焦点稳定；综合 80/80 测试通过，最后同步细化复测 17/17 通过。
- [x] 自动保存 rebase 加固：保存回执不再整体替换可见 draft，只原位推进 mutation baseline 与已完整双射的 checklist 持久 ID；映射分歧返回 conflict 且不修改当前输入。TaskEditorSession、autosave controller、workspace contract 共 24 条目标测试通过，相关 task-editor 源码结构检查通过。
- [~] 当前 checkpoint：迁移 4 条跨平台 UI 测试到自动保存语义。

## 当前验收阻塞

- 2026-07-21：macOS 已锁屏，Computer Use 无法自动解锁；真实 macOS UI 测试需用户手动解锁后继续。UI 测试源码已随签名测试构建成功编译，尚未把设备 UI 结果标为通过。
