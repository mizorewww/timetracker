# Time Tracker

Time Tracker 是一个使用 SwiftUI、SwiftData、Swift Charts、ActivityKit 和 CloudKit/iCloud 能力构建的本地优先时间账本应用。它的核心不是“待办事项列表”，也不是“番茄钟”，而是把用户真实发生过的工作、学习、生活和琐事记录成可追溯、可修正、可分析的时间账本。

应用当前覆盖 iPhone、iPad 和 macOS，并包含 Live Activity 扩展。项目代码已经按功能、领域和数据流拆分，目标是让后续接入 Widget、App Intents、Shortcuts、Apple Watch、HealthKit 或更强的 LLM 辅助时，不需要重写底层时间模型。

## 设计宗旨

Time Tracker 的第一原则是：时间记录是事实，任务、番茄钟、分析和预测都只是围绕事实的不同视图。

传统待办应用关注“我要做什么”，时间追踪应用关注“我做了多久”，番茄钟应用关注“我是否保持专注”。Time Tracker 试图把这三者合并成一个稳定的系统：

```text
任务告诉用户：我要做什么。
时间账本告诉用户：我实际上做了什么。
番茄钟告诉用户：我是否以专注方式完成。
分析告诉用户：我的时间模式是否健康、有效、可持续。
```

因此，项目坚持这些原则：

- `TimeSegment` 是事实来源。任何普通计时、手动补录、番茄钟、Live Activity 或未来 Widget/Watch 操作，最终都必须写入统一的时间账本。
- 任务是时间的归属对象，不是时间本身。任务可以移动、归档、软删除，但历史时间记录不应随意消失。
- UI 可以重构，分析可以重算，原始账本数据必须尽量稳定。
- Forecast 必须可解释。没有 checklist 进度和真实计时时，不凭空预测。
- 本地优先。用户数据保存在 SwiftData，本地可用；iCloud 同步是跨设备能力，不应把业务逻辑变成网络依赖。
- 多平台入口必须复用同一套命令和用例，避免 App、Live Activity、Widget 或 Watch 各写一套计时逻辑。

## 当前功能

### Today 首页

Today 是日常使用的核心入口，回答三个问题：现在正在追踪什么、今天已经发生了什么、下一步可以快速继续什么。

- 查看当前所有 Active Timers。
- 支持多个任务同时计时。
- 展示今日时间统计、趋势和时间线。
- Quick Start 支持固定任务和最近高频任务。
- 显示 checklist 驱动的剩余时间预测。
- 显示今日、本周、本月、本年进度，以及用户自定义倒计时事件。
- iPhone 使用紧凑底部标签；iPad/macOS 使用更适合大屏的分栏布局。

### 任务与任务树

任务系统用于组织时间归属，而不是替代时间账本。

- 无限嵌套任务树。
- 所有任务都可以包含子任务，也都可以被计时。
- 任务支持状态，例如未完成、计划中、已完成。
- 任务支持颜色、SF Symbol、备注、预计时间、截止时间等编辑信息。
- 任务支持归档和软删除。
- 移动任务时会防止循环，并更新子孙任务路径。
- 父任务的展示时间会递归包含自身和子任务时间。
- 根任务可以归入用户自定义 Category，用于区分工作、学习、生活、健康等不同语境。
- Category 可控制该分支是否参与预测，为后续不同预测模型和 HealthKit 等能力预留空间。

### Checklist

Checklist 是任务内部的执行拆分，不是子任务，也不能单独计时。计时仍绑定到任务本身。

- 每个任务可以创建 checklist。
- Checklist 项支持完成、取消完成、删除、排序。
- 未完成项优先显示，完成项置后并保留历史。
- 完成项保留是预测系统的一部分，因为它们提供了“完成一项平均需要多久”的证据。
- Checklist 项支持图标和颜色。
- 可使用 LLM 为 checklist 建议 SF Symbol 和颜色。
- Forecast 会根据 checklist 完成度和任务真实计时实时更新。

### 预测系统

预测系统只在有足够证据时工作，不用历史记录或手动预计时长凭空生成结论。

当前规则是等权 checklist 模型：

```text
如果任务没有 checklist：
  不预测，提示用户添加 checklist

如果 checklist 完成数为 0：
  不预测，提示用户至少完成一项并记录时间

如果已完成 checklist 但任务没有计时：
  不预测，提示用户需要真实计时

如果已完成数 > 0 且已计时：
  每项平均时间 = 当前任务直接记录时间 / 已完成项数量
  剩余时间 = 每项平均时间 * 未完成项数量

如果 checklist 全部完成：
  该任务自身剩余时间 = 0
```

父任务预测会递归包含子任务预测。父任务没有 checklist 但只有一个可预测子分支时，界面会直接展示那个子任务；如果有多个可预测子分支，会展示父任务汇总并说明它来自多个子任务。

### Inbox

Inbox 用于快速收集还没有整理归属的事项。

