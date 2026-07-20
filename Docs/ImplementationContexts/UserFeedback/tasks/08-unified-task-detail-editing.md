# 08：统一任务详情与编辑实现记忆

> 本文件只保存实现、验证和子代理编排记忆，不是任务来源。范围与完成状态必须重新读取
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中唯一的 `[~]` 项。

## 当前阶段

- [~] 已领取当前反馈，正在审计快速操作、任务详情/编辑状态、Markdown 备注和保存链路。
- 下一 checkpoint：形成调用图、HIG/依赖决策、失败测试与最小实现边界。

## 反馈边界

- 移除快速操作中的 Edit 入口。
- 合并任务详情与编辑页面，重新审视普通尺寸下的信息与编辑排版。
- 任务备注使用用户指定的 `https://github.com/Lakr233/MarkdownView`。
- 合并后的编辑自动保存，不再要求用户手动点击 Save。
- 不读取或处理当前 `[~]` 之后的反馈。

## 验收清单

- [ ] 盘点所有任务详情、编辑、快速操作和保存入口
- [ ] 核对 MarkdownView 当前依赖、API、平台支持和许可证
- [ ] 形成 iPhone、iPad、macOS 的 HIG 布局与编辑交互决策
- [ ] 用失败测试锁定入口、统一页面、Markdown 与自动保存语义
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

- [ ] UI/HIG 与跨平台入口审计
- [ ] 状态、持久化、自动保存与草稿恢复审计
- [ ] MarkdownView API、依赖质量和测试覆盖审计

## 运行资源所有权

- 静态审计阶段不启动模拟器、TestManager 或 Instruments。
- 后续设备矩阵由 primary agent 分配唯一 UDID 并记录；每个批次完成后清理 owned 资源。

## Checkpoint 记录

- [~] 当前 checkpoint：领取反馈、建立实现记忆和活动链接。
