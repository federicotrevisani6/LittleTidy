# LittleTidy

A safe, review-first disk maintenance utility for macOS. LittleTidy helps you
reclaim disk space by finding **duplicate files**, **large files**, and
**unused apps** — and it never deletes anything outright. Every candidate is
shown with a reason, size, and confidence level, and confirmed items are moved
to the **Trash**, so nothing is irreversible.

## Principles

- **Reversible by design** — items are moved to the Trash, never permanently deleted.
- **Nothing auto-selected** — you always choose what gets removed.
- **Scoped access** — scans only user-approved folders; system locations
  (`/System`, `/Library`, `/usr`, …) are excluded unless you explicitly opt in.
- **Transparent** — each candidate carries a reason, path, size, and confidence.
- **Non-blocking** — scans run off the main thread and are cancellable at any point.

## Features

- **Duplicate detection** via staged comparison: group by size → 64 KB
  quick fingerprint (head/middle/tail) → full SHA-256 confirmation. A
  recommended copy to keep is suggested per group, and the group can never be
  fully removed.
- **Large file ranking** by size, age, location, and file type, with safe-by-default
  exclusions (photo/music libraries, Xcode projects, VMs, app internals).
- **Unused app detection** in `/Applications` and `~/Applications`, classified by
  last-used date (Spotlight metadata with filesystem fallback). System and Apple
  apps are never recommended for removal.
- **App & developer cache cleanup** for regenerable caches: per-app
  `~/Library/Caches`, Xcode DerivedData, and dev-tool caches (npm, Yarn, pip,
  Gradle). Everything here is rebuilt automatically by its owning tool, and
  removal stays Trash-only.
- **Deep uninstall (opt-in)** for unused apps: locates related app data by
  *exact bundle identifier* (Application Support, Caches, Containers,
  Preferences, Saved State, Logs, …). Off by default, shown transparently
  before removal, and Trash-only. Group Containers and name-based matches are
  intentionally excluded to avoid removing another app's data.
- **Cleanup plan** with validation, warnings (cloud-synced folders, missing files,
  duplicate-keep rules), and a post-cleanup report of trashed / skipped / failed items.
- **Cleanup history**: each completed run is logged (date, bytes freed, per-category
  breakdown) and persisted, so you can see how much space you've reclaimed over time.
- **Storage map**: a squarified treemap of the largest folders across the scanned
  roots, aggregated from the indexed files (no extra disk traversal). Tap a tile to
  reveal it in Finder.
- **Security-scoped bookmarks** so approved folders persist across launches.

## Architecture

The scanning engine is a standalone, UI-free Swift module so it can be tested
in isolation.

| Target | Description |
|---|---|
| `LittleTidyCore` | Scanning engine, analyzers (duplicate / large file / app usage), trash plan builder & executor. Pure logic, fully unit-tested. |
| `LittleTidy` | SwiftUI app (sidebar + detail review UI, cleanup plan, settings). |
| `LittleTidyQA` | Command-line harness for exercising the engine against QA fixtures. |

```
Scan roots → directory enumerator → file metadata index
                                       ├── duplicate analyzer
                                       ├── large file analyzer
                                       └── app usage analyzer
                                              ↓
                                       review model → trash plan → executor
```

## Requirements

- macOS 26+
- Swift 6.2+ toolchain / Xcode 26+

## Build & run

```sh
# Build everything
swift build

# Run the test suite (engine)
swift test

# Run the app from Xcode
open LittleTidy.xcodeproj
```

A helper script is provided:

```sh
./script/build_and_run.sh
```

## Project layout

```
Sources/
  LittleTidyCore/   # engine + analyzers (tested, UI-free)
  LittleTidy/        # SwiftUI app
  LittleTidyQA/      # CLI QA harness
Tests/               # LittleTidyCore unit tests
QA/                  # manual QA checklist + generated fixtures
outputs/             # logic & UI design specs
```

## Status

Active development. The current version keeps the v1 safety model throughout:
Trash-only removal, no system areas by default, and opt-in deep uninstall. See
[outputs/mac-cleaner-logic-spec.md](outputs/mac-cleaner-logic-spec.md) for the
full design and background.

## License

Released under the [MIT License](LICENSE) — © 2026 Federico Trevisani. You may
use, modify, and distribute it freely, including in closed-source software,
provided the copyright notice and license text are retained.
