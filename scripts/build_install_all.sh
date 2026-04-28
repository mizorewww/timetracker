#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="${PROJECT:-$ROOT_DIR/timetracker.xcodeproj}"
SCHEME="${SCHEME:-timetracker}"
CONFIGURATION="${CONFIGURATION:-Debug}"
TEAM_ID="${DEVELOPMENT_TEAM:-LT98S43NKA}"
PRODUCT_NAME="${PRODUCT_NAME:-timetracker}"
BUNDLE_ID="${BUNDLE_ID:-me.mezorewww.timetracker}"
APPLICATIONS_DIR="${APPLICATIONS_DIR:-/Applications}"
DEVICE_TIMEOUT="${DEVICE_TIMEOUT:-30}"
LAUNCH_AFTER_INSTALL="${LAUNCH_AFTER_INSTALL:-0}"
ALLOW_DEVICE_FAILURES="${ALLOW_DEVICE_FAILURES:-0}"

BUILD_ROOT="$ROOT_DIR/build/Install"
DERIVED_DATA="$BUILD_ROOT/DerivedData"
IOS_PRODUCTS="$DERIVED_DATA/Build/Products/${CONFIGURATION}-iphoneos"
MAC_PRODUCTS="$DERIVED_DATA/Build/Products/${CONFIGURATION}"
IOS_APP="$IOS_PRODUCTS/${PRODUCT_NAME}.app"
MAC_APP="$MAC_PRODUCTS/${PRODUCT_NAME}.app"
MAC_DEST="$APPLICATIONS_DIR/${PRODUCT_NAME}.app"
DEVICE_FAILURES=()

mkdir -p "$BUILD_ROOT" "$DERIVED_DATA"

run_xcodebuild() {
  xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED_DATA" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    CODE_SIGN_STYLE=Automatic \
    -allowProvisioningUpdates \
    "$@"
}

require_app_bundle() {
  local app_path="$1"
  local label="$2"

  if [[ ! -d "$app_path" ]]; then
    echo "Expected $label app bundle was not found: $app_path" >&2
    exit 1
  fi
}

available_ios_devices_json() {
  local json_path="$1"
  local filter
  filter="State BEGINSWITH 'available' AND hardwareProperties.platform == 'iOS' AND hardwareProperties.reality == 'physical' AND deviceProperties.developerModeStatus == 'enabled'"

  xcrun devicectl list devices \
    --filter "$filter" \
    --timeout "$DEVICE_TIMEOUT" \
    --json-output "$json_path"
}

install_on_available_devices() {
  local devices_json
  devices_json="$(mktemp "${TMPDIR:-/tmp}/timetracker-devices.XXXXXX.json")"
  trap 'rm -f "$devices_json"; trap - RETURN' RETURN

  echo "==> Looking for available physical iOS/iPadOS development devices"
  available_ios_devices_json "$devices_json" >/dev/null

  local devices=()
  while IFS= read -r line; do
    devices+=("$line")
  done < <(/usr/bin/python3 - "$devices_json" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    payload = json.load(handle)

for device in payload.get("result", {}).get("devices", []):
    identifier = device.get("identifier")
    name = device.get("deviceProperties", {}).get("name", "Unknown Device")
    if identifier:
        print(f"{identifier}\t{name}")
PY
)

  if [[ ${#devices[@]} -eq 0 ]]; then
    echo "No available physical iOS/iPadOS development devices found. Skipping device install."
    return 0
  fi

  for entry in "${devices[@]}"; do
    local device_id="${entry%%$'\t'*}"
    local device_name="${entry#*$'\t'}"

    echo "==> Installing on $device_name ($device_id)"
    if xcrun devicectl device install app --device "$device_id" "$IOS_APP"; then
      if [[ "$LAUNCH_AFTER_INSTALL" == "1" ]]; then
        echo "==> Launching on $device_name"
        xcrun devicectl device process launch --device "$device_id" "$BUNDLE_ID" || DEVICE_FAILURES+=("$device_name launch")
      fi
    else
      DEVICE_FAILURES+=("$device_name install")
    fi
  done
}

report_device_failures() {
  if [[ ${#DEVICE_FAILURES[@]} -gt 0 ]]; then
    echo "Some device operations failed:" >&2
    printf '  - %s\n' "${DEVICE_FAILURES[@]}" >&2
    if [[ "$ALLOW_DEVICE_FAILURES" != "1" ]]; then
      exit 1
    fi
  fi
}

copy_mac_app_to_applications() {
  require_app_bundle "$MAC_APP" "macOS"

  if [[ -z "$PRODUCT_NAME" || "$MAC_DEST" != "$APPLICATIONS_DIR"/*.app ]]; then
    echo "Refusing to replace an unsafe Applications path: $MAC_DEST" >&2
    exit 1
  fi

  local temp_dest
  temp_dest="$APPLICATIONS_DIR/.${PRODUCT_NAME}.app.installing.$$"

  echo "==> Copying macOS app to $MAC_DEST"
  rm -rf "$temp_dest"
  ditto "$MAC_APP" "$temp_dest"
  rm -rf "$MAC_DEST"
  mv "$temp_dest" "$MAC_DEST"
  codesign --verify --deep --strict --verbose=2 "$MAC_DEST"
}

echo "==> Building iOS/iPadOS app ($CONFIGURATION, team $TEAM_ID)"
run_xcodebuild -sdk iphoneos -destination "generic/platform=iOS" build
require_app_bundle "$IOS_APP" "iOS"
install_on_available_devices

echo "==> Building macOS app ($CONFIGURATION, team $TEAM_ID)"
run_xcodebuild -destination "generic/platform=macOS" build
copy_mac_app_to_applications
report_device_failures

cat <<EOF

Done.
iOS app:       $IOS_APP
macOS app:     $MAC_DEST
Derived data:  $DERIVED_DATA

Tips:
  CONFIGURATION=Release scripts/build_install_all.sh
  LAUNCH_AFTER_INSTALL=1 scripts/build_install_all.sh
  ALLOW_DEVICE_FAILURES=1 scripts/build_install_all.sh

EOF
