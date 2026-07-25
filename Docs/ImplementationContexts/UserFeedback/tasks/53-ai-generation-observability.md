# 53:AI 生成任务界面可观测性(token 进度 + CoT/原始输出)实现记忆

> 本文件只用于主代理与子代理的实现、验证和编排记忆,不是任务来源。唯一范围与状态必须重新读取
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 条目。

## 当前阶段

- [x] 领取"生成任务展示模型目前输出了多少token,让用户知道是否卡死"与"AI生成任务界面可以查看CoT和原始输出"两条反馈(同一生成界面,合并为一个任务)。
- [x] 审计生成链路(UI → coordinator → LLMTaskPlanService → transport)与响应模型,确定流式进度与 CoT 捕获方案。
- [x] 实现流式 token 进度 + CoT/原始输出查看 + 行为测试。
- [~] 模拟器截图验收,`make test` 全绿。
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

### 设计(Checkpoint B 结论)

审计发现:transport 已用 `session.bytes`(AsyncBytes)逐字节读,SSE 只是消费方式变化;全仓库无 SSE 解析器,需自写(安全边界内,不引第三方 OpenAI 客户端);`content` 契约只含 JSON,CoT 走 provider 独立字段 `reasoning_content`;现有 `Transport` 闭包注入点保持不动,并列新增 `streamTransport` 即可全兼容。

方案:

1. **SSE 解析器** `Services/LLM/LLMServerSentEventParser.swift`:增量喂字节,按 `\n\n` 分帧,`data: ` 前缀,`[DONE]` 哨兵,跨块 UTF-8 安全(字节级缓冲,整帧解码)。纯函数可测。
2. **流式模型** `Services/LLM/LLMStreamModels.swift`:`OpenAIChatCompletionStreamChunk`(choices[].delta.{content?, reasoning_content?} + 尾块可选 usage);`stream`/`stream_options.include_usage` 加入 `OpenAIChatCompletionRequest`(可选字段,nil 不编码,非流式请求字节不变);非流式 `Message` 加可选 `reasoning_content`(Codable 容忍,旧 fixture 不破)。
3. **流式 transport** `LLMSecureHTTPTransport+Streaming.swift`:复用 ephemeral config/redirect/状态码/字节上限同一套校验;流式会话 `timeoutIntervalForResource` 提至 300s(长 CoT 生成),request idle 60s;累积总量仍受 2 MiB 上限。
4. **服务** `LLMTaskPlanService`:新增 `streamTransport: StreamingTransport?`(默认实现=真 SSE;测试注入假流),`generate` 优先走流式,累积 content/reasoning,`onProgress` 回报(内容字符数/估算 token/精确 usage);流结束仍走现有 content→payload 校验链,任何流错误回退非流式?——不,流失败直接报错(用户可重试),避免双重扣费/双倍等待。非流式路径同样捕获 `reasoning_content`。
5. **UI** `AITaskPlanGeneratorViews`:生成中 Section 显示"已输出约 N tokens"(generationRequestID 防过期);预览新增两个 DisclosureGroup:"思考过程"(MarkdownView,复用仓库既有依赖)与"原始输出"(等宽可选文本)。draft 携带非持久化的 reasoning/rawContent 字段。
6. **本地化**:新增 key 三语言同步(parity gate)。
7. **文档**:Architecture/PrivacyAndSecurity/Testing 同步流式与超时语义。

不需要新库(SSE 解析为 ~80 行纯函数;MarkdownView 复用既有依赖)。
