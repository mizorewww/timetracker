#!/usr/bin/env python3
"""Xcode 构建阶段:写入 AppBuildInfo.plist(branch / commit / dirty / 构建时间)。

通常由 App target 的 "Write Build Info" 构建阶段调用,依赖 Xcode 注入的
TARGET_BUILD_DIR 与 UNLOCALIZED_RESOURCES_FOLDER_PATH;缺失时打印跳过信息并成功退出。
"""

from __future__ import annotations

import os
import plistlib
from datetime import datetime, timezone
from pathlib import Path

from timetracker_tools.cli_utils import git_text


def main() -> int:
    target_build_dir = os.environ.get("TARGET_BUILD_DIR", "")
    resources_folder = os.environ.get("UNLOCALIZED_RESOURCES_FOLDER_PATH", "")
    if not target_build_dir or not resources_folder:
        print("Build info skipped: TARGET_BUILD_DIR or UNLOCALIZED_RESOURCES_FOLDER_PATH is missing.")
        return 0

    srcroot = os.environ.get("SRCROOT", "")
    if not srcroot:
        srcroot = git_text(os.getcwd(), "rev-parse", "--show-toplevel") or os.getcwd()

    resource_dir = Path(target_build_dir) / resources_folder
    plist_path = resource_dir / "AppBuildInfo.plist"

    branch = git_text(srcroot, "branch", "--show-current")
    if not branch:
        branch = git_text(srcroot, "rev-parse", "--abbrev-ref", "HEAD")
    if not branch or branch == "HEAD":
        branch = "detached"

    commit_full = git_text(srcroot, "rev-parse", "HEAD") or "unknown"
    commit_short = git_text(srcroot, "rev-parse", "--short=12", "HEAD") or "unknown"

    dirty = "false"
    if git_text(srcroot, "status", "--porcelain", "--untracked-files=normal"):
        dirty = "true"

    resource_dir.mkdir(parents=True, exist_ok=True)

    payload = {
        "GitBranch": branch,
        "GitCommitFull": commit_full,
        "GitCommitShort": commit_short,
        "GitDirty": dirty,
        "BuildDate": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    }

    tmp_path = plist_path.with_suffix(plist_path.suffix + ".tmp")
    with tmp_path.open("wb") as handle:
        plistlib.dump(payload, handle, sort_keys=True)
    os.replace(tmp_path, plist_path)

    print(f"Wrote build info: {plist_path} ({branch} {commit_short} dirty={dirty})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())