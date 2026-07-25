#!/usr/bin/env python3
"""用 SwiftFormat 格式化所有 Swift 源。

默认原地格式化;``--check`` 走 ``swiftformat --lint`` 只读校验(有改动则退出码 1)。
Swift 源根与排除项见仓库根的 ``.swiftformat``;本模块定位 ``swiftformat`` 二进制并传播其退出码。
前置依赖:``brew install swiftformat``。
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
from pathlib import Path

# 需格式化的 Swift 源根(仓库根下);排除项在 ``.swiftformat`` 的 ``--exclude`` 中声明。
SWIFT_ROOTS: tuple[str, ...] = (
    "timetracker",
    "timetrackerTests",
    "timetrackerUITests",
    "timetrackerWatchApp",
    "timetrackerWidgetExtension",
    "timetrackerLiveActivityExtension",
    "SharedLiveActivity",
)

BINARY = "swiftformat"
FALLBACK_DIRS = ("/opt/homebrew/bin", "/usr/local/bin", os.path.expanduser("~/.local/bin"))


def find_binary() -> str:
    """定位 ``swiftformat`` 二进制,缺失则提示安装。"""
    path = shutil.which(BINARY)
    if path:
        return path
    for d in FALLBACK_DIRS:
        candidate = Path(d) / BINARY
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return str(candidate)
    raise SystemExit(
        f"{BINARY} not found on PATH.\nInstall with: brew install swiftformat"
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="只读校验(--lint),不修改文件")
    parser.add_argument("--repo-root", default="", help="仓库根目录(默认按本文件定位)")
    args = parser.parse_args()

    repo = Path(args.repo_root).resolve() if args.repo_root else Path(__file__).resolve().parents[2]
    config = repo / ".swiftformat"
    if not config.is_file():
        raise SystemExit(f"SwiftFormat config not found: {config}")

    binary = find_binary()
    cmd = [binary, "--config", str(config)]
    if args.check:
        cmd.append("--lint")
    cmd.extend(str(repo / root) for root in SWIFT_ROOTS)

    print("$ " + " ".join(cmd))
    completed = subprocess.run(cmd, cwd=str(repo))
    return completed.returncode


if __name__ == "__main__":
    raise SystemExit(main())