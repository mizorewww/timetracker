#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT_DIR/timetracker.xcodeproj"
SCHEME="${SCHEME:-timetracker}"
CONFIGURATION="${CONFIGURATION:-Release}"
TEAM_ID="${DEVELOPMENT_TEAM:-LT98S43NKA}"
PRODUCT_NAME="${PRODUCT_NAME:-timetracker}"

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BUILD_ROOT="$ROOT_DIR/build"
DERIVED_DATA="$BUILD_ROOT/DerivedData"
ARCHIVE_ROOT="$BUILD_ROOT/Archives/$TIMESTAMP"
EXPORT_ROOT="$BUILD_ROOT/Exports/$TIMESTAMP"
LATEST_LINK="$BUILD_ROOT/Exports/latest"

IOS_ARCHIVE="$ARCHIVE_ROOT/${PRODUCT_NAME}-iOS.xcarchive"
MAC_ARCHIVE="$ARCHIVE_ROOT/${PRODUCT_NAME}-macOS.xcarchive"
IOS_EXPORT="$EXPORT_ROOT/iOS"
MAC_EXPORT="$EXPORT_ROOT/macOS"
IOS_EXPORT_OPTIONS="$ROOT_DIR/BuildSupport/ExportOptions-iOS-development.plist"

mkdir -p "$ARCHIVE_ROOT" "$IOS_EXPORT" "$MAC_EXPORT" "$DERIVED_DATA"

echo "==> Archiving iOS ($CONFIGURATION, team $TEAM_ID)"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "generic/platform=iOS" \
  -archivePath "$IOS_ARCHIVE" \
  -derivedDataPath "$DERIVED_DATA" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_STYLE=Automatic \
  -allowProvisioningUpdates \
  archive

echo "==> Exporting IPA"
xcodebuild \
  -exportArchive \
  -archivePath "$IOS_ARCHIVE" \
  -exportPath "$IOS_EXPORT" \
  -exportOptionsPlist "$IOS_EXPORT_OPTIONS" \
  -allowProvisioningUpdates

echo "==> Archiving macOS ($CONFIGURATION, team $TEAM_ID)"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "generic/platform=macOS" \
  -archivePath "$MAC_ARCHIVE" \
  -derivedDataPath "$DERIVED_DATA" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_STYLE=Automatic \
  -allowProvisioningUpdates \
  archive

MAC_APP_IN_ARCHIVE="$MAC_ARCHIVE/Products/Applications/${PRODUCT_NAME}.app"
MAC_APP_OUT="$MAC_EXPORT/${PRODUCT_NAME}.app"
MAC_ZIP_OUT="$MAC_EXPORT/${PRODUCT_NAME}-macOS-development.zip"

if [[ ! -d "$MAC_APP_IN_ARCHIVE" ]]; then
  echo "Expected macOS app not found at: $MAC_APP_IN_ARCHIVE" >&2
  exit 1
fi

echo "==> Copying signed macOS .app"
rm -rf "$MAC_APP_OUT" "$MAC_ZIP_OUT"
ditto "$MAC_APP_IN_ARCHIVE" "$MAC_APP_OUT"
ditto -c -k --keepParent "$MAC_APP_OUT" "$MAC_ZIP_OUT"

echo "==> Verifying signatures"
IPA_PATH="$(find "$IOS_EXPORT" -maxdepth 1 -name '*.ipa' -print -quit)"
if [[ -z "$IPA_PATH" ]]; then
  echo "IPA export failed: no .ipa file found in $IOS_EXPORT" >&2
  exit 1
fi
codesign --verify --deep --strict --verbose=2 "$MAC_APP_OUT"

rm -f "$LATEST_LINK"
ln -s "$EXPORT_ROOT" "$LATEST_LINK"

cat <<EOF

Done.
iOS IPA:       $IPA_PATH
macOS app:     $MAC_APP_OUT
macOS zip:     $MAC_ZIP_OUT
Archives:      $ARCHIVE_ROOT
Latest link:   $LATEST_LINK

EOF
