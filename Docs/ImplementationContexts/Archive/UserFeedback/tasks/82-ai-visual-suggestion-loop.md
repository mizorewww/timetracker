# 82：AI 视觉推荐打断输入与重复预测实现记忆

Status: Complete

状态：2026-07-28 完成

> 本文件是主代理与子代理的实现、验证和编排记忆；唯一任务来源仍是
> [`Docs/userfeedback.md`](../../../../userfeedback.md) 中对应的 `[~]` 条目。

## 认领的反馈条目

- 编辑任务时，AI 自动推荐图标/视觉属性不能打断正在进行的文本输入。
- 用户每次继续输入不能触发无界、重复或彼此追赶的预测请求。

## 初始范围

- 审计任务新建、编辑、详情与恢复路径中 AI visual suggestion 的触发条件、异步任务
  生命周期、草稿写回、焦点变化、去重和取消机制。
- 区分用户手动选择与 AI 自动建议，防止过期响应覆盖用户的新输入或显式选择。
- durable write 继续通过既有 command/session 边界；View 不直接写 repository。
- 优先使用 Swift Concurrency 的取消、去抖与稳定输入快照，不引入额外状态/网络库。

## 预期行为与 UI 验收清单（改动前）

- [x] 正常连续输入任务标题时，键盘/输入焦点不丢失，插入点不跳动。
- [x] 一次连续编辑只对稳定后的最新有效输入发起必要预测；旧任务可取消或其结果被丢弃。
- [x] 同一输入和同一预测结果不会形成属性写回 → 再预测的闭环。
- [x] 过期响应不能覆盖更新后的标题，也不能覆盖用户手动选择的图标/颜色。
- [x] 新建、编辑、详情与恢复草稿路径遵守相同语义；保存后 fresh reload 正确。
- [x] 正常字号下在受影响平台完成 XCTest/XCUITest 与截图验收。

## 测试优先清单

- [x] 先补服务/session 边界测试，复现连续编辑触发重复预测与过期响应写回。
- [x] 先补 UI 自动化或确定性焦点测试，证明预测完成时文本输入仍连续。
- [x] 实现后复跑定向行为测试和 iPhone UI 验收并保留截图；macOS 编译并明确跳过软件键盘专属断言。
- [x] 完整测试及格式/本地化门禁通过。
- [x] Release 全设备安装通过。

## Checkpoint 编排

- [x] A：完成调用链、焦点、副作用循环、测试与依赖审计。
- [x] B：新增先失败的行为/交互回归测试。
- [x] C：实现最新输入获胜、取消/去抖、去重及手动选择保护。
- [x] D：完成定向、全量、截图、Release 全设备安装与关闭。

## 库策略

- 先核实现有 Swift Concurrency 与网络客户端能力。若原生取消、`Task` 与 `Clock`
  已足够，不新增依赖；只有出现明确能力缺口时才评估活跃、维护良好且通常不少于
  1k stars 的成熟库，并记录版本、维护状态和替代方案。

## 子代理编排

- 主代理负责范围、活动记忆、测试优先、集成、模拟器/设备批次、提交与收口。
- 子代理并行进行 AI 状态/异步调用链、行为测试边界及 SwiftUI/HIG 焦点交互只读审计；
  结论汇总回本文件，避免同时修改主代理正在处理的文件。

## 进度记录

- 2026-07-28：按反馈顺序认领任务并建立 `~82` 活动实现记忆，进入 Checkpoint A。
- 2026-07-28：三路只读审计确认根因组合：task-detail autosave 无变化也旋转
  checklist/visual revision；失效请求没有按最新输入 identity 取消；请求指纹遗漏
  task title/path；visual-only store refresh 用整份 draft 替换或造成下一次 autosave
  的伪 CAS conflict，从而清空焦点并触发重试闭环。
- 2026-07-28：先补红测，再实现 350 ms trailing debounce、pending/in-flight
  统一并发槽、完整 scheduling fingerprint 和 latest identity 重验；无变化 checklist
  save/visual write 变为 no-op。
- 2026-07-28：`TaskEditorSession` 按 persisted checklist ID 做 visual-only 三方
  rebase，保留 visible row UUID、文本、顺序、dirty state 与焦点；本地手动 visual
  胜过 AI，并推进 baseline 使后续 autosave 可成功。
- 2026-07-28：定向行为测试通过：
  `LLMSuggestionCancellationTests` 11/11、
  `StoreScopedTaskDraftCommandCoordinatorTests` 10/10、
  `TaskEditorSessionTests` 25/25。
- 2026-07-28：iPhone 正常字号 XCUITest 通过；首个 AI 结果落下后没有重新点击
  输入框即可继续输入，键盘保持可见，最终只接受最新文本的 Dark green 视觉。
  结果包：`build/UITestResults/iOS-20260728-011306.xcresult`；目检截图：
  `build/UITestResults/iOS-20260728-011306-attachments/D7C17149-9F77-4903-9BAF-7D3F11962CA1.png`。
- 2026-07-28：未新增第三方依赖。采用 Apple 原生 Swift Concurrency
  `Task` 取消/`Task.sleep` 与 SwiftUI `FocusState`，并复用既有 store-scoped
  command、LLM transport 和 symbol/color picker。
- 2026-07-28：补充 `CoreCommandHandlerTests` 契约，确认无变化 visual save
  保留原 `clientMutationID`、`updatedAt` 与远端 writer；定向套件 17/17 通过。
- 2026-07-28：完整 `make test` 通过（1447 tests / 162 suites，52.505 秒）；
  `make format-check` 为 0/842，localization parity 为 9/9，hooks 与
  `git diff --check` 均通过。等待实现 checkpoint 提交与 `make build-install-all`。
- 2026-07-28：实现 checkpoint `3218876a`（`1.1.289 (344)`）完成；
  `make build-install-all` Release 构建、签名并安装到 iPad Pro M4、
  iPhone Air（含嵌入式 Watch companion）及 `/Applications/timetracker.app`。
  当前没有可见的独立物理 Apple Watch，因此 companion 的独立设备覆盖仍按项目
  既有规则依赖配对 iPhone 的 Automatic App Install。
