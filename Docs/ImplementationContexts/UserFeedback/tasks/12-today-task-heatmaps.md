# 12：Today 每任务 Heatmap 实现记忆

> 本文件只保存实现、验证和子代理编排记忆，不是任务来源。范围与完成状态必须重新读取
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中唯一的 `[~]` 项。

## 当前阶段

- [x] 领取 Heatmap 反馈并建立活动链接。
- [x] 审计任务模型、计时/Checklist 聚合、Today、设置、任务详情与 BlossomColor 组件。
- [x] 明确普通计时任务、Checklist 和现有任务量数据的每日强度语义与迁移默认值。
- [x] 实现持久化配置、每日聚合与任务详情默认关闭的追踪开关。
- [x] 实现并验证每任务配色与 Today 独立 Heatmap。
- [x] 完成 owned iPhone/iPad 模拟器交互、截图验收与批次资源清理。
- [~] 完成最终相关回归、Release 全设备安装与临时产物清理。
- [ ] 由 Codex 在唯一任务来源标记父项和全部子项完成并移除活动链接。

## 唯一反馈边界

- Today 可显示 GitHub 风格的 Heatmap；用户能从设置中选择要显示的任务。
- 每个任务拥有独立 Heatmap 与配色方案；复用仓库已有 BlossomColor 相关组件。
- 是否追踪 Heatmap 可在任务详情中开启，默认关闭。
- 强度首先按任务的真实每日数据决定：反馈明确提到 Checklist 完成数量、每日任务时长
  最大值阈值，以及任务量任务的每日任务量；实现前必须以现有模型能力确认精确定义。
- 不提前实现下一条“重复任务和简单任务量任务”；只为当前模型已经存在的数据类型提供语义，
  必要的未来兼容必须有测试且不能虚构新产品流程。
- 只处理 `Docs/userfeedback.md` 当前 `[~]` 项，不领取后续反馈。

## 设计与实现约束

- 使用 `apple-hig` 和 `swiftui-expert-skill`：图表必须有清晰标题/摘要，不能只靠颜色传达值，
  iPhone、可缩放 iPad 窗口和 macOS 都要保持可读布局。
- 优先 Apple Swift Charts 的 `RectangleMark` 或仓库已有成熟组件；不新增低质量重复实现。
- 新第三方 GitHub 依赖一般必须达到 1k stars，并在采用前核对维护状态、许可证和平台支持。
- 聚合、阈值和调色必须在模型/服务层可独立测试，不在 SwiftUI `body` 中排序或聚合。
- `ForEach`/Chart 数据必须使用持久稳定 identity；新 SwiftUI API 按部署目标正确 gate。
- 不新增 Liquid Glass。保留正式 Apple Developer 签名。
- 所有 UI 操作和截图只来自 owned 模拟器；物理设备只执行规定的 Release 安装，
  不启动、不操作 UI、不截图。

## 验收清单

- [x] 从设置选择/取消选择 Heatmap 任务，真实磁盘容器重开后保持
- [x] 任务详情开关默认关闭，并与设置选择保持单一语义
- [x] 每个已选择任务在 Today 显示独立、可辨识的 GitHub 风格年度/周期 Heatmap
- [x] 复用 BlossomColor 主题色并生成清晰的从浅到深强度层级
- [x] 普通时长、Checklist 完成数量和仓库已存在的任务量数据有确定、可测试的日聚合语义
- [x] 空数据、归档任务、删除/恢复数据、时区和跨日边界行为明确
- [~] iPhone/iPad/macOS 普通布局与深浅色不截断；iPhone/iPad simulator-only 截图已验收
- [~] 聚焦测试已通过；相关回归待最终批次
- [ ] `CONFIGURATION=Release scripts/build_install_all.sh` 成功并核验版本/签名
- [ ] 清理 owned 模拟器、进程和临时产物

## 子代理编排

- [x] 数据模型、迁移、每日聚合和阈值语义审计
- [x] Today、设置、任务详情与 BlossomColor 复用入口审计
- [x] 测试架构、Swift Charts/可复用库与模拟器验收路径审计

## 审计结论与锁定决策

- 现有实现仍将全部选择合成一张 Heatmap，只读取 Checklist，并写死 1/2/3/4 阈值和
  `AppColors.grossTime`；它仅作为可迁移的基础，不满足本项反馈。
- 不新增 SwiftData 模型或 V14 schema。默认关闭、任务顺序、设置多选和详情 Toggle 全部继续以
  已同步的 `AppPreferences.todayHeatmapTaskIDs` 为唯一真相，并统一调用
  `setTodayHeatmapTaskIDs`，避免双数据源。
- 每个被选择任务生成独立 snapshot；该图包含任务本身和未删除后代。父子同时被选择时分别显示，
  但单张图内按持久 ID 去重。归档选择保留历史，真正删除、孤儿和未来记录不计。
