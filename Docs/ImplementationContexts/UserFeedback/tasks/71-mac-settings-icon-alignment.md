# 71：macOS 设置图标对齐与尺寸 实现记忆

状态：2026-07-27 进行中

> 本文件是主代理与子代理的实现、验证和编排记忆；唯一任务来源仍是
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 条目。

## 认领的反馈条目

- macOS 设置页图标没有居中，尺寸也不合适。

## 预期行为

- macOS Settings 的类别图标在自己的视觉容器内水平、垂直居中。
- 图标、容器和行高遵循 macOS Settings 的信息密度与 Apple HIG，不照搬 iOS 的 44 pt 触控尺寸，也不因不同 SF Symbol 的固有包络而跳动。
- iOS/iPadOS 设置页不发生意外回归；可访问性标识和导航行为保持不变。

## UI 验收清单

- 先用确定性 Settings fixture 和真实 frame 记录当前失败。
- 普通字号检查至少一个窄符号和一个宽符号，共享相同中心与视觉槽位。
- macOS 截图检查类别列表、选中态、行距和图标光学尺寸。
- SwiftFormat、相关 XCUITest、默认 `make test` 和 Release 全设备安装通过。
- 释放所有 owned runner、窗口与临时构建资源。

## Checkpoint 编排

- [~] A：领取反馈、建立活动实现记忆并审计 Settings 图标 owner。
- [ ] B：确定原生 macOS 图标槽位规则，补充失败的几何测试。
- [ ] C：实现最小共享/平台布局修复并更新设计文档。
- [ ] D：完成格式、macOS 截图、跨平台回归、全量测试、Release 全设备安装与收口。

## 库策略

- 优先使用 SF Symbols、SwiftUI 原生 frame/alignment 与现有 Settings row 组件。
- 图标居中和 sizing 不应引入第三方 UI 库；只有原生组件无法表达关键行为时再评估成熟依赖。

## 进度记录

- 2026-07-27：认领任务并建立 `~71` 活动实现记忆。
