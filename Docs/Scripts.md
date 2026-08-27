# 脚本指南

开发命令统一从 **Makefile** 入口进入；`scripts/*.sh` 是薄 wrapper，实际逻辑由 **uv** 管理的 Python 模块实现(位于 `tools/timetracker_tools/`)。工具布局、wrapper 机制、env 覆盖与排错见 [DevelopmentTools](DevelopmentTools.md)。下文按目标/脚本说明行为与可配置变量；它们会执行真实的签名、安装、归档或修改工程文件，在 CI 或共享机器上使用前，请先确认环境变量中的 team、scheme 和输出目录。

## `make bump-version`(`bump_marketing_version.sh`)

递增 `timetracker.xcodeproj/project.pbxproj` 中全部 target 的版本信息：`MARKETING_VERSION` 的 patch 加一，`CURRENT_PROJECT_VERSION` 加一。例如 `1.1.33 (88)` 变为 `1.1.34 (89)`。版本规则与发布节奏见 [Versioning](Versioning.md)。

```sh
make bump-version
```

默认项目文件可用 `PROJECT_FILE` 覆盖，便于在临时副本上验证：

```sh
PROJECT_FILE=/tmp/timetracker.pbxproj make bump-version
```

## `make install-hooks`(`install_git_hooks.sh`)

为当前 clone 幂等配置 `core.hooksPath=.githooks`，并验证仓库内的 pre-commit hook 存在且可执行。Git 不会在 clone 后自动信任 tracked hook，因此每个新 clone 需要执行一次：

```sh
make install-hooks
```

只读检查当前 clone：

```sh
make check-hooks
```

## `make build-info`(`write_build_info_plist.sh`)

这是 App target 的 Xcode build phase 脚本，通常不应手动运行。它会在产物资源目录写入 `AppBuildInfo.plist`，提供 About 页面读取的 branch、完整和短 commit hash、工作区 dirty 状态，以及 UTC 构建时间。

脚本依赖 Xcode 注入的 `TARGET_BUILD_DIR` 和 `UNLOCALIZED_RESOURCES_FOLDER_PATH`；缺失时会成功退出并打印跳过信息。`SRCROOT` 可覆盖 Git 仓库根目录。dirty 状态包括已暂存、未暂存和未跟踪文件。

## `make localization-check`(`localization_check.sh`)

纯标准库静态校验:解析所有 target 的 `.strings`(`Localizable`/`InfoPlist`/`AppShortcuts`),比对 `en`/`zh-Hans`/`zh-Hant` 三语种 key 集合,任一资源不一致即退出码 1。无需 `xcodebuild`,毫秒级。

```sh
make localization-check
```

只在不一致时输出详情(`--quiet`):

```sh
scripts/localization_check.sh --quiet
```

该脚本也是 pre-commit 闸门:提交前先以 `--quiet` 跑一次,缺 key 即中止提交。`--repo-root` 可覆盖仓库根。范围只做 key-set parity；翻译含义、禁用术语和产品语气属于本地化审查，不再通过扫描字符串内容的 Swift 测试固化。

## `make format` / `make format-check`(`format.sh`)

