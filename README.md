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
- 自动签名,team `LT98S43NKA`;**不要**用 `CODE_SIGNING_ALLOWED=NO`、空 team 或 ad-hoc 签名让构建"通过"。
- 格式化工具:`brew install swiftformat`。
- clone 后执行一次 `make install-hooks`,安装校验三语种 `.strings` key parity 与 SwiftFormat 的 pre-commit 钩子。

## 常用命令

所有开发命令经 **Makefile** 唯一入口(Xcode `Write Build Info` 构建阶段与 pre-commit 钩子也调用 `make`);Makefile 经 `uv run --no-project --python 3.12` 调用 `tools/timetracker_tools/` 的纯标准库 Python 模块(系统 Python 只有 3.9)。

```sh
make help                # 列出全部目标
make test                # macOS 单元测试(默认验证入口;TEST_ONLY=timetrackerTests/Suite 聚焦,CONFIGURATION=Release 收集性能证据)
make build-macos         # macOS app 构建(generic/platform=macOS)
make build-ios           # iOS app 构建(generic/platform=iOS,含扩展)
make build-install-all   # 构建并安装 iOS+Watch 与 macOS(默认 Release,复制到 /Applications;.device-install-exclusions 可排除设备)
make export-artifacts    # 归档并导出签名产物(iOS IPA + macOS app/zip,默认到 build/Archives 与 build/Exports)
make localization-check  # 校验三语种 .strings key 一致(也是 pre-commit 闸门,无需 xcodebuild)
make format              # SwiftFormat 原地格式化;make format-check 只读校验
make bump-version        # 发布前手动递增 patch 版本与 build 号(所有 target)
make clean               # 删除 build/ 下的导出、归档与安装产物
```

命令行变量与 shell 环境变量等价(`CONFIGURATION=Release make export-artifacts` 等于 `make CONFIGURATION=Release export-artifacts`);内联构建/测试目标用 `make DEVELOPMENT_TEAM=<team> build-ios`。`make build-info` 由 Xcode 构建阶段自动调用,不是手动门禁。

## 文档

- [AGENTS.md](AGENTS.md) — agent 规则与门禁
- [Architecture](Docs/Architecture.md) — 结构、领域不变量、schema 规则
- [AgentDecisions](Docs/AgentDecisions.md) — 必须遵守的长期决策
- [userfeedback](Docs/userfeedback.md) — 用户反馈清单
