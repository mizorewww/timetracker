#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_FILE="${PROJECT_FILE:-$ROOT_DIR/timetracker.xcodeproj/project.pbxproj}"

if [[ ! -f "$PROJECT_FILE" ]]; then
  echo "Project file not found: $PROJECT_FILE" >&2
  exit 1
fi

CURRENT_VERSION="$(grep -E -m 1 'MARKETING_VERSION = [0-9]+(\.[0-9]+){1,2};' "$PROJECT_FILE" | sed -E 's/.*MARKETING_VERSION = ([0-9]+(\.[0-9]+){1,2});.*/\1/')"
CURRENT_BUILD="$(grep -E -m 1 'CURRENT_PROJECT_VERSION = [0-9]+;' "$PROJECT_FILE" | sed -E 's/.*CURRENT_PROJECT_VERSION = ([0-9]+);.*/\1/')"

if [[ -z "$CURRENT_VERSION" || -z "$CURRENT_BUILD" ]]; then
  echo "Unable to read MARKETING_VERSION or CURRENT_PROJECT_VERSION from $PROJECT_FILE" >&2
  exit 1
fi

IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"
PATCH="${PATCH:-0}"
NEXT_VERSION="$MAJOR.$MINOR.$((PATCH + 1))"
NEXT_BUILD="$((CURRENT_BUILD + 1))"

perl -0pi -e "s/MARKETING_VERSION = [0-9]+(?:\\.[0-9]+){1,2};/MARKETING_VERSION = $NEXT_VERSION;/g; s/CURRENT_PROJECT_VERSION = [0-9]+;/CURRENT_PROJECT_VERSION = $NEXT_BUILD;/g" "$PROJECT_FILE"

echo "Bumped version: $CURRENT_VERSION ($CURRENT_BUILD) -> $NEXT_VERSION ($NEXT_BUILD)"
