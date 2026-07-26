# 57：任务详情图标行右侧间距实现记忆

> 本文件是主代理与子代理的实现、验证和编排记忆。任务内容与状态的唯一来源仍是
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 条目。

## 当前阶段

- [x] 按文档顺序领取“任务详情图标右侧有奇怪空间”反馈。
- [x] 审计任务详情图标入口的布局 owner、导航行为、平台差异与历史边界。
- [~] 先写普通字号 UI 验收清单和失败证据。
- [ ] 做最小实现并补充稳定的自动化几何/交互断言。
- [ ] 运行格式、本地化、单元测试和 iPhone/iPad/macOS 截图验收。
- [ ] 提交小 checkpoint，执行 Release 全设备安装，标记反馈完成并移除活动链接。

## 唯一范围

- 修正任务详情中可点击图标入口右侧的异常空白，让图标、标题/提示和系统 disclosure
  行为符合当前 Form/List 的平台布局。
- 保留点击图标进入图标编辑页面的既有功能、标识、草稿状态和自动保存语义。
- 不顺带领取 Analytics 闪烁、AI、Release 测试数据或 Apple Health 后续反馈。

## 强制约束

- 主代理完整遵循仓库本地 `apple-hig` 和 `swiftui-expert-skill`。
- 优先使用 SwiftUI 原生 `NavigationLink`、`LabeledContent`、Form/List row 与系统间距；
  系统组件能覆盖时不自绘 disclosure，也不引入第三方 UI 库。
- UI 变更先建立普通字号验收清单；完成后用脚本化 XCUITest 和截图覆盖
  iPhone、iPad、macOS。
- 每个模拟器登记名称和 UDID，结束后终止 App/Runner、关机并删除。
- `Docs/userfeedback.md` 中用户并行新增或重新打开的其他条目不纳入本任务提交。

## Checkpoint 编排

- [x] Checkpoint A：领取、现状/历史/测试审计、验收契约。
- [ ] Checkpoint B：测试先行、最小布局修正和文档更新。
- [ ] Checkpoint C：跨平台截图、完整门禁、Release 全设备安装和反馈收口。

## 资源所有权

- 尚未创建模拟器或测试进程。

## 审计结论

- 布局 owner 是 `TaskDetailIdentityRow.identitySummary`：44pt `TaskIcon` 与标题区本应由
  外层 `HStack(spacing: 14)` 控制。
- 回归由提交 `36d697b6` 引入：当时把固定尺寸图标包进 iOS `NavigationLink`，但详情行
  没有像现有清单编辑行一样应用 `.buttonStyle(.plain)`。位于 `List`/`Form` 的默认
  导航链接因此可以把自身扩展为带 disclosure 语义的行内容，在图标右侧保留额外宽度。
- macOS 分支本来就是 plain `Button` + popover；修复应只补齐共享调用点的控件样式，
  不改导航目的地、草稿绑定、自动保存或 macOS 呈现方式。
- 现有 XCUITest 只验证进入选择器并截取进入后的页面，未保存详情行修复前截图，也未
  约束图标点击元素的宽度和图标到标题的可见间距。

## UI 验收清单

- [ ] 图标入口在普通字号下保持约 44pt 的原生最小点击尺寸，不再横向膨胀。
- [ ] 图标入口右边缘到标题输入框左边缘保持设计系统 14pt 间距（自动化容差 10...18pt）。
- [ ] 点击图标仍进入图标编辑页面，保留现有 push/popover 平台语义。
- [ ] iPhone compact-width 与 iPad/macOS regular-width 均不出现双 disclosure、截断或
  不对称 padding。
- [ ] 保留既有 accessibility identifier/label、键盘/指针行为和任务详情草稿语义。

## 测试先行契约

- 扩充 `testTaskDetailIconOpensSymbolColorPicker`，先等待标题输入框并截取详情 identity
  行，再断言图标入口宽度不超过 48pt、图标与标题间距在 10...18pt，最后继续验证进入
  共享图标选择器。
- 修复前 iOS 运行必须以几何断言失败并留下截图；修复后三平台复用同一交互测试。

## 库策略

- 首选 Apple SwiftUI 与项目现有 DesignSystem；目前没有引入第三方库的理由。
- 若审计发现系统组件无法覆盖，再先核查候选库的维护状态、许可证、近期发布和至少
  1k GitHub stars。
