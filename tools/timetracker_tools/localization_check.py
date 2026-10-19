#!/usr/bin/env python3
"""静态校验所有 .strings 资源在 en / zh-Hans / zh-Hant 之间 key 集合一致。

统一校验 `Localizable.strings`、`InfoPlist.strings` 与 `AppShortcuts.strings`
的 key parity,无需运行 xcodebuild。只比对 key 集合,不扫描源码或限制 value 内容。

退出码:全部一致为 0,任一资源不一致为 1。``--quiet`` 仅在出现不一致时输出。
"""

from __future__ import annotations

import argparse
import json
import subprocess
from pathlib import Path

# target -> 该 target 下需校验的资源族(.strings 文件名前缀)。
TARGETS: dict[str, tuple[str, ...]] = {
    "timetracker": ("Localizable", "InfoPlist", "AppShortcuts"),
    "timetrackerWatchApp": ("Localizable", "InfoPlist"),
    "timetrackerWidgetExtension": ("Localizable", "InfoPlist"),
    "timetrackerLiveActivityExtension": ("Localizable", "InfoPlist"),
}

LOCALES: tuple[str, ...] = ("en", "zh-Hans", "zh-Hant")


def parse_strings_keys(path: Path) -> set[str]:
    """用系统 plutil 解析 .strings,返回 key 集合(格式错误直接报错)。"""
    result = subprocess.run(
        ["plutil", "-convert", "json", "-o", "-", str(path)],
        check=True,
        capture_output=True,
    )
    return set(json.loads(result.stdout))


def _collect(
    repo: Path, target: str, resource: str
) -> tuple[dict[str, set[str]], dict[str, Path]]:
    """返回各 locale 的 key 集合与实际存在的文件路径。"""
    keys: dict[str, set[str]] = {}
    paths: dict[str, Path] = {}
    for locale in LOCALES:
        path = repo / target / f"{locale}.lproj" / f"{resource}.strings"
        if path.is_file():
            keys[locale] = parse_strings_keys(path)
            paths[locale] = path
        else:
            keys[locale] = set()
            paths[locale] = path  # 记下期望路径,便于报告"文件缺失"
    return keys, paths


def _compare(keys: dict[str, set[str]]) -> dict[str, list[str]]:
    """以三语种 union 为基准,返回每个 locale 相对 union 缺失的 key。"""
    union: set[str] = set()
    for ks in keys.values():
        union |= ks
    missing: dict[str, list[str]] = {}
    for locale, ks in keys.items():
        diff = sorted(union - ks)
        if diff:
            missing[locale] = diff
    return missing


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--repo-root",
        default="",
        help="仓库根目录(默认按本文件位置定位)",
    )
    parser.add_argument(
        "--quiet",
        action="store_true",
        help="仅在不一致时输出(OK 项静默)",
    )
    args = parser.parse_args()

    repo = Path(args.repo_root).resolve() if args.repo_root else Path(__file__).resolve().parents[2]
    if not repo.is_dir():
        raise SystemExit(f"Repo root not found: {repo}")

    fails: list[tuple[str, str, str]] = []  # (target, resource, 详情)
    ok_count = 0

    for target in TARGETS:
        for resource in TARGETS[target]:
            keys, paths = _collect(repo, target, resource)
            present = {loc for loc in LOCALES if paths[loc].is_file()}
            if not present:
                # 该 target 无此资源族,跳过(矩阵未声明即不应存在)。
                continue
            if len(present) != len(LOCALES):
                missing_locales = sorted(set(LOCALES) - present)
                fails.append(
                    (target, resource, f"missing files: {', '.join(missing_locales)}")
                )
                _print_fail(target, resource, [f"missing files: {', '.join(missing_locales)}"])
                continue
            missing = _compare(keys)
            if missing:
                details = [f"{loc} missing {len(ks)}: {', '.join(ks)}" for loc, ks in missing.items()]
                fails.append((target, resource, "; ".join(details)))
                _print_fail(target, resource, details)
            else:
                ok_count += 1
                if not args.quiet:
                    sample = next(iter(keys.values()))
                    print(f"OK   {target}/{resource}.strings ({len(sample)} keys)")

    total = ok_count + len(fails)
    print()
    if fails:
        print(f"Localization parity: FAIL ({len(fails)}/{total} resource(s) mismatched)")
        return 1
    print(f"Localization parity: OK ({ok_count}/{total} resource(s))")
    return 0


def _print_fail(target: str, resource: str, details: list[str]) -> None:
    print(f"FAIL {target}/{resource}.strings")
    for line in details:
        print(f"  {line}")


if __name__ == "__main__":
    raise SystemExit(main())
