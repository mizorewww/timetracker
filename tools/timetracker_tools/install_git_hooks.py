#!/usr/bin/env python3
"""为当前 clone 幂等配置 core.hooksPath=.githooks 并校验 pre-commit hook。

Git 不会在 clone 后自动信任 tracked hook,因此每个新 clone 需要执行一次。
``--check`` 为只读校验。
"""

from __future__ import annotations

import argparse
import os
import stat
from pathlib import Path

from timetracker_tools.cli_utils import git, git_text

EXPECTED_HOOKS_PATH = ".githooks"


def is_executable(path: Path) -> bool:
    return path.exists() and bool(path.stat().st_mode & stat.S_IXUSR)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", default="", help="仓库根目录(默认当前 git toplevel)")
    parser.add_argument("--check", action="store_true", help="只读校验,不修改配置")
    args = parser.parse_args()

    repo = args.repo_root or git_text(os.getcwd(), "rev-parse", "--show-toplevel")
    if not repo or git_text(repo, "rev-parse", "--is-inside-work-tree") not in ("true",):
        raise SystemExit(f"Not a Git working tree: {repo or os.getcwd()}")

    current_hooks_path = git_text(repo, "config", "--local", "--get", "core.hooksPath")

    check_only = args.check
    if not check_only:
        if (
            current_hooks_path
            and current_hooks_path != EXPECTED_HOOKS_PATH
            and os.environ.get("FORCE_HOOKS_PATH", "0") != "1"
        ):
            raise SystemExit(
                f"Refusing to replace existing core.hooksPath '{current_hooks_path}'.\n"
                "Re-run with FORCE_HOOKS_PATH=1 after reviewing the existing hooks."
            )
        git(repo, "config", "--local", "core.hooksPath", EXPECTED_HOOKS_PATH)
        current_hooks_path = EXPECTED_HOOKS_PATH

    if current_hooks_path != EXPECTED_HOOKS_PATH:
        raise SystemExit(
            "Git hooks are not installed for this clone.\n"
            "Run: scripts/install_git_hooks.sh"
        )

    resolved = git_text(repo, "rev-parse", "--git-path", "hooks/pre-commit")
    if not resolved:
        raise SystemExit("Unable to resolve pre-commit hook path.")
    resolved_path = Path(resolved)
    if not resolved_path.is_absolute():
        resolved_path = Path(repo) / resolved_path

    if not is_executable(resolved_path):
        raise SystemExit(
            f"Configured pre-commit hook is missing or not executable: {resolved_path}"
        )

    print(f"Git hooks ready: core.hooksPath={current_hooks_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())