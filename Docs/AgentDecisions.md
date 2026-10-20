# TimeTracker Agent 决策文档

状态：有效决策记录
最近更新：2026-10-20

只收录违反后会损坏用户数据或打散架构、且从代码里不容易看出的长期不变量。其余细节以代码、行为测试和 [Architecture](Architecture.md) 为准；历史决策由 git 承载。编号沿用原值以保持引用稳定。

## 数据

**AD-001：`TimeSegment` 是时间事实来源。** 统计与展示只从 canonical segment 派生，缓存只做加速；并行计时合法：gross = 片段之和，wall = 区间并集，overlap = `gross - wall`。用户可更正或软删除记录，事实来源不等于 append-only。

**AD-002：持久写入只走命令边界。** View、App Intent、Watch 与维护代码不直接写 SwiftData；生产写入按“取得 store lock → fresh `ModelContext` → 一次 `performAtomicMutation`”提交，失败整体回滚。锁内不做网络或 UI 等待；Keychain 等不能回滚的副作用失败要补偿并单独报告。

**AD-007：Schema 变更保留用户事实。** 新版本走 `VersionedSchema` + migration stage + 冻结旧模型快照，并配旧 store 兼容测试；无法安全迁移时停止并报错，不得静默创建空库或删除磁盘 store。

**AD-014：读侧先 LWW 再过滤 tombstone。** winner 依次比较 `updatedAt`、同时刻 tombstone 优先、`createdAt`，再按稳定 ID 决胜；可见查询不得在 LWW 之前丢弃已删除行。生产 store 永不物理清除 tombstone。

**AD-036：分批导入的孤儿记录只隔离不删除。** CloudKit 可能先导入 segment/session 后导入 task；读模型只暴露关系完整的 segment，父记录到达后自动恢复，不得用数据库清理代替隔离。

**AD-143：CloudKit 镜像是唯一的同步机制。** 合并交给 `NSPersistentCloudKitContainer` 与 AD-014；应用不做整库快照、分叉检测或“替换云端/本机”。容器打开顺序 demo → CloudKit → 同文件本地 → 内存 emergency（禁止写入），任何失败都不删除磁盘 store。iCloud 开关是设备本地设置。

## 边界

**AD-004：系统表面只是投影。** Widget、Watch、Live Activity、App Intents 复用领域命令，不保存唯一事实；提交后按 `StoreDomainEvent` 异步投影，投影失败不得把已提交动作报告为失败。快照与命令都有数量/字节上限。

**AD-005：秘密只在本机 Keychain。** API key 经 `LLMCredentialStoring`（实现为 `KeychainLLMCredentialStore`，device-only、不同步）存取，不进 SwiftData、UserDefaults、导出或日志；JSON 导出是只读快照，失败要 fail closed，不称为备份。

**AD-132：AI 只能提案，不能直接写入。** 模型工具调用只修改内存 overlay；Apply 在 store lock 内重新捕获完整 baseline 做 CAS，任何差异或失败都零写入，任务移除只归档。reasoning、tool round 与原始响应只存在于当前会话。

## 平台

**AD-139：按窗口宽度选择共享 shell。** `AppRootView` 以实测宽度选 compact（<720 pt）或 regular shell；`#if os(...)` 只封装真实缺失的 API 与系统 chrome，不按设备 idiom 复制同一页面。

**AD-144：iOS/iPadOS 的 shell 用 UIKit，页面保持 SwiftUI。** `ShellController` 按宽度（AD-139）放 `UITabBarController` 或 `UISplitViewController`，选中项经 UIKit 对 `@Observable` store 的自动观察跟随 `desktopDestination`；页面以 `UIHostingController` 承载并注入 scene 级环境。实测（`PagePerformanceUITests`，Release）页面绘制只占应用 CPU 约四分之一，整页改写 UIKit 收益有限，所以只有某页经度量证明是瓶颈时才改为 UIKit。macOS 保持 SwiftUI。
