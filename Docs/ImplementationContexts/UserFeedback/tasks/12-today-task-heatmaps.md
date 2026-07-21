# 12：Today 每任务 Heatmap 实现记忆

> 本文件只保存实现、验证和子代理编排记忆，不是任务来源。范围与完成状态必须重新读取
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中唯一的 `[~]` 项。

## 当前阶段

- [~] 领取 Heatmap 反馈并建立活动链接。
- [ ] 审计任务模型、计时/Checklist 聚合、Today、设置、任务详情与 BlossomColor 组件。
- [ ] 明确普通计时任务、Checklist 和未来任务量任务的每日强度语义与迁移默认值。
- [ ] 实现持久化配置、每日聚合、每任务配色与 Today Heatmap。
- [ ] 完成测试、owned 模拟器截图验收、Release 全设备安装与资源清理。
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

- [ ] 从设置选择/取消选择 Heatmap 任务，重启后保持
- [ ] 任务详情开关默认关闭，并与设置选择保持单一语义
- [ ] 每个已选择任务在 Today 显示独立、可辨识的 GitHub 风格年度/周期 Heatmap
- [ ] 复用 BlossomColor 主题色并生成清晰的从浅到深强度层级
- [ ] 普通时长、Checklist 完成数量和仓库已存在的任务量数据有确定、可测试的日聚合语义
- [ ] 空数据、归档任务、删除/恢复数据、时区和跨日边界行为明确
- [ ] iPhone/iPad/macOS 普通布局与深浅色不截断；适当 simulator-only 截图
- [ ] 聚焦测试与相关回归测试通过
- [ ] `CONFIGURATION=Release scripts/build_install_all.sh` 成功并核验版本/签名
- [ ] 清理 owned 模拟器、进程和临时产物

## 子代理编排

- [ ] 数据模型、迁移、每日聚合和阈值语义审计
- [ ] Today、设置、任务详情与 BlossomColor 复用入口审计
- [ ] 测试架构、Swift Charts/可复用库与模拟器验收路径审计

## 运行资源所有权

- 尚未创建 Task 12 owned 模拟器或测试进程。
- 不触碰 `AnalyticsReview-iPhone17Pro` 或其他非本任务资源。

## Checkpoint 记录

- [~] 当前 checkpoint：领取反馈、建立实现记忆与活动链接。
