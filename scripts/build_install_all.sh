#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="${PROJECT:-$ROOT_DIR/timetracker.xcodeproj}"
SCHEME="${SCHEME:-timetracker}"
CONFIGURATION="${CONFIGURATION:-Debug}"
TEAM_ID="${DEVELOPMENT_TEAM:-LT98S43NKA}"
PRODUCT_NAME="${PRODUCT_NAME:-timetracker}"
WATCH_PRODUCT_NAME="${WATCH_PRODUCT_NAME:-timetrackerWatchApp}"
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

plist_value() {
  local plist_path="$1"
  local key="$2"

  /usr/libexec/PlistBuddy -c "Print :$key" "$plist_path" 2>/dev/null
}

connected_watch_udids() {
  local json_path
  local udids
  json_path="$(mktemp "${TMPDIR:-/tmp}/timetracker-watch-devices.XXXXXX.json")"

  if ! xcrun devicectl list devices \
    --filter "hardwareProperties.platform == 'watchOS' AND hardwareProperties.reality == 'physical'" \
    --timeout "$DEVICE_TIMEOUT" \
    --json-output "$json_path" >/dev/null; then
    unlink "$json_path"
    echo "Warning: unable to query physical Apple Watch devices." >&2
    return 0
  fi

  udids="$(/usr/bin/python3 - "$json_path" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    payload = json.load(handle)

for device in payload.get("result", {}).get("devices", []):
    udid = device.get("hardwareProperties", {}).get("udid")
    if udid:
        print(udid)
PY
)"
  unlink "$json_path"
  printf '%s\n' "$udids"
}

validate_embedded_watch_profile() {
  local profile_path="$IOS_EMBEDDED_WATCH_APP/embedded.mobileprovision"
  local profile_plist
  local provisioned_devices
  local watch_udids=()
  local watch_udid

  if [[ ! -f "$profile_path" ]]; then
    echo "Embedded Watch app has no provisioning profile." >&2
    exit 1
  fi

  profile_plist="$(mktemp "${TMPDIR:-/tmp}/timetracker-watch-profile.XXXXXX.plist")"
  if ! security cms -D -i "$profile_path" >"$profile_plist"; then
    unlink "$profile_plist"
    echo "Unable to read the embedded Watch provisioning profile." >&2
    exit 1
  fi
  provisioned_devices="$(plist_value "$profile_plist" ProvisionedDevices || true)"
  unlink "$profile_plist"

  while IFS= read -r watch_udid; do
    [[ -n "$watch_udid" ]] && watch_udids+=("$watch_udid")
  done < <(connected_watch_udids)

  if [[ ${#watch_udids[@]} -eq 0 ]]; then
    echo "Warning: no physical Apple Watch is visible; embedded profile device coverage was not verified." >&2
    return 0
  fi

  for watch_udid in "${watch_udids[@]}"; do
    if [[ "$provisioned_devices" == *"$watch_udid"* ]]; then
      echo "==> Embedded Watch profile includes visible Apple Watch: $watch_udid"
      return 0
    fi
  done

  cat >&2 <<EOF
Embedded Watch provisioning profile does not include any visible Apple Watch.
Open Xcode with the paired iPhone connected, enable Developer Mode on the Watch,
register the Watch, and run this script again so automatic signing can refresh.
EOF
  exit 1
}

validate_embedded_watch_companion() {
  local ios_plist="$IOS_APP/Info.plist"
  local watch_plist="$IOS_EMBEDDED_WATCH_APP/Info.plist"
  local ios_bundle_id
  local watch_bundle_id
  local companion_bundle_id
  local runs_independently
  local is_watch_app

  require_app_bundle "$IOS_EMBEDDED_WATCH_APP" "embedded watchOS companion"
  ios_bundle_id="$(plist_value "$ios_plist" CFBundleIdentifier)"
  watch_bundle_id="$(plist_value "$watch_plist" CFBundleIdentifier)"
  companion_bundle_id="$(plist_value "$watch_plist" WKCompanionAppBundleIdentifier)"
  runs_independently="$(plist_value "$watch_plist" WKRunsIndependentlyOfCompanionApp || true)"
  is_watch_app="$(plist_value "$watch_plist" WKApplication || true)"

  if [[ "$watch_bundle_id" != "$ios_bundle_id.watchkitapp" ]]; then
    echo "Embedded Watch bundle ID must be $ios_bundle_id.watchkitapp, found: $watch_bundle_id" >&2
    exit 1
  fi

  if [[ "$companion_bundle_id" != "$ios_bundle_id" ]]; then
    echo "Embedded Watch companion ID must be $ios_bundle_id, found: $companion_bundle_id" >&2
    exit 1
  fi

  if [[ "$runs_independently" != "false" && "$runs_independently" != "NO" ]]; then
    echo "Embedded Watch app must depend on its iPhone companion." >&2
    exit 1
  fi

  if [[ "$is_watch_app" != "true" && "$is_watch_app" != "YES" ]]; then
    echo "Embedded bundle is not marked as a watchOS application." >&2
    exit 1
  fi

  codesign --verify --deep --strict --verbose=2 "$IOS_EMBEDDED_WATCH_APP"
  codesign --verify --deep --strict --verbose=2 "$IOS_APP"
  validate_embedded_watch_profile
  echo "==> iOS app contains dependent Watch companion: $watch_bundle_id"
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

echo "==> Building iOS/iPadOS app with embedded Watch companion ($CONFIGURATION, team $TEAM_ID)"
run_xcodebuild "$SCHEME" -sdk iphoneos -destination "generic/platform=iOS" build
require_app_bundle "$IOS_APP" "iOS"
validate_embedded_watch_companion
install_on_available_ios_devices

echo "==> Building macOS app ($CONFIGURATION, team $TEAM_ID)"
run_xcodebuild "$SCHEME" -destination "generic/platform=macOS" build
copy_mac_app_to_applications
report_device_failures

cat <<EOF

Done.
iOS app:       $IOS_APP
embedded watch: $IOS_EMBEDDED_WATCH_APP
macOS app:     $MAC_DEST
Derived data:  $DERIVED_DATA

The paired Apple Watch installs the embedded companion when Automatic App Install
is enabled in the iPhone Watch app.

Tips:
  CONFIGURATION=Release scripts/build_install_all.sh
  LAUNCH_AFTER_INSTALL=1 scripts/build_install_all.sh
  ALLOW_DEVICE_FAILURES=1 scripts/build_install_all.sh

EOF
