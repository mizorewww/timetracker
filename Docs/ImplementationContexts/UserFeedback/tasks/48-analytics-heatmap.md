# 48：分析页面加入 heatmap 实现记忆

> 本文件只用于主代理与子代理的实现、验证和编排记忆，不是任务来源。唯一范围与状态必须重新读取
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 条目。

## 当前阶段

- [x] 领取“heatmap 在分析页面也放一份”反馈。
- [~] 审计主页 heatmap 组件(HomeActivityHeatmapSection)与分析页面结构,确定复用路径。
- [ ] 确定放置位置与语义(与分析页 Day/Week/Month 的关系、用同一批追踪任务)。
- [ ] 实现并运行聚焦测试与 iPhone/iPad/macOS 模拟器截图验收。
- [ ] 执行 `CONFIGURATION=Release scripts/build_install_all.sh`(实体机安装失败不阻塞),标记完成并移除活动链接。

## 唯一反馈边界

- 在 Analytics 界面放置与主页一致的 task heatmap(复用组件与数据链)。
- 不领取 checklist 复用、主页滑动卡顿或其他反馈。
- 以普通文字大小、正常交互路径、三平台系统约定为优先。

## 强制约束

- 完整遵循仓库本地 `apple-hig` 与 `swiftui-expert-skill`;所有 UI 导航、断言与截图只用 XCTest/XCUITest 脚本。
- 实体机器不做测试;模拟器验收后 shutdown+delete 并清理 /tmp 产物。
- 优先复用 HomeActivityHeatmapSection 与其快照数据链;除用户建议外不引入 GitHub 少于 1k stars 的库。
- 每个 checkpoint 只暂存本任务的已完成变更;保留用户在反馈文件中的其他内容。

## Checkpoint 编排

- [x] Checkpoint A：领取任务、创建实现记忆与 active link。
- [ ] Checkpoint B：审计组件复用与分析页结构。
- [ ] Checkpoint C：实现并补齐聚焦测试。
- [ ] Checkpoint D：三平台模拟器验收与资源清理。
- [ ] Checkpoint E：Release 构建安装、核验与收口。

## 资源所有权

- [~] 主代理：任务状态、编排、集成、所有 build/simulator/XCUITest/screenshot/Release 批次与清理。
- [ ] 待分配：heatmap 组件与分析页审计。

## 已提交 checkpoint

- [~] 待提交：领取任务、实现记忆与 active link。
