# LLM 请求配置统一与建议生命周期泛型化

Status: in progress
Date: 2026-08-27

## Scope

Pure refactor; no observable behavior change.

- `LLMRequestConfiguration`（`timetracker/Services/LLM/LLMRequestConfiguration.swift`）取代
  `(endpoint, apiKey, modelID, reasoningEffort)` 四元组在 preferences → facade →
  `suggest()` → 私有 request builder 的透传；`validated()` 统一三个服务各自重复的
  trim / missingEndpoint / missingAPIKey / 字节上限 / endpoint 策略检查。
- `LLMSuggestionRequestLifecycle<ItemID, Failure>`（`timetracker/Stores/Facade/LLMSuggestionRequestLifecycle.swift`）
  承载 Inbox 建议与 Checklist 视觉建议共享的请求状态机：并发上限、in-flight 集合、
  requestID 时效检查、任务包装、pending FIFO、防抖、cancel 变体。两个 feature 只保留
  itemID 提取、service 调用与结果写回闭包。

## 行为差异（泛型化时如何容纳）

- Inbox 失败记录为面向 UI 的错误字符串（observed），Checklist 为
  `fingerprint + retryAfter` 退避（`ChecklistVisualSuggestionFailure` 值类型）→ 泛型参数 `Failure`。
- Inbox 用 pending FIFO 队列承载超限/冲突请求；Checklist 用 350 ms 逐项防抖且防抖占用并发槽
  → 生命周期同时提供 pending 与 debounce 两组原语，feature 各取所需。
- Checklist 有调度指纹协调（reconcile 取消被取代的请求）与 in-flight 元数据
  `schedulingFingerprintByItemID`；该状态保留在 store，cancel 时经 `onCancel` 闭包清理。
- 失败重试：Inbox 手动 `retryInboxSuggestion`；Checklist 60 秒自动退避。均保留在 feature 层。
- 观测性：视图读取 `store.inboxSuggestionInFlightIDs` 与失败字符串。生命周期类为
  `@Observable`，store 提供转发计算属性，Observation 跟踪经嵌套对象 registrar 保持等价。

## Test record

- `timetrackerTests/Core/CoreLLMResponseTransportTests.swift`：两处 `suggest(...)` 调用点随
  接口改为 `configuration:`。断言（oversized response 拒绝、状态优先级）未放宽。
  保护边界：LLM 响应大小上限的传输层契约，独立 oracle 为注入的 byte fixture。
  永久回归契约，非脚手架。
- 无新增测试；现有套件即行为契约。

## Verification

- `make format` / `make format-check`：干净（0/725 files require formatting）。
- `make test`（无 TEST_ONLY）：**TEST SUCCEEDED**，205 tests / 38 suites 全过，0 失败。
  最终 xcresult：`Test-timetracker-2026.08.27_16-45-13-+0800.xcresult`。
  中途两轮失败均为并行代理的 `Services/SystemIntegration/PathFileLock.swift`
  半成品（`Darwin.flock` 解析到 struct 而非函数），与本改动无关；对方修复后全绿。
- 资源清理：未创建模拟器；无遗留 xcodebuild/xctest 进程，无 Booted 设备。
