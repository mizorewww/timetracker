#!/usr/bin/env bash
# Thin wrapper: 为当前 clone 配置 core.hooksPath=.githooks 并校验 pre-commit hook。
# 实现见 tools/timetracker_tools/install_git_hooks.py(经 uv run 调用)。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v uv >/dev/null 2>&1 || for d in /opt/homebrew/bin /usr/local/bin "$HOME/.local/bin" "$HOME/.cargo/bin"; do
  case ":$PATH:" in *":$d:"*) ;; *) PATH="$d:$PATH";; esac
done
command -v uv >/dev/null 2>&1 || { echo "uv not found on PATH" >&2; exit 1; }
exec uv run --project "$ROOT" python -m timetracker_tools.install_git_hooks "$@"