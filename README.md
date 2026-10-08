# Timetracker

本地优先的 Apple 平台时间账本。所有统计都从 canonical `TimeSegment` 派生,UI、预测、图表和汇总只是可重建的投影。

自用项目,单一维护者;仓库即事实来源(版本、决策、验收证据都在仓库里,不依赖聊天记录)。

## 平台与能力

| Target | 说明 |
| --- | --- |
| `timetracker` | iPhone / iPad / Mac 主应用(SwiftUI + SwiftData,可选 iCloud 同步) |
| `timetrackerWidgetExtension` | 桌面小组件(App Group 共享快照) |
| `timetrackerLiveActivityExtension` | Live Activity / 灵动岛 |
| `timetrackerWatchApp` | Apple Watch 三页应用(Active Timers / Quick Start / All Tasks) |

主要功能:任务树与分类、清单进度、多计时器与一分钟内自动续接、手工补录、番茄钟、重复任务(模板 + 当天实例)、Today 时间线与 Heatmap、可解释的预测(显式预计时长优先)、Analytics(gross/wall/overlap)、Inbox 与 AI 建议(OpenAI-compatible endpoint,密钥仅存本机 Keychain)、JSON 导出、App Intents。

## 构建要求

- Xcode 需匹配声明的 SDK:iOS/iPadOS 26.2、macOS 15.7、watchOS 26.2。
- 自动签名,team `LT98S43NKA`;**不要**用 `CODE_SIGNING_ALLOWED=NO`、空 team 或 ad-hoc 签名让构建"通过"。签名与能力验证规则见 [Testing](Docs/Testing.md)。
- 格式化工具:`brew install swiftformat`。
- clone 后执行一次 `make install-hooks`,安装只校验三语种 `.strings` key parity 的 pre-commit 钩子。

## 常用命令

所有开发命令经 **Makefile** 入口;`scripts/*.sh` 只是 `uv run` 薄 wrapper,实际逻辑在 `tools/timetracker_tools/` 的纯标准库 Python 模块(无第三方运行依赖)。`uv` 会在首次运行时自动建好 `.venv`。

```sh
make help                # 列出全部目标
make test                # macOS 单元测试(默认验证入口;TEST_ONLY=timetrackerTests/Suite 聚焦,CONFIGURATION=Release 收集性能证据)
make build-macos         # macOS app 构建(generic/platform=macOS)
make build-ios           # iOS app 构建(generic/platform=iOS,含扩展)
make build-install-all   # 构建并安装 iOS+Watch 与 macOS(默认 Release,复制到 /Applications)
make export-artifacts    # 归档并导出签名产物(iOS IPA + macOS app/zip,默认到 build/Archives 与 build/Exports)
make localization-check  # 校验三语种 .strings key 一致(也是 pre-commit 闸门,无需 xcodebuild)
make format              # SwiftFormat 原地格式化;make format-check 只读校验
make bump-version        # 发布前手动递增版本,见 Versioning
make clean               # 删除 build/ 下的导出、归档与安装产物
```

命令行变量与 shell 环境变量等价(`CONFIGURATION=Release make export-artifacts` 等于 `make CONFIGURATION=Release export-artifacts`);内联构建/测试目标用 `make DEVELOPMENT_TEAM=<team> build-ios`。`make build-info` 由 Xcode 构建阶段自动调用,不是手动门禁。

## 文档地图

| 我想… | 读这里 |
| --- | --- |
| 第一次了解代码结构、找文件 | [ProjectMap](Docs/ProjectMap.md)(第一站) |
| 理解架构、领域模型、写代码放哪 | [Architecture](Docs/Architecture.md) |
| 看当前实现细节与维护者笔记 | [CodeGuide](Docs/CodeGuide.md) |
| 查必须遵守的工程决策 | [AgentDecisions](Docs/AgentDecisions.md) |
| 写/跑测试、验证与发布门禁 | [Testing](Docs/Testing.md) |
| 跑构建/发布/版本命令、工具链细节 | 本文件 + [Versioning](Docs/Versioning.md) |
| 改 UI | [UI-Design](Docs/UI-Design.md) + 仓库内 `apple-hig` / `swiftui-expert-skill` |
| 改用户可见文案 | [Localization](Docs/Localization.md) |
| 了解用户视角的当前行为 | [UserGuide](Docs/UserGuide.md) |
| 碰数据、AI、同步 | [PrivacyAndSecurity](Docs/PrivacyAndSecurity.md) |
| 计划下一步功能 | [NextDevelopmentPlan](Docs/NextDevelopmentPlan.md) |
| 用户反馈清单(任务来源) | [userfeedback](Docs/userfeedback.md) |

Agent 工作流程(文档阅读顺序、任务生命周期、验证分级、提交纪律)定义在 [AGENTS.md](AGENTS.md)。