- 快速新增收集项。
- 收集项可以完成、删除、编辑。
- 配置 OpenAI API 后，可自动建议应该归类到哪个任务。
- 用户可以接受建议，把 Inbox 项转换为目标任务下的 checklist。
- 用户也可以丢弃建议；编辑标题后可重新触发建议。
- LLM 结果会经过任务 ID、SF Symbol 和颜色校验，避免非法输出直接污染数据。

### 计时账本

计时系统以 `TimeSession` 和 `TimeSegment` 为核心。

- 开始任务会创建 `TimeSession` 和 active `TimeSegment`。
- 暂停任务会关闭当前 segment，但保留 session。
- 恢复任务会在同一个 session 下追加新的 segment。
- 停止任务会关闭 segment 并结束 session。
- 多个 `endedAt == nil` 的 segment 表示多个任务同时运行。
- 支持手动补录时间。
- 支持编辑和软删除时间记录。
- 跨天和重叠时间会在分析中按明确规则处理。

### 番茄钟

番茄钟是专注流程，不是独立账本。

- 番茄钟必须绑定任务。
- 开始番茄钟会创建 `PomodoroRun`、`TimeSession` 和 `TimeSegment`。
- 暂停、恢复、取消、完成都会同步更新 ledger。
- 完成最终专注轮次会正确结束关联 session。
- 番茄钟默认时长、休息时长和轮次可在设置中调整。

### Analytics

Analytics 从 `TimeSegment` 聚合，不把统计结果当成事实来源。

- Today、Week、Month 多范围统计。
- Gross Time 和 Wall Time 双口径：
  - Gross Time：所有任务时间直接相加。
  - Wall Time：去重后的真实时钟时间。
- 任务分布图按任务颜色展示。
- 今日活动分布处理短任务和重叠任务，避免极短记录完全不可见。
- 时间线支持重叠任务、相邻任务、跨天任务和长空白压缩。
- Month 图表使用真实日期，不用重复 weekday 作为数据 identity。
- Overlap 分析展示多任务同时计时造成的差异。
- Analytics 使用缓存 snapshot，避免 SwiftUI view body 内做重计算。

### Live Activity

当前包含 Live Activity 扩展，用于展示正在计时的任务。

- 展示任务图标、任务名和持续时间。
- 共享 ActivityAttributes，避免主 App 和扩展模型漂移。
- 文案走本地化，不在扩展中硬编码中文。

### 设置与维护

设置页用于用户可理解的偏好、数据维护和服务配置。

- 外观设置。
- Pomodoro 默认模式和时长。
- iCloud 同步开关和同步状态反馈。
- OpenAI endpoint、API key 和模型选择。
- 自动拉取可用模型。
- CSV 导出。
- 清除演示数据。
- 优化数据库，清理缺失或已删除任务关联的历史记录。
- About 页面展示 app 图标、版本号、build number、branch、commit hash 和构建时间。

## 数据模型

核心模型如下：

| Model | 作用 |
| --- | --- |
| `TaskNode` | 任务树节点。所有任务可计时、可嵌套、可归类。 |
| `TaskCategory` | 用户自定义根语境，例如工作、学习、生活。可影响预测策略。 |
| `ChecklistItem` | 任务内部 checklist 项，用于执行拆分和预测证据。 |
| `InboxItem` | 未整理的收集项，可由 LLM 建议归类。 |
| `TimeSession` | 一次工作意图，例如“写报告”。 |
| `TimeSegment` | 真实发生的一段时间，是时间账本事实来源。 |
| `PomodoroRun` | 番茄钟流程状态，最终生成或更新 TimeSegment。 |
| `CountdownEvent` | 用户自定义倒计时事件。 |
| `SyncedPreference` | 用户可感知设置，以 JSON 存入 SwiftData 并可通过 iCloud 同步。 |

核心数据普遍包含 `id`、`createdAt`、`updatedAt`、`deletedAt`、`deviceID` 和 `clientMutationID`，用于软删除、同步、冲突处理和幂等操作。

## 架构概览

项目采用本地优先的模块化单体结构。UI 不直接写 SwiftData，持久化和业务动作通过 command、repository、domain store 和 service 分层。

```text
SwiftUI Feature
  -> TimeTrackerStore facade
  -> Command handler
  -> Repository protocol
  -> SwiftData repository
  -> SwiftData model
  -> Domain store snapshot
  -> Pure services derive secondary state
```

主要边界：

- `Features`：SwiftUI 页面和局部组件。
- `SharedUI`：跨功能复用的原生风格控件、布局策略和视觉 token。
- `Stores/Facade`：`TimeTrackerStore` 的 UI-facing 适配层。
- `Stores/Domains`：Task、Ledger、Checklist、Rollup、Analytics、Preference 等领域状态。
- `Commands`：持久写入动作，例如开始计时、移动任务、切换 checklist、应用 Inbox 建议。
- `Repositories`：SwiftData 查询与写入实现。
- `Services`：可测试算法，例如时间聚合、forecast、timeline layout、CSV export、database maintenance。
- `Models`：SwiftData 模型、schema、迁移计划、read models。
- `SharedLiveActivity` / `timetrackerLiveActivityExtension`：Live Activity 共享模型和扩展 UI。

