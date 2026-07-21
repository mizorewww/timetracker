# 10：任务详情主要动作布局实现记忆

> 本文件只保存实现、验证和子代理编排记忆，不是任务来源。范围与完成状态必须重新读取
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中唯一的 `[~]` 项。

## 当前阶段

- [x] 已按文档顺序领取“Stop 复用顶部任务卡片、Add Time 替换原 Edit 位置”的反馈。
- [x] 已审计任务详情、统一编辑状态、顶部任务卡片和现有动作入口。
- [x] 已确认历史实现满足动作重排/复用，并加固陈旧 Stop 动作竞态与卡片边界回归测试。
- [~] 使用 owned 模拟器验证普通交互路径并进行 simulator-only 截图验收。
- [ ] 执行 Release 全设备安装、签名与版本核验，清理 owned 资源。
- [ ] 由 Codex 在反馈文档标记完成并移除活动软链接。

## 反馈边界

- 运行中任务的 Stop 应位于详情页最上方的任务卡片内，并复用已有任务卡片交互/视觉实现。
- 详情与编辑已合并；Add Time 应占用原 Edit 动作所在位置。
- 只处理 `Docs/userfeedback.md` 当前 `[~]` 项，不领取后续反馈。

## 验收清单

- [x] 定位顶部任务卡片、Stop、Edit、Add Time 的现有实现和数据流
- [x] 明确运行中、暂停、未运行等状态下的动作可见性与行为
- [x] 依照 Apple HIG 与 SwiftUI 最佳实践完成最小重排/复用
- [x] 覆盖布局、动作路由和状态变化的自动化回归测试
- [ ] 在 owned 模拟器验证 iPhone/iPad 普通路径并适当截图
- [ ] 运行 `CONFIGURATION=Release scripts/build_install_all.sh`
- [ ] 核验安装版本与签名，释放 owned 设备、进程和临时产物
- [ ] 由 Codex 在 `Docs/userfeedback.md` 标记完成并移除活动软链接

## 初始实现约束

- 优先复用仓库现有任务卡片与原生 SwiftUI `Button`/`ToolbarItem`，不新增重复组件或无必要依赖。
- iPhone/iPad 可点击区域至少 44×44pt；主要动作保持清晰、可预测且不依赖颜色表达。
- 不把 Stop 误设为默认 prominent 动作；它会结束当前计时，应保持语义和状态反馈明确。
- 保留正式 Apple Developer 签名；验证不得通过关闭签名规避问题。

## 子代理编排

- [x] 任务详情与任务卡片复用边界静态审计：正确复用边界是 `TaskTimerActionButton`；只读 Home 行不可包裹详情 `TextField`。
- [x] 回归测试、状态矩阵与验收路径独立审计：现有精准 UI 用例可在 owned iPhone/iPad 上直接验收。

## 运行资源所有权

- 尚未创建 Task 10 owned 模拟器。
- 不触碰 `AnalyticsReview-iPhone17Pro` 或其他不属于 Task 10 的设备/进程。
- 每个验证批次记录 UDID，结束后终止 App、关闭并删除 owned 设备，清理 Runner、构建与诊断进程。

## Checkpoint 记录

- [x] 领取反馈、建立实现记忆与活动链接：`0e84666`。
- [x] 历史核对：`5f4744e` 已把共享 Stop/Start 移入首个 identity Section，并用 Add Time 替换原 toolbar Edit；后续统一编辑重构保留该结构。
- [x] 复用边界：详情顶部含可编辑标题、焦点与校验，不能直接复用把只读身份包进导航 `Button` 的 `HomeTimerTaskRow`；共享 `TaskTimerActionButton` 才是正确组件边界。
- [x] 动作状态矩阵：当前任务运行时始终保留 Stop；可追踪未运行任务显示 Start/Switch；不可追踪且无活动段时隐藏计时与 Add Time；草稿恢复 toolbar 只显示恢复动作。
- [x] 竞态加固：详情计时按钮捕获当次渲染的 `activeSegment` 快照，陈旧 Stop 的第二次触发只尝试停止原 segment，不会因为重新读取为空而意外启动。
- [x] 测试边界：新增 `task.detail.identityCard`，UI 测试直接断言计时按钮完整位于首张卡片内；source contract 固定可见动作快照语义。
- [x] 聚焦验证：macOS `TaskUIContractTests`、`SharedComponentsContractTests`、`TaskWorkspaceContractTests` 共 59/59 通过，无失败或跳过；未启动模拟器。
- [x] 参考实现：Apple HIG Buttons/Toolbars 与 SwiftUI `Button`/`ToolbarItem`；未新增第三方依赖。
- [~] 当前 checkpoint：准备提交动作快照与卡片边界加固。
