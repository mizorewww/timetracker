# AI 多任务计划：产品与技术设计

## 目标与范围

本设计只实现 `Docs/userfeedback.md` 中当前标记为 `[~]` 的“Tasks / Generate
Task Plan”反馈：一次请求可以生成多个任务；固定提示词需要准确介绍应用内真实可创建的任务类型；用户能在创建前检查和修改草稿；“读书任务 + 第 1–10 章 checklist”能随同一个 category 原子创建；Task Plan 提示词提供 Markdown 编辑与渲染体验。

不在本任务中实现现有 category 复用、Apple Health 目录同步、Health 任务编辑限制或后续反馈。AI 计划中的 category 是同一份草稿内的新 category；AI 不会看到或引用用户现有数据，因此不会伪造现有对象 ID。

## 已有能力与缺口

现有 `LLMTaskPlanService` 已经使用三个扁平数组表达最多 8 个 category、64 个 task 和 256 个 checklist item，并支持多个根任务、父子层级、每任务 32 个 checklist、最多 6 层任务深度。解析后先形成本地 `AITaskPlanDraft`，预览页能编辑名称、删除 task 子树或 checklist，保存协调器也已经使用 fresh-context transaction、拓扑顺序和本地生成的稳定 UUID 实现整批回滚与重放幂等。

真正缺失的是：

- 固定 contract 和默认可编辑提示词只介绍 category、普通 task 与 checklist，没有解释 quantity 和 daily recurrence，也没有说明 Apple Health 是只读同步来源。
- AI task schema 不能表达 quantity goal 或 daily recurrence，所以即使提示词提到这些类型也无法安全落库。
- 预览无法辨认或核对 quantity / recurrence 语义。
- Task Plan 提示词目前只有系统 `TextEditor`，没有使用仓库已有 `MarkdownView` 呈现 Markdown。

## 应用内任务语义

AI 能创建的内容只有以下几种：

1. **Category**：宽泛的统计与组织分组；只分配给根 task。
2. **普通可计时 task**：可有 notes、预计分钟数、SF Symbol、颜色，也可作为其他 task 的父或子节点。
3. **Checklist item**：依附于一个 task 的完成步骤，本身不是独立可计时 task。章节、准备步骤等应优先用 checklist 表达。
4. **Quantity task**：普通 task 加一个 `targetAmount + unitLabel` 目标，例如 50 `push-ups`。目标范围复用 `TaskQuantityPolicy` 的 `1...1_000_000`，单位复用现有 UTF-8 与控制字符校验。
5. **Daily recurring template**：普通 task 加每日重复规则；应用从用户当前时区的当天开始自动物化每日子 task。它可以同时是 quantity task，例如“每天 50 个俯卧撑”。AI 不应同时手工生成未来每日副本。

Apple Health workout / sleep task 是确定性 catalog 中的同步管理对象，不属于 AI 可创建类型。提示词必须明确禁止创建“Health task”或用普通 task 冒充 Health 同步记录。

Due date、notes、estimated minutes、父子关系、图标与颜色是 task 属性，不单独称为任务类型。当前 AI schema 不增加 due date；没有可靠日期/时区上下文时不让模型猜测绝对时间。

## 响应 schema

继续保留 `categories`、`tasks`、`checklistItems` 三个扁平数组和引用校验。Task 对象增加两个可选维度：

```json
{
  "reference": "daily-pushups",
  "categoryReference": "fitness",
  "parentReference": null,
  "title": "Daily 50 Push-Ups",
  "notes": "Keep a controlled tempo.",
  "estimatedMinutes": 10,
  "iconName": "dumbbell",
  "colorHex": "34C759",
  "quantityGoal": {
    "targetAmount": 50,
    "unitLabel": "push-ups"
  },
  "recurrenceCadence": "daily"
}
```

- `quantityGoal` 缺失或 `null` 表示普通 task；对象内两个字段必须同时存在并通过现有 quantity policy。
- `recurrenceCadence` 缺失或 `null` 表示不重复；当前唯一允许值是 `"daily"`，其他字符串整份拒绝。旧模型响应省略新字段时仍能解码。
- 开始日和时区不由模型提供。解析成功时由应用使用同一个注入的 `now` 与 `timeZone` 构造 `TaskDailyRecurrenceDraft`，测试可注入固定值。
- quantity 与 recurrence 可以组合；所有新字段仍受现有响应字节、总数、引用、深度和字段预算约束。
- 未知对象形状、非法数值或不完整 quantity object 都让整份响应失败，不进行部分修复或部分写入。

## 提示词策略与兼容

固定 system contract 负责不可覆盖的 JSON 结构、安全限制、类型语义和 Health 禁令；用户可编辑 instructions 负责规划偏好。新的 Task Plan 默认 instructions 使用简短 Markdown 分段介绍 category、普通/父子 task、checklist、quantity、daily recurrence 及组合示例，并要求按用户需求生成所有有用的 task，而不是只返回一个代表性 task。

