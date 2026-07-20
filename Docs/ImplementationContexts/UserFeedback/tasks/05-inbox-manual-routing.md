# 05：Inbox 人工归类实现记忆

> 本文件只保存实现、验证和子代理编排记忆，不是任务来源。范围与完成状态必须重新读取
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中唯一的 `[~]` 项。

## 当前阶段

- 三条人工入口、共享 picker、领域 command 和 LLM 共用落地核心已经完成静态审计。
- 已修复 picker 打开期间 AI 建议、纯排序或同逻辑 CloudKit winner 替换导致人工选择被误拒绝的竞态。
- 领域边界与 iPhone、iPad、macOS 普通路径、截图证据已经验收。
- Release 已完成全设备安装、独立版本/签名核验和 owned 资源清理；反馈项已完成。

## 实现边界

- 人工入口必须覆盖归入 category、归入 task、作为 task checklist 三种目标。
- 选择目标前不修改数据；成功后 Inbox 条目只能被消费一次，失败时保留原条目。
- 排除不可用或会形成非法层级的目标，并处理目标在确认前被删除或归档的情况。
- iPhone 使用适合紧凑宽度的单一模态流程；iPadOS/macOS 保留上下文并支持指针、键盘选择。
- 不处理 `Docs/userfeedback.md` 中后续的选择器视觉统一、归档语义或详情编辑任务。

## 验收清单

- [x] 盘点模型关系、持久化约束、LLM 建议 command 与 Inbox UI
- [x] 建立人工归类 command 的领域测试和失败回滚测试
- [x] 实现三种人工归类入口并复用既有选择组件
- [x] 验证 iPhone、iPad、macOS 普通交互路径并截图
- [x] 运行 `CONFIGURATION=Release scripts/build_install_all.sh`
- [x] 核验安装版本与签名，释放 owned 设备、进程和临时产物
- [x] 只在 `Docs/userfeedback.md` 标记完成并移除活动软链接

## 依赖策略

- 优先使用 SwiftUI、SwiftData 与项目现有选择器/command。
- 如确需第三方库，先核对维护状态、许可证、平台兼容性和至少 1k GitHub stars；
  没有明确收益则不新增依赖。

## 子代理编排

- 已完成：领域审计确认三条人工路径与 LLM 复用 `createRouteDestination`，并定位逻辑 identity 竞态。
- 已完成：UI/HIG 审计确认继续使用行内 `Menu`、场景级单一 sheet 和两个现有共享 picker。
- 已完成：测试审计确认三路行为、重复消费、目标失效与原子回滚基础覆盖；补充分类 assignment 回滚和 picker 资格语义。
- 已完成：最终静态审查发现 macOS 消费断言把标题误当 `StaticText`、picker fallback
  作用域过宽和截图设备名判定不稳；现已改为追踪同一 Inbox UUID 的真实 `TextField`、
  sheet/picker 双层限定查询和 simulator model 判定。

## 运行资源所有权

- iPhone 17 Pro（iOS 27.0）：`30CFA1DF-4E56-4FD4-BD3A-CFC3E4F85A18`
- iPad Pro 11-inch M4（iOS 27.0）：`AF83CEAC-6D76-437A-BC4F-F6D412F59304`
- 两台设备只归本任务 UI 验收批次使用；已终止 App、关机并删除。
- 既有 `AnalyticsReview-iPhone17Pro` 不属于本任务，不启动、不删除。
- 清理复核时没有 Booted 设备，也没有本任务残留的 `xcodebuild`、`xctest`、
  UI Runner、App、Instruments、Simulator 或 Problem Reporter 进程。

## UI 与回归证据

- iPhone 17 Pro / iOS 27：三条人工路径 3/3；结果
  `/tmp/TimeTrackerTask05-iPhone-20260720-10.xcresult` 已解析通过并在资源清理时移除，
  最终截图保留在 `build/Task05InboxShots/iPhone-verified/`。
- iPad Pro 11-inch M4 / iOS 27：三条人工路径 3/3；结果
  `/tmp/TimeTrackerTask05-iPad-20260720-11.xcresult` 已解析通过并在资源清理时移除，
  最终截图保留在 `build/Task05InboxShots/iPad-verified/`。
- macOS 27：同一产品实现的三条人工路径 1/1；无遮挡 App 截图在
  `build/Task05InboxShots/macOS/`。当前测试代码另以
  `/tmp/TimeTrackerTask05-macOS-20260720-9.xcresult` 复验 1/1，并按三个
  Inbox UUID 验证真实标题字段被消费；结果包已在资源清理时移除。
- 后续三批 macOS 屏幕截图因 Codex 窗口在拍摄瞬间占据桌面而作废，不计入视觉证据；
  结构化断言与此前无遮挡截图均有效。
- 相关领域、路由器、共享 picker 与 UI 契约共 9 个 suites、81/81：
  `/tmp/TimeTrackerTask05-domain-final.xcresult` 已解析通过并在资源清理时移除。
- 所列四个最终结果均为 0 跳过、0 失败、0 运行时警告；截图已人工检查菜单完整性、
  三种搜索结果、模态尺寸和完成后的 Inbox 消费状态。

## Release 安装与签名

- 精确执行 `CONFIGURATION=Release scripts/build_install_all.sh`，退出码 0；
  构建元数据为 `main cee6372cccf1 dirty=false`。
- iPad Pro M4 `748D0137-ADC3-58AF-855C-1E98B3125F93` 与 iPhone Air
  `FBA36694-D841-56D4-8ED6-21942873B21B` 均已安装
  `me.mezorewww.timetracker` 1.1.52（107），并由 `devicectl` 独立查询确认。
- `/Applications/timetracker.app` 已原子替换为同版本 macOS Release；
  `codesign --verify --deep --strict` 通过，签名为
  `Apple Development: ZEXUAN GAO (PX46M259V3)`、Team `LT98S43NKA`。
- iOS 主 App 与嵌入 Watch App 均通过严格签名验证并属于 Team `LT98S43NKA`；
  iOS 保留 HealthKit、CloudKit、App Group，Watch companion 正确指向主 App。
- 当前没有可见的实体 Apple Watch，因此脚本无法独立核对嵌入描述文件的手表设备覆盖；
  Watch bundle、版本、companion 关系和代码签名均已验证。
- 本任务没有新增第三方依赖；产品实现复用 SwiftUI、SwiftData 和项目既有 picker，
  测试仅使用 XCTest 与测试侧 AppKit。

## Checkpoint 记录

- `41babb9`：修正 `parentEligibleTaskIDs` 的过期 UI 契约，单测 1/1。
- `a357333`：保留人工归类意图；新增 AI 落地、纯排序、逻辑 winner 替换三个竞态测试，manual-route suite 12/12。
- `51e7f28`：补齐完成/删除拒绝、分类 assignment 回滚、递归模板目标和三语中性错误；4 个 suites 共 38/38。
- `cee6372`：以强 UUID 消费断言复验 iPhone、iPad、macOS 三端人工归类路径，
  9 个 suites 共 81/81，并保留最终截图证据。
