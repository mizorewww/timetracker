# 19：不同 AI 提示词均可编辑实现记忆

> 本文件只用于主代理与子代理的实现、验证和编排记忆，不是任务来源。唯一范围与状态必须重新读取
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 条目。

## 当前阶段

- [x] 读取唯一反馈并领取任务。
- [ ] 审计现有 AI 配置、提示词种类、默认值、持久化和调用路径。
- [ ] 参考 Apple HIG、SwiftUI 专项规范与成熟库，确定编辑体验和依赖边界。
- [ ] 实现每一种现有 AI 提示词都可分别编辑、保存、恢复默认并被对应调用读取。
- [ ] 完成定向测试、owned 模拟器普通交互与截图验收并清理资源。
- [ ] 执行 `CONFIGURATION=Release scripts/build_install_all.sh` 并由 Codex 标记完成。

## 唯一反馈边界

- 配置 AI 时，产品中已经存在的不同 AI 提示词都应该可以编辑。
- 本任务只覆盖提示词配置与对应读取闭环，不领取下一条“Generate task plan 一次生成多个任务”的功能设计。
- 下一条反馈下的“单独写文档”和“编辑提示词采用 MarkdownView”是后续任务的子项，本任务不提前实现。
- 不领取 Apple Health 自动展示、Inbox、Timeline、Live Activity、首页图表或 category 等后续反馈。

## 强制约束

- 先列出真实存在的 prompt consumer 与当前唯一可编辑项，避免凭名称制造并不存在的 AI 功能。
- 默认提示词、用户覆盖值、空值/恢复默认、持久化/同步和调用端读取必须形成同一数据模型，不能只增加无效文本框。
- 密钥继续使用现有安全存储；本任务不得把 API key 或其他敏感信息写入普通偏好、日志、截图或测试夹具。
- 设置界面遵循 Apple HIG 的清晰分组、可撤销编辑和平台导航惯例；普通文字尺寸优先。
- 优先系统 SwiftUI 与仓库现有成熟依赖；一般拒绝 GitHub 低于 1k stars 的非用户指定库，也不为简单文本编辑引入包装库。
- UI 操作与截图只使用 owned 模拟器；物理 iPhone/iPad 只做最终 Release 安装和只读核验，不启动、不操作、不截图。
- 每个小 checkpoint 验证后提交；只暂存本任务状态差异，保护 `Docs/userfeedback.md` 中用户新增内容。

## 待审计问题

- 当前有哪些 AI prompt consumer，各自的默认提示词位于何处，是否存在硬编码或重复来源。
- 当前设置页只允许编辑哪一种 prompt，保存值是否真正进入 request builder。
- 用户覆盖值应使用现有 synced preference、设备本地 preference，还是已有的 prompt store；恢复默认的语义如何表达。
- iPhone、iPad 与 macOS 设置布局是否共享同一数据流，长文本编辑是否需要独立 sheet/editor。

## 资源所有权

- 尚未创建 simulator。开始 UI 批次时由主代理记录唯一 owned UDID，并在批次结束后终止 App、shutdown、delete，
  同时验证无 owned `xcodebuild`、`xctest`、UI runner、extension、trace 或 Booted device 残留。
