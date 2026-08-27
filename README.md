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
- 自动签名,team `LT98S43NKA`。**不要**用 `CODE_SIGNING_ALLOWED=NO` 或空 team 让构建"通过"。
- 格式化工具:`brew install swiftformat`(用于 `make format`)。
- clone 后先安装 pre-commit 钩子(校验三语种本地化 parity;版本号发布前手动 `make bump-version`,见 [Versioning](Docs/Versioning.md)):

```sh
make install-hooks
```

## 常用命令

开发命令统一从 Makefile 入口进入(逻辑由 uv 管理的 Python 工具实现,详见 [DevelopmentTools](Docs/DevelopmentTools.md)):

```sh
make venv              # 创建/同步 .venv(可选,wrapper 会自举)
make test              # macOS 单元测试(默认验证入口)
make localization-check # 校验 .strings 三语种 key 一致(也是 pre-commit 闸门)
make format            # 用 SwiftFormat 原地格式化(需 brew install swiftformat)
make format-check      # 只读校验是否符合 SwiftFormat
make build-ios         # iOS 设备构建
make export-artifacts  # 导出签名产物(iOS IPA + macOS app/zip)
make help              # 列出全部目标
```

各脚本行为与可配置变量见 [Scripts](Docs/Scripts.md),完整验证策略见 [Testing](Docs/Testing.md)。

## 文档地图

| 我想… | 读这里 |
| --- | --- |
| 第一次了解代码结构、找文件 | [ProjectMap](Docs/ProjectMap.md)(第一站) |
| 理解架构、领域模型、写代码放哪 | [Architecture](Docs/Architecture.md) |
| 看当前实现细节与维护者笔记 | [CodeGuide](Docs/CodeGuide.md) |
| 查必须遵守的工程决策 | [AgentDecisions](Docs/AgentDecisions.md) |
| 写/跑测试、验证与发布门禁 | [Testing](Docs/Testing.md) |
| 跑构建/发布/版本命令 | [DevelopmentTools](Docs/DevelopmentTools.md) |
| 改 UI | [UI-Design](Docs/UI-Design.md) + 仓库内 `apple-hig` / `swiftui-expert-skill` |
| 改用户可见文案 | [Localization](Docs/Localization.md) |
| 了解用户视角的当前行为 | [UserGuide](Docs/UserGuide.md) |
| 碰数据、AI、同步 | [PrivacyAndSecurity](Docs/PrivacyAndSecurity.md) |
| 计划下一步功能 | [NextDevelopmentPlan](Docs/NextDevelopmentPlan.md) |
| 重构前先查集中度与护栏 | [CodeRefactorPlan](Docs/CodeRefactorPlan.md) |
| 版本/构建信息 | [Versioning](Docs/Versioning.md) |
| 一次性审核证据(历史) | 见 git 历史(日期化 `Audit-*.md` 快照已于 2026-07-25 退役) |
| 用户反馈清单(任务来源) | [userfeedback](Docs/userfeedback.md) |

Agent 工作流程(文档阅读顺序、任务生命周期、验证分级、提交纪律)定义在 [AGENTS.md](AGENTS.md)。
