# 92：Apple Health 加载不结束实现记忆

状态：2026-07-28 用户复验失败后的第二轮修复已完成

> 本文件是主代理与子代理的实现、验证和编排记忆；唯一任务来源仍是
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的状态条目。

## 认领范围

- 复现并定位 Apple Health 增量刷新一直停留在加载态、从不成功的问题。
- 保持 Task88 已建立的 observer query、增量 anchor、本地 replica 与后台调度架构。
- 修复状态机/命令边界，不以轮询、假成功或绕过 HealthKit 权限替代。

## 验收条件

- [x] 先建立能复现无限加载的行为测试，并定位缺失的终止状态。
- [x] 授权、无数据、增量成功、失败、取消和不可用状态都能确定结束加载。
- [x] 增量 anchor 与 replica durable write 仍保持事务安全，不丢失重试机会。
- [x] 正常字号 UI/状态文案验收通过；需要时保存 Apple Health 设置/任务详情截图。
- [x] `make test`、格式、本地化门禁通过，实现提交后完成 `make build-install-all`。

## 子代理编排

- 子代理 A：只读追踪 HealthKit refresh/observer/anchor 状态机，给出可能无法结束的路径。
- 子代理 B：只读梳理现有 Apple Health 行为测试、UI 测试和缺口。
- 主代理：复现、测试先行、最小修复、验证、截图、提交、设备安装与关闭。

## 约束

- Apple HIG：授权、不可用、空数据、失败和加载必须是用户可区分的真实状态。
- SwiftUI skill：异步任务以单一 owner 驱动，所有成功/失败/cancellation 路径都清理
  presentation state；View 不拥有 HealthKit 持久化。
- 本任务优先复用 HealthKit、Swift Concurrency 和现有 replica 服务；除非现有能力不足，
  不新增第三方依赖。

## 进度记录

- 2026-07-28：修复前在独立临时 iPhone 17 Pro 模拟器运行既有
  `testAppleHealthTaskDetailShowsOnlyAnalyticsSections`，188 秒后仍找不到
  `task.detail.summary.gross`，1/1 失败，保留红测结果
  `build/UITestResults/iOS-20260728-220451.xcresult`，模拟器由 Makefile 自动关闭并删除。
  随后从 `TaskDetailAnalyticsLoadRequest` 移除 `appleHealthReplicaRevision`：本地 replica
  generation 更新不再取消发起该写入的加载；显式重试、范围、日期与实时 bucket 仍会按原
  规则触发新读取。
- 2026-07-28：同一 Apple Health Task Detail XCUITest 修复后 1/1 通过（111.141 秒），
  `task.detail.summary.gross`、`task.detail.summary.wall`、历史图表与本地 replica
  workout 均真实出现，加载/失败状态不再常驻；结果为
  `build/UITestResults/iOS-20260728-221029.xcresult`。已人工检查测试附件
  `iphone-task-detail-apple-health-analytics-only`：正常字号下 Summary 为
  Gross/Wall 50 min，Week 图表及筛选控件完整、无 spinner，符合 HIG 的“内容尽快可用、
  进度指示必须终止”。临时模拟器已自动关闭并删除。
- 2026-07-28：实现 checkpoint 完整 `make test` 通过 1571 tests / 176 suites
  （49.864 秒）；SwiftFormat 与聚焦 replica facade 5/5 均通过。下一步提交实现后运行
  `make build-install-all`，再关闭任务。
- 2026-07-28：实现提交为 `77b9828c`。Release `make build-install-all` 成功，版本
  1.1.345 (400) 已安装到 iPad Pro M4、iPhone Air，并将 universal macOS App 复制、
  验签到 `/Applications/timetracker.app`；iOS App 内含签名的 Watch companion。当前没有
  可见实体 Apple Watch，因此不声称独立 Watch 真机覆盖。所有临时 UI 模拟器已关闭并
  删除，未遗留 `xcodebuild`、`xctest`、UI runner 或 Booted simulator。
- 2026-07-28：用户真机复验仍然无限加载，重新打开任务。已确认第二条独立根因：
  Task Detail 把 `appleHealthReplicaRevision` 放入 `.task(id:)`；首次 HealthKit 增量读取
  写入本地 replica 后 revision 自增，SwiftUI 随即取消尚未提交 UI 终态的加载任务，
  下一轮又因 `loadedRequest == nil` 重新授权、标记同步并写入新 generation，形成自激
  取消循环。当前修复边界缩减为“HealthKit 首次读取并写本地；UI 从本地副本完成一次
  加载”，observer 只负责后续变更通知。
- 2026-07-28：认领用户新增的无限加载 bug，建立活动实现记忆；下一步先写失败测试并
  追踪 refresh 终止路径。
- 2026-07-28：子代理只读审计与行为红测共同确认，首次授权后同步等待
  `enableBackgroundDelivery` 会让 timeline 永久停在 `.requesting`，并阻止任何 replica
  query。新增的 suspended-observation 测试在旧实现稳定失败。
- 2026-07-28：checkpoint A 实现完成。Observer setup 改为 Store 持有、token 隔离的幂等
  Swift Concurrency task；首次 timeline/Health task analytics 在授权后立即开始 anchored
  sync，不等待后台投递注册。setup 失败恢复为可重试，Store 释放时取消 setup 并停止
  observer。聚焦 replica facade 5/5 测试通过；完整 `make test` 通过 1568 tests /
  176 suites，SwiftFormat、diff、三语言本地化与 hook 门禁通过。实现未改变视觉布局，
  采用状态机行为测试验收，不创建无信息增益的截图；待 checkpoint 提交与设备安装。
- 2026-07-28：checkpoint A 提交为 `2aff7826`。Release `make build-install-all` 成功：
  iOS App（含已签名 Watch companion）安装到 iPad Pro M4 与 iPhone Air，universal
  macOS App 安装并验签到 `/Applications/timetracker.app`。当前没有可见实体 Apple
  Watch，因此不声称独立 Watch 真机覆盖。

## 完成边界

- 第二轮修复删除了导致自激取消的 revision 任务身份，保留最直接的数据链路：
  HealthKit anchored query → SwiftData 本地 replica durable write → 同一加载从 replica
  投影 UI。没有新增抽象层、轮询或第三方库。
- 本任务修复异步生命周期与加载终态，没有修改 UI 布局或用户文案；HIG 验收由明确的
  requesting/loading/empty/content/failure 状态行为测试完成，不重复生成外观完全相同的截图。
- 未引入第三方依赖；继续使用 Apple HealthKit、Swift Concurrency、SwiftData replica 与
  现有 generation coalescing。
- 用户自有 `.gitignore` 修改未被读取为任务、未修改、未暂存或提交。
