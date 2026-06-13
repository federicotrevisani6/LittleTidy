#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURE_DIR="$ROOT_DIR/QA/MacCleanerFixture"

rm -rf "$FIXTURE_DIR"
mkdir -p \
  "$FIXTURE_DIR/Downloads" \
  "$FIXTURE_DIR/Documents" \
  "$FIXTURE_DIR/Movies" \
  "$FIXTURE_DIR/Applications/OldFixtureApp.app/Contents"

python3 - <<'PY' "$FIXTURE_DIR"
import os
import plistlib
import sys
from pathlib import Path

root = Path(sys.argv[1])

duplicate = b"MacCleaner duplicate fixture\n" * 45_000
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
    "CFBundleIdentifier": "com.federicotrevisani.MacCleanerFixture.OldFixtureApp",
    "CFBundleName": "OldFixtureApp",
    "CFBundleDisplayName": "Old Fixture App",
    "CFBundleShortVersionString": "1.0",
}
with (contents / "Info.plist").open("wb") as f:
    plistlib.dump(info, f)
(contents / "OldFixtureApp").write_bytes(b"fixture app executable\n")

old_timestamp = 946684800
for path in [app, contents, contents / "Info.plist", contents / "OldFixtureApp"]:
    os.utime(path, (old_timestamp, old_timestamp))

print(root)
PY

echo "Created QA fixture at: $FIXTURE_DIR"
echo
echo "Use this folder with MacCleaner:"
echo "  $FIXTURE_DIR"
