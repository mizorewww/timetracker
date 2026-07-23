# 38：可重复任务父级 Heatmap 实现记忆

> 本文件只用于主代理与子代理的实现、验证和编排记忆，不是任务来源。唯一范围与状态必须重新读取
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 条目。

## 当前阶段

- [x] 领取“可重复任务由子任务记录数量/时间、父任务显示 Heatmap”反馈并建立活动链接。
- [x] 审计任务量/可重复任务的父子模型、完成记录、Heatmap 聚合与三平台入口。
- [x] 实现 recurrence owner 投影、权威父级聚合并补齐聚焦测试。
- [~] 将 UI fixture 改为真实 recurrence，并补齐三平台脚本化验收。
- [ ] 分 checkpoint 提交，执行 `CONFIGURATION=Release scripts/build_install_all.sh`，由 Codex 标记完成并移除活动链接。

## 唯一反馈边界

- 仅修复可重复的任务量任务：子任务承载每次完成的数量或时间记录，父任务汇总并显示 Heatmap。
- 不领取后续 AI、首页、分类或其他反馈；具体父子语义、重复类型、聚合范围和展示入口必须由现有代码与测试证据确定。

## 强制约束

- 完整遵循仓库本地 `apple-hig` 与 `swiftui-expert-skill`；所有 UI 导航、断言与截图只用 XCTest/XCUITest 脚本。
- 不手动操作调试窗口；物理设备只做最终 Release 安装和只读版本/签名核验。
- 优先复用 SwiftUI、Swift Charts、SwiftData 及项目现有任务/Heatmap 结构；只有明确缺口才评估成熟依赖，除用户建议外不采用 GitHub 少于 1k stars 的库。
- 每个 checkpoint 只暂存本任务的已完成变更；保留 `Docs/userfeedback.md` 中用户自己的其余内容。

## Checkpoint 编排

- [x] Checkpoint A：领取任务、创建实现记忆与 active link。
- [x] Checkpoint B：审计父子数据流、完成记录、Heatmap 投影、库与自动化基线。
- [x] Checkpoint C：实现数据/聚合修复并完成聚焦验证。
- [~] Checkpoint D：补齐三平台脚本化 UI 验收。
- [ ] Checkpoint E：Release 全设备安装、签名/版本核验与收口。

## 审计证据

- [x] `TaskRecurrenceOccurrence` 的 `templateTaskID ↔ generatedTaskID` 是稳定重复关系；`parentID` 只是可编辑层级。生成时子任务初始挂在模板下并复制数量目标，但之后允许改父。
- [x] 模板是蓝图/容器，数量与时间命令已拒绝模板直接记录；生成子任务才承载 `TaskQuantityEntry` 与 `TimeSegment`。这部分数据写入语义正确。
- [x] 现有 snapshot 在“选中模板且 generated 的 `parentID` 未改动”时，能沿子树汇总同单位数量目标与时长；真正断点是详情开关、设置 picker、偏好命令和 Home 刷新身份都保存/读取原始 generated ID，于是 Heatmap 被固定在单日实例。
- [x] 次级断点是聚合只沿 `parentID`，没有使用 occurrence 权威映射；generated 改父后，模板 Heatmap 会漏掉它的历史。
- [x] 修复边界：建立可缓存的 recurrence Heatmap 投影，提供 generated→template owner、template→generated contributors、顺序稳定归一化、选择资格与 staged/corrupt graph fail-closed；普通父子 Heatmap 继续保留原语义。
- [x] 旧偏好兼容：读取时把有效 generated ID 投影到模板，父子同时存在时去重；写入时持久化模板 ID。未知/暂存不完整 ID 保留为隐藏选择供用户恢复，不静默删 Cloud 偏好。
- [x] HIG/SwiftUI：使用原生 Toggle、层级 picker、Swift Charts；视图只消费 Store 投影，不在 `body` 重建 recurrence 图；稳定 ID、可观察 revision 与明确父/子文案。

## 库与基线

- [x] 官方能力满足缺口：SwiftUI、Swift Charts、SwiftData、Foundation `Calendar`、Swift Testing 与 XCTest/XCUIAutomation；不新增运行时依赖。
- [x] 已审计 `apple/swift-collections`（现有工程依赖，GitHub 约 4.4k stars），但最多 64 项的有序 UUID 归一化用现有 `Array + Set` 更清晰，无需额外链接 `OrderedCollections` 产品。
- [x] 官方参考：[Swift Charts](https://developer.apple.com/documentation/charts)、[Calendar](https://developer.apple.com/documentation/foundation/calendar)、[XCUITest](https://developer.apple.com/documentation/xcuiautomation)、[swift-collections](https://github.com/apple/swift-collections)。
- [x] macOS arm64 聚焦基线通过：Heatmap、刷新身份、重复任务、数量详情与 UI contract 共 29 个测试；结果为 `** TEST SUCCEEDED **`。临时 DerivedData 与 xcresult 已移入废纸篓，无本批次遗留进程。

## 实现证据

- [x] `TodayHeatmapRecurrenceProjection` 缓存 LWW 后的完整 recurrence 图：有效 generated 归一到 template，模板取得所有 occurrence contributor；moved generated 仍按 occurrence owner 汇总。
- [x] staged/incomplete/corrupt 图 fail-closed：原偏好 ID 保留供恢复，但不渲染卡片、不进入 picker；未知 ID 同样不被静默覆写。
- [x] 偏好写命令、详情 Toggle、设置 picker、Home refresh identity 与 snapshot 全部消费同一投影；普通任务与普通父子 Heatmap 语义不变。
- [x] Snapshot 将权威 generated IDs 作为额外遍历根，与现有层级子树 Set 合并；因此 generated 的普通后代也被计入且不会重复。
- [x] 聚焦验证通过：36 个 projection/Heatmap/刷新/UI contract/picker 测试 + 1 个真实 Store 集成测试；覆盖旧 generated 偏好、详情开关持久化为模板、父子去重、数量与时长、移父、损坏与 staged 图。两个 xcresult、DerivedData 与测试进程均已清理。

## 资源所有权

- [~] 主代理：任务状态、编排、集成、所有 build/TestManager/simulator/XCUITest/screenshot/Release 批次与清理。
- [x] `task38_model_audit`：只读确认真实 recurrence 写入语义、owner 断点与可编辑 `parentID` 风险。
- [x] `task38_heatmap_audit`：只读确认 snapshot/偏好/刷新身份断点与权威 contributor 建议。
- [x] `task38_test_audit`：只读确认现有 fixture 是普通父子而非 recurrence，并给出真实 rule/occurrence 的三平台脚本矩阵。

## 已提交 checkpoint

- [x] `6def19c9`：领取任务、建立实现记忆与 active link。
- [x] `1bc53743`：静态/库审计与聚焦自动化基线。
- [~] 待提交：recurrence owner、权威父级聚合、Store 接线与聚焦测试。
