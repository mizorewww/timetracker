# 68：iPhone Timeline 时间标注左对齐 实现记忆

Status: Complete

状态：2026-07-27 已完成

> 本文件是主代理与子代理的实现、验证和编排记忆；唯一任务来源仍是
> [`Docs/userfeedback.md`](../../../../userfeedback.md) 中对应的 `[~]` 条目。

## 认领的反馈条目

- iPhone Today Timeline 在重叠记录较少时，时间轴标注没有左对齐。
- “xxx min skipped” 省略标签可以避让时间文字，但不应改变时间刻度的基准对齐。

## 预期行为

- iPhone 普通字号下，Timeline 的开始、结束与中间时间标注使用同一明确的左对齐规则。
- gap/skipped 标签避免遮挡时间刻度，但不能推动或重新居中时间标注。
- iPad 与 macOS 现有横向 Timeline 语义、任务条和 gap 标注不回归。

## UI 验收清单

- 确定性 fixture 覆盖重叠记录较少且包含 skipped gap 的 iPhone Timeline。
- 几何断言验证时间刻度 leading edge 符合统一对齐策略，且不与 gap 标签相交。
- iPhone 普通字号截图人工检查通过。
- 既有 Timeline overlap/gap collision XCUITest 与全量单测通过。
- Release 全设备安装完成，owned 模拟器与 runner 全部释放。

## Checkpoint 编排

- [x] A：领取反馈并建立活动实现记忆。
- [x] B：并行审计时间刻度定位、gap 避让与稳定测试探针。
- [x] C：先补失败的几何测试，再实现最小共享布局修复并更新文档。
- [x] D：完成单测、iPhone XCUITest/截图、回归检查、Release 全设备安装与收口。

## 子 Agent 分工

- 代码审计：定位 iPhone 纵向 Timeline 时间标签的定位公式和 gap 避让分支。
- 设计审计：依据 Apple HIG 与现有视觉语言给出时间轴左对齐、间距和避让边界。
- 测试审计：复用或扩展 short/overlap/gap fixture，给出稳定 identifier 与几何断言。

## 库策略

- 优先复用现有 SwiftUI Timeline layout engine、Chart mark 与几何策略。
- 仅当成熟库提供不可替代能力时引入；本任务不为简单轴标签对齐增加依赖。

## 进度记录

- 2026-07-27：认领任务，创建实现记忆和 `~68` 活动链接，开始三路只读审计。
- 2026-07-27：三路审计一致确认动态 skipped gutter 内的 `.trailing` 是根因；保留现有 Y 碰撞过滤、动态 gutter、lane 和横向轴策略。
- 2026-07-27：新增实际时间文字 footprint 探针和固定双 gap iPhone 几何测试；修正测试滚动目标后得到预期红灯：时间文字 `minX=115 pt`，chart `minX=32 pt`。
- 2026-07-27：将 compact 纵向时间文字改为语义 `.leading`，并补充 UI/代码/测试约束文档；未引入新库。
- 2026-07-27：目标 iPhone XCUITest 转绿；4 个可见 tick 共用 chart leading edge，2 个 skipped 胶囊互不覆盖且不与 tick 相交。截图 `iOS-20260727-152213-attachments/7D71C533-5A6F-4033-9707-EE274E769BC3.png` 人工检查通过。
- 2026-07-27：验证通过：SwiftFormat 830/830、localization 9/9、Timeline 纯布局 38/38、iPhone short/dense overlap、iPad Pro 11" M4 双方向 gap、macOS gap，以及全量 `make test` 1419 tests / 157 suites。
- 2026-07-27：`make build-install-all` 通过；Release 1.1.237 (292) 已安装到 iPad Pro M4 与 iPhone Air，内嵌 Watch companion，并复制到 `/Applications/timetracker.app`；macOS 深度严格签名校验通过。
