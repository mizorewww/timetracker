# 22：Inbox 完成态可逆切换实现记忆

> 本文件只用于主代理与子代理的实现、验证和编排记忆，不是任务来源。唯一范围与状态必须重新读取
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 条目。

## 当前阶段

- [x] 领取反馈，审计 Inbox 完成态模型、命令、列表分组与行交互。
- [x] 定位完成后无法恢复的根因，并确定与现有架构一致的最小修复。
- [x] 实现完成/未完成双向切换及单元/契约回归测试。
- [x] 使用 owned iPhone/iPad simulator 验证普通交互路径并按需截图，随后清理资源。
- [ ] 执行 `CONFIGURATION=Release scripts/build_install_all.sh`，标记反馈完成并移除活动链接。

## 唯一反馈边界

- Inbox 中已勾选完成的任务必须能够切回未完成状态。
- 保持现有 Inbox 捕获、建议项、任务转换与删除语义不变。
- 不领取后续 Timeline、Live Activity、首页统计或 Apple Health 历史反馈。

## 强制约束

- 优先复用现有 Inbox command/state service，不建立平行完成态或仅在 View 中伪造状态。
- UI 与截图只使用明确登记的 owned simulator；物理设备只做最终 Release 安装和只读核验，不启动、不操作、不截图。
- 每个小 checkpoint 验证后提交；只暂存本任务状态差异，保护 `Docs/userfeedback.md` 中用户新增内容。

## Checkpoint 编排

- [x] Checkpoint A：静态审计模型、命令、列表分组、跨设备入口和现有测试。
  - 根因是 UI 可达性：`InboxCommandHandler.toggle` 与 store-scoped coordinator 已支持双向切换及 `completedAt` 清空，但条目完成后立即移入默认折叠的 completed section；最后一条 open item 完成后还会在历史区之前显示矛盾的空态。
  - iPhone、iPad、macOS 共用该 Inbox view；Watch、Widget、App Intent 没有 Inbox completion 入口，本任务不扩展系统动作。
  - Apple HIG 要求可逆操作的结果保持可见并让纠错机会靠近相关内容；SwiftUI 官方 `DisclosureGroup`/`onChange` 文档确认展开状态应由明确状态控制。参考：<https://developer.apple.com/design/human-interface-guidelines/undo-and-redo>、<https://developer.apple.com/design/human-interface-guidelines/feedback>、<https://developer.apple.com/documentation/swiftui/disclosuregroup>。
  - 不新增第三方库：现有 SwiftUI `Button`/`List`、SwiftData 原子 mutation、Swift Testing/XCTest 已覆盖需要的状态与交互；外部状态库会破坏现有 store-scoped baseline 语义。
- [x] Checkpoint B：实现与单元/契约测试。
  - open→completed 时先展开 completed section；open 与 completed 都为空时才显示空态；完成圆点和“Mark Open”菜单统一经过父级双向 callback，因此刚完成的同一行仍在原上下文可见并可恢复。
  - fresh-context complete→reopen、`completedAt` 清空、open/completed read model 转移，以及已完成标题提交后使用同一行引用恢复均有回归。
  - 13 个 Inbox/命令/同步/schema/UI contract suite 共 `138/138` 通过；首次新测试失败是夹具种了两条 open item 却错误预期列表为空，修正断言后通过，产品代码无对应失败。
  - simulator 进一步暴露 SwiftUI `List` 的结构快照问题：模型已完成/恢复，但同一 cell 跨 open/completed 条件 Section 迁移后会保留旧分组或失活交互。完成 callback 现只传稳定 UUID、点击时解析最新 read model、避免给跨分组变化套外层动画，并在切换后重建 List 容器；任务 UUID 与图标自身状态动画保持不变。
- [~] Checkpoint C：owned simulator 验收、精确 Release 安装、状态与资源收口。
  - `TT-Task22-iPhone-20260722-1644`（iPhone 17 Pro / iOS 27.0）与 `TT-Task22-iPad-20260722-1644`（iPad Pro 11-inch M5 / iOS 27.0）分别通过完成→同一按钮恢复用例 `1/1`；测试同时要求同标识标题和按钮最终各只有一个，防止旧 List cell/AX ghost 被误判为通过。
  - 两个平台各验收 completed reachable 与 reopened 两张截图：iPhone/iPad 的完成计数、展开历史、44pt completion 控件、删除线和恢复后的未完成行均正确；未使用、启动或截图任何物理设备。
  - 最终相关 13 个 Inbox/命令/同步/schema/UI contract suite `132/132` 通过；owned simulator 均已 terminate、shutdown、delete，Simulator/Problem Reporter 已退出，无 Booted device、owned runner、`xcodebuild`、`xctest`、Instruments 进程残留。

## 资源所有权

- released owned iPhone：`TT-Task22-iPhone-20260722-1644`，UDID `1C6BB874-3023-4867-9A57-F44E3AE41EF1`，已删除。
- released owned iPad：`TT-Task22-iPad-20260722-1644`，UDID `CEF7E14F-2DA0-4B5B-A2E4-2A107D06F207`，已删除。
- 两台设备仅用于 Task22 普通字号 UI test / screenshot；批次已完成资源释放核验。
