#!/usr/bin/env bash
set -euo pipefail

SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/timetracker-versioning-tests.XXXXXX")"
cleanup() {
  find "$TEMP_ROOT" -depth -delete 2>/dev/null || true
}
trap cleanup EXIT

export HOME="$TEMP_ROOT/home"
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME"

TEST_REPO="$TEMP_ROOT/repository"
mkdir -p "$TEST_REPO/.githooks" "$TEST_REPO/scripts" "$TEST_REPO/timetracker.xcodeproj"
cp "$SOURCE_ROOT/.githooks/pre-commit" "$TEST_REPO/.githooks/pre-commit"
cp "$SOURCE_ROOT/scripts/install_git_hooks.sh" "$TEST_REPO/scripts/install_git_hooks.sh"
cp "$SOURCE_ROOT/scripts/stage_commit_version.sh" "$TEST_REPO/scripts/stage_commit_version.sh"
chmod +x "$TEST_REPO/.githooks/pre-commit" "$TEST_REPO/scripts/install_git_hooks.sh" "$TEST_REPO/scripts/stage_commit_version.sh"

: > "$TEST_REPO/timetracker.xcodeproj/project.pbxproj"
for _ in {1..12}; do
  printf 'MARKETING_VERSION = 1.1.52;\nCURRENT_PROJECT_VERSION = 107;\n' >> "$TEST_REPO/timetracker.xcodeproj/project.pbxproj"
done
printf 'baseline\n' > "$TEST_REPO/checkpoint.txt"

git -C "$TEST_REPO" init -q
git -C "$TEST_REPO" config user.name "Version Hook Test"
git -C "$TEST_REPO" config user.email "version-hook-test@example.invalid"
git -C "$TEST_REPO" config commit.gpgsign false
git -C "$TEST_REPO" add .
git -C "$TEST_REPO" commit -q -m "baseline"

project_value_from_ref() {
  local ref="$1"
  local key="$2"
  local object
  if [[ "$ref" == ":" ]]; then
    object=":timetracker.xcodeproj/project.pbxproj"
  else
    object="${ref}:timetracker.xcodeproj/project.pbxproj"
  fi
  git -C "$TEST_REPO" show "$object" | sed -nE "s/.*$key = ([0-9.]+);/\\1/p" | sort -u
}

project_value_from_worktree() {
  local key="$1"
  sed -nE "s/.*$key = ([0-9.]+);/\\1/p" "$TEST_REPO/timetracker.xcodeproj/project.pbxproj" | sort -u
}

project_value_count_from_ref() {
  local ref="$1"
  local key="$2"
  local object
  if [[ "$ref" == ":" ]]; then
    object=":timetracker.xcodeproj/project.pbxproj"
  else
    object="${ref}:timetracker.xcodeproj/project.pbxproj"
  fi
  git -C "$TEST_REPO" show "$object" | grep -Ec "$key = [0-9.]+;"
}

assert_equal() {
  local expected="$1"
  local actual="$2"
  local label="$3"
  if [[ "$actual" != "$expected" ]]; then
    echo "$label: expected '$expected', got '$actual'" >&2
    exit 1
  fi
}

"$TEST_REPO/scripts/install_git_hooks.sh" >/dev/null
"$TEST_REPO/scripts/install_git_hooks.sh" --check >/dev/null
assert_equal ".githooks" "$(git -C "$TEST_REPO" config --local --get core.hooksPath)" "installed hooks path"

printf 'first\n' >> "$TEST_REPO/checkpoint.txt"
git -C "$TEST_REPO" add checkpoint.txt
git -C "$TEST_REPO" commit -q -m "first automatic bump"
assert_equal "1.1.53" "$(project_value_from_ref HEAD MARKETING_VERSION)" "first marketing version"
assert_equal "108" "$(project_value_from_ref HEAD CURRENT_PROJECT_VERSION)" "first build version"

printf 'second\n' >> "$TEST_REPO/checkpoint.txt"
git -C "$TEST_REPO" add checkpoint.txt
git -C "$TEST_REPO" commit -q -m "second automatic bump"
assert_equal "1.1.54" "$(project_value_from_ref HEAD MARKETING_VERSION)" "second marketing version"
assert_equal "109" "$(project_value_from_ref HEAD CURRENT_PROJECT_VERSION)" "second build version"

git -C "$TEST_REPO" commit --allow-empty -q -m "allow-empty automatic bump"
assert_equal "1.1.55" "$(project_value_from_ref HEAD MARKETING_VERSION)" "allow-empty marketing version"
assert_equal "110" "$(project_value_from_ref HEAD CURRENT_PROJECT_VERSION)" "allow-empty build version"

printf 'retry\n' >> "$TEST_REPO/checkpoint.txt"
git -C "$TEST_REPO" add checkpoint.txt
cat > "$TEST_REPO/.githooks/commit-msg" <<'HOOK'
#!/usr/bin/env bash
exit 1
HOOK
chmod +x "$TEST_REPO/.githooks/commit-msg"
if git -C "$TEST_REPO" commit -q -m "intentional commit-msg failure"; then
  echo "Commit unexpectedly succeeded while commit-msg was failing." >&2
  exit 1
