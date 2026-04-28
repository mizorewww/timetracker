#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${TARGET_BUILD_DIR:-}" || -z "${UNLOCALIZED_RESOURCES_FOLDER_PATH:-}" ]]; then
  echo "Build info skipped: TARGET_BUILD_DIR or UNLOCALIZED_RESOURCES_FOLDER_PATH is missing."
  exit 0
fi

SRCROOT="${SRCROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
RESOURCE_DIR="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH"
PLIST_PATH="$RESOURCE_DIR/AppBuildInfo.plist"

git_value() {
  git -C "$SRCROOT" "$@" 2>/dev/null || true
}

BRANCH="$(git_value branch --show-current)"
if [[ -z "$BRANCH" ]]; then
  BRANCH="$(git_value rev-parse --abbrev-ref HEAD)"
fi
if [[ -z "$BRANCH" || "$BRANCH" == "HEAD" ]]; then
  BRANCH="detached"
fi

COMMIT_FULL="$(git_value rev-parse HEAD)"
COMMIT_SHORT="$(git_value rev-parse --short=12 HEAD)"
if [[ -z "$COMMIT_FULL" ]]; then
  COMMIT_FULL="unknown"
fi
if [[ -z "$COMMIT_SHORT" ]]; then
  COMMIT_SHORT="unknown"
fi

DIRTY="false"
if ! git -C "$SRCROOT" diff --quiet --ignore-submodules -- 2>/dev/null || \
   ! git -C "$SRCROOT" diff --cached --quiet --ignore-submodules -- 2>/dev/null; then
  DIRTY="true"
fi

mkdir -p "$RESOURCE_DIR"

GIT_BRANCH="$BRANCH" \
GIT_COMMIT_FULL="$COMMIT_FULL" \
GIT_COMMIT_SHORT="$COMMIT_SHORT" \
GIT_DIRTY="$DIRTY" \
BUILD_DATE="$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
/usr/bin/python3 - "$PLIST_PATH" <<'PY'
import os
import plistlib
import sys

payload = {
    "GitBranch": os.environ["GIT_BRANCH"],
    "GitCommitFull": os.environ["GIT_COMMIT_FULL"],
    "GitCommitShort": os.environ["GIT_COMMIT_SHORT"],
    "GitDirty": os.environ["GIT_DIRTY"],
    "BuildDate": os.environ["BUILD_DATE"],
}

with open(sys.argv[1], "wb") as handle:
    plistlib.dump(payload, handle, sort_keys=True)
PY

echo "Wrote build info: $PLIST_PATH ($BRANCH $COMMIT_SHORT dirty=$DIRTY)"
