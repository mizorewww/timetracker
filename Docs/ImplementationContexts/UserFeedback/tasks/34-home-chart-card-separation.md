# 34：首页 Heatmap 与柱状图卡片拆分实现记忆

> 本文件只用于主代理与子代理的实现、验证和编排记忆，不是任务来源。唯一范围与状态必须重新读取
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 条目。

## 当前阶段

- [x] 领取“首页不要把 heatmap 和柱状图混在一起，每个元素单独做卡片”的反馈。
- [~] 审计首页 Heatmap、柱状图、说明文字和共享卡片容器的当前层级。
- [ ] 复用现有首页组件完成最小拆分，补齐 Core/UI contract/XCUITest 与截图验收。
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

- [~] Checkpoint A：范围领取、当前视图层级审计与自动化验收设计。
- [ ] Checkpoint B：最小实现、聚焦测试与脚本截图验收。
- [ ] Checkpoint C：Release 全设备安装、签名/版本只读核验与收口。

## 资源所有权

- 暂未创建 simulator、xcresult 或本任务 DerivedData；创建后必须记录 UDID/路径并在 checkpoint 结束时释放。
