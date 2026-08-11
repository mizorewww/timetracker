# 10：任务详情主要动作布局实现记忆

Status: Complete

> 本文件只保存实现、验证和子代理编排记忆，不是任务来源。范围与完成状态以
> [`Docs/userfeedback.md`](../../../../userfeedback.md) 中对应条目为准。

## 当前阶段

- [x] 已按文档顺序领取“Stop 复用顶部任务卡片、Add Time 替换原 Edit 位置”的反馈。
- [x] 已审计任务详情、统一编辑状态、顶部任务卡片和现有动作入口。
- [x] 已确认历史实现满足动作重排/复用，并加固陈旧 Stop 动作竞态与卡片边界回归测试。
- [x] 使用 owned 模拟器验证普通交互路径并进行 simulator-only 截图验收。
- [x] 执行 Release 全设备安装、签名与版本核验，清理构建资源。
- [x] 由 Codex 在反馈文档标记完成并移除活动软链接。

## 反馈边界

- 运行中任务的 Stop 应位于详情页最上方的任务卡片内，并复用已有任务卡片交互/视觉实现。
- 详情与编辑已合并；Add Time 应占用原 Edit 动作所在位置。
- 只处理 `Docs/userfeedback.md` 中此前领取并现已完成的对应条目，不领取后续反馈。

## 验收清单

- [x] 定位顶部任务卡片、Stop、Edit、Add Time 的现有实现和数据流
- [x] 明确运行中、暂停、未运行等状态下的动作可见性与行为
- [x] 依照 Apple HIG 与 SwiftUI 最佳实践完成最小重排/复用
- [x] 覆盖布局、动作路由和状态变化的自动化回归测试
- [x] 在 owned 模拟器验证 iPhone/iPad 普通路径并适当截图
- [x] 运行 `CONFIGURATION=Release scripts/build_install_all.sh`
- [x] 核验安装版本与签名，释放 owned 设备、进程和临时产物
- [x] 由 Codex 在 `Docs/userfeedback.md` 标记完成并移除活动软链接

## 初始实现约束

- 优先复用仓库现有任务卡片与原生 SwiftUI `Button`/`ToolbarItem`，不新增重复组件或无必要依赖。
- iPhone/iPad 可点击区域至少 44×44pt；主要动作保持清晰、可预测且不依赖颜色表达。
- 不把 Stop 误设为默认 prominent 动作；它会结束当前计时，应保持语义和状态反馈明确。
- 保留正式 Apple Developer 签名；验证不得通过关闭签名规避问题。

## 子代理编排

- [x] 任务详情与任务卡片复用边界静态审计：正确复用边界是 `TaskTimerActionButton`；只读 Home 行不可包裹详情 `TextField`。
- [x] 回归测试、状态矩阵与验收路径独立审计：现有精准 UI 用例可在 owned iPhone/iPad 上直接验收。
- [x] 第二次 iPhone 失败独立诊断：launch request 参数正确但进程异常进入生产 CloudKit store，demo fixture 缺失；擦除 owned Simulator 后同用例及 iPad 均通过，未把基础设施瞬态误判为详情 UI 回归。

## 运行资源所有权

- Task 10 owned iPhone 17 Pro：`CFB636E3-65F0-4278-9D33-CC3318E51ADC`，验证后已关闭并删除。
- Task 10 owned iPad Pro 11-inch (M4)：`21F8B762-CFFE-451E-A823-A7CFE7687404`，验证后已关闭并删除。
- 不触碰 `AnalyticsReview-iPhone17Pro` 或其他不属于 Task 10 的设备/进程。
- 每个验证批次记录 UDID，结束后终止 App、关闭并删除 owned 设备，清理 Runner、构建与诊断进程。

## Checkpoint 记录

