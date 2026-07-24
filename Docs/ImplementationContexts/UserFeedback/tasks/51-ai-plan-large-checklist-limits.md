# 51：AI 大计划忠实渲染与清单上限实现记忆

> 本文件只用于主代理与子代理的实现、验证和编排记忆，不是任务来源。唯一范围与状态必须重新读取
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 条目。

## 当前阶段

- [x] 领取“生成的计划含有过多分类/任务/清单项应忠实渲染;一个任务下生成150个checklist失败”反馈。
- [~] 审计计划数量上限(system contract 8分类/64任务/32清单每项/256总计)、验证失败路径与预览渲染截断。
- [ ] 确定新上限(支持 150+ 清单项)与忠实渲染方案(大计划预览不截断不卡死)。
- [ ] 实现并运行聚焦测试与模拟器截图验收。
- [ ] 执行 `CONFIGURATION=Release scripts/build_install_all.sh`(实体机安装失败不阻塞),标记完成并移除活动链接。

## 唯一反馈边界

- 大计划:上限调整 + 预览忠实渲染;150 清单项单任务必须可生成、可预览、可创建。
- 不领取 iCloud 冲突、token 显示或其他反馈。
- 以普通文字大小、正常交互路径、三平台系统约定为优先。

## 强制约束

- 完整遵循仓库本地 `apple-hig` 与 `swiftui-expert-skill`;所有 UI 导航、断言与截图只用 XCTest/XCUITest 脚本。
- 实体机器不做测试;模拟器验收后 shutdown+delete 并清理 /tmp 产物。
- 优先复用现有组件;除用户建议外不引入 GitHub 少于 1k stars 的库。
- 每个 checkpoint 只暂存本任务的已完成变更;保留用户在反馈文件中的其他内容。

## Checkpoint 编排

- [x] Checkpoint A：领取任务、创建实现记忆与 active link。
- [ ] Checkpoint B：审计上限与渲染路径。
- [ ] Checkpoint C：实现并补齐聚焦测试(含 150 清单项端到端)。
- [ ] Checkpoint D：三平台模拟器验收与资源清理。
- [ ] Checkpoint E：Release 构建安装、核验与收口。

## 资源所有权

- [~] 主代理：任务状态、编排、集成、所有 build/simulator/XCUITest/screenshot/Release 批次与清理。
- [ ] 待分配：上限与渲染审计。

## 已提交 checkpoint

- [~] 待提交：领取任务、实现记忆与 active link。
