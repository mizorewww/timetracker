#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(git rev-parse --show-toplevel)"
PROJECT_RELATIVE_PATH="${PROJECT_RELATIVE_PATH:-timetracker.xcodeproj/project.pbxproj}"
PROJECT_FILE="$ROOT_DIR/$PROJECT_RELATIVE_PATH"

if [[ ! -f "$PROJECT_FILE" ]]; then
  echo "Project file not found: $PROJECT_FILE" >&2
  exit 1
fi

if ! git -C "$ROOT_DIR" rev-parse --verify HEAD >/dev/null 2>&1; then
  echo "Automatic version staging requires an existing HEAD commit." >&2
  exit 1
fi

if ! git -C "$ROOT_DIR" cat-file -e "HEAD:$PROJECT_RELATIVE_PATH" 2>/dev/null; then
  echo "Project file is not present in HEAD: $PROJECT_RELATIVE_PATH" >&2
  exit 1
fi

if ! git -C "$ROOT_DIR" cat-file -e ":$PROJECT_RELATIVE_PATH" 2>/dev/null; then
  echo "Project file is not present in the Git index: $PROJECT_RELATIVE_PATH" >&2
  exit 1
fi

TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/timetracker-version-hook.XXXXXX")"
cleanup() {
  find "$TEMP_ROOT" -depth -delete 2>/dev/null || true
}
trap cleanup EXIT

HEAD_PROJECT="$TEMP_ROOT/head.pbxproj"
INDEX_PROJECT="$TEMP_ROOT/index.pbxproj"
git -C "$ROOT_DIR" show "HEAD:$PROJECT_RELATIVE_PATH" > "$HEAD_PROJECT"
git -C "$ROOT_DIR" show ":$PROJECT_RELATIVE_PATH" > "$INDEX_PROJECT"

unique_marketing_version() {
  local project_file="$1"
  local values
  local count
  values="$(grep -Eo 'MARKETING_VERSION = [0-9]+(\.[0-9]+){1,2};' "$project_file" | sed -E 's/MARKETING_VERSION = ([0-9]+(\.[0-9]+){1,2});/\1/' | sort -u || true)"
  count="$(printf '%s\n' "$values" | awk 'NF { count += 1 } END { print count + 0 }')"
  if [[ "$count" != "1" ]]; then
    echo "Expected one consistent MARKETING_VERSION in $project_file; found $count." >&2
    return 1
  fi
  printf '%s' "$values"
}

unique_build_version() {
  local project_file="$1"
  local values
  local count
  values="$(grep -Eo 'CURRENT_PROJECT_VERSION = [0-9]+;' "$project_file" | sed -E 's/CURRENT_PROJECT_VERSION = ([0-9]+);/\1/' | sort -u || true)"
  count="$(printf '%s\n' "$values" | awk 'NF { count += 1 } END { print count + 0 }')"
  if [[ "$count" != "1" ]]; then
    echo "Expected one consistent CURRENT_PROJECT_VERSION in $project_file; found $count." >&2
    return 1
  fi
  printf '%s' "$values"
}

set_project_version() {
  local project_file="$1"
  local marketing_version="$2"
  local build_version="$3"
  perl -0pi -e "s/MARKETING_VERSION = [0-9]+(?:\\.[0-9]+){1,2};/MARKETING_VERSION = $marketing_version;/g; s/CURRENT_PROJECT_VERSION = [0-9]+;/CURRENT_PROJECT_VERSION = $build_version;/g" "$project_file"
}

HEAD_VERSION="$(unique_marketing_version "$HEAD_PROJECT")"
HEAD_BUILD="$(unique_build_version "$HEAD_PROJECT")"
INDEX_VERSION="$(unique_marketing_version "$INDEX_PROJECT")"
INDEX_BUILD="$(unique_build_version "$INDEX_PROJECT")"
WORKTREE_VERSION="$(unique_marketing_version "$PROJECT_FILE")"
WORKTREE_BUILD="$(unique_build_version "$PROJECT_FILE")"
IFS='.' read -r MAJOR MINOR PATCH <<< "$HEAD_VERSION"
PATCH="${PATCH:-0}"
NEXT_VERSION="$MAJOR.$MINOR.$((PATCH + 1))"
NEXT_BUILD="$((HEAD_BUILD + 1))"

valid_prepared_pair() {
  local marketing_version="$1"
  local build_version="$2"
  [[ "$marketing_version" == "$HEAD_VERSION" && "$build_version" == "$HEAD_BUILD" ]] ||
    [[ "$marketing_version" == "$NEXT_VERSION" && "$build_version" == "$NEXT_BUILD" ]]
}

if ! valid_prepared_pair "$INDEX_VERSION" "$INDEX_BUILD"; then
  echo "Refusing unexpected staged version $INDEX_VERSION ($INDEX_BUILD); expected $HEAD_VERSION ($HEAD_BUILD) or $NEXT_VERSION ($NEXT_BUILD)." >&2
  exit 1
fi

if ! valid_prepared_pair "$WORKTREE_VERSION" "$WORKTREE_BUILD"; then
  echo "Refusing unexpected working-tree version $WORKTREE_VERSION ($WORKTREE_BUILD); expected $HEAD_VERSION ($HEAD_BUILD) or $NEXT_VERSION ($NEXT_BUILD)." >&2
  exit 1
fi

# Preserve all already-staged project edits while changing only version fields.
set_project_version "$INDEX_PROJECT" "$NEXT_VERSION" "$NEXT_BUILD"
unique_marketing_version "$INDEX_PROJECT" >/dev/null
unique_build_version "$INDEX_PROJECT" >/dev/null

INDEX_ENTRY_COUNT="$(git -C "$ROOT_DIR" ls-files -s -- "$PROJECT_RELATIVE_PATH" | awk '$3 == 0 { count += 1 } END { print count + 0 }')"
INDEX_MODE="$(git -C "$ROOT_DIR" ls-files -s -- "$PROJECT_RELATIVE_PATH" | awk '$3 == 0 { print $1; exit }')"
if [[ "$INDEX_ENTRY_COUNT" != "1" || -z "$INDEX_MODE" ]]; then
  echo "Project file has an unresolved or invalid index entry: $PROJECT_RELATIVE_PATH" >&2
  exit 1
fi

INDEX_BLOB="$(git -C "$ROOT_DIR" hash-object -w -- "$INDEX_PROJECT")"
git -C "$ROOT_DIR" update-index --cacheinfo "$INDEX_MODE" "$INDEX_BLOB" "$PROJECT_RELATIVE_PATH"

# Keep the working copy aligned without staging unrelated working-tree edits.
set_project_version "$PROJECT_FILE" "$NEXT_VERSION" "$NEXT_BUILD"
unique_marketing_version "$PROJECT_FILE" >/dev/null
unique_build_version "$PROJECT_FILE" >/dev/null

echo "Prepared commit version: $HEAD_VERSION ($HEAD_BUILD) -> $NEXT_VERSION ($NEXT_BUILD)"
