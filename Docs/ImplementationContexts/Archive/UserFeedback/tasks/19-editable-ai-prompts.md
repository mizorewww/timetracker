# 19：不同 AI 提示词均可编辑实现记忆

Status: Complete

> 本文件只用于主代理与子代理的实现、验证和编排记忆，不是任务来源。唯一范围与状态必须重新读取
> [`Docs/userfeedback.md`](../../../../userfeedback.md) 中对应的 `[~]` 条目。

## 当前阶段

- [x] 读取唯一反馈并领取任务。
- [x] 审计现有 AI 配置、提示词种类、默认值、持久化和调用路径。
- [x] 参考 Apple HIG、SwiftUI 专项规范与成熟库，确定编辑体验和依赖边界。
- [x] 实现每一种现有 AI 提示词都可分别编辑、保存、恢复默认并被对应调用读取。
- [x] 完成定向测试、owned 模拟器普通交互与截图验收并清理资源。
- [x] 执行 `CONFIGURATION=Release scripts/build_install_all.sh` 并由 Codex 标记完成。

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

- [x] 全仓只有三个真实 prompt consumer：Inbox 路由、Checklist 视觉建议、Task Plan；模型列表 GET 不是 prompt consumer。
- [x] Task Plan 的行为说明已可编辑并进入 request；Inbox 与 Checklist 仍把行为说明和固定 JSON contract 混在 service 中。
- [x] 三种行为说明都是非敏感 synced preference；API Key 继续只保存在设备 Keychain。空白输入恢复该种 prompt 的 catalog default。
- [x] iPhone、iPad 与 macOS 复用一个泛型长文本编辑器；Intelligence 设置直接列出三种 prompt，避免额外的嵌套列表 sheet。

## 已确定实现设计

- `LLMPromptKind` 只建模 `inboxRouting`、`checklistVisual`、`taskPlan` 三种真实功能，并集中各自默认行为说明。
- 保留已有 `LLMTaskPlanInstructions` key 兼容用户数据；为 Inbox 与 Checklist 分别新增独立 synced key，降低跨设备写冲突粒度。
- Inbox/Checklist 的 editable instructions 放入动态 user JSON；JSON keys、候选 ID、符号/颜色白名单继续留在不可编辑 system contract，响应端验证不放宽。
- prompt 保存与远端偏好刷新都必须使对应旧请求失效；Checklist request fingerprint 也包含 prompt，旧 completion 不得回写。
- 设置页三行进入同一个 `TextEditor` 实现，保留 Save/Cancel、4 KiB UTF-8 校验、恢复默认与未保存退出确认。

## 依赖与资料结论

- 采用系统 SwiftUI `Form`、`TextEditor`、`NavigationStack`、`confirmationDialog` 和仓库现有 `EditorSafety`；本任务不新增库。
- Apple 一手参考：HIG Settings、Text views、Undo and redo、Generative AI，以及 SwiftUI `TextEditor` / `Form` 文档。
- 未采用 `STTextView`（约 1.6k stars，GPLv3/商业许可且偏代码编辑器）或 `Runestone`（约 3.2k stars，代码编辑器能力过重）。
- 仓库已有 `MarkdownView` 是渲染器、约 138 stars，且属于下一条用户明确提出的子任务；本任务不使用。

## Checkpoint 编排

- [x] Checkpoint A：prompt catalog、同步偏好、service request、旧请求失效和定向单元测试。
- [x] Checkpoint B：三行设置入口、泛型编辑器、本地化、UI/contract 测试与 owned 模拟器截图。
- [x] Checkpoint C：全量回归、精确 Release 全设备安装、状态标记和资源清理。

## Checkpoint A 结果

- 新建统一 `LLMPromptKind` catalog；保留 Task Plan 既有同步 key，并为 Inbox / Checklist 新增独立、非敏感的同步偏好。
- Inbox / Checklist request 将用户行为说明放入 user JSON；固定响应 schema、目标语义、候选 ID 和图标/颜色白名单仍在不可编辑 system contract。
- 本地保存或远端同步改变 prompt 时，只替换相应请求；旧 request ID、旧配置或旧 prompt 的 completion 均不可落库。
- prompt 仍限 24 KiB，outer request 明确限 64 KiB，覆盖 JSON 二次转义最坏开销且不裁掉已预算候选。
- 定向回归：94 passed、0 failed、0 skipped；结果为
  `build/Task19PromptDataTests/DerivedData/Logs/Test/Test-timetracker-2026.07.22_13-10-00-+0800.xcresult`。
- 两轮只读子代理审查完成；修复组合预算和对称失效覆盖后最终均为 no findings。
- 本检查点未启动 simulator；验证后无 Booted device、`xcodebuild`、`xctest` 或 runner 残留。