- [x] 领取反馈、建立实现记忆与活动链接：`0e84666`。
- [x] 历史核对：`5f4744e` 已把共享 Stop/Start 移入首个 identity Section，并用 Add Time 替换原 toolbar Edit；后续统一编辑重构保留该结构。
- [x] 复用边界：详情顶部含可编辑标题、焦点与校验，不能直接复用把只读身份包进导航 `Button` 的 `HomeTimerTaskRow`；共享 `TaskTimerActionButton` 才是正确组件边界。
- [x] 动作状态矩阵：当前任务运行时始终保留 Stop；可追踪未运行任务显示 Start/Switch；不可追踪且无活动段时隐藏计时与 Add Time；草稿恢复 toolbar 只显示恢复动作。
- [x] 竞态加固：详情计时按钮捕获当次渲染的 `activeSegment` 快照，陈旧 Stop 的第二次触发只尝试停止原 segment，不会因为重新读取为空而意外启动。
- [x] 测试边界：source contract 固定可见动作快照语义；沿用现有 UI 几何断言证明计时按钮与标题位于首张卡片、Add Time 位于其上方 toolbar。
- [x] 聚焦验证：macOS `TaskUIContractTests`、`SharedComponentsContractTests`、`TaskWorkspaceContractTests` 共 59/59 通过，无失败或跳过；未启动模拟器。
- [x] 参考实现：Apple HIG Buttons/Toolbars 与 SwiftUI `Button`/`ToolbarItem`；未新增第三方依赖。
- [x] 首轮 iPhone UI 失败证据：精准用例真实执行 1 项，在新增 container identifier 覆盖既有子元素 identifier 后失败；属于测试辅助语义回归，未冒充产品布局失败。
- [x] 第二轮 iPhone UI 启动失败证据：精准用例真实执行 1 项；XCTest 日志证明已传入 `--uitesting`、`replaceOnLaunch`、`task-detail` 和目标任务标题，但进程异常进入生产 CloudKit store，最终 UI hierarchy 停在无 demo 数据的 Today。失败发生在 fixture bootstrap/路由启动阶段，尚未进入本任务布局断言；日志显示启动前 PID 为 0，因此不臆测为旧进程复用。
- [x] iPhone 模拟器验收：擦除 owned iPhone 后精准用例 `testTaskDetailPromotesTimerAndManualTimeActions` 真实执行 1 项、1/1 通过；验证 Stop→Start→Stop、Add Time sheet、顶部卡片几何与 44×44pt 目标。截图：`build/Task10SimulatorValidation/FinalScreenshots/iphone-task-detail-top-actions.png`。
- [x] iPad 模拟器验收：owned iPad 上同一精准用例真实执行 1 项、1/1 通过；额外验证 iPad Stop 保留可见文字。截图：`build/Task10SimulatorValidation/FinalScreenshots/ipad-task-detail-top-actions.png`。
- [x] 截图人工验收：两张图均只来自 owned 模拟器；Stop 位于首张任务卡片，Add Time 位于原 Edit 的顶部工具栏区域，无裁切、重叠或异常间距。
- [x] 修正后聚焦验证：macOS `TaskUIContractTests`、`SharedComponentsContractTests`、`TaskWorkspaceContractTests` 共 59/59 通过，无失败或跳过。
- [x] 模拟器清理：两个 owned UDID 均已关闭并删除，无 owned `xcodebuild`、`xctest`、Runner、诊断进程或 Booted 设备残留；`AnalyticsReview-iPhone17Pro` 保持 Shutdown 且未触碰。
- [x] 规定安装命令：`CONFIGURATION=Release scripts/build_install_all.sh` 完整退出 0；iOS/iPadOS 与 macOS Release 均构建成功，macOS 成品已替换到 `/Applications/timetracker.app`。
- [x] 物理设备安装核验：iPad Pro M4（`748D0137-ADC3-58AF-855C-1E98B3125F93`）与 iPhone Air（`FBA36694-D841-56D4-8ED6-21942873B21B`）均安装 `me.mezorewww.timetracker` 1.1.52 (107)，`devicectl` 报告为 Developer App；只安装，未启动、未操作 UI、未截图。
- [x] Release 签名核验：iOS 主 App、内嵌 `me.mezorewww.timetracker.watchkitapp` 与 `/Applications/timetracker.app` 均为 1.1.52 (107)、Team `LT98S43NKA`，`codesign --verify --deep --strict` 全部通过。
- [x] Release 资源清理：验证后删除 `build/Install`（约 2.1 GB）及其 DerivedData；保留两张 simulator-only 最终验收图。脚本会话已退出，未创建或占用额外模拟器。
- [x] Release 证据 checkpoint：`d521def`。
- [x] Task 10 完成：由 Codex 将唯一任务来源中的该项标记为 `[x]`，并移除活动实现记忆链接。
