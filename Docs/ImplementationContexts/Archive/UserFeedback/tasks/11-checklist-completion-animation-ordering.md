# 11：Checklist 完成动画与自动下沉实现记忆

Status: Complete

> 本文件只保存实现、验证和子代理编排记忆，不是任务来源。范围与完成状态必须重新读取
> [`Docs/userfeedback.md`](../../../../userfeedback.md) 中唯一的 `[~]` 项。

## 当前阶段

- [x] 领取“勾选 checklist 加动画，完成内容自动移动到最下面”的反馈并建立活动链接。
- [x] 审计所有 checklist 展示入口、完成命令、持久化排序与现有测试。
- [x] 实现并验证完成/取消完成时的状态反馈和稳定排序。
- [x] 在 owned 模拟器完成普通路径与 simulator-only 截图验收。
- [x] 执行 Release 全设备安装、签名/版本核验与资源清理。
- [x] 由 Codex 在唯一任务来源标记完成并移除活动链接。

## 反馈边界

- 点击 checklist 完成控件时提供短促、清晰且可取消的状态变化动画。
- 已完成条目自动显示在未完成条目之后；不臆造新的手动排序规则，先以现有持久化顺序语义为准。
- 覆盖现有 checklist 可见入口，不把同一数据在不同页面表现成互相矛盾的顺序。
- 只处理 `Docs/userfeedback.md` 当前 `[~]` 项，不领取后续反馈。

## 验收清单

- [x] 定位 checklist 行、完成动作、排序字段与所有展示入口
- [x] 明确完成、取消完成、连续快速点击及跨刷新后的顺序语义
- [x] 使用原生 SwiftUI 动画与稳定 `ForEach` identity 完成实现
- [x] 覆盖排序/持久化语义的单元或契约测试
- [x] 在 owned iPhone/iPad 模拟器验证普通交互并适当截图
- [x] 运行 `CONFIGURATION=Release scripts/build_install_all.sh`
- [x] 核验安装版本与签名，清理 owned 设备、进程和临时产物
- [x] 由 Codex 在 `Docs/userfeedback.md` 标记完成并移除活动链接

## 实现约束

- 采用 Apple HIG 的目的性、短促动作反馈；避免装饰性或阻塞式动画，并尊重系统 Reduce Motion 行为。
- 复用现有 checklist 控件、命令与排序服务；优先原生 SwiftUI `Button`、`withAnimation`、transition/符号效果，不新增重复组件。
- `ForEach` 必须保持持久稳定 identity；不能用数组索引或可变内容作为 identity。
- 不新增 Liquid Glass；保留正式 Apple Developer 签名。
- 所有验收截图仅来自 owned 模拟器；物理设备只执行规定的 Release 安装，不启动、不操作 UI、不截图。

## 子代理编排

- [x] 数据模型、命令、持久化排序语义独立审计。
- [x] SwiftUI checklist 展示入口、动画边界与跨平台一致性独立审计。
- [x] 现有测试覆盖、可复用测试夹具与模拟器验收路径独立审计。

## 审计与实现结论

- 新建/编辑、正常任务详情、草稿恢复详情都汇聚到
  `TaskChecklistEditorSection` 与共享 `ChecklistCompletionButton`；AI 只读预览和
  Inbox 编辑行不属于本反馈的可勾选任务 checklist 入口。
- UI 已采用持久 UUID 作为 `ForEach` identity；完成图标以 0.22 秒 snappy
  opacity/scale 反馈，行位置以 0.28 秒 snappy 动画变化，两者均尊重 Reduce Motion。
- 编辑会话原本已把完成项追加到完成组末尾、把重新打开项放到未完成组末尾；本次
  修正直接 Store 命令路径，使其也只移动目标项的 `sortOrder` 到目标组末尾，不再出现
  编辑页与直接命令对“最下面”的不同解释，也不会修改 sibling mutation revision。
- 不采用 `completedAt` 作为展示顺序：该字段是真实完成时间，而且会覆盖现有完成组
  手动排序。排序继续复用现有 `ChecklistOrderingService` 与 canonical `sortOrder`。
- UI 测试补充完成状态的 accessibility value 断言、route fallback，并按运行设备生成
  `iphone-` / `ipad-` 截图名，避免双设备截图误标或互相覆盖。

## 运行资源所有权

- owned iPhone 17 Pro `Task11-iPhone17Pro-20260721`
  (`9C9066F5-F884-42E6-962F-15574C2D3AF8`) 已关闭并删除。
- owned iPad Pro 11-inch (M4) `Task11-iPadPro11M4-20260721`
  (`6EDBE64F-ADE3-43A5-A507-4837198A56DB`) 已关闭并删除。
- 两套 DerivedData、xcresult、导出附件和 `/tmp/TimeTrackerTask11FocusedTests*` 已删除；
  仅保留 `build/Task11SimulatorValidation/FinalScreenshots/` 的四张 simulator 截图
  （约 1.2 MB）。无 owned Booted 设备或测试进程残留。
- `build/Install/` Release 临时构建目录已删除；没有 `xcodebuild`、`xctest`、UI runner
  或 Instruments 进程残留。
- 不触碰 `AnalyticsReview-iPhone17Pro` 或其他未由 Task 11 创建的设备/进程。

## Checkpoint 记录

- [x] `c53235e`：领取反馈、建立实现记忆与活动链接。
- [x] `de181a2`：统一编辑会话与直接命令的完成组末尾语义，并加强排序、快速双切、
  稳定 identity 和 Reduce Motion 契约。
- [x] 聚焦实现验证：macOS arm64 上运行命令、会话、排序、协调器和 UI 契约测试，
  `/tmp/TimeTrackerTask11FocusedTests4.xcresult` 为 100/100 通过、0 失败、0 跳过。
- [x] owned iPhone 17 Pro 与 iPad Pro 11-inch (M4) 分别运行
  `testCompletingChecklistItemMovesItBelowIncompleteWork`，均为 1/1 通过、0 失败、0 跳过；
  前后四张 simulator-only 截图已人工检查，状态值和最终几何顺序正确。
- [x] `CONFIGURATION=Release scripts/build_install_all.sh` 退出码为 0；Release 1.1.52 (107)
  已安装到 iPhone Air (`FBA36694-D841-56D4-8ED6-21942873B21B`) 与 iPad Pro M4
  (`748D0137-ADC3-58AF-855C-1E98B3125F93`)，macOS App 已复制到
  `/Applications/timetracker.app`。物理设备仅安装，未启动、未操作 UI、未截图。
- [x] iOS 主 App、Live Activity、Widget、嵌入 Watch companion 与 macOS App 均为
  1.1.52 (107)，Team `LT98S43NKA`，`codesign --verify` 通过。当前没有可见物理
  Apple Watch，因此只核验了已签名嵌入 companion；配对 Watch 的实际安装仍由系统的
  Automatic App Install 决定。
- [x] `Docs/userfeedback.md` 中本任务已由 Codex 标记为 `[x]`，活动链接已移除；后续
  Heatmap 反馈仍为 `[ ]`，尚未领取。
