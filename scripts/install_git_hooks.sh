#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXPECTED_HOOKS_PATH=".githooks"
CHECK_ONLY=0

if [[ "${1:-}" == "--check" ]]; then
  CHECK_ONLY=1
elif [[ -n "${1:-}" ]]; then
  echo "Usage: $0 [--check]" >&2
  exit 2
fi

if ! git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Not a Git working tree: $ROOT_DIR" >&2
  exit 1
fi

CURRENT_HOOKS_PATH="$(git -C "$ROOT_DIR" config --local --get core.hooksPath || true)"

if [[ "$CHECK_ONLY" == "0" ]]; then
  if [[ -n "$CURRENT_HOOKS_PATH" && "$CURRENT_HOOKS_PATH" != "$EXPECTED_HOOKS_PATH" && "${FORCE_HOOKS_PATH:-0}" != "1" ]]; then
    echo "Refusing to replace existing core.hooksPath '$CURRENT_HOOKS_PATH'." >&2
    echo "Re-run with FORCE_HOOKS_PATH=1 after reviewing the existing hooks." >&2
    exit 1
  fi

  git -C "$ROOT_DIR" config --local core.hooksPath "$EXPECTED_HOOKS_PATH"
  CURRENT_HOOKS_PATH="$EXPECTED_HOOKS_PATH"
fi

if [[ "$CURRENT_HOOKS_PATH" != "$EXPECTED_HOOKS_PATH" ]]; then
  echo "Git hooks are not installed for this clone." >&2
  echo "Run: scripts/install_git_hooks.sh" >&2
  exit 1
fi

RESOLVED_HOOK="$(git -C "$ROOT_DIR" rev-parse --git-path hooks/pre-commit)"
if [[ "$RESOLVED_HOOK" != /* ]]; then
  RESOLVED_HOOK="$ROOT_DIR/$RESOLVED_HOOK"
fi

if [[ ! -x "$RESOLVED_HOOK" ]]; then
  echo "Configured pre-commit hook is missing or not executable: $RESOLVED_HOOK" >&2
  exit 1
fi

echo "Git hooks ready: core.hooksPath=$CURRENT_HOOKS_PATH"
