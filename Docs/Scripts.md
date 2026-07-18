# 脚本指南

仓库内的脚本均从仓库根目录调用，并以 `bash` 为运行环境。它们会执行真实的签名、安装、归档或修改工程文件；在 CI 或共享机器上使用前，请先确认环境变量中的 team、scheme 和输出目录。

## `bump_marketing_version.sh`

递增 `timetracker.xcodeproj/project.pbxproj` 中全部 target 的版本信息：`MARKETING_VERSION` 的 patch 加一，`CURRENT_PROJECT_VERSION` 加一。例如 `1.1.33 (88)` 变为 `1.1.34 (89)`。

```sh
./scripts/bump_marketing_version.sh
```

默认项目文件可用 `PROJECT_FILE` 覆盖，便于在临时副本上验证：

```sh
PROJECT_FILE=/tmp/timetracker.pbxproj ./scripts/bump_marketing_version.sh
```

正常提交时 `.githooks/pre-commit` 会自动调用它并暂存项目文件。若某次紧急提交不应递增版本，请使用：

```sh
SKIP_VERSION_BUMP=1 git commit -m "message"
```

## `write_build_info_plist.sh`

这是 App target 的 Xcode build phase 脚本，通常不应手动运行。它会在产物资源目录写入 `AppBuildInfo.plist`，提供 About 页面读取的 branch、完整和短 commit hash、工作区 dirty 状态，以及 UTC 构建时间。

脚本依赖 Xcode 注入的 `TARGET_BUILD_DIR` 和 `UNLOCALIZED_RESOURCES_FOLDER_PATH`；缺失时会成功退出并打印跳过信息。`SRCROOT` 可覆盖 Git 仓库根目录。dirty 状态包括已暂存、未暂存和未跟踪文件。

## `export_signed_artifacts.sh`

归档 iOS 和 macOS Release 产物，导出开发签名 IPA，复制并签名校验 macOS `.app`，再生成 macOS zip：

```sh
./scripts/export_signed_artifacts.sh
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
BUILD_ROOT=/tmp/timetracker-artifacts ./scripts/export_signed_artifacts.sh
```

需要可用的 Xcode、开发证书和匹配的 provisioning profile；导出失败时保留已生成的归档和日志以供排查。

## `build_install_all.sh`

构建含 Watch 伴侣的 iOS/iPadOS app 和 macOS app，安装到可用的物理 iOS/iPadOS 设备，并将 macOS app 复制到 `/Applications/timetracker.app`：

```sh
./scripts/build_install_all.sh
```

它会使用独立的 `build/Install/DerivedData`，并保留自动签名。iOS 构建会同时构建依赖型 Watch App、将其嵌入 iOS app 的 `Watch/` 目录，并在安装前校验两端 bundle ID、伴侣关系、签名，以及开发 profile 是否包含当前可见的 Apple Watch。看不到物理 Watch 时会给出提示但继续安装 iPhone app。脚本只把 iOS app 安装到 iPhone；配对 Apple Watch 的安装由系统处理。macOS 目标会先复制到同一目录中的临时 `.app`，再替换目的 app；非法的 `PRODUCT_NAME` 会被拒绝，避免删除 `/Applications` 外的路径。

常用变量：

| 变量 | 默认值 | 用途 |
| --- | --- | --- |
| `PROJECT`、`SCHEME` | 项目 / `timetracker` | iOS/macOS 构建目标 |
| `CONFIGURATION` | `Debug` | 构建配置 |
| `DEVELOPMENT_TEAM` | `LT98S43NKA` | 自动签名团队 |
| `APPLICATIONS_DIR` | `/Applications` | macOS app 安装目录 |
| `LAUNCH_AFTER_INSTALL=1` | `0` | iOS 安装后启动 app |
| `ALLOW_DEVICE_FAILURES=1` | `0` | 将设备安装/启动失败降为非致命 |
| `DEVICE_TIMEOUT` | `30` | `devicectl` 查询超时秒数 |

iPhone 的 Watch app 中启用“自动安装 App”后，安装 iOS app 会让系统把内嵌伴侣安装到兼容的配对 Apple Watch。这个系统级用户设置不能由应用或脚本强制开启；关闭时可在 Watch app 的“可用 App”中手动安装。Debug 开发安装还要求 Apple Watch 已开启 Developer Mode、对 Xcode 可见且已包含在 provisioning profile 中；App Store/TestFlight 发行安装不使用开发设备名单。
