# 14：Quick Start 编辑页添加流程实现记忆

> 本文件只保存实现、验证与子代理编排记忆，不是任务来源。范围与状态必须重新读取
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的唯一 `[~]` 项。

## 当前阶段

- [~] 领取反馈、读取 Apple HIG / SwiftUI 强制技能并建立活动链接。
- [ ] 审计现有 Quick Start 编辑状态、持久化命令、候选过滤、动画与测试。
- [ ] 分 checkpoint 实现并验证添加后的固定列表迁移和候选区移除。
- [ ] 使用 owned iPhone / iPad 模拟器完成普通路径与截图验收。
- [ ] 执行 `CONFIGURATION=Release scripts/build_install_all.sh`，清理资源并由 Codex 标记完成。

## 唯一反馈边界

- Quick Start 编辑页点击“添加”后，任务应以清晰但克制的动画进入固定列表。
- 已添加任务必须立即从下方候选区消失，不能同时出现在两个区域。
- 拖动手势只是用户给出的可选方案；若采用，仍必须保留可发现、可访问的按钮入口。
- 不领取或实现本条之后的任何反馈。

## 强制设计与实现约束

- Apple HIG：使用标准按钮与列表语义；插入/移除动画用于解释状态变化，必须简短、可打断，并在
  Reduce Motion 下退化为低运动量反馈；iOS/iPadOS 触控目标至少 44×44 pt，macOS 至少 28×28 pt。
- SwiftUI：`ForEach` 使用持久且唯一的任务 ID；动态列表不使用 index/offset identity；事件驱动修改用
  窄作用域 `withAnimation`，transition 位于被插入/移除的稳定行上；视图自有 `@State` 保持 private。
- 先复用现有 Quick Start 持久化命令和仓库组件，不创建第二套选择状态或写入路径。
- 优先原生 SwiftUI 动画与系统列表能力；只有原生能力无法满足反馈时才评估成熟依赖，不为增加库而增加库。
- 所有 UI 操作和截图只使用 owned 模拟器；物理设备仅用于最终 Release 安装，不启动、不操作、不截图。
- 每个小 checkpoint 验证并提交；只暂存本任务差异，保护 `Docs/userfeedback.md` 末尾 8 条用户新增反馈。

## 初始验收问题

- 当前“固定列表”和“候选区”是否来自同一 canonical selection，还是存在重复派生状态。
- 点击添加的持久化成功/失败边界在哪里；动画不得先于持久化成功制造虚假完成状态。
- 添加、移除、重排、搜索/筛选后是否仍保证集合互斥和稳定 identity。
- iPhone、iPad 和 macOS 是否共用同一编辑组件；动画与行操作需分别符合触控和指针/键盘输入。
- Reduce Motion、快速连点、并发刷新、空候选区及恢复/重启后持久化是否已有覆盖。

## Checkpoint 记录

- [~] 初始 checkpoint：领取反馈、完成强制技能读取、建立实现记忆与 active link；下一步只做静态审计，
  冻结现有行为和可复用边界后再实现。
