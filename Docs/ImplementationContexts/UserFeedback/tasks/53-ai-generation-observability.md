# 53:AI 生成任务界面可观测性(token 进度 + CoT/原始输出)实现记忆

> 本文件只用于主代理与子代理的实现、验证和编排记忆,不是任务来源。唯一范围与状态必须重新读取
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 条目。

## 当前阶段

- [x] 领取"生成任务展示模型目前输出了多少token,让用户知道是否卡死"与"AI生成任务界面可以查看CoT和原始输出"两条反馈(同一生成界面,合并为一个任务)。
- [~] 审计生成链路(UI → coordinator → LLMTaskPlanService → transport)与响应模型,确定流式进度与 CoT 捕获方案。
- [ ] 实现流式 token 进度 + CoT/原始输出查看 + 行为测试。
- [ ] 模拟器截图验收,`make test` 全绿。
- [ ] 执行 `CONFIGURATION=Release scripts/build_install_all.sh`(实体机安装失败不阻塞),标记完成并移除活动链接。

## 唯一反馈边界

- 仅处理:① 生成过程中展示已输出 token 量(用户可判断是否卡死);② 生成界面可查看 CoT(推理内容)和原始输出。
- 不领取其他反馈项;不改提示词内容(提示词不足是另一条反馈)。
- 安全边界不动:ephemeral session、2 MiB 上限、60s 超时、HTTPS/回环校验、redirect 策略。

## 强制约束

- 完整遵循仓库本地 `apple-hig` 与 `swiftui-expert-skill`;所有 UI 导航、断言与截图只用 XCTest/XCUITest 脚本。
- 实体机器不做测试;模拟器验收后 shutdown+delete 并清理 /tmp 产物。
- 优先复用现有组件;除用户建议外不引入 GitHub 少于 1k stars 的库;网络栈必须留在仓库自有安全传输边界内,不为流式引入第三方 OpenAI 客户端。
- 每个 checkpoint 只暂存本任务的已完成变更;保留用户在反馈文件中的其他内容。

## Checkpoint 编排

- [x] Checkpoint A:领取任务、创建实现记忆与 active link。
- [~] Checkpoint B:审计生成链路与响应契约。
- [ ] Checkpoint C:实现 + 补齐行为测试。
- [ ] Checkpoint D:模拟器验收与资源清理。
- [ ] Checkpoint E:Release 构建安装、核验与收口。

## 资源所有权

- [~] 主代理:任务状态、编排、集成、所有 build/simulator/测试/Release 批次与清理。
- [ ] 子代理(审计):生成链路调用点、预览 UI 结构、现有流式/进度基础设施盘点。

## 已提交 checkpoint

- [ ] 待提交:领取任务、实现记忆与 active link。

## 实现与验收记录

(待填)
