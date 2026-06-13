# MacCleaner

A safe, review-first disk maintenance utility for macOS. MacCleaner helps you
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
- **Cleanup plan** with validation, warnings (cloud-synced folders, missing files,
  duplicate-keep rules), and a post-cleanup report of trashed / skipped / failed items.
- **Security-scoped bookmarks** so approved folders persist across launches.

## Architecture

The scanning engine is a standalone, UI-free Swift module so it can be tested
in isolation.

| Target | Description |
|---|---|
| `MacCleanerCore` | Scanning engine, analyzers (duplicate / large file / app usage), trash plan builder & executor. Pure logic, fully unit-tested. |
| `MacCleaner` | SwiftUI app (sidebar + detail review UI, cleanup plan, settings). |
| `MacCleanerQA` | Command-line harness for exercising the engine against QA fixtures. |

```
Scan roots → directory enumerator → file metadata index
                                       ├── duplicate analyzer
                                       ├── large file analyzer
                                       └── app usage analyzer
                                              ↓
                                       review model → trash plan → executor
```

## Requirements

- macOS 14+
- Swift 6 toolchain / Xcode 16+

## Build & run

```sh
# Build everything
swift build

# Run the test suite (engine)
swift test

# Run the app from Xcode
open MacCleaner.xcodeproj
```

A helper script is provided:

```sh
./script/build_and_run.sh
```

## Project layout

```
Sources/
  MacCleanerCore/   # engine + analyzers (tested, UI-free)
  MacCleaner/        # SwiftUI app
  MacCleanerQA/      # CLI QA harness
Tests/               # MacCleanerCore unit tests
QA/                  # manual QA checklist + generated fixtures
outputs/             # logic & UI design specs
```

## Status

Active development. The current version covers the v1 safety model: Trash-only
removal, no system areas, and no related-app-data cleanup. See
[outputs/mac-cleaner-logic-spec.md](outputs/mac-cleaner-logic-spec.md) for the
full design and roadmap (developer/app caches, deep uninstall, storage treemap).

## License

To be decided — see project owner. Until a `LICENSE` file is added, all rights
are reserved.