详细文件定位请看 [Docs/ProjectMap.md](Docs/ProjectMap.md)。架构规则请看 [Docs/Architecture.md](Docs/Architecture.md) 和 [Docs/CodeRefactorPlan.md](Docs/CodeRefactorPlan.md)。

## 目录结构

```text
timetracker/
  App/                 App entry, scenes, root views, build metadata, demo data
  Commands/            Durable write actions and use-case-style handlers
  Features/            Home, Inbox, Tasks, Pomodoro, Analytics, Settings, Sidebar, Inspector
  Models/              SwiftData models, schema versions, migration, read models
  Repositories/        SwiftData-backed repository implementations
  Services/            Analytics, forecasting, checklist, ledger, LLM, maintenance, tasks
  Stores/              Domain stores, facade, refresh planner, selection/navigation
  Shared/              Strings and extension-safe shared helpers
  SharedUI/            Native-styled shared components and layout policies

timetrackerLiveActivityExtension/
SharedLiveActivity/
timetrackerTests/
timetrackerUITests/
Docs/
scripts/
BuildSupport/
DesignAssets/
```

## 本地开发

### 准备

1. 使用 Xcode 打开 `timetracker.xcodeproj`。
2. 确认 shared scheme 中存在 `timetracker`。
3. 建议启用仓库自带 git hook，让每次 commit 自动递增 patch version 和 build number：

```sh
git config core.hooksPath .githooks
```

### 运行测试

macOS 单元测试：

```sh
xcodebuild test -project timetracker.xcodeproj -scheme timetracker -destination 'platform=macOS' -only-testing:timetrackerTests
```

iOS generic build：

```sh
xcodebuild build -project timetracker.xcodeproj -scheme timetracker -destination 'generic/platform=iOS'
```

检查 scheme：

```sh
xcodebuild -list -project timetracker.xcodeproj
```

导出签名产物：

```sh
./scripts/export_signed_artifacts.sh
```

更多测试要求见 [Docs/Testing.md](Docs/Testing.md)。

## 版本与构建信息

版本号由仓库管理，而不是靠聊天上下文记忆。

- `MARKETING_VERSION` 是用户可见版本号。
- `CURRENT_PROJECT_VERSION` 是 build number。
- `.githooks/pre-commit` 会在普通 commit 时自动把 patch version 增加 `0.0.1`，并把 build number 增加 `1`。
- `scripts/write_build_info_plist.sh` 会在 build phase 中写入 `AppBuildInfo.plist`，包含 branch、commit hash、dirty flag 和构建时间。

详见 [Docs/Versioning.md](Docs/Versioning.md)。

## 开发规则

为了避免项目重新变成难以维护的大文件，后续开发应遵守：

1. 功能先写预期和测试，再写 UI。
2. SwiftUI view 只负责展示和收集输入。
3. 持久写入必须经过 command handler。
4. SwiftData 查询和写入只放在 repository。
5. 复杂计算必须放在 service，并有单元测试。
6. 新增用户可见字符串必须补 English、简体中文、繁体中文。
7. Schema 变化必须考虑旧 iCloud store 的兼容性。
8. 新增系统入口必须复用同一套 command/use-case，不复制 ledger 逻辑。
9. 自定义 UI/动画要谨慎，优先使用系统组件和原生交互。
10. 性能问题先用测试或 Instruments 定位，再改架构。

## 相关文档

| 文档 | 内容 |
| --- | --- |
| [Docs/ProjectMap.md](Docs/ProjectMap.md) | 新人定位文件夹和模块的入口。 |
| [Docs/Architecture.md](Docs/Architecture.md) | 领域模型、ledger 原则、forecast 规则和数据流。 |
| [Docs/CodeRefactorPlan.md](Docs/CodeRefactorPlan.md) | 当前架构状态和重构护栏。 |
| [Docs/NativeUIPlan.md](Docs/NativeUIPlan.md) | 原生优先 UI 规则和屏幕级 UI 清理计划。 |
| [Docs/NextDevelopmentPlan.md](Docs/NextDevelopmentPlan.md) | 后续产品方向和验收标准。 |
| [Docs/Testing.md](Docs/Testing.md) | 测试命令、覆盖要求、性能验证和设备验证。 |
| [Docs/Localization.md](Docs/Localization.md) | 多语言和文案治理。 |
| [Docs/Versioning.md](Docs/Versioning.md) | 版本号、build number 和构建信息写入。 |

## 后续方向

下一阶段重点不是增加更多孤立页面，而是继续强化“统一时间账本”：

- 打磨 Inbox 和 LLM 归类体验。
- 改进 checklist forecast 的解释和可信度。
- 继续优化 Analytics 的可读性和性能。
- 增加 App Intents、Widget、Shortcuts 和 Apple Watch，但必须复用 command 层。
- 为不同 TaskCategory 引入更合理的预测策略，例如工作线性外推、生活/健康更偏习惯统计。
- 加强 iCloud schema 兼容测试，避免旧设备数据被新版本破坏。

只要 `TimeSegment` 事实层保持稳定，未来系统入口、分析维度、AI 辅助和跨设备能力都可以在同一套账本上扩展。
