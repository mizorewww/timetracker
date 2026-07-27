# 76：macOS 全局字体可读性 实现记忆

状态：2026-07-27 实现中

> 本文件是主代理与子代理的实现、验证和编排记忆；唯一任务来源仍是
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 条目。

## 认领的反馈条目

- macOS App 各主要页面的文字整体偏小，需要在普通字号和日常窗口宽度下提升
  阅读、扫描与操作辨识度。

## 范围

- 先审计 macOS 主窗口的 Today、Inbox、Tasks、Focus、Analytics、Task Detail
  与 Settings，区分正文、导航、section/card 标题、指标、metadata、caption 和
  控件标签的真实语义 owner。
- 优先修复被错误降级为 caption/footnote 或硬编码小字号的共享组件，不把合法的
  辅助 metadata、图例或次级说明机械放大成正文。
- 保持 iPhone/iPad、Watch、Widget、Live Activity 的字号和布局不变；跨平台共享
  组件需要显式、可测试的平台展示策略。
- 不借此重做颜色、间距、信息架构或业务行为。

## UI 验收清单

- 保存正常字号、日常窗口尺寸下的 macOS 修改前后截图，至少覆盖 Today、Tasks、
  Analytics、Task Detail 与 Settings，并检查 Inbox/Focus 的共享组件。
- 核对正文与操作标签不低于平台默认 body 语义，section/card 标题保持明确层级；
  metadata 与 caption 只在确属辅助内容时使用。
- 长本地化文本、搜索、侧边栏、列表滚动、窗口缩放和主要导航仍可用；不通过固定
  point size、全局 environment 强制字号或逐页面 magic scale 实现。
- iPhone/iPad 的根导航与共享组件做定向回归。
- SwiftFormat、相关 XCUITest、默认 `make test` 与 Release
  `make build-install-all` 通过，并释放所有 owned 资源。

## Checkpoint 编排

- [ ] A：领取反馈、建立活动实现记忆并生成 macOS 主要页面字体清单。
- [ ] B：保存修改前截图，按 HIG 将问题收敛到明确的共享 owner。
- [ ] C：分小 checkpoint 实现、验证并更新工程文档。
- [ ] D：完成跨页面/跨平台 UI、全量测试、Release 全设备安装与收口。

## 库策略

- 优先使用 SwiftUI 动态系统文字样式、原生 control/list/sidebar 以及 SF Symbols，
  不引入全局字体缩放库或自建 typography framework。
- 参考 Apple HIG 的 Typography、Sidebars、Lists and Tables、Buttons、
  Text Fields 与 Settings 规则；只有成熟原生/现有组件无法满足明确行为时才评估
  维护活跃且一般不少于 1k stars 的第三方库。

## 子代理编排

- 主代理负责范围裁决、共享 typography owner、实现、构建/模拟器所有权和提交。
- 可并行的静态页面清单、HIG 复核与测试覆盖审计由子代理完成；所有结论回写本文件，
  子代理不得并发修改同一 Swift 文件。

## 进度记录

- 2026-07-27：认领任务并建立 `~76` 活动实现记忆。
