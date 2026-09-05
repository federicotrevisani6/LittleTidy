#!/usr/bin/env bash
set -euo pipefail

APP_NAME="LittleTidy"
SCHEME="LittleTidy"
PROJECT="LittleTidy.xcodeproj"
TEAM_ID="3VU7K9SUV8"
SIGN_IDENTITY="Developer ID Application: Federico Trevisani (3VU7K9SUV8)"
CONFIGURATION="Release"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
SKIP_NOTARIZATION=0

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RELEASE_DIR="$ROOT_DIR/dist/release"
ARCHIVE_PATH="$RELEASE_DIR/$APP_NAME.xcarchive"

usage() {
  cat >&2 <<USAGE
usage: $0 [--notary-profile PROFILE] [--skip-notarization]

Environment:
  NOTARY_PROFILE  Keychain profile previously created with:
                  xcrun notarytool store-credentials <profile-name>
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --notary-profile)
      NOTARY_PROFILE="${2:-}"
      shift 2
      ;;
    --skip-notarization)
      SKIP_NOTARIZATION=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

cd "$ROOT_DIR"

VERSION="$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -showBuildSettings 2>/dev/null | awk -F'= ' '/MARKETING_VERSION/ {print $2; exit}')"
BUILD_NUMBER="$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -showBuildSettings 2>/dev/null | awk -F'= ' '/CURRENT_PROJECT_VERSION/ {print $2; exit}')"
VERSION="${VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"

APP_PATH="$ARCHIVE_PATH/Products/Applications/$APP_NAME.app"
NOTARY_ZIP="$RELEASE_DIR/$APP_NAME-$VERSION-build-$BUILD_NUMBER-notary.zip"
FINAL_ZIP="$RELEASE_DIR/$APP_NAME-$VERSION-build-$BUILD_NUMBER-macOS.zip"

if ! security find-identity -v -p codesigning | grep -Fq "$SIGN_IDENTITY"; then
  echo "Missing signing identity: $SIGN_IDENTITY" >&2
  exit 1
fi

rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"

if command -v xcodegen >/dev/null 2>&1; then
  xcodegen generate
fi

xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -archivePath "$ARCHIVE_PATH" \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
  ENABLE_HARDENED_RUNTIME=YES \
  SKIP_INSTALL=NO

echo "Re-signing embedded frameworks, helpers, and app bundle inside-out with secure timestamp..."

find "$APP_PATH/Contents/Frameworks" -type d -name "*.xpc" | while read -r item; do
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$item"
done

find "$APP_PATH/Contents/Frameworks" -type d -name "*.app" | while read -r item; do
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$item"
done

find "$APP_PATH/Contents/Frameworks" -type f -perm +111 | while read -r item; do
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$item"
done

find "$APP_PATH/Contents/Frameworks" -depth 1 -type d -name "*.framework" | while read -r item; do
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$item"
done

codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_PATH"

codesign --verify --deep --strict --verbose=2 "$APP_PATH"

ditto -c -k --keepParent "$APP_PATH" "$NOTARY_ZIP"

if [[ "$SKIP_NOTARIZATION" == "0" ]]; then
  if command -v asc >/dev/null 2>&1; then
    echo "Submitting to Apple Notary API via asc CLI..."
    asc notarization submit --file "$NOTARY_ZIP" --wait
  elif [[ -n "$NOTARY_PROFILE" ]]; then
    echo "Submitting to Apple Notary API via notarytool ($NOTARY_PROFILE)..."
    xcrun notarytool submit "$NOTARY_ZIP" \
      --keychain-profile "$NOTARY_PROFILE" \
      --wait
  else
    echo "Missing asc CLI credentials or --notary-profile. Re-run with --skip-notarization for a signed-only artifact." >&2
    exit 1
  fi

  xcrun stapler staple "$APP_PATH"
  xcrun stapler validate "$APP_PATH"
fi

if [[ "$SKIP_NOTARIZATION" == "0" ]]; then
  spctl --assess --type execute --verbose=4 "$APP_PATH"
else
  spctl --assess --type execute --verbose=4 "$APP_PATH" || {
    echo "Signed-only artifact was rejected by Gatekeeper because it is not notarized." >&2
  }
fi

rm -f "$FINAL_ZIP"
ditto -c -k --keepParent "$APP_PATH" "$FINAL_ZIP"

FINAL_DMG="$RELEASE_DIR/$APP_NAME-$VERSION-build-$BUILD_NUMBER.dmg"
LATEST_DMG="$RELEASE_DIR/$APP_NAME.dmg"

if command -v create-dmg >/dev/null 2>&1; then
  echo "Creating DMG package..."
  rm -f "$FINAL_DMG" "$LATEST_DMG"
  create-dmg \
    --volname "$APP_NAME" \
    --window-pos 200 120 \
    --window-size 660 400 \
    --icon-size 160 \
    --icon "$APP_NAME.app" 180 170 \
    --app-drop-link 480 170 \
    --hide-extension "$APP_NAME.app" \
    "$FINAL_DMG" \
    "$APP_PATH"
  cp "$FINAL_DMG" "$LATEST_DMG"

  if [[ "$SKIP_NOTARIZATION" == "0" ]]; then
    echo "Stapling notarization ticket to DMG..."
    xcrun stapler staple "$FINAL_DMG" || true
    xcrun stapler staple "$LATEST_DMG" || true
  fi

  SIGN_UPDATE_BIN="$(find "$ROOT_DIR/.build" -name "sign_update" -type f 2>/dev/null | head -1)"
  if [[ -n "$SIGN_UPDATE_BIN" && -x "$SIGN_UPDATE_BIN" ]]; then
    echo "Signing DMG with Sparkle EdDSA..."
    "$SIGN_UPDATE_BIN" "$FINAL_DMG"
  fi
fi

echo "Release ZIP: $FINAL_ZIP"
if [[ -f "$FINAL_DMG" ]]; then
  echo "Release DMG: $FINAL_DMG"
fi
