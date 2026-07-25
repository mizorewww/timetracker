#!/usr/bin/env bash
# Thin wrapper: 隔离临时仓库中跑版本钩子集成测试。
# 实现见 tools/timetracker_tools/test_versioning_hooks.py(经 uv run 调用)。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v uv >/dev/null 2>&1 || for d in /opt/homebrew/bin /usr/local/bin "$HOME/.local/bin" "$HOME/.cargo/bin"; do
  case ":$PATH:" in *":$d:"*) ;; *) PATH="$d:$PATH";; esac
done
command -v uv >/dev/null 2>&1 || { echo "uv not found on PATH" >&2; exit 1; }
exec uv run --project "$ROOT" python -m timetracker_tools.test_versioning_hooks "$@"