# 34：首页 Heatmap 与柱状图卡片拆分实现记忆

> 本文件只用于主代理与子代理的实现、验证和编排记忆，不是任务来源。唯一范围与状态必须重新读取
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 条目。

## 当前阶段

- [x] 领取“首页不要把 heatmap 和柱状图混在一起，每个元素单独做卡片”的反馈。
- [x] 审计首页 Heatmap、柱状图、说明文字和共享卡片容器的当前层级。
- [x] 复用现有首页组件完成最小拆分，补齐 UI contract/XCUITest 与截图验收。
- [~] 提交已验证并完成资源清理的实现 checkpoint。
- [ ] 执行 `CONFIGURATION=Release scripts/build_install_all.sh`，标记反馈完成并移除活动链接。

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
- [x] Checkpoint B：最小实现、聚焦测试与脚本截图验收。
- [~] Checkpoint C：Release 全设备安装、签名/版本只读核验与收口。

## 资源所有权

- `task34_home_audit`、`task34_hig_audit` 与 `task34_test_audit` 仅做只读审计；未编辑、构建、测试、创建 simulator 或操作窗口。
- Checkpoint B 最终 contract 使用 `/tmp/timetracker-task34-contract-dd` 与 `/tmp/timetracker-task34-contract-final.xcresult`，7/7 通过；结束时必须删除并核验无 owned 测试进程。
- Checkpoint B 自有 iPhone 17 Pro simulator：`codex-task34-iPhone17Pro`，UDID `D9B2021C-54E1-4328-B79B-36F17F319B8B`。
- Checkpoint B 自有 iPad Pro 11-inch (M5) simulator：`codex-task34-iPadPro11`，UDID `A6AE3D7D-81D5-4AE0-9D74-4C045E69A386`。
- UI 批次结果、DerivedData 与截图均使用 `/tmp/timetracker-task34-*`；批次结束时必须终止 app/runner、关闭并删除上述设备、退出本批次打开的 Simulator/Problem Reporter，并删除临时产物。
- Checkpoint B 收尾已终止 app/runner、shutdown 并删除上述两个 owned simulator；`/tmp/timetracker-task34-*`、owned `xcodebuild`/`xctest`/extension/trace 进程、Booted device、Simulator/Problem Reporter UI 均复核为零。

## Checkpoint A 审计结论

- `PhoneHomeView` 与宽屏 `HomeViews` 已把周 Gross 柱状图和 Heatmap 作为相邻但独立的 section；两类图分别走 `BarMark` 与 `RectangleMark`，Store/快照数据链也完全独立，不能为本任务改 Charts 或数据层。
- 周柱状图在 iPhone 是只有一个 chart row 的独立原生 `Section`，宽屏柱图和每张 Heatmap 也已分别使用现有 `.appCard`，这些路径无需修改。
- 唯一视觉缺口在 iPhone `.insetGrouped`：当前一个 `Section` 内的 `ForEach(snapshots)` 会被系统绘制成一张连续分组背景，多张任务 Heatmap 因而像同一张卡。Apple 官方对 `insetGrouped` 的说明也明确其背景会从 section header 连续包住该 section 的所有 items。
- 最初假设是让每个稳定 `taskID` 对应的 Heatmap 各自产生一个原生 `Section`，但脚本截图证明这些 `Section` 嵌在自定义 `TimelineView` 后仍会被外层 `List` 绘成一张连续白色分组面；该假设已被验收否决，不能当作完成方案。
- 最终方案保持稳定的单一 `ForEach(snapshots)`，每个 snapshot 生成自己的 `Section`，仅第一项按稳定 `snapshot.id` 显示共享 header；可视化 body 使用共享 `homeVisualizationListCard` 形成真实 `.appCard`，外层 row/section 统一清空背景并隐藏 separator，从而避免共享外卡和嵌套系统卡片。
- 保留第 30 项已经验收的层级：统计图总标题和累计值在卡片外，详细说明继续位于 Info 二级面；本任务只拆可视化 body 的卡片边界。
- 自动 contract 锁定“每个 snapshot 产生一个 Section”并禁止回到“一个 Section 内 ForEach”；XCUITest 复用现有 `--uitesting-today-heatmap` fixture，新增稳定 card ID、相邻卡片不相交断言与脚本截图，不新增 fixture、不手动操作窗口。
- 参考 Apple 官方 SwiftUI `Section`、`List.insetGrouped` 与 HIG Lists and tables：<https://developer.apple.com/documentation/swiftui/section>、<https://developer.apple.com/documentation/swiftui/liststyle/insetgrouped>、<https://developer.apple.com/design/human-interface-guidelines/lists-and-tables>。
- 库：原生 SwiftUI `List`/`Section`、既有 Swift Charts、现有 `appCard` 与 XCTest/XCUITest 已覆盖需求；没有理由新增第三方依赖。

## Checkpoint B 实现与验收

- `HomeSectionContainer` 提供统一的 `homeVisualizationListCard` 与 `homeVisualizationListSection`：前者建立独立卡片边界和稳定自动化 ID，后者清除外层 List 连续背景与 separator。
- iPhone 周 Gross 柱状图使用 `home.weeklyGross.card`；每张 Heatmap 使用 `home.heatmap.card.<task UUID>`，标题 `home.weeklyGross.header` / `home.heatmaps.header` 保持在卡片外。
- Heatmap 的 `ForEach` 不再把首项拆成单独静态节点，删除首个任务时不会把前一任务的横向滚动状态迁移给下一任务。
- UI contract `/tmp/timetracker-task34-contract-final.xcresult`：7/7 通过，覆盖共享修饰器、透明外层 row、稳定迭代身份与卡片 ID。
- iPhone 聚焦卡片验收 `/tmp/timetracker-task34-iphone-card-acceptance.xcresult`：1/1 通过；脚本让柱图与前两张 Heatmap 边界同屏，断言 body 被各自卡片包含、卡片互不相交且间距不少于 8pt，并捕获 `iphone-home-visualization-card-separation`。
- iPad 聚焦验收 `/tmp/timetracker-task34-ipad-card-acceptance.xcresult`：1/1 通过；同一 XCUITest 脚本完成竖屏与横屏几何断言及截图。
- 旧完整 Heatmap 回归首次在独立卡片增加纵向间距后暴露 duration grid 仅“可点击”但未完全避开底部系统栏；测试补齐 `scrollUntilFullyVisibleAboveSystemChrome`，冷启动重跑 `/tmp/timetracker-task34-iphone-long-regression-retry.xcresult` 1/1 通过。
- 最终 iPhone、iPad 竖屏和 iPad 横屏截图均已视觉检查：灰色页面背景可见，每个可视化有独立白色圆角卡片和清晰间隔，没有共享外框。
- 复核代理提出的两项 P2（首项身份不稳定、测试未定位真实卡片边界）均已修复；复核代理只读且未占用 simulator。
- 新增库：无。实现仅复用 SwiftUI、Swift Charts、现有 `appCard` 与 XCTest/XCUITest。
