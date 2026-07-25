"""共享 CLI 辅助:子进程包装、git 调用、pbxproj 版本读写。"""

from __future__ import annotations

import os
import re
import subprocess
from pathlib import Path
from typing import Sequence

# pbxproj 中版本字段的正则。保留与原 bash/perl 行为一致:
# MARKETING_VERSION 形如 1.2 或 1.2.3 或 1.2.3.4(后两段可选),CURRENT_PROJECT_VERSION 为纯整数。
MARKETING_VALUE_RE = re.compile(rb"MARKETING_VERSION = ([0-9]+(?:\.[0-9]+){1,2});")
BUILD_VALUE_RE = re.compile(rb"CURRENT_PROJECT_VERSION = ([0-9]+);")
MARKETING_FIELD_RE = re.compile(rb"MARKETING_VERSION = [0-9]+(?:\.[0-9]+){1,2};")
BUILD_FIELD_RE = re.compile(rb"CURRENT_PROJECT_VERSION = [0-9]+;")


def run(
    cmd: Sequence[str | Path],
    *,
    check: bool = True,
    capture_output: bool = False,
    env: dict[str, str] | None = None,
    cwd: str | Path | None = None,
    text: bool = True,
) -> subprocess.CompletedProcess[str]:
    """运行子进程。默认不捕获输出,以保留 xcodebuild/git 的实时日志。"""
    return subprocess.run(
        [str(c) for c in cmd],
        check=check,
        capture_output=capture_output,
        env=env,
        cwd=str(cwd) if cwd is not None else None,
        text=text,
    )


def git(
    repo: str | Path,
    *args: str,
    check: bool = True,
    capture_output: bool = True,
) -> subprocess.CompletedProcess[str]:
    """在 ``repo`` 中运行 git,默认捕获 stdout。"""
    return run(["git", "-C", str(repo), *args], check=check, capture_output=capture_output)


def git_text(repo: str | Path, *args: str, default: str | None = None) -> str:
    """运行 git 并返回去除首尾空白后的 stdout;失败时返回 ``default``(不抛错)。"""
    try:
        result = git(repo, *args, check=True, capture_output=True)
    except subprocess.CalledProcessError:
        return "" if default is None else default
    return result.stdout.strip()


def git_bytes(repo: str | Path, *args: str, check: bool = True) -> bytes:
    """运行 git 并返回原始 stdout 字节(用于 pbxproj 等二进制安全读取)。"""
    result = subprocess.run(
        ["git", "-C", str(repo), *args],
        check=check,
        capture_output=True,
    )
    return result.stdout


def unique_marketing_version(project_bytes: bytes, *, source_label: str = "project file") -> str:
    """校验 pbxproj 字节中 MARKETING_VERSION 唯一,返回该值。"""
    values = {m.group(1).decode() for m in MARKETING_VALUE_RE.finditer(project_bytes)}
    if len(values) != 1:
        raise SystemExit(
            f"Expected one consistent MARKETING_VERSION in {source_label}; found {len(values)}."
        )
    return next(iter(values))


def unique_build_version(project_bytes: bytes, *, source_label: str = "project file") -> str:
    """校验 pbxproj 字节中 CURRENT_PROJECT_VERSION 唯一,返回该值。"""
    values = {m.group(1).decode() for m in BUILD_VALUE_RE.finditer(project_bytes)}
    if len(values) != 1:
        raise SystemExit(
            f"Expected one consistent CURRENT_PROJECT_VERSION in {source_label}; found {len(values)}."
        )
    return next(iter(values))


def read_pbxproj(path: str | Path) -> bytes:
    return Path(path).read_bytes()


def set_project_version_bytes(project_bytes: bytes, marketing_version: str, build_version: str) -> bytes:
    """在 pbxproj 字节中全局替换版本字段,返回新字节。"""
    new = MARKETING_FIELD_RE.sub(f"MARKETING_VERSION = {marketing_version};".encode(), project_bytes)
    new = BUILD_FIELD_RE.sub(f"CURRENT_PROJECT_VERSION = {build_version};".encode(), new)
    return new


def write_project_version(path: str | Path, marketing_version: str, build_version: str) -> None:
    """读 pbxproj、替换版本字段、写回(原地)。"""
    data = read_pbxproj(path)
    new = set_project_version_bytes(data, marketing_version, build_version)
    Path(path).write_bytes(new)


def split_marketing(version: str) -> tuple[str, str, str]:
    """拆分 MARKETING_VERSION 为 (major, minor, patch),patch 缺省为 0。"""
    parts = version.split(".")
    major = parts[0]
    minor = parts[1] if len(parts) > 1 else "0"
    patch = parts[2] if len(parts) > 2 else "0"
    return major, minor, patch


def next_version(marketing: str, build: str) -> tuple[str, str]:
    """按 HEAD+1 patch/build 计算下一版本。"""
    major, minor, patch = split_marketing(marketing)
    next_marketing = f"{major}.{minor}.{int(patch) + 1}"
    next_build = str(int(build) + 1)
    return next_marketing, next_build


def env(name: str, default: str) -> str:
    """读环境变量,缺失返回 default。"""
    return os.environ.get(name, default)