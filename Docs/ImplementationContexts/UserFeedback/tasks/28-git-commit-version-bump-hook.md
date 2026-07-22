# 28：每次 Git commit 自动递增版本实现记忆

> 本文件只用于主代理与子代理的实现、验证和编排记忆，不是任务来源。唯一范围与状态必须重新读取
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 条目。

## 当前阶段

- [~] 领取反馈，审计现有 hook、版本字段、安装包版本展示与失效根因。
- [ ] 确定不会递归提交、不会丢失用户变更且能在每个成功 commit 中生效的版本递增契约。
- [ ] 实现 hook 与自动化回归，在隔离仓库中证明连续 commit 连续递增。
- [ ] 精确执行 `CONFIGURATION=Release scripts/build_install_all.sh`，标记反馈完成并移除活动链接。

## 唯一反馈边界

- 每次 `git commit` 都必须自动递增 App 版本，让测试包能直接辨认具体构建版本，不能只依赖 commit hash。
- 不领取 Live Activity、主页统计图、Apple Health 或后续任何反馈。

## 强制约束

- 先审计仓库已有 hook 安装机制、版本源与 Xcode build settings；不建立第二套互相竞争的版本系统。
- hook 必须适用于普通提交与本代理的小 checkpoint，不得形成递归 commit，不得暂存或改写无关用户文件。
- 验证必须在隔离的临时 Git 仓库/工作树完成，不污染真实历史；验证后删除全部临时资源。
- 每个小 checkpoint 验证后提交；只暂存本任务状态差异，保护 `Docs/userfeedback.md` 中其他用户新增内容。

## Checkpoint 编排

- [~] Checkpoint A：现有 hook、安装入口、版本字段与失败模式审计。
- [ ] Checkpoint B：修复实现与隔离连续提交回归。
- [ ] Checkpoint C：Release 全设备安装、版本只读核验与收口。
