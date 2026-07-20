# 01：合并一分钟内的同任务计时段

## 反馈

> 如果同一个任务两个计时段间隔小于一分钟，自动合并为一段。

## 预期语义

- 只合并同一个稳定任务身份下、时间顺序相邻的计时段。
- “小于一分钟”按严格 `< 60 秒` 处理；恰好 60 秒不合并。
- 不合并不同任务、重叠/负间隔或无法可靠判定任务身份的数据。
- 自动合并不能绕过现有 store lock、同步冲突处理、活动计时唯一性和持久化回滚边界。
- UI、App Intent、Watch 与 Widget 入口共享同一条业务规则，不能各自复制算法。
- Pomodoro 与普通计时共享 store-scoped 锁和事务边界，但明确不参与快速重启合并。

## 验收证据

- [x] 找到所有创建/重启计时入口和现有统一边界
- [x] 单元测试覆盖 `< 60`、`== 60`、不同任务、活动计时与持久化失败
- [x] 相关测试与构建通过
- [x] `CONFIGURATION=Release scripts/build_install_all.sh` 全设备安装通过
- [x] 终止测试 App，释放并删除本任务拥有的模拟器，确认无遗留构建/测试/扩展进程
- [x] 回写 `Docs/userfeedback.md` 并从 `~active/` 移除链接

## 完成结论

- 状态：2026-07-20 完成。
- 生产实现：`9d9b2a4` 建立快速重启合并，`166c3ff` 补齐离线并发设备的确定性收敛。
- 规则：仅稳定任务身份相同、间隔 `0 <= gap < 60 秒`、没有中间工作且不属于手工导入或 Pomodoro 时合并；恰好 60 秒不合并。
- 合并保留原 Session 身份与起点，把前段写为 tombstone，并使用由前段 ID 派生的确定性新 Segment ID；延迟到达的旧停止命令不会误停新段。
- 统一入口：普通 UI、Shortcut/App Intent、Watch、Widget/Deep Link 最终都进入 `StoreScopedTimerCommandCoordinator`。

## 验证记录

- 核心策略、协调器、并发冲突与持久化回滚聚焦测试：24 项通过；新增的只读 store 测试证明最终 save 失败时 Session、前段 tombstone 和确定性替换会整体回滚。
- `CorePerformanceBudgetTests`：10 项通过；包含 50,000 段数据下的快速重启预算。
- Shortcut/System Action、Watch command processor、Widget Deep Link 三组入口测试：93 项通过；每条新回归都覆盖 start → stop → `< 60 秒` restart，并验证 Session/起点保留、前段 tombstone、确定性替换 ID 与唯一可见活动段。
- `CONFIGURATION=Release scripts/build_install_all.sh` 成功：Release iOS 包及嵌入 Watch companion 签名验证通过，macOS universal app 构建并安装到 `/Applications/timetracker.app`。
- 同一份 Release iOS 包收到 iPhone Air 与 iPad Pro M4 的明确安装成功回执；两台设备均为 bundle version 107。当前没有可见物理 Apple Watch，Watch companion 通过 iPhone 嵌入交付，无法在本任务验证手表端自动安装画面。
- 本任务没有 UI 变更，因此不生成无信息量截图。
- 未创建或启动 Simulator；聚焦测试的临时 DerivedData 已删除。收尾检查无 Booted simulator，也无遗留 `xcodebuild`、`xctest`、测试 runner、扩展或 Instruments 进程。

## 依赖

- 没有新增第三方库。
- 使用现有 Foundation、SwiftData、CryptoKit 与 Darwin `flock`；这是本地事务、确定性身份和跨进程互斥语义，新增 UI/网络库不能降低实现复杂度或风险。
