# 46：Quickstart 可排序实现记忆

Status: Complete

> 本文件只用于主代理与子代理的实现、验证和编排记忆，不是任务来源。唯一范围与状态必须重新读取
> [`Docs/userfeedback.md`](../../../../userfeedback.md) 中对应的 `[~]` 条目。

## 当前阶段

- [x] 领取“quickstart要可以被排序”反馈。
- [x] 审计 Quick Start 的存储(固定列表顺序)、编辑页(任务14的动画/置顶)与排序现状。
- [x] 确定排序交互(参照 category 排序任务36 / checklist Sort 模式)。
- [x] 实现并运行聚焦测试与 iPhone/iPad/macOS 模拟器截图验收。
- [x] 执行 `CONFIGURATION=Release scripts/build_install_all.sh`(实体机安装失败不阻塞),标记完成并移除活动链接。

## 唯一反馈边界

- 只做 Quick Start 固定任务的用户自定义排序。
- 不领取 iPad/mac Now 同步、heatmap 进分析页或其他反馈。
- 以普通文字大小、正常交互路径、三平台系统约定为优先。

## 强制约束

- 完整遵循仓库本地 `apple-hig` 与 `swiftui-expert-skill`;所有 UI 导航、断言与截图只用 XCTest/XCUITest 脚本。
- 实体机器不做测试;模拟器验收后 shutdown+delete 并清理 /tmp 产物。
- 优先复用现有排序模式(category 排序、checklist Sort);除用户建议外不引入 GitHub 少于 1k stars 的库。
- 每个 checkpoint 只暂存本任务的已完成变更;保留用户在反馈文件中的其他内容。

## Checkpoint 编排

- [x] Checkpoint A：领取任务、创建实现记忆与 active link。
- [x] Checkpoint B：审计 Quick Start 存储与编辑交互。
- [x] Checkpoint C：实现排序并补齐聚焦测试。
- [x] Checkpoint D：三平台模拟器验收与资源清理。
- [x] Checkpoint E：Release 构建安装、核验与收口。

## 资源所有权

- [x] 主代理：任务状态、编排、集成、所有 build/simulator/XCUITest/screenshot/Release 批次与清理。
- [x] 主代理(直接审计,无需子代理)：Quick Start 存储与编辑审计。

## 已提交 checkpoint

- [x] `b8d027bf`:实现 + 契约/UI + 三平台验收(1.1.130 (185));领取任务与 active link 创建时已提交。


## 实现与验收记录

- 存储 `quickStartTaskIDs: [UUID]` 本就有序;主页与编辑器展示顺序均跟随数组序,只需排序交互。
- 实现:编辑器固定区每行新增 `QuickStartPinnedReorderControls`(上移/下移 chevron,44pt 目标,边界禁用,与 category 排序一致),`movePinned` 走既有 `withSelectionAnimation` swapAt;`#N` 序号徽标加 `fixedSize` 防止被挤压。
- 契约测试 `quickStartEditorReordersPinnedRowsWithAnimatedControls`;UI 测试 `testQuickStartEditorReordersPinnedTasks`(先 pin 第三项→上移到 #2→保存→主页顺序断言),iPhone/iPad/macOS 全通过;macOS 截图因既有截图设施限制跳过(与任务43同)。
- 插曲:iPad 模拟器连续 3 次 launch 超时,重建模拟器后通过,资源已清理。
- [x] `CONFIGURATION=Release scripts/build_install_all.sh`:iOS/macOS BUILD SUCCEEDED,iPhone Air 已装 `1.1.130 (185)`,无设备安装失败。
- [x] 反馈已由主代理标记完成,active link 已移除;owned 模拟器与 /tmp 产物已清理。