# 52:iCloud 冲突优先自动合并实现记忆

Status: Complete

> 本文件只用于主代理与子代理的实现、验证和编排记忆,不是任务来源。唯一范围与状态必须重新读取
> [`Docs/userfeedback.md`](../../../../userfeedback.md) 中对应的 `[~]` 条目。

## 当前阶段

- [x] 领取"目前总是提示icloud冲突,可merge的应该优先merge,实在冲突再提示选择副本"反馈。
- [x] 审计冲突检测与解决路径(SyncConflictService 家族),确定"可 merge"判定边界。
- [x] 实现可合并场景的自动合并 + 行为测试。
- [x] 模拟器/单试验收,`make test` 全绿。
- [x] 执行 `CONFIGURATION=Release scripts/build_install_all.sh`(实体机安装失败不阻塞),标记完成并移除活动链接。

## 唯一反馈边界

- 仅处理:冲突解决策略从"总是提示用户选副本"改为"可自动合并优先自动合并,真正不可合并才提示"。
- 不领取其他反馈项。
- 同步/数据安全改动必须先读 `Docs/PrivacyAndSecurity.md` 与 `Docs/Architecture.md` schema 规则。

## 强制约束

- 完整遵循仓库本地 `apple-hig` 与 `swiftui-expert-skill`;所有 UI 导航、断言与截图只用 XCTest/XCUITest 脚本。
- 实体机器不做测试;模拟器验收后 shutdown+delete 并清理 /tmp 产物。
- 优先复用现有组件;除用户建议外不引入 GitHub 少于 1k stars 的库。
- 每个 checkpoint 只暂存本任务的已完成变更;保留用户在反馈文件中的其他内容。

## Checkpoint 编排

- [x] Checkpoint A:领取任务、创建实现记忆与 active link。
- [x] Checkpoint B:审计冲突路径与可合并判定。
- [x] Checkpoint C:实现自动合并 + 补齐行为测试。
- [x] Checkpoint D:验收与资源清理。
- [x] Checkpoint E:Release 构建安装、核验与收口。(2026-07-25:Release 全量构建成功,iOS+Watch+macOS 安装流程完成,macOS 装入 /Applications)

## 资源所有权

- [~] 主代理:任务状态、编排、集成、所有 build/simulator/测试/Release 批次与清理。
- [ ] 子代理(审计):冲突服务调用链与提示触发点盘点。

## 已提交 checkpoint

- [x] 实现与测试:`695fbca9` feat: auto-merge diverged iCloud branches before prompting for a copy choice。
- [x] 已收口:userfeedback 勾选 [x],active link 已移除,任务关闭。

### 验收记录补充(Checkpoint D/E)

- 焦点套件:CoreSyncSnapshotMergeTests(8)+ CoreSyncConflictTests + ResolutionIdentity + StoreSerialization + StateWrite + ActivityOutcome 全绿。
- `make test` 全量:2 个与本改动无关的既有隔离缺陷(PreferenceSyncBehaviorTests.checklistCompletion… / TaskPersistencePolicyTests.archiveCommandPreserves…),干净 HEAD 同现,单独跑通过;已向用户报告。
- 本任务为同步/数据层改动,无 UI,无需模拟器截图;未占用模拟器资源。
- Release:build_install_all 完成(exit 0),macOS 装入 /Applications,iOS+Watch 流程走完;实体机状态不阻塞。

## 实现与验收记录

### 设计(Checkpoint B 结论)

审计发现:冲突判定是整份快照 SHA-256 比对,任何一端分叉即提示;state 只存 baseFingerprint 不存 base 快照,无法做经典三方合并。但所有 17 种快照 record 都带 `createdAt/updatedAt/deletedAt`,且仓库已有记录级 LWW 先例(`isPreferredLogicalWinner`、preference 按 key 逻辑 winner、`PersistentModelDeduplication.isPreferred`)。

方案:**双向 LWW 并集合并**(不需要 base 快照):

1. 新纯服务 `SyncDataSnapshot+Merge.swift`:对每张表按 record id 取 LWW winner(updatedAt 新者胜 → 同刻墓碑胜 → createdAt 新者胜 → canonical JSON 字节序兜底,保证跨设备确定性);`syncedPreferences` 按逻辑 key 分组合并(与 RestorePlanning 的 logical winner 语义一致);optional 表 nil=未知,任一非 nil 则以非 nil 为准合并。
2. 接线 `SyncConflictService+CloudImport`:两处 `saveConflict` 调用点 + 已有 pending conflict 的折叠路径 + `reconcilePendingLocalSnapshot` 全部先尝试自动合并:
   - `merged == cloud` → 直接 acceptCloudSnapshot(常见多设备场景:云端严格领先,无需 restore,且 base 得以前进,打破"base 停滞→反复冲突"循环);
   - 否则 `restoreAsLocalWinner`(内含 validateForRestore preflight)→ 更新 localSnapshot/localFingerprint + advanceLocalGeneration,清除 pending conflict;
   - 合并/验证/恢复任一步抛错 → 回退原 saveConflict 提示路径(这才是"实在冲突再提示")。
3. 显式用户选择路径(pendingForcedUpload/explicitlyReplaceCloud)不动。

不需要新库(纯 Foundation)。
