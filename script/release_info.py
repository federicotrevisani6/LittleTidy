#!/usr/bin/env python3
"""Print the app's marketing version and build number from the Xcode project.

The JSON-based project file tolerates trailing commas, so it is read as text:
find MARKETING_VERSION, take the `build-settings` block that contains it, and
read CURRENT_PROJECT_VERSION from that same block. Output is `key=value` lines,
ready to append to $GITHUB_OUTPUT.
"""
import re
import sys
from pathlib import Path

PROJECT = Path(__file__).resolve().parent.parent / "LittleTidy.xcodeproj" / "project.xcproj"


def main() -> int:
    text = PROJECT.read_text()
    marketing = list(re.finditer(r'"MARKETING_VERSION"\s*:\s*"([^"]+)"', text))
    if len(marketing) != 1:
        print(f"expected exactly one MARKETING_VERSION, found {len(marketing)}", file=sys.stderr)
        return 1

    start = text.rfind('"build-settings"', 0, marketing[0].start())
    if start < 0:
        print("MARKETING_VERSION is not inside a build-settings block", file=sys.stderr)
        return 1
    open_brace = text.index("{", start)
    depth = 0
    end = open_brace
    for index in range(open_brace, len(text)):
        if text[index] == "{":
            depth += 1
        elif text[index] == "}":
            depth -= 1
            if depth == 0:
                end = index
                break
    block = text[open_brace:end]
    build = re.search(r'"CURRENT_PROJECT_VERSION"\s*:\s*"([^"]+)"', block)
    if not build:
        print("CURRENT_PROJECT_VERSION is missing next to MARKETING_VERSION", file=sys.stderr)
        return 1

    version = marketing[0].group(1)
    if not re.fullmatch(r"\d+\.\d+\.\d+", version) or not build.group(1).isdigit():
        print(f"unexpected version format: {version} ({build.group(1)})", file=sys.stderr)
        return 1

    print(f"version={version}")
    print(f"build={build.group(1)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
