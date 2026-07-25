#!/usr/bin/env bash
# Thin wrapper: Xcode 构建阶段写入 AppBuildInfo.plist。
# 实现见 tools/timetracker_tools/write_build_info_plist.py(经 uv run 调用)。
# 依赖 Xcode 注入的 TARGET_BUILD_DIR / UNLOCALIZED_RESOURCES_FOLDER_PATH。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v uv >/dev/null 2>&1 || for d in /opt/homebrew/bin /usr/local/bin "$HOME/.local/bin" "$HOME/.cargo/bin"; do
  case ":$PATH:" in *":$d:"*) ;; *) PATH="$d:$PATH";; esac
done
command -v uv >/dev/null 2>&1 || { echo "uv not found on PATH" >&2; exit 1; }
exec uv run --project "$ROOT" python -m timetracker_tools.write_build_info_plist "$@"