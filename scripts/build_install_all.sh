#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="${PROJECT:-$ROOT_DIR/timetracker.xcodeproj}"
SCHEME="${SCHEME:-timetracker}"
WATCH_SCHEME="${WATCH_SCHEME:-timetrackerWatchApp}"
CONFIGURATION="${CONFIGURATION:-Debug}"
TEAM_ID="${DEVELOPMENT_TEAM:-LT98S43NKA}"
PRODUCT_NAME="${PRODUCT_NAME:-timetracker}"
WATCH_PRODUCT_NAME="${WATCH_PRODUCT_NAME:-timetrackerWatchApp}"
BUNDLE_ID="${BUNDLE_ID:-me.mezorewww.timetracker}"
APPLICATIONS_DIR="${APPLICATIONS_DIR:-/Applications}"
DEVICE_TIMEOUT="${DEVICE_TIMEOUT:-30}"
LAUNCH_AFTER_INSTALL="${LAUNCH_AFTER_INSTALL:-0}"
ALLOW_DEVICE_FAILURES="${ALLOW_DEVICE_FAILURES:-0}"
ALLOW_INVALID_WATCH_PROFILE="${ALLOW_INVALID_WATCH_PROFILE:-0}"
BUILD_WATCH_FOR_PHYSICAL="${BUILD_WATCH_FOR_PHYSICAL:-0}"

BUILD_ROOT="$ROOT_DIR/build/Install"
DERIVED_DATA="$BUILD_ROOT/DerivedData"
IOS_PRODUCTS="$DERIVED_DATA/Build/Products/${CONFIGURATION}-iphoneos"
WATCH_PRODUCTS="$DERIVED_DATA/Build/Products/${CONFIGURATION}-watchos"
MAC_PRODUCTS="$DERIVED_DATA/Build/Products/${CONFIGURATION}"
IOS_APP="$IOS_PRODUCTS/${PRODUCT_NAME}.app"
WATCH_APP="$WATCH_PRODUCTS/${WATCH_PRODUCT_NAME}.app"
IOS_EMBEDDED_WATCH_APP="$IOS_APP/Watch/${WATCH_PRODUCT_NAME}.app"
MAC_APP="$MAC_PRODUCTS/${PRODUCT_NAME}.app"
MAC_DEST="$APPLICATIONS_DIR/${PRODUCT_NAME}.app"
DEVICE_FAILURES=()

mkdir -p "$BUILD_ROOT" "$DERIVED_DATA"

