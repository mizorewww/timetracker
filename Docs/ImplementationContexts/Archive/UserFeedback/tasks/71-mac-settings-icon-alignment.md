# 71：macOS 设置图标对齐与尺寸 实现记忆

Status: Complete

状态：2026-07-27 已完成

> 本文件是主代理与子代理的实现、验证和编排记忆；唯一任务来源仍是
> [`Docs/userfeedback.md`](../../../../userfeedback.md) 中对应的 `[~]` 条目。

## 认领的反馈条目

- macOS 设置页图标没有居中，尺寸也不合适。

## 预期行为

- macOS Settings 的类别图标在自己的视觉容器内水平、垂直居中。
- 图标、容器和行高遵循 macOS Settings 的信息密度与 Apple HIG，不照搬 iOS 的 44 pt 触控尺寸，也不因不同 SF Symbol 的固有包络而跳动。
- iOS/iPadOS 设置页不发生意外回归；可访问性标识和导航行为保持不变。

## UI 验收清单

- 先用确定性 Settings fixture 截图记录当前顶部对齐与过大彩色图标。
- 普通字号检查至少一个窄符号和一个宽符号，共享相同中心与视觉槽位。
- macOS 截图检查类别列表、选中态、行距和图标光学尺寸。
- SwiftFormat、相关 XCUITest、默认 `make test` 和 Release 全设备安装通过。
- 释放所有 owned runner、窗口与临时构建资源。

## Checkpoint 编排

- [x] A：领取反馈、建立活动实现记忆并审计 Settings 图标 owner。
- [x] B：确定原生 macOS 图标槽位规则，补充先失败的尺寸策略测试。
- [x] C：实现最小平台布局修复并更新设计文档。
- [x] D：完成格式、macOS 截图、跨平台回归、全量测试、Release 全设备安装与收口。

## 库策略

- 优先使用 SF Symbols、SwiftUI 原生 frame/alignment 与现有 Settings row 组件。
- 图标居中和 sizing 不应引入第三方 UI 库；只有原生组件无法表达关键行为时再评估成熟依赖。
- Apple 的 `sidebarRowSize` 环境值是系统偏好的原生入口，无需引入新依赖。

## 进度记录

- 2026-07-27：认领任务并建立 `~71` 活动实现记忆。
- 2026-07-27：基线 `macOS-20260727-165057.xcresult` 通过并保留截图；截图确认原 18 pt/28 pt 彩色图标按双行文本块顶部对齐。
- 2026-07-27：三路只读审计一致定位 `HStack(alignment: .top)` 与跨平台固定尺寸；Apple HIG/官方 SwiftUI 文档确认 macOS 侧栏必须响应 small/medium/large `sidebarRowSize`。
- 2026-07-27：尺寸策略测试先因缺少 `SettingsSidebarIconMetrics` 编译失败，随后覆盖 small 12/18/6、medium 14/20/8、large 16/24/10 并通过。
- 2026-07-27：macOS 分类行改为系统偏好驱动的单色 SF Symbol 稳定槽位，与完整标题/副标题块居中；iOS/iPadOS 分支保持原样。`macOS-20260727-170230.xcresult` 通过，截图确认窄/宽/复合符号同列且选中态清晰。
- 2026-07-27：一次中间方案把 15/22 固定值锁死，审计指出它不响应 Sidebar Icon Size 后即撤回；随后清理了该方案造成的精确 DerivedData stale ABI 构建产物。
- 2026-07-27：`make format` 与 `make format-check` 通过（831 个 Swift 文件无改动）；iPhone 17 Pro `iOS-20260727-170407.xcresult` 与 iPad Pro 13-inch M4 `iOS-20260727-170709.xcresult` 的 Settings 导航回归通过，临时模拟器均由 Makefile 删除。
- 2026-07-27：默认 `make test` 通过，1420 tests / 158 suites，0 failures。
- 2026-07-27：实现 checkpoint `c9af4e8c`（`Align mac settings category icons`）将版本推进到 1.1.246 (301)。
- 2026-07-27：`make build-install-all` 的 Release 构建、签名与安装通过；1.1.246 (301) 已安装到 iPad Pro M4 `748D0137-ADC3-58AF-855C-1E98B3125F93`、iPhone Air `FBA36694-D841-56D4-8ED6-21942873B21B`，嵌入 Watch app 验签通过，macOS app 已复制并验签到 `/Applications/timetracker.app`。没有可见物理 Apple Watch，伴生 app 将由已配对 iPhone 的 Automatic App Install 管理。
- 2026-07-27：任务完成，反馈标为 `[x]`，活动链接已移除；Release 构建资源随后按工作流清理。
