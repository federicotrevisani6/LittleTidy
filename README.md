# LittleTidy

A safe, review-first System Data and disk maintenance utility for macOS.
LittleTidy explains storage hidden by macOS, with a specialist view of
**Xcode**, **Simulator**, **XCTest**, **Device Support**, and **Archives**. It
also finds duplicate files, large files, unused apps, and caches.

## Principles

- **Reversible where possible** — normal files move to the Trash. Simulator
  operations use Apple's supported `simctl` mechanism and are identified as
  irreversible before confirmation.
- **Conservative recommendations** — only high-confidence rebuildable or
  unavailable data is preselected; review, protected, and unclassified totals
  remain separate.
- **Scoped access** — scans only user-approved folders; system locations
  (`/System`, `/Library`, `/usr`, …) are excluded unless you explicitly opt in.
- **Transparent** — each candidate carries a reason, path, size, and confidence.
- **Non-blocking** — scans run off the main thread and are cancellable at any point.

## Features

- **Developer Storage diagnosis** for Simulator devices and runtimes,
  XCTestDevices, DerivedData, Device Support, and Xcode archives. Results are
  split into Recommended, Review, Protected, and Unclassified instead of
  presenting all detected storage as safe cleanup.
- **Active-work protection** keeps booted Simulator devices out of cleanup and
  blocks every developer-storage deletion while Xcode is open. Valuable Xcode
  archives remain protected from automatic selection but can be explicitly
  reviewed and moved to the Trash.
- **Mechanism-aware cleanup** moves rebuildable directories to the Trash and
  removes only explicitly selected inactive Simulator devices through `simctl`,
  after refreshing their state immediately before execution.
- **Native macOS selection controls** provide reliable, keyboard-accessible
  checkboxes throughout review lists and developer storage.
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
| `LittleTidyCore` | Scanning engine, developer-storage inventory and policy, analyzers, command client, and mechanism-specific cleanup executors. Pure logic, fully unit-tested. |
| `LittleTidy` | SwiftUI app (sidebar + detail review UI, cleanup plan, settings). |
| `LittleTidyQA` | Command-line harness for exercising the engine against QA fixtures. |

```
Scan roots → directory enumerator → file metadata index
                                       ├── duplicate analyzer
                                       ├── large file analyzer
                                       └── app usage analyzer
                                              ↓
                                       review model → trash plan → executor

Developer roots + simctl → inventory → recommendation policy
                                      ├── Trash-restorable cleanup
                                      └── revalidated simctl cleanup
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

## Release packaging

GitHub release artifacts should be Developer ID signed and notarized before
upload. The release script archives the app, signs it with the local Developer
ID Application certificate, notarizes and staples both the app and DMG, then
generates the EdDSA-signed Sparkle `appcast.xml`. Artifacts are written under
`dist/release/`.

Authenticate `asc` once (preferred), or save notarytool credentials in the
Keychain as a fallback:

```sh
xcrun notarytool store-credentials littletidy-notary
```

Then package a notarized release:

```sh
./script/package_release.sh --release-notes release-notes/0.6.0.md
```

For local signing validation without notarization:

```sh
./script/package_release.sh --skip-notarization
```

## Documentation

Comprehensive architectural and engineering documentation is available:

- **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** — Architectural deep dive: scanning pipeline, analysis layers, state management, and Tahoe design system.
- **[docs/DEVELOPER_STORAGE.md](docs/DEVELOPER_STORAGE.md)** — Deep dive into Developer Storage: Xcode DerivedData, Simulators, Runtimes, XCTest, local ML and model caches, measurement optimizations, and safety policies.
- **[docs/SAFETY_AND_PERMISSIONS.md](docs/SAFETY_AND_PERMISSIONS.md)** — Safety invariants, Full Disk Access (FDA), security-scoped bookmarks, Trash protection, and real-time app uninstall monitoring.

## Project layout

```
docs/                # In-depth architectural & domain specifications
Sources/
  LittleTidyCore/    # Engine + analyzers + policies + execution (tested, UI-free)
  LittleTidy/        # SwiftUI app (stores, sidebar, views, components)
  LittleTidyQA/      # Headless CLI QA harness
Tests/               # Unit test suites (LittleTidyCoreTests, LittleTidyTests)
QA/                  # Manual QA checklist + generated fixtures
outputs/             # Product specs and historical design audits
script/              # Build, fixture, and release scripts
```

## Status

Active development. Developer Storage is intentionally conservative: archives,
active devices, and unclassified XCTest data are diagnosis-first; Simulator
runtimes remain review-only and are revalidated before supported removal.
See [outputs/littletidy-system-data-master-plan.md](outputs/littletidy-system-data-master-plan.md)
for the product, safety, engineering, testing, and release plan.

## License

Released under the [MIT License](LICENSE) — © 2026 Federico Trevisani. You may
use, modify, and distribute it freely, including in closed-source software,
provided the copyright notice and license text are retained.
