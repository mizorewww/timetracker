#!/usr/bin/env python3
"""手动递增 pbxproj 中全部 target 的版本信息。

MARKETING_VERSION 的 patch 加一,CURRENT_PROJECT_VERSION 加一。
版本号不再随提交自动递增;发布前运行 `make bump-version`(见 Docs/Versioning.md)。
"""

from __future__ import annotations

import argparse
from pathlib import Path

from timetracker_tools.cli_utils import (
    BUILD_VALUE_RE,
    MARKETING_VALUE_RE,
    env,
    next_version,
    read_pbxproj,
    set_project_version_bytes,
)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--project-file",
        default=env("PROJECT_FILE", ""),
        help="pbxproj 路径(默认 <repo>/timetracker.xcodeproj/project.pbxproj,可用 PROJECT_FILE 覆盖)",
    )
    args = parser.parse_args()

    project_file = args.project_file or str(
        Path(__file__).resolve().parents[2] / "timetracker.xcodeproj" / "project.pbxproj"
    )
    if not Path(project_file).is_file():
        raise SystemExit(f"Project file not found: {project_file}")

    data = read_pbxproj(project_file)

    marketing_match = MARKETING_VALUE_RE.search(data)
    build_match = BUILD_VALUE_RE.search(data)
    if marketing_match is None or build_match is None:
        raise SystemExit(
            f"Unable to read MARKETING_VERSION or CURRENT_PROJECT_VERSION from {project_file}"
        )

    current_version = marketing_match.group(1).decode()
    current_build = build_match.group(1).decode()

    next_version_str, next_build = next_version(current_version, current_build)

    new_data = set_project_version_bytes(data, next_version_str, next_build)
    Path(project_file).write_bytes(new_data)

    print(f"Bumped version: {current_version} ({current_build}) -> {next_version_str} ({next_build})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())