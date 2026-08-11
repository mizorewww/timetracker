# 83：Checklist 行对齐与超长内容实现记忆

Status: Complete

状态：2026-07-28 完成

> 本文件是主代理与子代理的实现、验证和编排记忆；唯一任务来源仍是
> [`Docs/userfeedback.md`](../../../../userfeedback.md) 中对应的 `[~]` 条目。

## 认领的反馈条目

- Checklist 图标与文本在行内应按视觉中心对齐。
- 超长 checklist 文本应保持可读、可编辑，不能被单行截断或破坏操作区域。
- Checklist 文本的垂直位置应从行的中部开始呈现，而不是贴近顶部或底部。

## 初始范围

- 审计任务详情、新建/编辑、只读展示、iPhone/iPad/macOS 中 checklist row 的共享与
  平台专用实现。
- 先明确图标、完成控件、文本、拖拽与二级操作的布局契约，再修改最小所有者。
- 不改变 checklist 持久化、排序、AI visual、删除或完成语义。
- 优先使用 SwiftUI 原生布局；只有出现明确能力缺口时才评估成熟依赖。

## UI 验收清单（改动前）

- [x] 正常字号下，完成控件、图标、菜单与 checklist 整个文本块共享视觉中心。
- [x] 两行及多行长文本完整换行，不挤压完成、拖拽或二级操作控件。
- [x] 编辑时多行文本可继续输入并自然增高，插入点和键盘焦点稳定。
- [x] iPhone、iPad 与 macOS 的相同语义保持一致，同时遵守各平台点击目标和间距。
- [x] 正常长度 checklist 的行高和信息密度不出现无谓回退。
- [x] XCTest/XCUITest 与正常字号截图覆盖短文本、超长文本和编辑态。

## 测试优先清单

- [x] 先补布局 policy / presentation 边界测试或 UI 自动化红测。
- [x] 实现后跑受影响定向测试、完整 `make test`、格式与本地化门禁。
- [x] iPhone/iPad/macOS 正常字号截图验收并清理自有资源。
- [x] `make build-install-all` 安装最终任务版本。

## Checkpoint 编排

- [x] A：完成视图所有者、平台差异、HIG 与测试边界审计。
- [x] B：新增先失败的布局/交互回归测试。
- [x] C：实现居中、多行与操作区域保护。
- [x] D：完成定向、全量、截图、Release 全设备安装与关闭。

## 库策略

- 先核实 SwiftUI `TextField(axis:)`、`TextEditor`、alignment guide、
  `fixedSize` 与 layout priority 能力。若原生能力足够，不新增依赖。
- 若必须引入库，要求维护活跃、许可证合适，且除用户指定外通常不少于 1k stars；
  记录版本、维护状态、替代方案与使用边界。

## 子代理编排

- 主代理负责范围、活动记忆、模拟器/设备所有权、集成、提交和收口。
- 子代理可并行进行 SwiftUI/HIG、布局测试与跨平台只读审计；不得与主代理并发修改
  同一文件。

## 进度记录

- 2026-07-28：按反馈顺序认领任务，建立 `~83` 活动实现记忆并进入 Checkpoint A。
- 2026-07-28：三路只读审计确认生产路径统一经过 `ChecklistEditorRow`；根因是
  `.top` 对齐、完成控件额外 top padding，以及 `1...4` 的封闭行数上限。Inbox
  使用另一共享行的显式居中策略，不在本任务中改动。
- 2026-07-28：新增 iPhone/macOS 共用 UI 红测；改动前短标题的完成控件与文本中心
  相差 13 pt，测试按预期失败。验收契约统一为“操作控件围绕整个多行文本块居中”，
  并覆盖无上限增高、焦点连续输入、键盘保留和最小操作目标。
- 2026-07-28：采用原生 SwiftUI `.center`、`.lineLimit(nil)` 与
  `.layoutPriority(1)` 修复，不新增第三方依赖；Inbox 继续保留既有 `1...5` 上限。
- 2026-07-28：按 Apple `EnvironmentValues.lineLimit` 的无上限合同采用显式 `nil`。
  XCUITest 在软件键盘覆盖期间只报告 TextField 的可见裁剪 frame，因此改用 test-only
  seed 在键盘出现前测量完整行；保留大于四行的断言防止回退。
- 2026-07-28：iPhone 17 Pro、11-inch iPad Pro (M4) 与 macOS 定向 UI 测试通过。
  三个平台都验证短/长标题的几何中心、完整值和最小操作目标；iPhone/iPad 额外验证
  完整重输、无二次点按继续输入和软件键盘保留。三张普通字号截图已人工检查；macOS
  截图前关闭了系统 `WidgetRenderer_Activities` 崩溃报告窗口并重拍干净证据。
- 2026-07-28：`make format`、`make format-check`、`make localization-check` 通过；
  完整 `make test` 通过 1,447 tests / 162 suites。
- 2026-07-28：实现 checkpoint 已提交为 `4582169d`；`make build-install-all`
  成功构建并安装 Release `1.1.292 (347)` 到 iPad Pro M4、iPhone Air（包含并验证
  Watch companion）和 `/Applications/timetracker.app`。当前未发现可直接安装的
  物理 Watch，配对设备开启 Automatic App Install 后由 iPhone 安装 companion。
