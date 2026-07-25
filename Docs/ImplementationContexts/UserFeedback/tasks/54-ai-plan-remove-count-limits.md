# 54:移除 AI 计划数量上限(超级大 JSON)实现记忆

> 本文件只用于主代理与子代理的实现、验证和编排记忆,不是任务来源。唯一范围与状态必须重新读取
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 条目。

## 当前阶段

- [x] 领取"依然没有解决AI给出超级大json的问题,不知道为什么要限制各个组件的长度.限制长度是一个很糟糕的设计"反馈。
- [~] 审计数量上限与响应字节上限的所有执行点与文档承诺,确定"字节上限保底、数量上限移除"方案。
- [ ] 实现上限移除 + 响应容量提升 + 行为测试。
- [ ] 模拟器截图验收,`make test` 全绿。
- [ ] 执行 `CONFIGURATION=Release scripts/build_install_all.sh`(实体机安装失败不阻塞),标记完成并移除活动链接。

## 唯一反馈边界

- 仅处理:AI 任务计划生成对分类/任务/清单数量的硬性拒绝(超级大 JSON 失败)。
- 保留:传输 2 MiB 安全上限(安全边界)、结构校验(引用/环/深度/字段合法性)、原子创建。
- 不领取其他反馈项;提示词质量问题是另一条独立反馈。

## 强制约束

- 完整遵循仓库本地 `apple-hig` 与 `swiftui-expert-skill`;所有 UI 导航、断言与截图只用 XCTest/XCUITest 脚本。
- 实体机器不做测试;模拟器验收后 shutdown+delete 并清理 /tmp 产物。
- 优先复用现有组件;除用户建议外不引入 GitHub 少于 1k stars 的库。
- 每个 checkpoint 只暂存本任务的已完成变更;保留用户在反馈文件中的其他内容。

## Checkpoint 编排

- [x] Checkpoint A:领取任务、创建实现记忆与 active link。
- [~] Checkpoint B:审计上限执行点与契约文本。
- [ ] Checkpoint C:实现 + 补齐行为测试。
- [ ] Checkpoint D:模拟器验收与资源清理。
- [ ] Checkpoint E:Release 构建安装、核验与收口。

## 资源所有权

- [~] 主代理:任务状态、编排、集成、所有 build/simulator/测试/Release 批次与清理。

## 已提交 checkpoint

- [ ] 待提交:领取任务、实现记忆与 active link。

## 实现与验收记录

(待填)
