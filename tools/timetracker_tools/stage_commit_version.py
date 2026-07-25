#!/usr/bin/env python3
"""pre-commit 钩子内部调用:把下一次版本写入 Git index 与工作树。

下一版本始终按 ``HEAD + 1 patch/build`` 计算,因此同一次失败提交反复重试不会继续累加。
脚本直接更新 Git index 中的 project blob,只同步工作树的版本字段,不会把其他未暂存的
Xcode 工程改动带入提交。
"""

from __future__ import annotations

import argparse
import os
import subprocess
import tempfile
from pathlib import Path

from timetracker_tools.cli_utils import (
    git,
    git_bytes,
    git_text,
    next_version,
    read_pbxproj,
    set_project_version_bytes,
    unique_build_version,
    unique_marketing_version,
)


def cat_file_exists(repo: str, spec: str) -> bool:
    try:
        git(repo, "cat-file", "-e", spec, check=True, capture_output=True)
        return True
    except subprocess.CalledProcessError:
        return False


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", default="", help="仓库根目录(默认当前 git toplevel)")
    parser.add_argument(
        "--project-relative-path",
        default=os.environ.get("PROJECT_RELATIVE_PATH", "timetracker.xcodeproj/project.pbxproj"),
        help="相对仓库根的 pbxproj 路径",
    )
    args = parser.parse_args()

    repo = args.repo_root or git_text(os.getcwd(), "rev-parse", "--show-toplevel")
    if not repo:
        raise SystemExit("Not a Git working tree.")

    project_relative = args.project_relative_path
    project_file = Path(repo) / project_relative

    if not project_file.is_file():
        raise SystemExit(f"Project file not found: {project_file}")

    if not git_text(repo, "rev-parse", "--verify", "HEAD"):
        raise SystemExit("Automatic version staging requires an existing HEAD commit.")

    if not cat_file_exists(repo, f"HEAD:{project_relative}"):
        raise SystemExit(f"Project file is not present in HEAD: {project_relative}")

    if not cat_file_exists(repo, f":{project_relative}"):
        raise SystemExit(f"Project file is not present in the Git index: {project_relative}")

    head_bytes = git_bytes(repo, "show", f"HEAD:{project_relative}")
    index_bytes = git_bytes(repo, "show", f":{project_relative}")
    worktree_bytes = read_pbxproj(project_file)

    head_version = unique_marketing_version(head_bytes, source_label="HEAD")
    head_build = unique_build_version(head_bytes, source_label="HEAD")
    index_version = unique_marketing_version(index_bytes, source_label="index")
    index_build = unique_build_version(index_bytes, source_label="index")
    worktree_version = unique_marketing_version(worktree_bytes, source_label="worktree")
    worktree_build = unique_build_version(worktree_bytes, source_label="worktree")

    next_version_str, next_build = next_version(head_version, head_build)

    def valid_pair(marketing: str, build: str) -> bool:
        return (marketing == head_version and build == head_build) or (
            marketing == next_version_str and build == next_build
        )

    if not valid_pair(index_version, index_build):
        raise SystemExit(
            f"Refusing unexpected staged version {index_version} ({index_build}); "
            f"expected {head_version} ({head_build}) or {next_version_str} ({next_build})."
        )

    if not valid_pair(worktree_version, worktree_build):
        raise SystemExit(
            f"Refusing unexpected working-tree version {worktree_version} ({worktree_build}); "
            f"expected {head_version} ({head_build}) or {next_version_str} ({next_build})."
        )

    # 只改版本字段,保留 index 中其它已暂存改动。
    new_index_bytes = set_project_version_bytes(index_bytes, next_version_str, next_build)
    unique_marketing_version(new_index_bytes, source_label="index")
    unique_build_version(new_index_bytes, source_label="index")

    ls = git_text(repo, "ls-files", "-s", "--", project_relative)
    mode = ""
    stage0_count = 0
    for line in ls.splitlines():
        parts = line.split()
        if len(parts) < 3:
            continue
        if parts[2] == "0":
            stage0_count += 1
            if not mode:
                mode = parts[0]
    if stage0_count != 1 or not mode:
        raise SystemExit(
            f"Project file has an unresolved or invalid index entry: {project_relative}"
        )

    with tempfile.TemporaryDirectory(prefix="timetracker-version-hook.") as tmp:
        index_blob_path = Path(tmp) / "index.pbxproj"
        index_blob_path.write_bytes(new_index_bytes)
        index_blob = git_text(repo, "hash-object", "-w", "--", str(index_blob_path))
        if not index_blob:
            raise SystemExit("Failed to hash staged project blob.")
        git(repo, "update-index", "--cacheinfo", mode, index_blob, project_relative)

    # 同步工作树版本字段,不暂存其它工作树改动。
    new_worktree_bytes = set_project_version_bytes(worktree_bytes, next_version_str, next_build)
    project_file.write_bytes(new_worktree_bytes)
    unique_marketing_version(new_worktree_bytes, source_label="worktree")
    unique_build_version(new_worktree_bytes, source_label="worktree")

    print(f"Prepared commit version: {head_version} ({head_build}) -> {next_version_str} ({next_build})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())