## Checkpoint B 结果

- Intelligence 设置直接列出 Inbox Routing、Checklist Visual 和 Task Planning 三个独立入口，复用同一个
  `LLMPromptInstructionsEditor`。
- 编辑器使用系统 `Form` / `TextEditor`，提供 Save、Cancel、4 KiB UTF-8 计数与验证、草稿恢复默认和
  未保存离开确认；尾随空白归一化后不会产生假 dirty。
- iOS/iPadOS 在 AI Assistant 的 `NavigationStack` 内 push 编辑器，不再在 Settings sheet 上叠加第二层 sheet；
  显式 close 只 pop prompt，返回原 AI 设置页。macOS 保留独立 sheet。
- 三套主要本地化键齐全，`plutil -lint` 全部通过。
- 最终定向回归：56 passed、0 failed、0 skipped；结果为
  `build/Task19PromptUI/DerivedData/Logs/Test/Test-timetracker-2026.07.22_13-49-33-+0800.xcresult`。
- iPhone 最终 UI 测试 1 passed：
  `build/Task19PromptUI/iPhoneDerivedData/Logs/Test/Test-timetracker-2026.07.22_13-41-33-+0800.xcresult`。
- iPad 最终 UI 测试 1 passed：
  `build/Task19PromptUI/iPadDerivedData/Logs/Test/Test-timetracker-2026.07.22_13-45-16-+0800.xcresult`。
- UI 测试逐种验证编辑、保存、重开、恢复默认、再次重开；Inbox 额外验证脏草稿保留/放弃。
- 主代理已检查 iPhone 与 iPad 各三张截图：三入口列表、Checklist 编辑器和放弃确认均无重叠、截断或
  平台不一致。最终只读子代理复审为 no findings。
- 本检查点不新增第三方库；两台 owned simulator 均已终止 App、shutdown 并 delete，且无 Booted device、
  `xcodebuild`、`xctest`、UI runner、extension 或 trace 残留。

## Checkpoint C 全量回归记录

- macOS 全量 `timetrackerTests` 已执行；结果为 1534 passed、12 failed、0 skipped（1546 total）：
  `build/Task19PromptUI/FullRegressionDerivedData/Logs/Test/Test-timetracker-2026.07.22_13-54-00-+0800.xcresult`。
- 12 个失败均不位于 AI prompt catalog、同步偏好、service request、设置编辑器或本任务 UI tests：包括既有源码行数预算、
  Live Activity / Home UI 静态契约、Cloud sync 静态契约和归档时间戳严格 `Date` 相等测试。
- 本任务最终专项回归仍为 56 passed、0 failed、0 skipped，三种 prompt 的 simulator UI 闭环也全部通过；不得把
  repository-wide 全量回归表述为通过。
- 独立只读复审确认：本任务直接新增/修改的 15 个单元测试全部通过，涉及改动的 7 个 unit-test suites 合计
  85 passed、0 failed；全量回归的失败测试文件及其断言读取的源文件均未被本任务改动。
- 全量回归未创建 simulator；运行结束后没有 owned `xcodebuild`、`xctest`、runner 或 Booted device 残留。
- 精确命令 `CONFIGURATION=Release scripts/build_install_all.sh` 退出码为 0；iOS/iPadOS、嵌入式 watchOS companion
  与 macOS Release 均构建、签名并安装成功。
- iPad Pro M4（`748D0137-ADC3-58AF-855C-1E98B3125F93`）与 iPhone Air
  （`FBA36694-D841-56D4-8ED6-21942873B21B`）只读核验均显示 `me.mezorewww.timetracker` 版本
  `1.1.52 (107)`；未启动、操作或截图物理设备。
- iOS app、embedded Watch app 与 `/Applications/timetracker.app` 均通过 `codesign --verify --deep --strict`；
  Team Identifier 为 `LT98S43NKA`。iOS binary 为 `arm64`，Watch binary 为 `arm64 arm64_32`，macOS binary 为
  `arm64 x86_64`。

## 资源所有权

- Checkpoint B 的 owned iPhone `Task19Prompt-iPhone-20260722-1330`（UDID
  `2B2144DE-03A7-429B-8DFD-8EA843A21139`）已清理并删除。
- Checkpoint B 的 owned iPad `Task19Prompt-iPad-20260722-1330`（UDID
  `9EF8B4CE-BFD5-446E-990E-1525424A7B4D`）已清理并删除。
- Checkpoint C 未创建 simulator；Release 完成后无 Booted device、owned `xcodebuild`、`xctest`、UI runner、
  extension 或 trace 进程残留。
