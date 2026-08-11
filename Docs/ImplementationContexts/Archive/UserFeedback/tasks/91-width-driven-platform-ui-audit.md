# 91：按宽度收敛平台 UI 实现记忆

Status: Complete

状态：2026-07-28 已完成

> 本文件是主代理与子代理的实现、验证和编排记忆；唯一任务来源仍是
> [`Docs/userfeedback.md`](../../../../userfeedback.md) 中对应的 `[~]` 条目。

## 认领范围

- 全量审计 App SwiftUI 中按 iOS/iPadOS/macOS 或设备 idiom 分叉的 UI。
- 能由可用宽度、系统容器和 capability 决定的布局，改为共享的宽度驱动策略。
- 保留真正依赖 AppKit/UIKit、系统 scene、菜单、Watch 或平台框架的必要条件编译。
- 把保留/删除理由、共享布局契约和后续新增分支规则写入当前工程文档。

## 验收条件

- [x] 形成逐项可追踪的 UI 平台分支清单，区分删除、共享、保留及理由。
- [x] iPhone 风格由实际可用宽度决定，不读取设备型号/屏幕宽度，也不因窗口折叠丢失导航状态。
- [x] 删除能被共享 SwiftUI/宽度策略替代的平台分支，保留分支只封装真实平台能力。
- [x] 先建立布局策略/行为测试，再修改 root 与受影响 UI；普通字号设备矩阵与截图通过。
- [x] `make test`、格式、本地化门禁通过，实现提交后完成 `make build-install-all`。

## 子代理编排

- 子代理 A：只读枚举生产 SwiftUI 的条件编译、设备 idiom 与屏幕宽度判断，给出逐项裁决候选。
- 子代理 B：只读梳理 root navigation、compact/regular 布局策略与现有行为/UI 测试缺口。
- 子代理 C：只读复核真正需要平台 API 的边界和 Apple HIG/SwiftUI 约束，提出最小设备截图矩阵。
- 主代理：范围裁决、测试先行、分层实现、文档、截图、提交、设备安装与关闭。

## 设计约束

- Apple HIG：以窗口可用空间和系统导航容器为主，不把设备型号当作布局；保留各平台标准
  scene、菜单、工具栏和输入行为。
- SwiftUI skill：共享状态与 route 必须位于布局分支之上；布局切换不得重建业务 store、
  丢失 selection 或复制持久化。
- 优先使用 SwiftUI 自带的 `NavigationSplitView`、size class、容器测量和
  `ViewThatFits`；没有第二调用者不新增抽象或第三方布局依赖。

## 进度记录

- 2026-07-28：认领任务，建立活动实现记忆；下一步仅审计生产 UI 分支与对应测试。
- 2026-07-28：三个只读子代理完成分支清单、根布局/测试缺口和 capability
  边界复核。确认生产代码没有 `UIDevice`、`UIScreen` 或设备 idiom 布局读取；需要
  修改的重复布局集中在 root 状态所有权、图表 size class、feature 内重复 shell
  判断和跨平台字体映射。
- 2026-07-28：先让 Today route 行为测试因缺少 store-owned route 编译失败，再把
  Today task route、当前根目的地和 scene router 保持在 compact/regular 分支之上。
  `CoreTasksRouteTests` 11/11、`CoreArchitectureBehaviorTests` 4/4 通过。
- 2026-07-28：删除同一信息角色的跨平台字体条件分支；Timeline、Inbox、
  Pomodoro、Home rows 和 Task category 改为只消费根发布的 `layoutShell`；
  Daily time-series chart 改为测量自己的有限宽度。
- 2026-07-28：保留的条件编译仅限框架/API 不存在、macOS Settings/window/menu
  plumbing、系统 list/presentation chrome、输入方式与 HealthKit/Watch/ActivityKit
  capability。窄 Mac 的 focused scene 值上移到 root，并新增原生 Settings scene
  端到端回归。
- 2026-07-28：审计收口后，生产 App 中只有 `AppRootView` 读取系统 size class，
  没有 `UIDevice`、`userInterfaceIdiom`、`UIScreen.main` 或 `NSScreen.main`
  产品布局读取。删除项为重复平台字体、重复 compact 判断和平台化滚动指示器；
  共享项为 root shell、Today route、Timeline/Inbox/Pomodoro/Home/Task rows 与
  Daily time-series 容器测量；保留项为系统 scene/chrome、输入和框架 capability。
- 2026-07-28：本任务没有新增第三方依赖。继续使用 SwiftUI 自带的
  `NavigationSplitView`、`TabView`、环境值和 `onGeometryChange`；为单个布局判断
  引入第三方库会增加依赖与平台漂移，系统容器已经完整表达需求。
- 2026-07-28：验证通过：`make test` 176 suites / 1567 tests；`make format-check`
  0/875；9/9 本地化资源 parity；hooks 和 `git diff --check`。Adaptive shell：
  macOS 3/3、iPhone 2/2、iPad 2/2；普通字号截图矩阵：
  macOS/iPhone/iPad 各 7 张。主代理抽查代表性截图，子代理逐张复核 21/21，
  未发现文字重叠、意外裁切、控件碰撞或图表轴标签不清。
- 2026-07-28：实现提交 `b660e3b3` 后，`make build-install-all` 以 Release 和
  Automatic Signing 构建成功；iPad Pro M4、iPhone Air 安装成功，macOS 签名验证
  后复制到 `/Applications/timetracker.app`。Watch companion 已嵌入 iOS App；
  当前没有可见实体 Apple Watch，由配对 iPhone 的 Automatic App Install 接续。
- 2026-07-28：Task91 验收完成，反馈项改为 `[x]`，移除 active link。
