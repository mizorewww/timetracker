# 15：侧边栏计时状态对齐与任务间距实现记忆

> 本文件只保存实现、验证与子代理编排记忆，不是任务来源。范围与状态必须重新读取
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的唯一 `[~]` 项。

## 当前阶段

- [x] 领取反馈、读取 Apple HIG / SwiftUI 强制技能并建立活动链接。
- [~] 审计侧边栏任务行的视图层级、对齐轴、默认行 inset 与自定义 spacing。
- [ ] 实现最小修复并补齐稳定的布局契约测试。
- [ ] 使用 owned iPhone / iPad 模拟器完成普通路径与截图验收。
- [ ] 执行 `CONFIGURATION=Release scripts/build_install_all.sh`，清理资源并由 Codex 标记完成。

## 唯一反馈边界

- 侧边栏中“正在计时”状态图标与任务图标应处于同一水平中心线。
- 相邻任务行的垂直节奏应一致，消除当前异常的额外间距。
- 不领取或实现本条之后的任何反馈。

## 强制设计与实现约束

- Apple HIG：侧边栏使用熟悉的 SF Symbols 与系统选择/列表行为；状态图标颜色只在表达运行状态时使用；
  保持适合 iPadOS/macOS 的紧凑但可读信息密度，并适应可调整窗口宽度。
- SwiftUI：一个任务对应一个稳定 identity 的单根 row；优先在同一 `HStack` 中用 `.center` 对齐，避免
  用独立 overlay/offset 修补；明确区分 `List` 的 row inset/spacing 与 row 内 padding，防止垂直间距叠加。
- 先复用仓库现有侧边栏、任务图标和计时状态组件，不创建第二套计时状态或自定义列表系统。
- 原生 SwiftUI `List`、布局容器与 SF Symbols 足以覆盖时不新增依赖；第三方库必须有清晰边界并通过成熟度审计。
- 所有 UI 操作和截图只使用 owned 模拟器；物理设备仅用于最终 Release 安装，不启动、不操作、不截图。
- 每个小 checkpoint 验证并提交；只暂存本任务差异，保护 `Docs/userfeedback.md` 末尾 8 条用户新增反馈。

## 初始验收问题

- 正在计时图标是否由 overlay、独立 frame、baseline alignment 或条件分支导致垂直偏移。
- 异常间距来自 `List` section/row 默认值、`listRowInsets`、row 内 padding，还是条件状态视图改变行高。
- iPadOS 与 macOS 是否共用 row；普通任务与正在计时任务的测量高度是否一致。
- 修复后选择态、点击目标、截断、计时刷新与列表 identity 是否保持稳定。

## Checkpoint 记录

- [~] 初始 checkpoint：领取反馈、完成强制参考读取、建立实现记忆与 active link。

## 依赖与互联网库审计

- 待核对 Apple 官方 SwiftUI `List` / `HStack` / alignment 文档以及仓库现有依赖。
- 本项优先使用 Apple SwiftUI；不为标准侧边栏行布局引入整套第三方 UI 框架。

## 模拟器验收与资源所有权

- 待创建 fresh owned iPhone / iPad 模拟器并在此记录 UDID；不得复用或操作他人拥有的设备。
- 截图应同时包含至少两个相邻任务与一个正在计时任务，核对图标中心线、行高和任务间垂直节奏。
- 批次结束后终止 App/runner，shutdown + delete owned 模拟器，并确认无 owned 测试/trace 进程残留。
