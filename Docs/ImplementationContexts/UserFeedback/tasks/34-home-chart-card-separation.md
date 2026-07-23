# 34：首页 Heatmap 与柱状图卡片拆分实现记忆

> 本文件只用于主代理与子代理的实现、验证和编排记忆，不是任务来源。唯一范围与状态必须重新读取
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 条目。

## 当前阶段

- [x] 领取“首页不要把 heatmap 和柱状图混在一起，每个元素单独做卡片”的反馈。
- [x] 审计首页 Heatmap、柱状图、说明文字和共享卡片容器的当前层级。
- [~] 复用现有首页组件完成最小拆分，补齐 Core/UI contract/XCUITest 与截图验收。
- [ ] 提交实现 checkpoint，执行 `CONFIGURATION=Release scripts/build_install_all.sh`，标记反馈完成并移除活动链接。

## 唯一反馈边界

- 首页 Heatmap 与柱状图不得共享同一张视觉卡片。
- 每个可视化元素应拥有独立、清晰的卡片边界与信息层级。
- 不领取后续首页、Category、AI 或其他反馈。

## 强制约束

- 完整遵循仓库本地 `apple-hig` 与 `swiftui-expert-skill`；UI 调试、导航、断言与截图全部使用 XCTest/XCUITest 脚本。
- 不手动操作调试窗口；物理设备只做最终 Release 安装和只读版本/签名核验，不启动、点击或截图。
- 优先复用现有 SwiftUI/Home 组件与成熟依赖；若评估第三方库，必须核验维护质量与 GitHub stars，除用户建议外不采用少于 1k stars 的库。
- 每个 checkpoint 只暂存本任务变更，保护 `Docs/userfeedback.md` 中其余用户新增内容。

## Checkpoint 编排

- [x] Checkpoint A：范围领取、当前视图层级审计与自动化验收设计。
- [~] Checkpoint B：最小实现、聚焦测试与脚本截图验收。
- [ ] Checkpoint C：Release 全设备安装、签名/版本只读核验与收口。

## 资源所有权

- `task34_home_audit`、`task34_hig_audit` 与 `task34_test_audit` 仅做只读审计；未编辑、构建、测试、创建 simulator 或操作窗口。
- 暂未创建 simulator、xcresult 或本任务 DerivedData；创建后必须记录 UDID/路径并在 checkpoint 结束时释放。

## Checkpoint A 审计结论

- `PhoneHomeView` 与宽屏 `HomeViews` 已把周 Gross 柱状图和 Heatmap 作为相邻但独立的 section；两类图分别走 `BarMark` 与 `RectangleMark`，Store/快照数据链也完全独立，不能为本任务改 Charts 或数据层。
- 周柱状图在 iPhone 是只有一个 chart row 的独立原生 `Section`，宽屏柱图和每张 Heatmap 也已分别使用现有 `.appCard`，这些路径无需修改。
- 唯一视觉缺口在 iPhone `.insetGrouped`：当前一个 `Section` 内的 `ForEach(snapshots)` 会被系统绘制成一张连续分组背景，多张任务 Heatmap 因而像同一张卡。Apple 官方对 `insetGrouped` 的说明也明确其背景会从 section header 连续包住该 section 的所有 items。
- 最小修复是让每个稳定 `taskID` 对应的 Heatmap 各自产生一个原生 `Section`；首张 section 保留一次共享标题、任务数与 Info，其余 section 不重复 header，loading 仍使用单一带 header 的 section。不得在 iPhone 原生 List 卡片内再嵌 `.appCard`。
- 保留第 30 项已经验收的层级：统计图总标题和累计值在卡片外，详细说明继续位于 Info 二级面；本任务只拆可视化 body 的卡片边界。
- 自动 contract 锁定“每个 snapshot 产生一个 Section”并禁止回到“一个 Section 内 ForEach”；XCUITest 复用现有 `--uitesting-today-heatmap` fixture，新增稳定 card ID、相邻卡片不相交断言与脚本截图，不新增 fixture、不手动操作窗口。
- 参考 Apple 官方 SwiftUI `Section`、`List.insetGrouped` 与 HIG Lists and tables：<https://developer.apple.com/documentation/swiftui/section>、<https://developer.apple.com/documentation/swiftui/liststyle/insetgrouped>、<https://developer.apple.com/design/human-interface-guidelines/lists-and-tables>。
- 库：原生 SwiftUI `List`/`Section`、既有 Swift Charts、现有 `appCard` 与 XCTest/XCUITest 已覆盖需求；没有理由新增第三方依赖。
