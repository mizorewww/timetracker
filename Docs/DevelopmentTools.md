# 开发工具(DevelopmentTools)

仓库的开发命令统一从 **Makefile** 入口进入;构建、发布、版本与钩子的实际逻辑用 **Python** 实现,由 **uv** 管理环境,`scripts/*.sh` 退化为只调 `uv run` 的薄 wrapper。本文是这套工具的全景说明;具体脚本行为与可配置变量见 [Scripts](Scripts.md),版本机制背景见 [Versioning](Versioning.md)。

## 一、统一入口 `make`

`make help` 列出全部目标。常用:

| 目标 | 作用 |
| --- | --- |
| `make venv` | 用 `uv sync` 创建/同步 `.venv`(也可由 wrapper 自举,非必须) |
| `make install-hooks` | 安装 pre-commit 钩子(localization parity 闸门,clone 后执行一次) |
| `make check-hooks` | 只读校验钩子是否就位 |
| `make bump-version` | 发布前手动递增 marketing/build 版本(规则见 [Versioning](Versioning.md)) |
| `make build-ios` | 构建 iOS app(`generic/platform=iOS`) |
| `make build-macos` | 构建 macOS app(`generic/platform=macOS`) |
| `make build-install-all` | 构建 iOS+Watch 与 macOS(默认 Release),安装到设备并复制到 /Applications |
| `make test` | macOS 单元测试；默认以 Debug 运行 `timetrackerTests`，可用 `TEST_ONLY=timetrackerTests/SuiteName` 聚焦套件，或用 `CONFIGURATION=Release` 收集一次性 Release 性能证据 |
| `make test-ui-ios` / `make test-ui-macos` | 运行 `UI_TEST_ONLY` 指定的 XCUITest；iOS 使用运行后自动删除的临时模拟器，结果保存在 `build/UITestResults` |
| `make localization-check` | 静态校验所有 `.strings` 资源在三语种间 key 一致(无需 `xcodebuild`,也作为 pre-commit 闸门) |
| `make format` | 用 SwiftFormat 原地格式化所有 Swift 源 |
| `make format-check` | 只读校验 Swift 源是否符合 SwiftFormat(不修改) |
| `make export-artifacts` | 归档并导出签名产物(iOS IPA + macOS app/zip) |
| `make build-info` | 写入 `AppBuildInfo.plist`(通常由 Xcode 构建阶段调用,手动运行会因缺 Xcode 变量而跳过) |
| `make clean` | 删除 `build/` 下的导出、归档与安装产物 |

### env 变量覆盖

Makefile 把命令行变量与 shell 环境变量透传给 wrapper/脚本,因此原有覆盖方式继续生效,两种写法等价:

```sh
CONFIGURATION=Release make export-artifacts
make CONFIGURATION=Release export-artifacts
LAUNCH_AFTER_INSTALL=1 ALLOW_DEVICE_FAILURES=1 make build-install-all
CONFIGURATION=Debug make build-install-all   # 显式装 Debug 包（会解锁演示数据/冒烟入口）
BUILD_ROOT=/tmp/timetracker-artifacts make export-artifacts
```

`build-ios` / `build-macos` / `test` 这三个内联目标用 make 变量,覆盖时统一用 `make DEVELOPMENT_TEAM=<team> build-ios`(命名与脚本侧 `DEVELOPMENT_TEAM` 一致)。各脚本可配置变量的完整清单见 [Scripts](Scripts.md)。

## 二、uv + Python 工具布局

```
pyproject.toml              # uv 项目:声明 tools/timetracker_tools 为包,纯标准库,无第三方运行依赖
uv.lock                     # uv 锁文件(提交进仓库,保证可复现)
.venv/                      # uv 创建(gitignore,不入库)
tools/timetracker_tools/    # Python 实现
  cli_utils.py              # 共享:subprocess 包装、git 辅助、pbxproj 版本读写
  build_install_all.py
  export_signed_artifacts.py
  bump_marketing_version.py
  install_git_hooks.py
  write_build_info_plist.py
  localization_check.py        # .strings 三语种 key parity 静态校验
  format.py                    # 定位 swiftformat 二进制并传播退出码(逻辑在外部 swiftformat)
scripts/*.sh                # 薄 wrapper:补 PATH + exec uv run python -m timetracker_tools.<name>
```