用 [SwiftFormat](https://github.com/nicklockwood/swiftformat)(Nick Lockwood)格式化所有 Swift 源根(`timetracker`、`timetrackerTests`、`timetrackerUITests`、`timetrackerWatchApp`、`timetrackerWidgetExtension`、`timetrackerLiveActivityExtension`、`SharedLiveActivity`),配置在仓库根 `.swiftformat`(排除 `build/`、`.venv/`、`timetracker.xcodeproj/`)。

```sh
make format         # 原地格式化
make format-check   # 只读校验(--lint),不符合则退出码 1
```

前置依赖:`brew install swiftformat`。`format.py` 只定位二进制并转发参数,格式化逻辑在外部 `swiftformat`;`--check` 透传为 `--lint`。`.swiftformat` 禁用了若干会改写语义/产生无效代码的默认规则(`organizeDeclarations`、`opaqueGenericParameters`、`noForceUnwrapInTests`、`preferKeyPath`),详见配置文件注释。

## `make export-artifacts`(`export_signed_artifacts.sh`)

归档 iOS 和 macOS Release 产物，导出开发签名 IPA，复制并签名校验 macOS `.app`，再生成 macOS zip：

```sh
make export-artifacts
```

默认产物位于 `build/Archives/<timestamp>` 与 `build/Exports/<timestamp>`，`build/Exports/latest` 是指向最近一次导出的符号链接。若同一秒重复执行，脚本自动追加 `-1`、`-2` 等后缀，避免覆盖已有产物；若 `latest` 是真实文件或目录，脚本会拒绝替换。

可配置变量：

| 变量 | 默认值 | 用途 |
| --- | --- | --- |
| `PROJECT` | `timetracker.xcodeproj` | Xcode 项目目录 |
| `SCHEME` | `timetracker` | 归档 scheme |
| `CONFIGURATION` | `Release` | 构建配置 |
| `DEVELOPMENT_TEAM` | `LT98S43NKA` | 自动签名团队 |
| `PRODUCT_NAME` | `timetracker` | 产物 `.app` 名称 |
| `BUILD_ROOT` | `build` | 归档和导出根目录 |
| `IOS_EXPORT_OPTIONS` | `BuildSupport/ExportOptions-iOS-development.plist` | IPA 导出配置 |

例如：

```sh
BUILD_ROOT=/tmp/timetracker-artifacts make export-artifacts
```

需要可用的 Xcode、开发证书和匹配的 provisioning profile；导出失败时保留已生成的归档和日志以供排查。

## `make build-install-all`(`build_install_all.sh`)

构建含 Watch 伴侣的 iOS/iPadOS app 和 macOS app，安装到可用的物理 iOS/iPadOS 设备，并将 macOS app 复制到 `/Applications/timetracker.app`：

```sh
make build-install-all
```

它会使用独立的 `build/Install/DerivedData`，并保留自动签名。iOS 构建会同时构建依赖型 Watch App、将其嵌入 iOS app 的 `Watch/` 目录，并在安装前校验两端 bundle ID、伴侣关系、签名，以及开发 profile 是否包含当前可见的 Apple Watch。看不到物理 Watch 时会给出提示但继续安装 iPhone app。脚本只把 iOS app 安装到 iPhone；配对 Apple Watch 的安装由系统处理。macOS 目标会先复制到同一目录中的临时 `.app`，再替换目的 app；非法的 `PRODUCT_NAME` 会被拒绝，避免删除 `/Applications` 外的路径。

常用变量：

| 变量 | 默认值 | 用途 |
| --- | --- | --- |
| `PROJECT`、`SCHEME` | 项目 / `timetracker` | iOS/macOS 构建目标 |
| `CONFIGURATION` | `Release` | 构建配置。默认 Release：本目标安装到真机与 `/Applications`，而 Debug 二进制会定义 `DEBUG`，解锁演示数据与云冒烟测试入口 |
| `DEVELOPMENT_TEAM` | `LT98S43NKA` | 自动签名团队 |
| `APPLICATIONS_DIR` | `/Applications` | macOS app 安装目录 |
| `LAUNCH_AFTER_INSTALL=1` | `0` | iOS 安装后启动 app |
| `ALLOW_DEVICE_FAILURES=1` | `0` | 将设备安装/启动失败降为非致命 |
| `DEVICE_TIMEOUT` | `30` | `devicectl` 查询超时秒数 |

iPhone 的 Watch app 中启用“自动安装 App”后，安装 iOS app 会让系统把内嵌伴侣安装到兼容的配对 Apple Watch。这个系统级用户设置不能由应用或脚本强制开启；关闭时可在 Watch app 的“可用 App”中手动安装。Debug 开发安装还要求 Apple Watch 已开启 Developer Mode、对 Xcode 可见且已包含在 provisioning profile 中；App Store/TestFlight 发行安装不使用开发设备名单。