run_xcodebuild() {
  local scheme="$1"
  shift

  xcodebuild \
    -project "$PROJECT" \
    -scheme "$scheme" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED_DATA" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    CODE_SIGN_STYLE=Automatic \
    -allowProvisioningUpdates \
    -allowProvisioningDeviceRegistration \
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

report_embedded_watch_content() {
  if [[ -d "$IOS_EMBEDDED_WATCH_APP" ]]; then
    echo "==> iOS app includes Watch companion: $IOS_EMBEDDED_WATCH_APP"
  else
    echo "Warning: iOS app does not include embedded Watch companion at $IOS_EMBEDDED_WATCH_APP" >&2
  fi
}

profile_platforms() {
  local app_path="$1"
  local profile_path="$app_path/embedded.mobileprovision"
  local plist_path

  if [[ ! -f "$profile_path" ]]; then
    echo ""
    return 0
  fi

  plist_path="$(mktemp "${TMPDIR:-/tmp}/timetracker-profile.XXXXXX.plist")"
  if security cms -D -i "$profile_path" >"$plist_path" 2>/dev/null; then
    /usr/libexec/PlistBuddy -c 'Print :Platform' "$plist_path" 2>/dev/null | tr '\n' ' '
  fi
  rm -f "$plist_path"
}

profile_provisioned_devices() {
  local app_path="$1"
  local profile_path="$app_path/embedded.mobileprovision"
  local plist_path

  if [[ ! -f "$profile_path" ]]; then
    return 0
  fi

  plist_path="$(mktemp "${TMPDIR:-/tmp}/timetracker-profile-devices.XXXXXX.plist")"
  if security cms -D -i "$profile_path" >"$plist_path" 2>/dev/null; then
    /usr/libexec/PlistBuddy -c 'Print :ProvisionedDevices' "$plist_path" 2>/dev/null || true
  fi
  rm -f "$plist_path"
}

profile_name() {
  local app_path="$1"
  local profile_path="$app_path/embedded.mobileprovision"
  local plist_path

  if [[ ! -f "$profile_path" ]]; then
    echo "missing embedded.mobileprovision"
    return 0
  fi

  plist_path="$(mktemp "${TMPDIR:-/tmp}/timetracker-profile-name.XXXXXX.plist")"
  if security cms -D -i "$profile_path" >"$plist_path" 2>/dev/null; then
    /usr/libexec/PlistBuddy -c 'Print :Name' "$plist_path" 2>/dev/null || echo "unknown profile"
  else
    echo "unreadable embedded.mobileprovision"
  fi
  rm -f "$plist_path"
}

connected_watch_udids() {
  local json_path
  json_path="$(mktemp "${TMPDIR:-/tmp}/timetracker-watch-udids.XXXXXX.json")"
  trap 'rm -f "$json_path"; trap - RETURN' RETURN

  xcrun devicectl list devices \
    --filter "hardwareProperties.platform == 'watchOS' AND hardwareProperties.reality == 'physical'" \
    --timeout "$DEVICE_TIMEOUT" \
    --json-output "$json_path" >/dev/null

  /usr/bin/python3 - "$json_path" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    payload = json.load(handle)

for device in payload.get("result", {}).get("devices", []):
    udid = device.get("hardwareProperties", {}).get("udid")
    if udid:
        print(udid)
PY
}

profile_contains_connected_watch() {
  local app_path="$1"
  local devices
  local watch_ids=()

  devices="$(profile_provisioned_devices "$app_path")"
  while IFS= read -r watch_id; do
    [[ -n "$watch_id" ]] && watch_ids+=("$watch_id")
  done < <(connected_watch_udids)

  # macOS ships Bash 3.2. With `set -u`, expanding an empty array is an
  # unbound-variable error, so supply an empty fallback when no Watch is seen.
  for watch_id in "${watch_ids[@]:-}"; do
    if [[ "$devices" == *"$watch_id"* ]]; then
      return 0
    fi
  done

  return 1
}

validate_watch_profile() {
  local app_path="$1"
  local label="$2"
  local platforms
  local name

  require_app_bundle "$app_path" "$label"

  platforms="$(profile_platforms "$app_path")"
  name="$(profile_name "$app_path")"

  if [[ "$platforms" == *watchOS* || "$platforms" == *WatchOS* ]]; then
    echo "==> $label provisioning profile supports watchOS: $name"
    return 0
  fi

  if profile_contains_connected_watch "$app_path"; then
    echo "==> $label provisioning profile includes the connected Apple Watch: $name"
    return 0
  fi

  cat >&2 <<EOF
Error: $label is signed with a provisioning profile that cannot be verified for the connected Apple Watch.
  App:      $app_path
  Profile:  $name
  Platform: ${platforms:-missing}

Apple Watch will reject this build with:
  "This app cannot be installed because its integrity could not be verified."

Fix:
  1. Make the physical Apple Watch visible to Xcode/devicectl.
  2. Enable Developer Mode on the Watch.
  3. Re-run this script so Xcode can register the Watch and refresh the provisioning profile.

Set ALLOW_INVALID_WATCH_PROFILE=1 only if you intentionally want to install the iOS app while skipping Watch verification.
EOF

  if [[ "$ALLOW_INVALID_WATCH_PROFILE" != "1" ]]; then
    exit 1
  fi
}

available_ios_devices_json() {
  local json_path="$1"
  local filter
  filter="(State BEGINSWITH 'available' OR State BEGINSWITH 'connected') AND hardwareProperties.platform == 'iOS' AND hardwareProperties.reality == 'physical' AND deviceProperties.developerModeStatus == 'enabled'"

  xcrun devicectl list devices \
    --filter "$filter" \
    --timeout "$DEVICE_TIMEOUT" \
    --json-output "$json_path"
}

available_watch_devices_json() {
  local json_path="$1"
  local filter
  filter="State BEGINSWITH 'available' AND hardwareProperties.platform == 'watchOS' AND hardwareProperties.reality == 'physical' AND deviceProperties.developerModeStatus == 'enabled' AND deviceProperties.ddiServicesAvailable == true AND connectionProperties.tunnelState == 'connected'"

  xcrun devicectl list devices \
    --filter "$filter" \
    --timeout "$DEVICE_TIMEOUT" \
    --json-output "$json_path"
}

visible_watch_devices_json() {
  local json_path="$1"
  local filter
  filter="State BEGINSWITH 'available' AND hardwareProperties.platform == 'watchOS' AND hardwareProperties.reality == 'physical'"

  xcrun devicectl list devices \
    --filter "$filter" \
    --timeout "$DEVICE_TIMEOUT" \
    --json-output "$json_path"
}

device_entries_from_json() {
  local json_path="$1"

  /usr/bin/python3 - "$json_path" <<'PY'
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
}

install_app_on_device() {
  local device_id="$1"
  local device_name="$2"
  local app_path="$3"
  local platform_label="$4"
  local launch_bundle_id="$5"

  echo "==> Installing $platform_label app on $device_name ($device_id)"
  if xcrun devicectl device install app --device "$device_id" "$app_path"; then
    if [[ -n "$launch_bundle_id" && "$LAUNCH_AFTER_INSTALL" == "1" ]]; then
      echo "==> Launching on $device_name"
      xcrun devicectl device process launch --device "$device_id" "$launch_bundle_id" || DEVICE_FAILURES+=("$device_name launch")
    fi
  else
    DEVICE_FAILURES+=("$device_name install")
  fi
}

install_on_available_ios_devices() {
  local devices_json
  devices_json="$(mktemp "${TMPDIR:-/tmp}/timetracker-devices.XXXXXX.json")"
  trap 'rm -f "$devices_json"; trap - RETURN' RETURN

  echo "==> Looking for available or connected physical iOS/iPadOS development devices"
  available_ios_devices_json "$devices_json" >/dev/null

  local devices=()
  while IFS= read -r line; do
    devices+=("$line")
  done < <(device_entries_from_json "$devices_json")

  if [[ ${#devices[@]} -eq 0 ]]; then
    echo "No available physical iOS/iPadOS development devices found. Skipping device install."
    return 0
  fi

  for entry in "${devices[@]}"; do
    local device_id="${entry%%$'\t'*}"
    local device_name="${entry#*$'\t'}"

    install_app_on_device "$device_id" "$device_name" "$IOS_APP" "iOS/iPadOS" "$BUNDLE_ID"
  done
}

install_on_available_watch_devices() {
  local devices_json
  devices_json="$(mktemp "${TMPDIR:-/tmp}/timetracker-watch-devices.XXXXXX.json")"
  local visible_json
  visible_json="$(mktemp "${TMPDIR:-/tmp}/timetracker-visible-watch-devices.XXXXXX.json")"
  trap 'rm -f "$devices_json" "$visible_json"; trap - RETURN' RETURN

  echo "==> Looking for directly installable physical watchOS development devices"
  available_watch_devices_json "$devices_json" >/dev/null

  local devices=()
  while IFS= read -r line; do
    devices+=("$line")
  done < <(device_entries_from_json "$devices_json")

  if [[ ${#devices[@]} -eq 0 ]]; then
    echo "No directly installable physical watchOS development devices found. Skipping direct watch install."
    echo "The iOS app still carries the embedded Watch companion for paired-watch installation."
    if visible_watch_devices_json "$visible_json" >/dev/null; then
      /usr/bin/python3 - "$visible_json" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    payload = json.load(handle)

for device in payload.get("result", {}).get("devices", []):
    name = device.get("deviceProperties", {}).get("name", "Apple Watch")
    tunnel = device.get("connectionProperties", {}).get("tunnelState", "unknown")
    ddi = device.get("deviceProperties", {}).get("ddiServicesAvailable")
    developer = device.get("deviceProperties", {}).get("developerModeStatus", "unknown")
    print(f"  - {name}: tunnel={tunnel}, DDI={ddi}, developerMode={developer}")
PY
    fi
    return 0
  fi

  for entry in "${devices[@]}"; do
    local device_id="${entry%%$'\t'*}"
    local device_name="${entry#*$'\t'}"

    install_app_on_device "$device_id" "$device_name" "$WATCH_APP" "watchOS" ""
  done
}

watch_xcodebuild_destinations() {
  xcodebuild -project "$PROJECT" -scheme "$WATCH_SCHEME" -showdestinations 2>/dev/null | /usr/bin/python3 -c '
import re
import sys

for line in sys.stdin:
    line = line.strip()
    if "platform:watchOS" not in line or "Simulator" in line or "error:" in line:
        continue
    match = re.search(r"id:([^,}]+)", line)
    if not match or "placeholder" in match.group(1):
        continue
    print(f"platform=watchOS,id={match.group(1)}")
'
}

build_watch_app() {
  if [[ "$BUILD_WATCH_FOR_PHYSICAL" != "1" ]]; then
    echo "==> Building generic watchOS app"
    run_xcodebuild "$WATCH_SCHEME" -destination "generic/platform=watchOS" build
    return 0
  fi

  local destinations=()
  while IFS= read -r destination; do
    [[ -n "$destination" ]] && destinations+=("$destination")
  done < <(watch_xcodebuild_destinations)

  if [[ ${#destinations[@]} -eq 0 ]]; then
    echo "==> No physical Watch destination found for xcodebuild; building generic watchOS app"
    run_xcodebuild "$WATCH_SCHEME" -destination "generic/platform=watchOS" build
    return 0
  fi

  for destination in "${destinations[@]}"; do
    echo "==> Building watchOS app for $destination"
    run_xcodebuild "$WATCH_SCHEME" -destination "$destination" build
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

  if [[ -z "$PRODUCT_NAME" || "$PRODUCT_NAME" == *"/"* || "$PRODUCT_NAME" == "." || "$PRODUCT_NAME" == ".." || "$MAC_DEST" != "$APPLICATIONS_DIR"/*.app ]]; then
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

echo "==> Building watchOS app ($CONFIGURATION, team $TEAM_ID)"
build_watch_app
require_app_bundle "$WATCH_APP" "watchOS"
validate_watch_profile "$WATCH_APP" "watchOS app"

echo "==> Building iOS/iPadOS app ($CONFIGURATION, team $TEAM_ID)"
run_xcodebuild "$SCHEME" -sdk iphoneos -destination "generic/platform=iOS" build
require_app_bundle "$IOS_APP" "iOS"
report_embedded_watch_content
validate_watch_profile "$IOS_EMBEDDED_WATCH_APP" "embedded Watch companion"
install_on_available_ios_devices

install_on_available_watch_devices

echo "==> Building macOS app ($CONFIGURATION, team $TEAM_ID)"
run_xcodebuild "$SCHEME" -destination "generic/platform=macOS" build
copy_mac_app_to_applications
report_device_failures

cat <<EOF

Done.
iOS app:       $IOS_APP
watchOS app:   $WATCH_APP
embedded watch: $IOS_EMBEDDED_WATCH_APP
macOS app:     $MAC_DEST
Derived data:  $DERIVED_DATA

Tips:
  CONFIGURATION=Release scripts/build_install_all.sh
  WATCH_SCHEME=timetrackerWatchApp scripts/build_install_all.sh
  LAUNCH_AFTER_INSTALL=1 scripts/build_install_all.sh
  ALLOW_DEVICE_FAILURES=1 scripts/build_install_all.sh
  ALLOW_INVALID_WATCH_PROFILE=1 scripts/build_install_all.sh

EOF
