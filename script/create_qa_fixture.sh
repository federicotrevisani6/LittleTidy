#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURE_DIR="$ROOT_DIR/QA/LittleTidyFixture"

rm -rf "$FIXTURE_DIR"
mkdir -p \
  "$FIXTURE_DIR/Downloads" \
  "$FIXTURE_DIR/Documents" \
  "$FIXTURE_DIR/Movies" \
  "$FIXTURE_DIR/Applications/OldFixtureApp.app/Contents" \
  "$FIXTURE_DIR/Library/Developer/Xcode/DerivedData/FixtureProject" \
  "$FIXTURE_DIR/Library/Developer/Xcode/iOS DeviceSupport/18.4" \
  "$FIXTURE_DIR/Library/Developer/Xcode/Archives/2026-07-11/Fixture 11-07-26.xcarchive" \
  "$FIXTURE_DIR/Library/Developer/XCTestDevices" \
  "$FIXTURE_DIR/Library/Developer/CoreSimulator/Devices/FIXTURE-DEVICE/data" \
  "$FIXTURE_DIR/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS 18.4.simruntime"

python3 - <<'PY' "$FIXTURE_DIR"
import os
import plistlib
import sys
from pathlib import Path

root = Path(sys.argv[1])

duplicate = b"LittleTidy duplicate fixture\n" * 45_000
(root / "Downloads" / "duplicate-copy-a.bin").write_bytes(duplicate)
(root / "Documents" / "duplicate-copy-b.bin").write_bytes(duplicate)
(root / "Documents" / "unique-same-size.bin").write_bytes(b"Unique fixture payload\n" * 58_000)

large_path = root / "Movies" / "large-video-fixture.mov"
with large_path.open("wb") as f:
    f.truncate(6 * 1024 * 1024)

installer_path = root / "Downloads" / "installer-fixture.dmg"
with installer_path.open("wb") as f:
    f.truncate(2 * 1024 * 1024)

app = root / "Applications" / "OldFixtureApp.app"
contents = app / "Contents"
info = {
    "CFBundleIdentifier": "com.federicotrevisani.LittleTidyFixture.OldFixtureApp",
    "CFBundleName": "OldFixtureApp",
    "CFBundleDisplayName": "Old Fixture App",
    "CFBundleShortVersionString": "1.0",
}
with (contents / "Info.plist").open("wb") as f:
    plistlib.dump(info, f)
(contents / "OldFixtureApp").write_bytes(b"fixture app executable\n")

developer_payloads = [
    root / "Library/Developer/Xcode/DerivedData/FixtureProject/build.o",
    root / "Library/Developer/Xcode/iOS DeviceSupport/18.4/symbols.bin",
    root / "Library/Developer/Xcode/Archives/2026-07-11/Fixture 11-07-26.xcarchive/Info.plist",
    root / "Library/Developer/XCTestDevices/test-device.bin",
    root / "Library/Developer/CoreSimulator/Devices/FIXTURE-DEVICE/data/device.bin",
    root / "Library/Developer/CoreSimulator/Profiles/Runtimes/iOS 18.4.simruntime/runtime.bin",
]
for index, path in enumerate(developer_payloads, start=1):
    path.write_bytes(bytes([index]) * (256 * 1024))

old_timestamp = 946684800
for path in [app, contents, contents / "Info.plist", contents / "OldFixtureApp"]:
    os.utime(path, (old_timestamp, old_timestamp))

print(root)
PY

echo "Created QA fixture at: $FIXTURE_DIR"
echo
echo "Use this folder with LittleTidy:"
echo "  $FIXTURE_DIR"
