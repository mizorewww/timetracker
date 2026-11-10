#!/usr/bin/env python3
"""静态校验所有 .xcstrings String Catalog 资源在 en / zh-Hans / zh-Hant 之间词条完整一致。

统一校验 `Localizable.xcstrings`、`InfoPlist.xcstrings` 与 `AppShortcuts.xcstrings`
的 key parity 与翻译完整性，无需运行 xcodebuild。

退出码：全部一致为 0，任一资源缺失或不一致为 1。`--quiet` 仅在出现不一致时输出。
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

TARGETS: dict[str, tuple[str, ...]] = {
    "timetracker": ("Localizable", "InfoPlist", "AppShortcuts"),
    "timetrackerWatchApp": ("Localizable", "InfoPlist"),
    "timetrackerWidgetExtension": ("Localizable", "InfoPlist"),
    "timetrackerLiveActivityExtension": ("Localizable", "InfoPlist"),
}

LOCALES: tuple[str, ...] = ("en", "zh-Hans", "zh-Hant")


def check_xcstrings(path: Path) -> tuple[int, dict[str, list[str]]]:
    """解析 .xcstrings JSON，返回 (总 key 数, 各 locale 缺失译文的 key 列表)。"""
    data = json.loads(path.read_text(encoding="utf-8"))
    strings = data.get("strings", {})
    if not isinstance(strings, dict):
        raise ValueError(f"Invalid 'strings' dictionary in {path}")

    missing: dict[str, list[str]] = {loc: [] for loc in LOCALES}
    for key in sorted(strings.keys()):
        entry = strings[key]
        localizations = entry.get("localizations", {}) if isinstance(entry, dict) else {}
        for loc in LOCALES:
            loc_entry = localizations.get(loc, {})
            string_unit = loc_entry.get("stringUnit", {}) if isinstance(loc_entry, dict) else {}
            value = string_unit.get("value")
            if not isinstance(value, str):
                missing[loc].append(key)

    return len(strings), {loc: ks for loc, ks in missing.items() if ks}


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

    fails: list[tuple[str, str, str]] = []
    ok_count = 0

    for target, resources in TARGETS.items():
        for resource in resources:
            path = repo / target / f"{resource}.xcstrings"
            if not path.is_file():
                fails.append((target, resource, f"missing file: {path.relative_to(repo)}"))
                _print_fail(target, resource, [f"missing file: {path.relative_to(repo)}"])
                continue
            key_count, missing = check_xcstrings(path)
            if missing:
                details = [f"{loc} missing {len(ks)}: {', '.join(ks)}" for loc, ks in missing.items()]
                fails.append((target, resource, "; ".join(details)))
                _print_fail(target, resource, details)
            else:
                ok_count += 1
                if not args.quiet:
                    print(f"OK   {target}/{resource}.xcstrings ({key_count} keys)")

    total = ok_count + len(fails)
    print()
    if fails:
        print(f"Localization parity: FAIL ({len(fails)}/{total} resource(s) mismatched)")
        return 1
    print(f"Localization parity: OK ({ok_count}/{total} resource(s))")
    return 0


def _print_fail(target: str, resource: str, details: list[str]) -> None:
    print(f"FAIL {target}/{resource}.xcstrings")
    for line in details:
        print(f"  {line}")


if __name__ == "__main__":
    raise SystemExit(main())
