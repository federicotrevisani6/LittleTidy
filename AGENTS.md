# LittleTidy — Agent & Developer Guide

Shared guide for AI agents and human contributors working on **LittleTidy**: mission, safety invariants, project layout, commands and coding conventions. Claude Code loads it through the `@AGENTS.md` import in `CLAUDE.md`.

---

## 1. Project Overview & Mission

**LittleTidy** is a native macOS utility (macOS 26+, Swift 6.2+) designed to inspect, explain, and safely recover disk space hidden within macOS **System Data**, with a specialist focus on **Apple Developer Storage** and conservative general cleanup.

### Primary Problem Solved
macOS Storage Settings aggregates tens or hundreds of gigabytes into an opaque "System Data" category without explaining what is inside or whether it can be safely removed. Generic cleaner apps often treat all developer files as disposable caches, risking build breaks, lost archives, or simulator corruption. LittleTidy provides deep, transparent diagnosis and mechanism-specific cleanup.

### Core Philosophy: "Diagnosis First, Safe Action Second"
1. **Explain Before Cleaning**: Every candidate carries an exact filesystem path, human-readable reason, byte size, confidence level, and operational consequence.
2. **Never Equate Detected Storage with Disposable Storage**: Reclaimable space is strictly segmented into four tiers:
   - `Recommended`: Confidently rebuildable or orphaned data (e.g. DerivedData, unavailable simulator devices). Preselected by default.
   - `Review`: Useful or reinstallable data (e.g. Device Support symbols, old shutdown simulators, local AI model weights). Requires manual review and opt-in.
   - `Protected`: Active or critical assets (e.g. Xcode archives, booted simulators, current runtimes, CoreDevice mounts). Never auto-selected; protected from accidental deletion.
   - `Unclassified`: Data whose ownership or safety cannot yet be proven (e.g. XCTest folders not registered in `simctl --set testing`). Surfaced for diagnostic awareness only; deletion is disabled.
3. **Reversible by Default**: Standard files and directories are moved to the macOS Trash (`FileManager.default.trashItem`) rather than permanently deleted.
4. **Supported Mechanisms Only**: Simulator devices and runtimes are never deleted by directly pruning internal CoreSimulator directories; they are manipulated via Apple's official `xcrun simctl` CLI.
5. **Active-Work Protection (Fail-Closed)**: While Xcode runs, only per-project DerivedData and inactive Simulator/XCTest devices that no process has open (fresh `lsof` snapshot) can be cleaned; every other Xcode-owned item waits until Xcode quits. If the snapshot fails, the item is blocked. Homebrew cleanup is independent of Xcode. If a simulator is booted, it is protected.
6. **Conservative Leftover Matching**: When detecting uninstalled app leftovers, matching is restricted to exact bundle identifier matches (`CFBundleIdentifier`). Shared Group Containers and fuzzy name matches are excluded to prevent cross-app data loss.
7. **Local-First & Private**: Scanning, analysis, and indexing are 100% on-device. No telemetry, file paths, or inventory data leave the user's machine.

---

## 2. Hard Safety Invariants

LittleTidy deletes files on real machines, and a mistake here can destroy data the user cannot get back. Every code change must keep all of these rules. If a task seems to need an exception, stop and ask before writing it.

