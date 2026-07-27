# 67：Today 首行 Apple Health 时间标签重叠 实现记忆

状态：2026-07-27 已完成

> 本文件是主代理与子代理的实现、验证和编排记忆；唯一任务来源仍是
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 条目及其复用
> 普通任务显示方案的子注记。

## 认领的反馈条目

- Today Timeline 第一行是 Apple Health 记录时，时间标签会与时间图表重叠。
- Apple Health 与普通时间段应尽量共享显示与布局方案，避免两套布局继续漂移。

## 预期行为

- Apple Health 记录位于 Timeline 第一行或后续任意行时，时间文字、任务摘要和图表
  均不重叠、不裁切。
- 普通计时记录与 Apple Health 记录复用同一行几何与标签定位策略；只保留数据语义
  与可编辑性所必需的差异。
- iPhone、iPad 和 macOS 普通字号下保持现有 Timeline 密度、对齐与点击语义。

## UI 验收清单

- 专用 fixture 保证 Apple Health 是第一条可见 Timeline 记录，并断言时间标签与图表
  frame 不相交。
- 同屏普通记录维持同一列、相同 leading edge 和行间距。
- iPhone、macOS 截图以及 iPad 几何验收在普通字号下无重叠、截断或意外纵向空白。
- 非 Health 时间段的编辑入口不回归；Health 记录继续保持只读。
- 批次结束后关闭并删除 owned 模拟器，清理测试 runner 与临时构建产物。

## Checkpoint 编排

- [x] A：领取反馈并建立活动实现记忆。
- [x] B：审计 Timeline 普通/Health 行的 read model、布局分支、fixture 与 HIG 约束。
- [x] C：先补会失败的几何/行为测试，再实现共享布局并更新当前文档。
- [x] D：完成单测、三平台 XCUITest/截图、Release 全设备安装与收口。

## 子 Agent 分工

- 代码审计：定位首行 Health 专属布局与普通记录共享边界，提出最小修复。
- 设计审计：检查时间标签、图表、摘要的层级、对齐与第一行边界。
- 测试审计：寻找或补充稳定的 Health Timeline fixture、identifier 与三平台截图路径。

## 库策略

- 优先复用现有 SwiftUI Timeline 行、布局策略与 Health read model。
- 仅当成熟库提供不可替代能力时引入；本任务不为简单 frame/对齐计算增加依赖。

## 进度记录

- 2026-07-27：认领任务，创建实现记忆和 `~67` 活动链接，开始共享行布局审计。
- 2026-07-27：三路只读审计完成。代码审计确认图表 read model 已共享，漂移来自普通 `TimelineRow` 的响应式布局与 Health 专属刚性 row；设计审计要求两类记录共用 24 pt icon、compact/regular `ViewThatFits` 与相同列/inset；测试审计确定使用 Health-first 固定夹具与 chart/row/time/title/menu 探针。
- 2026-07-27：抽取 `TodayTimelineRecordContent`、presentation、duration 与 inset，共享普通/Health 时间、身份、来源和时长布局；Health 保留 counted duration 与只读 wrapper，普通记录保留 live/fixed duration 和菜单。未新增第三方依赖。
- 2026-07-27：最终 Health-first XCUITest 在 iPhone、11″ iPad Pro 和 macOS
  通过。iPhone 精确验证时间/标题列对齐并留存截图
  `build/UITestResults/iOS-20260727-145309.xcresult`；macOS 验证共享整行几何、
  来源与只读语义并留存截图
  `build/UITestResults/macOS-20260727-145611.xcresult`；iPad 在
  `build/UITestResults/iOS-20260727-144046.xcresult` 验证图表/首行/相邻行不相交。
  iPadOS 27 beta 的 AX 叶节点滚动坐标与截图服务不稳定，因此 iPad 使用稳定的整行
  几何断言，截图证据由 iPhone/macOS 承担。
- 2026-07-27：`make format-check`、`make localization-check`、Apple Health Timeline
  定向单测 30 项及 `make test` 全量 1419 项均通过。
- 2026-07-27：实现与验证以 `bc65c439`（`Unify Today timeline record rows`）
  提交；版本钩子推进到 1.1.234 (289)。`make build-install-all` Release 全设备
  安装通过：iPad Pro M4、iPhone Air、内嵌 Watch companion 均构建/安装成功，
  macOS app 已复制到 `/Applications/timetracker.app` 并通过签名验证。反馈与子
  Note 标记 `[x]`，移除 `~67` 活动链接。
