# 55：Live Activity 恢复原设计实现记忆

> 本文件只用于主代理与子代理的实现、验证和编排记忆，不是任务来源。唯一范围与状态必须重新读取
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 条目。

## 当前阶段

- [x] 领取反馈并建立活动任务链接。
- [x] 读取 Live Activity 相关架构、UI、测试、隐私规范与 Apple 官方资料。
- [x] 对比反馈前后 Git 历史、当前实现和现有系统表面测试，定义“原设计”的可验证边界。
- [x] 先建立 UI 验收清单，再做最小回滚。
- [ ] 完成格式化、单元测试、脚本化模拟器截图验收和小 checkpoint 提交。
- [ ] 执行 `make build-install-all`，关闭反馈并移除活动链接。

## 唯一反馈边界

- 恢复 Live Activity 在第 29 项排版优化之前的视觉设计，消除该改动引入的错乱或劣化。
- 保留已经验证的 ActivityKit 生命周期、超过八小时计时、深链和隐私语义，除非历史证据证明某项与视觉回滚不可分。
- 不领取主页图表、Apple Health、AI 或其他后续反馈。

## 强制约束

- 主代理完整遵循仓库本地 `apple-hig` 与 `swiftui-expert-skill`；子代理只承担有边界的只读审计。
- 先用 Git 历史和截图/测试证据确定恢复目标，不凭印象重画。
- 优先复用 ActivityKit、WidgetKit、SwiftUI、SF Symbols 与现有测试工具；若系统 API 已覆盖需求，不引入第三方 UI 依赖。
- 所有模拟器由主代理登记名称和 UDID；完成后终止 App/Runner、关机并删除设备。
- 每个 checkpoint 只暂存本任务文件，保护 `Docs/userfeedback.md` 中其他用户新增内容。

## Checkpoint 编排

- [x] Checkpoint A：领取、历史审计、原设计契约与验收清单。
- [ ] Checkpoint B：最小回滚、定向测试、系统表面截图验收。
- [ ] Checkpoint C：全量测试、Release 全设备安装、反馈收口。

## 子代理编排

- [x] 历史审计（`/root/history_audit`）：只读比较 Live Activity 关键提交前后差异，给出最小恢复候选；没有改文件、运行构建或模拟器。
- [x] 测试审计（`/root/test_audit`）：只读检查现有 Live Activity contract/XCUITest，指出哪些断言绑定了劣化布局、哪些生命周期保障必须保留；没有改文件、运行构建或模拟器。

## 资源所有权

- 当前没有主代理或子代理拥有 simulator、XCTest、Instruments、物理设备或构建进程。
- 后续每个模拟器批次必须在此记录设备名、UDID、结果与清理状态。

## 决策与证据

- 原设计基线是 `292fcf8c^`（`87002027`）：它已经包含 `c79f0f27` 的超过八小时计时修复；实际视觉结构来自更早的 `937ced42`。
- `292fcf8c` 之后没有提交再改三个视觉文件或 `ExpandedActivityDetails.swift`；当前视觉实现与该劣化提交完全相同。
- 采用混合回滚，不机械 `git revert 292fcf8c`：
  - 恢复 `LiveActivityTimerPresentationViews.swift` 原来的计时缩放和按表面区分的固定宽度；
  - 恢复 `LiveActivityTimerViews.swift` 原来的统一 `ViewThatFits`、弹性摘要、`Spacer` 和布局优先级；
  - 恢复 `TimeTrackerLiveActivityBundle.swift` 紧凑/最小视图原来的缩放与宽度，移除任务 29 加入的 condensed/compressed 字宽；
  - 保留任务 29 同时加入的可访问标识、完整 `HH:MM:SS` 可访问值、过期提示和频繁更新语义。
- 不触碰 ActivityKit 协调器、`staleDate: nil`、任务投影边界、Today 深链、隐私修饰或只读交互。
- 任务 29 新增的源码字符串布局扫描测试后来已经按仓库决策删除，不恢复它们；现有 XCUITest 只放宽中线、精确间距和旧坐标 ROI 等视觉耦合断言。
- `Docs/CodeGuide.md`、`Docs/Testing.md` 与 AD-118 的正常字号 expanded 单行契约来自原设计简化 checkpoint，继续作为首选结果；恢复的 `ViewThatFits` 仅在完整内容实际放不下时安全纵排，避免为了单行再次裁切或重叠。
- Apple 官方资料确认 Live Activity 应同时支持 Lock Screen、compact、minimal、expanded，内容要一眼可读、只占必要空间；expanded 区域由系统分配宽度，过宽内容应自适应而不是强行固定单行。
- 不新增第三方依赖：ActivityKit、WidgetKit、SwiftUI 与 SF Symbols 已完整覆盖这个系统表面；第三方 UI 库无法控制 Dynamic Island 的系统布局。

## UI 验收清单

- [ ] Lock Screen 普通字号：图标、任务摘要和完整长时计时互不覆盖；空间不足时可以回到原设计的纵向排布。
- [ ] Expanded Dynamic Island 普通字号：优先保持原设计的单行；长标题或受限宽度时允许 `ViewThatFits` 安全纵排，不裁掉完整计时。
- [ ] Compact leading：图标和标题保持原来的 62pt 弹性边界；标题可缩放且不会挤占 trailing 计时。
- [ ] Compact trailing 与 minimal：恢复 50pt/45pt 边界和原缩放比例，仍可见超过八小时的 `HH:MM:SS`。
- [ ] 所有表面继续打开 Today，不出现 Stop；标题/路径仍标记隐私，计时继续每秒推进。
- [ ] XCUITest 保留注册、唯一 AX 标识、长时 OCR、计时推进、无 Stop 和截图证据，只放宽任务 29 独有的“expanded 必须强制同一行”几何断言。

## 基线验证

- `make install-hooks` 与 `make check-hooks`：通过。
- `make test`：1433 个测试中的 Live Activity 长时契约通过；有两个与本任务无关的既有失败：
  - `PreferenceSyncBehaviorTests.checklistCompletionMovesOnlyTheTargetToTheDestinationGroupEnd`
  - `TaskPersistencePolicyTests.archiveCommandPreservesTheOriginalArchiveTimestamp`
- 对上述两个 suite 的定向复跑再次得到相同失败，确认不是本任务造成，也不并入本 checkpoint。
