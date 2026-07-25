#!/usr/bin/env python3
"""静态校验所有 .strings 资源在 en / zh-Hans / zh-Hant 之间 key 集合一致。

补充 `LocalizationContractTests` 的覆盖盲区:`InfoPlist.strings` 与 `AppShortcuts.strings`
的 key parity,并为 `Localizable.strings` 提供一个无需 xcodebuild 的快速静态校验。
只比对 key 集合;value 内容禁令(如"软删除")仍由 Swift 单元测试负责,二者互补。

退出码:全部一致为 0,任一资源不一致为 1。``--quiet`` 仅在出现不一致时输出。
"""

from __future__ import annotations

import argparse
from pathlib import Path

# target -> 该 target 下需校验的资源族(.strings 文件名前缀)。
TARGETS: dict[str, tuple[str, ...]] = {
    "timetracker": ("Localizable", "InfoPlist", "AppShortcuts"),
    "timetrackerWatchApp": ("Localizable", "InfoPlist"),
    "timetrackerWidgetExtension": ("Localizable", "InfoPlist"),
    "timetrackerLiveActivityExtension": ("Localizable", "InfoPlist"),
}

LOCALES: tuple[str, ...] = ("en", "zh-Hans", "zh-Hant")


def _read_quoted(text: str, i: int) -> tuple[str, int]:
    """从 text[i] == '"' 起读取带转义的引号串,返回(原始内容, 结束下标)。"""
    i += 1  # 跳过开头引号
    start = i
    while i < len(text):
        c = text[i]
        if c == "\\":
            i += 2
            continue
        if c == '"':
            return text[start:i], i + 1
        i += 1
    return text[start:i], i  # 未闭合,容错返回


def parse_strings_keys(text: str) -> set[str]:
    """解析 .strings 文本,返回 key 集合。

    兼容带引号/不带引号 key、带引号 value(``\\"`` 转义)、多行 value(累积到 ``;``);
    跳过 ``//`` 行注释与 ``/* */`` 块注释。
    """
    # 先剥离注释。.strings 的 value 为本地化文案,实务上不会包含 /* 或 //,可安全剥离。
    text = _strip_block_comments(text)
    text = _strip_line_comments(text)

    keys: set[str] = set()
    i, n = 0, len(text)
    while i < n:
        while i < n and text[i].isspace():
            i += 1
        if i >= n:
            break
        # 读取 key
        if text[i] == '"':
            key, i = _read_quoted(text, i)
        else:
            j = i
            while j < n and not text[j].isspace() and text[j] != "=":
                j += 1
            key, i = text[i:j], j
        # 跳过空白与 '='
        while i < n and text[i].isspace():
            i += 1
        if i < n and text[i] == "=":
            i += 1
        while i < n and text[i].isspace():
            i += 1
        # 跳过 value 直到 ';'（尊重引号)
        if i < n and text[i] == '"':
            _, i = _read_quoted(text, i)
            while i < n and text[i].isspace():
                i += 1
        else:
            while i < n and text[i] != ";":
                i += 1
        if i < n and text[i] == ";":
            i += 1
        if key:
            keys.add(key)
    return keys


def _strip_block_comments(text: str) -> str:
    out: list[str] = []
    i, n = 0, len(text)
    while i < n:
        if text[i : i + 2] == "/*":
            end = text.find("*/", i + 2)
            i = n if end == -1 else end + 2
        else:
            out.append(text[i])
            i += 1
    return "".join(out)


def _strip_line_comments(text: str) -> str:
    out: list[str] = []
    for line in text.splitlines(keepends=True):
        # 在引号外的 // 才是注释;实务 .strings 注释都在行首,简化处理即可。
        stripped = line.lstrip()
        if stripped.startswith("//"):
            continue
        out.append(line)
    return "".join(out)


def _collect(
    repo: Path, target: str, resource: str
) -> tuple[dict[str, set[str]], dict[str, Path]]:
    """返回各 locale 的 key 集合与实际存在的文件路径。"""
    keys: dict[str, set[str]] = {}
    paths: dict[str, Path] = {}
    for locale in LOCALES:
        path = repo / target / f"{locale}.lproj" / f"{resource}.strings"
        if path.is_file():
            keys[locale] = parse_strings_keys(path.read_text(encoding="utf-8"))
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