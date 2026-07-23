# 38：可重复任务父级 Heatmap 实现记忆

> 本文件只用于主代理与子代理的实现、验证和编排记忆，不是任务来源。唯一范围与状态必须重新读取
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 条目。

## 当前阶段

- [x] 领取“可重复任务由子任务记录数量/时间、父任务显示 Heatmap”反馈并建立活动链接。
- [~] 审计任务量/可重复任务的父子模型、完成记录、Heatmap 聚合与三平台入口。
- [ ] 设计并实现最小修复，补齐单元测试与脚本化 UI 验收。
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
- [~] Checkpoint B：审计父子数据流、完成记录、Heatmap 投影、库与自动化基线。
- [ ] Checkpoint C：实现数据/聚合修复并完成聚焦验证。
- [ ] Checkpoint D：补齐三平台脚本化 UI 验收。
- [ ] Checkpoint E：Release 全设备安装、签名/版本核验与收口。

## 审计证据

- [~] 待填：任务模型、父子关系和重复任务生成路径。
- [ ] 待填：数量/时间记录与父级 Heatmap 当前断点。
- [ ] 待填：现有测试、可复用库与 HIG/SwiftUI 约束。

## 资源所有权

- [~] 主代理：任务状态、编排、集成、所有 build/TestManager/simulator/XCUITest/screenshot/Release 批次与清理。
- [~] 子代理只做只读静态审计；未经主代理另行记录不得编辑、构建、创建设备或操作窗口。

## 已提交 checkpoint

- [ ] 待提交：领取任务、建立实现记忆与 active link。
