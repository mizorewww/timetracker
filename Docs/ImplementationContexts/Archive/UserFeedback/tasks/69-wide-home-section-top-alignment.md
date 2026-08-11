# 69：宽屏主页区块起始高度一致 实现记忆

Status: Complete

状态：2026-07-27 已完成

> 本文件是主代理与子代理的实现、验证和编排记忆；唯一任务来源仍是
> [`Docs/userfeedback.md`](../../../../userfeedback.md) 中对应的 `[~]` 条目。

## 认领的反馈条目

- 在宽度较宽的设备上，主页“现在”和“概览”两列的内容开始高度不一致。

## 预期行为

- iPad 与 macOS 宽屏主页中，“现在”和“概览”使用一致的顶部布局基准。
- 标题、卡片内容与已有平台间距遵循 Apple HIG；普通字号下不出现人为占位或多余留白。
- iPhone 紧凑单列主页不改变，宽屏内各区块的内容与交互不回归。

## UI 验收清单

- 使用确定性 UI fixture 在 iPad 与 macOS 宽屏窗口断言两列起始几何关系。
- 普通字号截图人工检查标题层级、顶部间距与两列视觉基准。
- iPhone 紧凑主页回归通过。
- 相关布局单测、XCUITest 与全量 `make test` 通过。
- Release 全设备安装完成，owned 模拟器与 runner 全部释放。

## Checkpoint 编排

- [x] A：领取反馈并建立活动实现记忆。
- [x] B：并行审计宽屏主页组合、间距来源与稳定 UI 测试探针。
- [x] C：先补失败的几何测试，再实现最小共享布局修复并更新文档。
- [x] D：完成格式、单测、iPad/macOS XCUITest/截图、紧凑回归、Release 全设备安装与收口。

## 子 Agent 分工

- 代码审计：定位宽屏主页“现在”与“概览”的容器层级、条件分支和顶部间距来源。
- 设计审计：依据 Apple HIG 与现有设计语言确定应对齐的视觉基准及平台间距边界。
- 测试审计：寻找可复用主页 fixture、稳定 identifier 与 iPad/macOS 几何断言。

## 库策略

- 优先复用现有 SwiftUI adaptive layout、主页 section 容器与测试 fixture。
- 先确认成熟布局库是否提供不可替代价值；不为简单的顶部对齐增加依赖。

## 进度记录

- 2026-07-27：认领任务，创建实现记忆和 `~69` 活动链接。
- 2026-07-27：代码、设计与测试子 Agent 独立审计一致定位到 header slot 不同：Overview 的 Info 按钮把标题行撑到平台最小点击高度，而 Now 仅有自然 headline 高度。
- 2026-07-27：先用确定性 fixture 获得 macOS 失败证据：Now/Overview 可见标题顶部分别为 110/116 pt；旧测试错误地比较标题与外层 group，12 pt 容差会假绿。
- 2026-07-27：card `HomeSectionHeader` 统一复用 `AppLayout.minimumInteractiveTarget`，宽屏 Now 改用同一 header；`.listSection` 与 iPhone 紧凑组合不变。没有增加透明按钮、偏移、设备分支或第三方库。
- 2026-07-27：macOS 与 iPad Pro 13″ M4 横屏几何测试均以标题叶子探针在 2 pt 容差内通过；普通字号截图确认标题、首卡顶部、双栏间距和 Info 按钮正常。最终严格证据为 `macOS-20260727-160325.xcresult` 与 `iOS-20260727-160541.xcresult`；一次因错误 Make 变量而落到 iPhone 并跳过的运行不计作验收。
- 2026-07-27：默认 iPhone 的 `AdaptiveShellUITests/testNowSectionRendersInWhicheverShellIsChosen` 通过，确认紧凑单列 Now 未回归；结果为 `iOS-20260727-160737.xcresult`。
- 2026-07-27：SwiftFormat 830 个文件零改动/零 lint，本地化 9/9、版本钩子检查通过；signed macOS 全量 `make test` 共 1419 个测试通过。
- 2026-07-27：Release 1.1.240 (295) 全设备门禁通过；iOS app 与内嵌 Watch 伴侣签名有效并安装到 iPad Pro M4 `748D0137-ADC3-58AF-855C-1E98B3125F93`、iPhone Air `FBA36694-D841-56D4-8ED6-21942873B21B`，macOS 通用 app 签名有效并复制到 `/Applications/timetracker.app`。当前无可见物理 Apple Watch，故实表仅依赖配对 iPhone 的自动安装。