已经保存的自定义 instructions 必须原样保留。只有内容精确等于上一版随应用发布的 Task Plan 默认文案时，读取层才把它识别为 legacy default 并升级到新的 Markdown 默认值；任何其他文本都视作用户自定义值。恢复默认使用新文案，4 KiB UTF-8 上限和控制字符规则保持不变。

## 原子保存与幂等

保存前一次性完成 category/task/checklist 引用、图、文本、估时、quantity 和 recurrence 校验，并拒绝与 Apple Health 固定 task/category ID 相交的直接构造草稿。网络模型拿不到 UUID，但 coordinator 仍保留这层最终防线；普通随机 ID 且标题为“跑步”或“睡眠习惯”的用户任务不受影响。落库继续在一个 `StoreScopedTimerMutationTransaction.withFreshContext` 中执行：

1. 创建计划内 category。
2. 按父节点优先的拓扑顺序创建 task 与 checklist。
3. 对每个 task 复用 `TaskProgressDraftPersistencePolicy` 和 `TaskDraftProgressMutationService` 保存 quantity goal 与 daily recurrence；每日规则可在同一 context 中物化当天 task。
4. 任一 checkpoint 抛错时让 fresh context 整体回滚，包括 category、task、checklist、quantity goal、recurrence rule、occurrence 和物化 task。

计划自己的 category/task UUID 全部已存在时，重放仍返回 no-op success；只有一部分存在时返回 identity conflict，不补齐半份计划。事务提交后用全域 task/checklist 事件刷新 store，包含 recurrence 物化与 quantity read model。

## 编辑与预览交互

### 生成计划

- 请求阶段仍使用系统 `TextEditor`，明确告知内容会发送到用户配置的 endpoint。
- 生成后先显示数量摘要和 category 分组，再显示所有 task；每行保留稳定 UUID，删除父 task 会连同子树删除。
- quantity task 显示目标数量和单位；daily template 显示“每天重复”标记；组合类型同时显示。目标值与单位在草稿中可编辑并实时走同一 persistence policy 校验，非法草稿禁用“创建计划”。
- 创建按钮只执行完整草稿的一次原子操作。错误就地显示，草稿留在页面中供修改或重试。

### Task Plan 提示词

`MarkdownView 4.1.7` 是 MIT 许可的原生 iOS/macOS Markdown **渲染器**，不提供文本编辑 API；仓库已经锁定并用于 task notes。因而编辑器采用明确的“编辑 / 预览”分段：系统 `TextEditor` 负责多行输入、键盘、选择和撤销，`MarkdownView(draft)` 负责实时渲染同一份字符串。Save、Cancel、恢复默认、4 KiB 字节计数和 dirty-discard 行为保持不变。

这既满足“采用 MarkdownView”，也不会把只读 renderer 强行改造成不可靠的输入控件。iPhone 使用单列分段切换，iPad/macOS 延续同一信息架构；普通字号下不设置固定文字高度，预览由外层 Form 滚动。

上游与平台资料：

- [Lakr233/MarkdownView](https://github.com/Lakr233/MarkdownView)（仓库锁定 4.1.7；MIT；用户明确指定，因此不受默认 1k-star 门槛限制）
- [Apple SwiftUI TextEditor](https://developer.apple.com/documentation/swiftui/texteditor)（系统多行编辑控件）

## 验收矩阵

### Service / schema

- 一个 payload 映射多个 category、根 task、子 task 与 checklist，引用和顺序正确。
- 旧 payload 缺少新字段仍可生成普通 task。
- quantity-only、daily-only、quantity + daily 都映射为真实 draft；固定日期/时区得到确定 start day。
- 不完整/超范围 quantity、非法单位、未知 recurrence、重复/孤儿/循环/过深/超数量 payload 整份拒绝。
- system contract 包含所有真实类型、Health 禁令、多个任务要求与 schema 字段；请求和响应 UTF-8 预算仍成立。
- 精确 legacy default 升级，新默认与自定义 instructions 都分别保持。

### Atomic mutation

- 同一 transaction 创建多个 category/task/checklist，并保存 quantity goal、daily rule、当天 occurrence 与生成 task。
- 在 category、task、checklist、quantity、rule 或 occurrence checkpoint 注入失败时，fresh context 中所有计划事实均为空。
- 同一草稿重放 no-op；混合已存在 identity 仍整份拒绝。

### UI / simulator

- Task Plan 设置可在 Edit 与 Markdown Preview 之间切换；编辑、保存、恢复默认和丢弃确认回归。
- 读书验收 fixture：一个 Reading category、一个读书 task、10 个从 Chapter 1 到 Chapter 10 的 checklist；预览与创建后的详情均可见。
- 另一个 fixture 覆盖多根 task、quantity + daily 标签/编辑和原子创建。
- 使用主代理登记的 owned iPhone 与 iPad simulator 跑普通路径并截图检查；结束后终止 app、删除 owned simulator，确认没有遗留 Booted device 或测试进程。
- 最终执行精确命令 `CONFIGURATION=Release scripts/build_install_all.sh`；物理设备仅安装与只读版本核验，不启动、不操作、不截图。
