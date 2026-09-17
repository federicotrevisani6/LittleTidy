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
RELEASE_NOTES_PATH=""
REPOSITORY_SLUG="federicotrevisani6/LittleTidy"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RELEASE_DIR="$ROOT_DIR/dist/release"
ARCHIVE_PATH="$RELEASE_DIR/$APP_NAME.xcarchive"

usage() {
  cat >&2 <<USAGE
usage: $0 [--notary-profile PROFILE] [--release-notes FILE] [--skip-notarization]

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
    --release-notes)
      RELEASE_NOTES_PATH="${2:-}"
      shift 2
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
APPCAST_DIR="$RELEASE_DIR/appcast"

if [[ -z "$RELEASE_NOTES_PATH" ]]; then
  RELEASE_NOTES_PATH="$ROOT_DIR/release-notes/$VERSION.md"
fi

submit_for_notarization() {
  local artifact="$1"
  if command -v asc >/dev/null 2>&1; then
    echo "Submitting $(basename "$artifact") to Apple Notary API via asc CLI..."
    asc notarization submit --file "$artifact" --wait
  elif [[ -n "$NOTARY_PROFILE" ]]; then
    echo "Submitting $(basename "$artifact") via notarytool ($NOTARY_PROFILE)..."
    xcrun notarytool submit "$artifact" \
      --keychain-profile "$NOTARY_PROFILE" \
      --wait
  else
    echo "Missing asc CLI credentials or --notary-profile." >&2
    exit 1
  fi
}

if ! security find-identity -v -p codesigning | grep -Fq "$SIGN_IDENTITY"; then
  echo "Missing signing identity: $SIGN_IDENTITY" >&2
  exit 1
fi

rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"

if [[ ! -f "$PROJECT/project.xcproj" ]]; then
  echo "Missing JSON-based Xcode project: $PROJECT/project.xcproj" >&2
  exit 1
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
  submit_for_notarization "$NOTARY_ZIP"

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

  echo "Signing DMG with Developer ID..."
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$FINAL_DMG"
  codesign --verify --strict --verbose=2 "$FINAL_DMG"

  if [[ "$SKIP_NOTARIZATION" == "0" ]]; then
    submit_for_notarization "$FINAL_DMG"
    echo "Stapling notarization ticket to DMG..."
    xcrun stapler staple "$FINAL_DMG"
    xcrun stapler validate "$FINAL_DMG"
    spctl --assess --type open --context context:primary-signature --verbose=4 "$FINAL_DMG"
  fi

  cp "$FINAL_DMG" "$LATEST_DMG"

  GENERATE_APPCAST_BIN="$(find "$ROOT_DIR/.build" -name "generate_appcast" -type f 2>/dev/null | head -1)"
  if [[ -z "$GENERATE_APPCAST_BIN" || ! -x "$GENERATE_APPCAST_BIN" ]]; then
    echo "Missing Sparkle generate_appcast tool. Run swift build first." >&2
    exit 1
  fi

  echo "Generating Sparkle appcast with EdDSA signature..."
  mkdir -p "$APPCAST_DIR"
  cp "$ROOT_DIR/appcast.xml" "$APPCAST_DIR/appcast.xml"
  cp "$LATEST_DMG" "$APPCAST_DIR/$APP_NAME.dmg"
  if [[ -f "$RELEASE_NOTES_PATH" ]]; then
    cp "$RELEASE_NOTES_PATH" "$APPCAST_DIR/$APP_NAME.md"
  else
    echo "Missing release notes: $RELEASE_NOTES_PATH" >&2
    exit 1
  fi
  "$GENERATE_APPCAST_BIN" \
    --download-url-prefix "https://github.com/$REPOSITORY_SLUG/releases/download/v$VERSION/" \
    --embed-release-notes \
    "$APPCAST_DIR"
  cp "$APPCAST_DIR/appcast.xml" "$ROOT_DIR/appcast.xml"
  xmllint --noout "$ROOT_DIR/appcast.xml"
fi

echo "Release ZIP: $FINAL_ZIP"
if [[ -f "$FINAL_DMG" ]]; then
  echo "Release DMG: $FINAL_DMG"
  echo "Sparkle DMG: $LATEST_DMG"
  echo "Sparkle appcast: $ROOT_DIR/appcast.xml"
fi