| Invariant | Implementation Rule |
|---|---|
| **Trash Over Permanent Delete** | Default deletion mode is `moveToTrash`. Permanent deletion (`removeItem`) is only an opt-in toggle guarded in settings. |
| **Simctl For Simulator Management** | Never run `rm -rf` or `FileManager.removeItem` on CoreSimulator devices or runtimes. Use `xcrun simctl delete <UDID>` or `xcrun simctl runtime delete <ID>`. |
| **Simctl State Revalidation** | Simulator state must be re-checked immediately before execution (checking if a device changed to `Booted` since the scan). |
| **Xcode Lock Guard** | Before every item, `DeveloperStorageCleanupExecutor` applies `xcodeActivityRule`. `requiresXcodeQuit` items are skipped while Xcode runs (or if the check fails). `openFileCheck` items (per-project DerivedData, Simulator and XCTest devices) proceed only if `openFileSnapshot()` succeeds and shows no open file inside the item; a nil snapshot blocks. Never weaken this to skip the snapshot. |
| **Homebrew Through brew Only** | Homebrew space is reclaimed only with `brew cleanup` from `/opt/homebrew/bin/brew` or `/usr/local/bin/brew` (`HomebrewCleanup.isKnownExecutable`). Never delete Cellar or cache folders directly. |
| **Agent Sessions Only When Closed** | A Claude session folder is a cleanup candidate only if its UUID is not live in `~/.claude/sessions` (`ClaudeSessionRegistry`). The executor rereads the registry and requires an open-file snapshot with nothing open inside it; an unreadable registry or snapshot blocks it. AI app caches (`aiCaches`) always require the open-file check. |
| **Snapshots Through macOS Thinning Only** | Time Machine local snapshot space is released only with `tmutil thinlocalsnapshots / <bytes> 4` (`LocalSnapshotReleaser`), after a cleanup and an explicit confirmation. Never run `tmutil deletelocalsnapshots` or name a snapshot. |
| **XCTest Through simctl Testing Set** | XCTest clones are removed only with `xcrun simctl --set testing delete <UDID>` after revalidation. No clone is removable while a test session is active: any clone of the set not shut down, or `xcodebuild` running. Unregistered XCTest folders remain `unclassified`. |
| **Duplicate Keep Invariant** | A duplicate group never has all copies deleted. At least one file is always kept (`TrashPlanBuilder.duplicateGroupWouldRemoveAllCopies`). |
| **System Apps Protection** | Any app inside `/System/Applications` or `/System/` is never part of a cleanup plan. |
| **Symbolic Link Protection** | Symlinks are never traversed or deleted as part of trash plans to prevent escaping approved boundaries. |
| **Approved Roots Boundary** | Every candidate in a general trash plan must reside within user-approved scan roots. |
| **No Group Containers in Leftovers** | Deep app uninstall never touches `~/Library/Group Containers` or use prefix/wildcard search on generic names. Exact bundle IDs only. |
| **CoreDevice Protection** | Mounted device filesystems in `~/Library/Developer/CoreDevice` must never be recursively traversed or cleaned (reported as `bytes: 0`, `protected`). |

---

## 3. Targets & Project Structure

The project has two checked-in build definitions:
- **Swift Package Manager (`Package.swift`)**: Core command-line build and test definition.
- **Xcode 27 JSON-based project (`LittleTidy.xcodeproj/project.xcproj`)**: Authoritative Xcode definition for code signing, AppKit resources, schemes, and packaging. Edit this file directly or through Xcode. Never regenerate the project with XcodeGen.

```
LittleTidy/
├── Package.swift               # SPM definition (LittleTidyCore, LittleTidy, LittleTidyQA, tests)
├── LittleTidy.xcodeproj/       # Xcode container
│   └── project.xcproj          # JSON-based Xcode 27 project source of truth
├── Sources/
│   ├── LittleTidyCore/         # Pure Swift logic, analyzers, policies, execution (UI-free)
│   ├── LittleTidy/             # SwiftUI + AppKit macOS application
│   └── LittleTidyQA/           # Headless CLI testing harness for QA fixtures
├── Tests/
│   ├── LittleTidyCoreTests/    # Swift Testing suite for LittleTidyCore
│   └── LittleTidyTests/        # Swift Testing suite for Store and UI logic
├── QA/                         # Manual QA checklist & fixture configuration
├── script/                     # Helper build, fixture, and release scripts
├── outputs/                    # Product specs and historical design audits
└── docs/                       # In-depth architectural & domain documentation
```

### Target Responsibilities
1. **`LittleTidyCore`** (Library/Framework): UI-free, dependency-free (except Foundation/CryptoKit/CoreServices). Fully testable from the command line. Contains all scanner logic, analyzers, CLI command clients, policies, and cleanup executors.
2. **`LittleTidy`** (macOS Executable App): SwiftUI app target with AppKit extensions. Depends on `LittleTidyCore` and `Sparkle` (for automatic software updates). Houses the `@MainActor` state stores, sidebar navigation, detail views, and macOS Tahoe-styled UI surfaces.
3. **`LittleTidyQA`** (CLI Tool): Small command-line executable that imports `LittleTidyCore` and runs an end-to-end inventory on synthetic QA fixture folders to verify detection counts and invariants in automated environments.