- 每任务主题色直接使用已由 `BlossomColorPicker` 编辑和同步的 `TaskNode.colorHex`，四档强度色
  从该主题色派生，不另存一份会漂移的 Heatmap 色。
- 数据源自动且互斥：分支内存在有效任务量目标时使用任务量；否则存在 Checklist 时使用完成数；
  否则使用 gross 计时时长。当前项只消费已有 V13 任务量数据，不提前实现下一条任务量/重复任务 UI。
- 时长通过 `TrackedTimePolicy` 裁剪到现在和 53 周窗口，再用
  `TimeAggregationService.secondsByDay` 按 Calendar 日界线拆分；跨日和 DST 不使用固定 24 小时。
- Checklist 采用仓库现有语义：只计当前仍完成且有 `completedAt <= now` 的 canonical 可见项目；
  取消、删除或重新完成会撤销/移动历史贡献。
- 时长与 Checklist 的正值档位按窗口内最大每日值 `M` 归一化：0 为空，正值按
  `ceil(4 * value / M)` 落入四档。任务量按当日累计量 / 有效目标量落入同样四档并封顶，避免少量
  记录因自身成为观察最大值而错误显示最深色。
- 日期使用调用方当前 Calendar 和半开日区间；系统日历/时区变化时现有 Today 刷新机制会重新分桶。
- UI 使用 Apple 原生 Swift Charts `RectangleMark`，保留系统坐标与图表可访问性；不继续扩写手绘网格。
  调研到的原生 Swift Heatmap 专用包均远低于 1k stars，通用高星图表库又没有日历 Heatmap 且会
  引入 UIKit/适配成本，因此不新增第三方依赖。
- UI 复审后的收口：最多 64 个图表在宽屏卡片布局中使用 `LazyVStack`；不足一分钟的时长用秒显示，
  不再出现有颜色却显示 `0 min`；任务量总值在标题中只显示本地化数字、完整单位保留在副标题和
  可访问性摘要；简繁中文使用“累计计时时长/累計計時時長”，不泄漏英文 Gross。
- Task Detail 的默认关闭 UI 测试使用标准确定性 fixture 中未选择的第三个任务，并沿真实的
  Today -> Tasks -> 搜索 -> 详情路径验证默认关闭、开启后色阶出现、返回 Today 后立即显示。
  UI 测试专用容器按设计是内存型，不能伪装成跨进程持久化证据；真正的持久化由临时磁盘
  SwiftData store 写入后销毁并重建 `ModelContainer` 的单元测试验证。
- UI 验收只使用本任务 owned iPhone/iPad 模拟器；物理设备只执行最终 Release 安装，不启动、
  不操作、不截图。

## 运行资源所有权

- `Task12-Heatmap-iPhone17Pro`：`2FD5F08C-F779-49B6-854D-8B58881971C1`，
  iOS 13 个聚焦测试通过后已终止 App、shutdown 并 delete；名称/UDID 均不再存在。
- `Task12-Heatmap-UI-iPhone17Pro`：`C293811F-C2C3-4A22-B0DF-A466C66328EE`，
  3 个 simulator-only UI 测试通过并导出 10 张 XCTest PNG；已终止 App、shutdown 并 delete。
- `Task12-Heatmap-UI-iPadPro13`：`AFF6A870-C4D2-40A8-B257-0BBC0975A7C0`，
  同组 3 个 simulator-only UI 测试通过并导出 10 张 XCTest PNG；已终止 App、shutdown 并 delete。
- 不触碰 `AnalyticsReview-iPhone17Pro` 或其他非本任务资源。

## Checkpoint 记录

- [x] `82b9bb3`：领取反馈、建立实现记忆与活动链接。
- [x] `5568ab8`：记录模型、UI、依赖与测试审计结论。
- [x] `8c7485b`：实现并验证每任务聚合模型、动态阈值和详情开关。
- [x] `0ddec3f`：Swift Charts 每任务卡片、Blossom 主题色、详情预览、本地化及确定性 UI fixture；
  owned iPhone 模拟器 13 个聚焦测试通过；UI 复审收口后 macOS 13 个聚焦测试再次通过，
  模拟器批次已完整清理。
- [x] owned iPhone/iPad 模拟器交互与截图验收：两个平台各 3/3 UI 测试通过；逐张检查默认关闭、
  开启色阶、Today 同步、清单/时长独立蓝橙色板、层级选择器和选择摘要；两个 owned 模拟器及
  相关进程均已清理。持久化另以真实磁盘 SwiftData 容器重开测试通过；最终 macOS 聚焦批次
  14/14 通过。
- [~] 当前 checkpoint：最终聚焦/相关回归与 Release 全设备安装。