- **无第三方 Python 运行依赖**:实现只用标准库(`subprocess`、`plistlib`、`json`、`argparse`、`re`、`pathlib`、`tempfile`)。`uv sync` 只装本包自身。
- **外部二进制**:`make format` / `make format-check` 调用 [SwiftFormat](https://github.com/nicklockwood/swiftformat)(Nick Lockwood),需 `brew install swiftformat`;配置在仓库根 `.swiftformat`。`format.py` 只负责定位二进制与转发参数,不在 Python 侧实现格式化逻辑。
- **`uv run` 自举**:wrapper 调 `uv run --project <root> python -m timetracker_tools.<name>`,`uv run` 会在缺失时自动创建 `.venv` 并以 editable 方式装好包,因此首次运行不必先 `make venv`。`make venv` 只是显式 bootstrap,便于离线/CI 预热。
- **`uv.lock` 提交**:锁文件入库以保证不同机器环境一致;`.venv/` 不入库。

## 三、shell wrapper 机制

所有 `scripts/*.sh` 用同一模板,只改模块名:

```sh
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v uv >/dev/null 2>&1 || for d in /opt/homebrew/bin /usr/local/bin "$HOME/.local/bin" "$HOME/.cargo/bin"; do
  case ":$PATH:" in *":$d:"*) ;; *) PATH="$d:$PATH";; esac
done
command -v uv >/dev/null 2>&1 || { echo "uv not found on PATH" >&2; exit 1; }
exec uv run --project "$ROOT" python -m timetracker_tools.<name> "$@"
```

PATH 兜底是为了应对 **Xcode 构建阶段**环境 PATH 受限的情况(见下)。wrapper 只做"找到 uv + 转发参数",不要往 wrapper 里写业务逻辑——逻辑一律放 Python 模块。

## 四、Xcode 构建阶段与 git hook 如何调到 Python

两处外部调用方写死了 `scripts/` 路径,刻意保留不改,经由 wrapper 间接调 Python:

- **Xcode 构建阶段**:`timetracker.xcodeproj/project.pbxproj` 的 "Write Build Info" 阶段 `shellScript = "$SRCROOT/scripts/write_build_info_plist.sh"`。该 wrapper 再 `uv run` 调 `write_build_info_plist.py`,后者从 Xcode 注入的 `TARGET_BUILD_DIR` / `UNLOCALIZED_RESOURCES_FOLDER_PATH` 定位资源目录并写入 `AppBuildInfo.plist`。
- **pre-commit hook**:`.githooks/pre-commit` 只调 `scripts/localization_check.sh --quiet`(三语种 `.strings` key parity 闸门,失败即中止提交)。版本号不再随提交自动递增;发布前手动 bump,规则见 [Versioning](Versioning.md)。

### 排错:uv 不在 Xcode 构建阶段的 PATH

Xcode 构建环境的 PATH 通常不含 `/opt/homebrew/bin`,wrapper 已自动补齐常见安装位置。若仍报 `uv not found on PATH`:

1. 先在终端 `make venv` 建好 `.venv`;
2. 把对应 wrapper 的 `exec uv run ...` 行临时改为直调 venv python(绕开 uv):
   ```sh
   exec "$ROOT/.venv/bin/python" -m timetracker_tools.write_build_info_plist "$@"
   ```
   这是仅 build-info wrapper 可用的降级路径(其它脚本也适用,但需保证 `.venv` 已存在且包已装)。

### 关于 git hook 的 `uv run` 开销

uv 为 Rust 实现,每次 `uv run` 的 sync 检查很快(约数十毫秒)。若仍嫌每次 commit 有开销,可把 `.githooks/pre-commit` 改为直调 venv python:

```sh
"$REPO_ROOT/.venv/bin/python" -m timetracker_tools.localization_check --quiet
```

代价是要求 `.venv` 已存在(不再自举)。默认保持 `uv run` 以保留自举能力。

## 五、何时改 Python 模块、何时改 wrapper

- 改业务行为(版本算法、构建参数、产物路径、校验规则)→ 改 `tools/timetracker_tools/*.py`。
- 改调用入口/目标名/内联 xcodebuild 参数 → 改 `Makefile`。
- wrapper 几乎不需要改;只有 uv 调用方式或 PATH 兜底策略调整时才动 `scripts/*.sh`。
- 新增脚本:在 `tools/timetracker_tools/` 加模块(`if __name__ == "__main__": raise SystemExit(main())`),在 `scripts/` 加同名 wrapper,在 `Makefile` 加目标,在 [Scripts](Scripts.md) 补说明。

## 六、验证

工具链的回归门禁:

```sh
make venv              # 建环境(可选,wrapper 会自举)
make help              # 列出目标
make check-hooks       # 校验钩子
make localization-check
```

Xcode 构建阶段与真实 commit 的端到端验证见 [Testing](Testing.md)。