---

## 4. File Map and Data Flow

The per-file map and the end-to-end data flow diagram are in [docs/FILE_MAP.md](docs/FILE_MAP.md). Read it when you need to find where something lives. Deeper references: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md), [docs/DEVELOPER_STORAGE.md](docs/DEVELOPER_STORAGE.md), [docs/SAFETY_AND_PERMISSIONS.md](docs/SAFETY_AND_PERMISSIONS.md).

---

## 5. Developer Workflows & Commands

### Build and Test
```bash
# Build all targets in Debug mode
swift build

# Run unit tests (LittleTidyCoreTests)
swift test

# Run a specific test suite or test
swift test --filter DeveloperStorageTests

# Build release binary (Universal arm64 & x86_64)
swift build -c release --product LittleTidy --arch arm64 --arch x86_64
```

### Xcode
```bash
# Open the project in Xcode
open LittleTidy.xcodeproj

# Inspect the JSON-based project and schemes
xcodebuild -list -project LittleTidy.xcodeproj

# Run tests via xcodebuild (executes both LittleTidyCoreTests and LittleTidyTests)
xcodebuild test -project LittleTidy.xcodeproj -scheme LittleTidy -destination "platform=macOS"
```

### Run Helper Script
```bash
# Compile and launch the app bundle under dist/LittleTidy.app
./script/build_and_run.sh

# Debug with LLDB
./script/build_and_run.sh --debug

# Stream log output
./script/build_and_run.sh --logs
```

### QA Fixture Verification
```bash
# 1. Create realistic synthetic test fixtures in QA/LittleTidyFixture
./script/create_qa_fixture.sh

# 2. Run the headless CLI auditor
swift run LittleTidyQA

# Expected QA output:
# scannedFiles=10
# duplicates=1
# largeFiles=5
# unusedApps=1
# developerItems=6
# developerBytes=<non-zero>
```

### Release Packaging & Notarization
```bash
# Package a notarized release DMG/Zip using stored credentials:
./script/package_release.sh --notary-profile littletidy-notary

# Package for local verification without notarization:
./script/package_release.sh --skip-notarization
```

---

## 6. Modern Swift & Concurrency Guidelines

Follow these conventions in all code changes:

1. **Swift 6 Strict Concurrency**:
   - `LittleTidyCore` code must be fully `Sendable` compliant.
   - Use `actor` for services managing concurrent state or process execution (`DeveloperStorageAnalyzer`, `DeveloperStorageCleanupExecutor`, `DeveloperToolCommandClient`, `DeveloperToolActivityChecker`).
   - Use `@unchecked Sendable` only on classes with internal synchronization (`NSLock`) such as `AppTrashWatcher` and `FSEventTrashFolderMonitor`.
   - All UI-bound state and stores (`ScanReviewStore`, `AppDelegate`, Views) must be `@MainActor`.
2. **Cancellation Checks**:
   - Long loops in analyzers must frequently call `try Task.checkCancellation()` to ensure user-initiated scan cancellations respond immediately.
3. **Fail-Closed Design**:
   - In security and permission checks, any error must default to the safe state (e.g. if checking whether Xcode is running fails, assume Xcode IS running; if ownership of an XCTest folder is ambiguous, mark as `unclassified`).
4. **AppKit Integration**:
   - Use `NSColor` dynamic colors wrapped in SwiftUI `Color` (`CleanerPalette.swift`) to ensure full support for Dark Mode and high contrast.
   - Use native buttons and standard system symbols (`SF Symbols`).
5. **No Shell Invocations**:
   - Never invoke shell scripts or subshells (`/bin/sh`, `/bin/bash`, `system()`) to execute commands. Always configure `Process` directly with an explicit `executableURL` and argument array.

## iPhone Duo folding and unfolding

Before folding, unfolding, or changing the hinge angle of an iPhone Duo simulator, you must read and follow the [hinge skill](/Users/federicotrevisani/.agents/skills/hinge/SKILL.md), installed from `artemnovichkov/hinge`. Use its bundled `scripts/hinge` commands and follow its display-switching and screenshot workflow.
