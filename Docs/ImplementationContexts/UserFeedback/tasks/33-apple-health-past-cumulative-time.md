# 33：Apple Health 过去累计时间与时间段实现记忆

> 本文件只用于主代理与子代理的实现、验证和编排记忆，不是任务来源。唯一范围与状态必须重新读取
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 条目。

## 当前阶段

- [x] 领取“Apple Health 任务似乎无法查看过去累积时间和过去时间段”的反馈。
- [~] 对照上一项历史分析实现，以脚本化测试复现真实剩余缺口。
- [ ] 审计数据查询范围、累计口径、详情/统计入口与刷新生命周期。
- [ ] 实现最小修复并补齐 Core/UI contract/XCUITest。
- [ ] 提交实现 checkpoint，执行 `CONFIGURATION=Release scripts/build_install_all.sh`，标记反馈完成并移除活动链接。

## 唯一反馈边界

- Apple Health 固定任务应能查看过去累计时间，以及用户选择的过去时间段。
- 不领取后续首页卡片、category 展开或其他反馈。

## 强制约束

- 完整遵循仓库本地 `apple-hig` 与 `swiftui-expert-skill`；UI 调试、导航、断言与截图全部使用 XCTest/XCUITest 脚本。
- 不手动操作调试窗口；物理设备只做最终 Release 安装和只读版本/签名核验，不启动、点击或截图。
- 优先复用现有历史分析服务和系统框架；若评估第三方库，必须核验维护质量与 GitHub stars，除用户建议外不采用少于 1k stars 的库。
- 每个 checkpoint 只暂存本任务变更，保护 `Docs/userfeedback.md` 中其余用户新增内容。

## Checkpoint 编排

- [~] Checkpoint A：范围领取、上一实现差距审计与自动化复现设计。
- [ ] Checkpoint B：最小实现、聚焦测试与脚本截图验收。
- [ ] Checkpoint C：Release 全设备安装、签名/版本只读核验与收口。

## 初始假设

- 上一项已加入 Week/Month 历史时间线与累计 summary，但新反馈说明真实普通路径可能仍受默认范围、入口可发现性、刷新时机或查询截止时间影响。
- 必须先复现，不以“已有相似代码”替代用户可见验收。

## 资源所有权

- 尚未创建本任务 simulator；任何创建的 UDID 必须记录于此并在批次结束后 shutdown/delete。