fi
assert_equal "1.1.56" "$(project_value_from_ref : MARKETING_VERSION)" "idempotent staged marketing version"
assert_equal "111" "$(project_value_from_ref : CURRENT_PROJECT_VERSION)" "idempotent staged build version"
find "$TEST_REPO/.githooks/commit-msg" -delete
git -C "$TEST_REPO" commit -q -m "retry remains idempotent"
assert_equal "1.1.56" "$(project_value_from_ref HEAD MARKETING_VERSION)" "retry commit marketing version"
assert_equal "111" "$(project_value_from_ref HEAD CURRENT_PROJECT_VERSION)" "retry commit build version"

printf 'STAGED_USER_SETTING = YES;\n' >> "$TEST_REPO/timetracker.xcodeproj/project.pbxproj"
git -C "$TEST_REPO" add timetracker.xcodeproj/project.pbxproj
printf 'UNSTAGED_USER_SETTING = YES;\n' >> "$TEST_REPO/timetracker.xcodeproj/project.pbxproj"
printf 'preserve\n' >> "$TEST_REPO/checkpoint.txt"
git -C "$TEST_REPO" add checkpoint.txt
git -C "$TEST_REPO" commit -q -m "preserve unstaged project edit"
assert_equal "1.1.57" "$(project_value_from_ref HEAD MARKETING_VERSION)" "preserved-edit marketing version"
assert_equal "112" "$(project_value_from_ref HEAD CURRENT_PROJECT_VERSION)" "preserved-edit build version"
if ! git -C "$TEST_REPO" show HEAD:timetracker.xcodeproj/project.pbxproj | grep -q 'STAGED_USER_SETTING'; then
  echo "Staged project edit was lost from the commit." >&2
  exit 1
fi
if git -C "$TEST_REPO" show HEAD:timetracker.xcodeproj/project.pbxproj | grep -q 'UNSTAGED_USER_SETTING'; then
  echo "Unstaged project edit leaked into the commit." >&2
  exit 1
fi
if ! grep -q 'UNSTAGED_USER_SETTING' "$TEST_REPO/timetracker.xcodeproj/project.pbxproj"; then
  echo "Unstaged project edit was lost from the working tree." >&2
  exit 1
fi
assert_equal "1.1.57" "$(project_value_from_ref : MARKETING_VERSION)" "clean index marketing version"
assert_equal "112" "$(project_value_from_ref : CURRENT_PROJECT_VERSION)" "clean index build version"
assert_equal "1.1.57" "$(project_value_from_worktree MARKETING_VERSION)" "clean worktree marketing version"
assert_equal "112" "$(project_value_from_worktree CURRENT_PROJECT_VERSION)" "clean worktree build version"
assert_equal "12" "$(project_value_count_from_ref HEAD MARKETING_VERSION)" "marketing version configuration count"
assert_equal "12" "$(project_value_count_from_ref HEAD CURRENT_PROJECT_VERSION)" "build version configuration count"

git -C "$TEST_REPO" commit --amend --no-edit -q
assert_equal "1.1.58" "$(project_value_from_ref HEAD MARKETING_VERSION)" "amended marketing version"
assert_equal "113" "$(project_value_from_ref HEAD CURRENT_PROJECT_VERSION)" "amended build version"
if ! grep -q 'UNSTAGED_USER_SETTING' "$TEST_REPO/timetracker.xcodeproj/project.pbxproj"; then
  echo "Amend lost the unstaged project edit." >&2
  exit 1
fi

perl -0pi -e 's/MARKETING_VERSION = [0-9]+(?:\.[0-9]+){1,2};/MARKETING_VERSION = 9.9.99;/g; s/CURRENT_PROJECT_VERSION = [0-9]+;/CURRENT_PROJECT_VERSION = 999;/g' "$TEST_REPO/timetracker.xcodeproj/project.pbxproj"
git -C "$TEST_REPO" add timetracker.xcodeproj/project.pbxproj
if git -C "$TEST_REPO" hook run pre-commit >/dev/null 2>&1; then
  echo "Hook accepted an unexpected staged version." >&2
  exit 1
fi
assert_equal "9.9.99" "$(project_value_from_ref : MARKETING_VERSION)" "rejected staged marketing version remains unchanged"
assert_equal "999" "$(project_value_from_ref : CURRENT_PROJECT_VERSION)" "rejected staged build version remains unchanged"
assert_equal "9.9.99" "$(project_value_from_worktree MARKETING_VERSION)" "rejected worktree marketing version remains unchanged"
assert_equal "999" "$(project_value_from_worktree CURRENT_PROJECT_VERSION)" "rejected worktree build version remains unchanged"

echo "Versioning hook integration tests passed."
