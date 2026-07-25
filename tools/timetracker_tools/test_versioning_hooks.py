#!/usr/bin/env python3
"""版本钩子集成测试。

在隔离 HOME 的临时 Git 仓库中安装真实 pre-commit 钩子(直调本 venv 的 Python 模块),
验证连续提交与 --allow-empty / --amend 递增、commit-msg 失败重试幂等、12 组版本一致、
未暂存 project 修改不会泄漏进 commit,以及异常版本状态会在修改前被拒绝。
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from timetracker_tools.cli_utils import run

PROJECT_REL = "timetracker.xcodeproj/project.pbxproj"
MARKETING_RE = re.compile(rb"MARKETING_VERSION = ([0-9.]+);")
BUILD_RE = re.compile(rb"CURRENT_PROJECT_VERSION = ([0-9.]+);")
MARKETING_COUNT_RE = re.compile(rb"MARKETING_VERSION = [0-9.]+;")
BUILD_COUNT_RE = re.compile(rb"CURRENT_PROJECT_VERSION = [0-9.]+;")


def assert_equal(expected: str, actual: str, label: str) -> None:
    if actual != expected:
        raise SystemExit(f"{label}: expected '{expected}', got '{actual}'")


def make_env(home: Path) -> dict[str, str]:
    env = dict(os.environ)
    env["HOME"] = str(home)
    env["GIT_CONFIG_GLOBAL"] = "/dev/null"
    env["GIT_CONFIG_NOSYSTEM"] = "1"
    return env


def git(repo: Path, *args: str, env: dict[str, str], check: bool = True) -> subprocess.CompletedProcess:
    return run(["git", "-C", str(repo), *args], check=check, capture_output=True, env=env)


def git_show(repo: Path, ref: str, env: dict[str, str]) -> bytes:
    spec = f":{PROJECT_REL}" if ref == ":" else f"{ref}:{PROJECT_REL}"
    result = git(repo, "show", spec, env=env, check=True)
    return result.stdout.encode() if isinstance(result.stdout, str) else result.stdout


def unique_value(data: bytes, regex: re.Pattern[bytes]) -> str:
    values = sorted({m.group(1).decode() for m in regex.finditer(data)})
    return values[0] if values else ""


def project_value_from_ref(repo: Path, ref: str, key: str, env: dict[str, str]) -> str:
    data = git_show(repo, ref, env)
    regex = MARKETING_RE if key == "MARKETING_VERSION" else BUILD_RE
    return unique_value(data, regex)


def project_value_count_from_ref(repo: Path, ref: str, key: str, env: dict[str, str]) -> int:
    data = git_show(repo, ref, env)
    regex = MARKETING_COUNT_RE if key == "MARKETING_VERSION" else BUILD_COUNT_RE
    return len(regex.findall(data))


def project_value_from_worktree(repo: Path, key: str) -> str:
    data = (repo / PROJECT_REL).read_bytes()
    regex = MARKETING_RE if key == "MARKETING_VERSION" else BUILD_RE
    return unique_value(data, regex)


def write_pre_commit_hook(temp_repo: Path) -> None:
    hooks_dir = temp_repo / ".githooks"
    hooks_dir.mkdir(parents=True, exist_ok=True)
    hook = hooks_dir / "pre-commit"
    hook.write_text(
        "#!/usr/bin/env bash\n"
        "set -euo pipefail\n"
        f'exec "{sys.executable}" -m timetracker_tools.stage_commit_version '
        f'--repo-root "{temp_repo}" "$@"\n'
    )
    hook.chmod(0o755)


def write_project_file(temp_repo: Path, *, base_lines: int = 12) -> None:
    project = temp_repo / PROJECT_REL
    project.parent.mkdir(parents=True, exist_ok=True)
    content = "MARKETING_VERSION = 1.1.52;\nCURRENT_PROJECT_VERSION = 107;\n" * base_lines
    project.write_text(content)


def main() -> int:
    source_root = Path(__file__).resolve().parents[2]
    temp_root = Path(tempfile.mkdtemp(prefix="timetracker-versioning-tests."))
    try:
        home = temp_root / "home"
        home.mkdir(parents=True, exist_ok=True)
        env = make_env(home)

        test_repo = temp_root / "repository"
        test_repo.mkdir(parents=True, exist_ok=True)
        write_project_file(test_repo)
        (test_repo / "checkpoint.txt").write_text("baseline\n")
        write_pre_commit_hook(test_repo)

        git(test_repo, "init", "-q", env=env)
        git(test_repo, "config", "user.name", "Version Hook Test", env=env)
        git(test_repo, "config", "user.email", "version-hook-test@example.invalid", env=env)
        git(test_repo, "config", "commit.gpgsign", "false", env=env)
        git(test_repo, "add", ".", env=env)
        git(test_repo, "commit", "-q", "-m", "baseline", env=env)

        # 安装钩子(直接调本模块,等价于 scripts/install_git_hooks.sh 的 wrapper 落到 Python 实现)。
        run([sys.executable, "-m", "timetracker_tools.install_git_hooks", "--repo-root", str(test_repo)],
            check=True)
        run([sys.executable, "-m", "timetracker_tools.install_git_hooks", "--repo-root", str(test_repo), "--check"],
            check=True)
        assert_equal(
            ".githooks",
            git(test_repo, "config", "--local", "--get", "core.hooksPath", env=env).stdout.strip(),
            "installed hooks path",
        )

        def append_checkpoint(line: str) -> None:
            with (test_repo / "checkpoint.txt").open("a") as handle:
                handle.write(line + "\n")

        def commit(message: str, *, allow_empty: bool = False, amend: bool = False) -> None:
            args = ["commit", "-q", "-m", message]
            if allow_empty:
                args.insert(1, "--allow-empty")
            if amend:
                args += ["--amend", "--no-edit"]
            git(test_repo, *args, env=env)

        append_checkpoint("first")
        git(test_repo, "add", "checkpoint.txt", env=env)
        commit("first automatic bump")
        assert_equal("1.1.53", project_value_from_ref(test_repo, "HEAD", "MARKETING_VERSION", env), "first marketing version")
        assert_equal("108", project_value_from_ref(test_repo, "HEAD", "CURRENT_PROJECT_VERSION", env), "first build version")

        append_checkpoint("second")
        git(test_repo, "add", "checkpoint.txt", env=env)
        commit("second automatic bump")
        assert_equal("1.1.54", project_value_from_ref(test_repo, "HEAD", "MARKETING_VERSION", env), "second marketing version")
        assert_equal("109", project_value_from_ref(test_repo, "HEAD", "CURRENT_PROJECT_VERSION", env), "second build version")

        commit("allow-empty automatic bump", allow_empty=True)
        assert_equal("1.1.55", project_value_from_ref(test_repo, "HEAD", "MARKETING_VERSION", env), "allow-empty marketing version")
        assert_equal("110", project_value_from_ref(test_repo, "HEAD", "CURRENT_PROJECT_VERSION", env), "allow-empty build version")

        # commit-msg 失败时,已暂存的版本应保持幂等,重试不累加。
        append_checkpoint("retry")
        git(test_repo, "add", "checkpoint.txt", env=env)
        commit_msg = test_repo / ".githooks" / "commit-msg"
        commit_msg.write_text("#!/usr/bin/env bash\nexit 1\n")
        commit_msg.chmod(0o755)
        if git(test_repo, "commit", "-q", "-m", "intentional commit-msg failure", env=env, check=False).returncode == 0:
            raise SystemExit("Commit unexpectedly succeeded while commit-msg was failing.")
        assert_equal("1.1.56", project_value_from_ref(test_repo, ":", "MARKETING_VERSION", env), "idempotent staged marketing version")
        assert_equal("111", project_value_from_ref(test_repo, ":", "CURRENT_PROJECT_VERSION", env), "idempotent staged build version")
        commit_msg.unlink()
        commit("retry remains idempotent")
        assert_equal("1.1.56", project_value_from_ref(test_repo, "HEAD", "MARKETING_VERSION", env), "retry commit marketing version")
        assert_equal("111", project_value_from_ref(test_repo, "HEAD", "CURRENT_PROJECT_VERSION", env), "retry commit build version")

        # 已暂存 project 修改保留进 commit;未暂存 project 修改不泄漏。
        with (test_repo / PROJECT_REL).open("a") as handle:
            handle.write("STAGED_USER_SETTING = YES;\n")
        git(test_repo, "add", PROJECT_REL, env=env)
        with (test_repo / PROJECT_REL).open("a") as handle:
            handle.write("UNSTAGED_USER_SETTING = YES;\n")
        append_checkpoint("preserve")
        git(test_repo, "add", "checkpoint.txt", env=env)
        commit("preserve unstaged project edit")
        assert_equal("1.1.57", project_value_from_ref(test_repo, "HEAD", "MARKETING_VERSION", env), "preserved-edit marketing version")
        assert_equal("112", project_value_from_ref(test_repo, "HEAD", "CURRENT_PROJECT_VERSION", env), "preserved-edit build version")
        head_bytes = git_show(test_repo, "HEAD", env)
        if b"STAGED_USER_SETTING" not in head_bytes:
            raise SystemExit("Staged project edit was lost from the commit.")
        if b"UNSTAGED_USER_SETTING" in head_bytes:
            raise SystemExit("Unstaged project edit leaked into the commit.")
        if b"UNSTAGED_USER_SETTING" not in (test_repo / PROJECT_REL).read_bytes():
            raise SystemExit("Unstaged project edit was lost from the working tree.")
        assert_equal("1.1.57", project_value_from_ref(test_repo, ":", "MARKETING_VERSION", env), "clean index marketing version")
        assert_equal("112", project_value_from_ref(test_repo, ":", "CURRENT_PROJECT_VERSION", env), "clean index build version")
        assert_equal("1.1.57", project_value_from_worktree(test_repo, "MARKETING_VERSION"), "clean worktree marketing version")
        assert_equal("112", project_value_from_worktree(test_repo, "CURRENT_PROJECT_VERSION"), "clean worktree build version")
        assert_equal("12", str(project_value_count_from_ref(test_repo, "HEAD", "MARKETING_VERSION", env)), "marketing version configuration count")
        assert_equal("12", str(project_value_count_from_ref(test_repo, "HEAD", "CURRENT_PROJECT_VERSION", env)), "build version configuration count")

        commit("amend automatic bump", amend=True)
        assert_equal("1.1.58", project_value_from_ref(test_repo, "HEAD", "MARKETING_VERSION", env), "amended marketing version")
        assert_equal("113", project_value_from_ref(test_repo, "HEAD", "CURRENT_PROJECT_VERSION", env), "amended build version")
        if b"UNSTAGED_USER_SETTING" not in (test_repo / PROJECT_REL).read_bytes():
            raise SystemExit("Amend lost the unstaged project edit.")

        # 异常版本应在修改前被拒绝,index 与 worktree 都保持不变。
        (test_repo / PROJECT_REL).write_text(
            (test_repo / PROJECT_REL).read_text()
            .replace("MARKETING_VERSION = 1.1.58;", "MARKETING_VERSION = 9.9.99;")
            .replace("CURRENT_PROJECT_VERSION = 113;", "CURRENT_PROJECT_VERSION = 999;")
        )
        git(test_repo, "add", PROJECT_REL, env=env)
        if git(test_repo, "hook", "run", "pre-commit", env=env, check=False).returncode == 0:
            raise SystemExit("Hook accepted an unexpected staged version.")
        assert_equal("9.9.99", project_value_from_ref(test_repo, ":", "MARKETING_VERSION", env), "rejected staged marketing version remains unchanged")
        assert_equal("999", project_value_from_ref(test_repo, ":", "CURRENT_PROJECT_VERSION", env), "rejected staged build version remains unchanged")
        assert_equal("9.9.99", project_value_from_worktree(test_repo, "MARKETING_VERSION"), "rejected worktree marketing version remains unchanged")
        assert_equal("999", project_value_from_worktree(test_repo, "CURRENT_PROJECT_VERSION"), "rejected worktree build version remains unchanged")

        print("Versioning hook integration tests passed.")
        return 0
    finally:
        shutil.rmtree(temp_root, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())