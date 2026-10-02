#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="LittleTidy"
BUNDLE_ID="com.federicotrevisani.LittleTidy"
MIN_SYSTEM_VERSION="26.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"

cd "$ROOT_DIR"
pkill -x "$APP_NAME" >/dev/null 2>&1 || true

swift build --product "$APP_NAME"
swift build --product LittleTidyHelper
BUILD_DIR="$(swift build --show-bin-path)"
BUILD_BINARY="$BUILD_DIR/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
/usr/bin/install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_BINARY"
mkdir -p "$APP_CONTENTS/Frameworks" "$APP_CONTENTS/Resources"
ditto "$BUILD_DIR/Sparkle.framework" "$APP_CONTENTS/Frameworks/Sparkle.framework"
ditto "$BUILD_DIR/LittleTidy_LittleTidy.bundle" "$APP_CONTENTS/Resources/LittleTidy_LittleTidy.bundle"
mkdir -p "$APP_CONTENTS/Library/HelperTools" "$APP_CONTENTS/Library/LaunchDaemons"
cp "$(swift build --show-bin-path)/LittleTidyHelper" "$APP_CONTENTS/Library/HelperTools/LittleTidyHelper"
cp "$ROOT_DIR/Support/com.federicotrevisani.LittleTidy.Helper.plist" "$APP_CONTENTS/Library/LaunchDaemons/"
# SMAppService requires a stable signed publisher identity for authenticated XPC.
SIGN_IDENTITY="Developer ID Application: Federico Trevisani (3VU7K9SUV8)"


cp "$ROOT_DIR/Sources/LittleTidy/Info.plist" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $APP_NAME" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleDevelopmentRegion en" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString 0.6.0" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion 8" "$INFO_PLIST"

if /usr/bin/security find-identity -v -p codesigning | /usr/bin/grep -Fq "$SIGN_IDENTITY"; then
  while IFS= read -r item; do
    /usr/bin/codesign --force --options runtime --sign "$SIGN_IDENTITY" "$item"
  done < <(/usr/bin/find "$APP_CONTENTS/Frameworks/Sparkle.framework" -depth \( -type f -perm +111 -o -type d -name '*.xpc' -o -type d -name '*.app' \))
  /usr/bin/codesign --force --options runtime --sign "$SIGN_IDENTITY" "$APP_CONTENTS/Frameworks/Sparkle.framework"
  /usr/bin/codesign --force --options runtime --sign "$SIGN_IDENTITY" --identifier com.federicotrevisani.LittleTidy.Helper "$APP_CONTENTS/Library/HelperTools/LittleTidyHelper"
  /usr/bin/codesign --force --options runtime --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
else
  echo "This complete bundle requires the configured Developer ID to sign the app, Sparkle, and helper." >&2
  exit 1
fi

/usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify-admin)
    /usr/bin/open -n "$APP_BUNDLE" --args --verify-admin
    sleep 3
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  --verify|verify)
    open_app
    sleep 3
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify|--verify-admin]" >&2
    exit 2
    ;;
esac
