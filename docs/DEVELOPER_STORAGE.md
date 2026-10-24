# LittleTidy — Developer Storage Deep Dive

This document details the domain rules, scanning mechanics, measurement optimizations, safety policies, and supported cleanup mechanisms for **Developer Storage** in LittleTidy.

---

## 1. Why Developer Storage Requires Specialist Treatment

Apple developer tooling (Xcode, Simulator, CoreDevice, XCTest) can consume hundreds of gigabytes of disk space that macOS Storage Settings aggregates under "System Data". 

Most disk cleaning utilities make one of two catastrophic mistakes:
1. **Blind File Trashing**: Directly deleting directories inside `~/Library/Developer/CoreSimulator/Devices` or `/Library/Developer/CoreSimulator/Profiles/Runtimes`. This corrupts the CoreSimulator database, leaves phantom devices in Xcode's run destinations, and can cause Xcode crashes.
2. **Flattening into Generic Caches**: Advertising Xcode Archives, symbol caches, and active simulator devices as "Junk/Cache" and preselecting them for deletion.

LittleTidy takes the opposite approach:
- Every developer artifact is categorized by its real domain meaning.
- Every item has an explicit recovery cost (e.g. rebuildable, reinstallable, irreversible).
- Apple-supported command-line tools (`xcrun simctl`) are used for simulator lifecycles.
- All operations are gated on an active-work check (`Xcode` cannot be running).

---

## 2. Taxonomy of Developer Storage Categories

LittleTidy tracks 11 distinct categories of developer storage:

| Category | Default Location | Default Recommendation | Cleanup Mechanism | Recoverability |
|---|---|---|---|---|
| **Derived Data** | `~/Library/Developer/Xcode/DerivedData/*` (one item per project) | `Recommended` | `.trash` | `recreatable` |
| **Simulator Devices** | `~/Library/Developer/CoreSimulator/Devices` | `Review` (or `Recommended` if unavailable) | `.simctl` | `irreversible` |
| **Simulator Runtimes** | `~/Library/Developer/CoreSimulator/Profiles/Runtimes` or disk images | `Review` (Protected if default) | `.xcodeManaged` (`simctl runtime`) | `reinstallable` |
| **XCTest Devices** | `~/Library/Developer/XCTestDevices/<UDID>` registered in `simctl --set testing` | `Recommended` (Protected if booted; Unclassified if not registered) | `.simctl` (`--set testing`) | `recreatable` |
| **Device Support** | `~/Library/Developer/Xcode/iOS DeviceSupport` | `Review` | `.trash` | `recreatable` |
| **Package Caches** | `~/Library/Caches/org.swift.swiftpm`, `~/.swiftpm/cache`, CocoaPods, Carthage | `Recommended` | `.trash` | `recreatable` |
| **Homebrew** | Old kegs and downloads reported by `brew cleanup --dry-run -s --prune=all` | `Recommended` | `.homebrewCleanup` | `reinstallable` |
| **AI Models** | Ollama, Hugging Face, PyTorch, MLX, LM Studio, Jan | `Review` | `.trash` | `reinstallable` |
| **AI Caches & Logs** | Exact cache/log paths for Claude, Cursor, Codex, Continue, Gemini | `Recommended` | `.trash` | `recreatable` |
| **AI Sessions & Artifacts** | Claude/Codex sessions and Cursor workspace storage | `Review` | `.trash` | `trashRestorable` |
| **Archives & Symbols**| `~/Library/Developer/Xcode/Archives` | `Protected` | `.trash` (explicit user opt-in only) | `trashRestorable` |
| **Android Emulators** | `~/.android/avd/*.avd` | `Review` | `.trash` | `reinstallable` |
| **Test Artifacts** | `~/Library/Developer/Xcode/DerivedData/*/Logs/Test` | `Review` | `.trash` | `trashRestorable` |
| **Other Developer Data**| `~/Library/Developer/*` (unclassified remainder) | `Unclassified` | `.unsupported` | `unknown` |

---

## 3. Deep Dive into Specific Subsystems

### 3.1 Derived Data (`.derivedData`)
- **What it is**: Xcode build products, indexes, intermediate files, and precompiled headers.
- **Safety**: Safe to remove when Xcode is not actively compiling. Xcode automatically rebuilds these artifacts on the next build.
- **Granularity**: One item per child folder. The project name comes from `info.plist` → `WorkspacePath`; folders without it (for example `ModuleCache.noindex`) are listed as shared build data. A missing workspace is reported as "Project no longer exists".
- **Cleanup**: Handled via `.trash` (moving the project's DerivedData folder to Trash). While Xcode runs, see §4.
- **Consequence**: `temporarySlowdown` (subsequent build will perform a clean compile).

### 3.2 Simulator Devices (`.simulatorDevices`)
- **Discovery**: Ingested via `xcrun simctl list devices --json`.
- **Active State Detection**:
  - If `state == "Booted"`: Marked as `StorageActivityState.active`. Recommendation is set to `Protected`. **Selection is strictly disabled**.
  - If `isAvailable == false`: The simulator device references a runtime that is no longer installed on macOS. Recommendation is `Recommended` (safe to remove).
  - If `state == "Shutdown"` and available: Recommendation is `Review`.
- **Measurement**: Measuring simulator data folders via standard recursive directory traversal is extremely slow due to thousands of nested application sandboxes. LittleTidy uses batch direct execution of `/usr/bin/du -sk` across all device paths simultaneously, yielding sub-second measurement.
- **Cleanup Mechanism**: Strictly executed via:
  ```bash
  xcrun simctl delete <UDID>
  ```
  Before issuing this command, LittleTidy re-queries `simctl` to guarantee the device did not transition to `Booted` while the user was reviewing the list.

### 3.2.1 XCTest Devices (`.xctestDevices`)
- **What it is**: Clones of a Simulator device that Xcode creates for parallel testing. They live in simctl's dedicated "testing" device set.
- **Discovery**: `xcrun simctl --set testing list devices --json`. Each registered device becomes an item measured at `XCTestDevices/<UDID>`. Registered devices whose folder is already gone are listed at 0 bytes so simctl can remove the stale registration.
- **Policy**: Shutdown clones are `Recommended` only while the whole testing set is idle. If any clone is not shut down (Booted, Booting, Creating, …), a test session is active: Xcode can boot any clone of the set mid-run, so every clone becomes `Protected` (`xctestSessionActiveDecision`). Folders simctl does not list stay `Unclassified` (`unverifiedXCTestDecision`). If simctl fails, the whole directory is reported as diagnosis-only, as before.
- **Cleanup**: `xcrun simctl --set testing delete <UDID>`. Immediately before, the executor skips the clone if `xcodebuild` is running (`pgrep -x xcodebuild`; a failed check counts as running), then re-lists the testing set and skips it if it no longer exists or if any clone of the set is not shut down. Never `rm`.

### 3.2.2 Clones, snapshots, and guaranteed reclaimable space
Allocated size (`du`) can far exceed what removal frees right away, for two reasons:
- Simulator devices and XCTest clones are created with `clonefile` and share blocks with other devices.
- A local APFS snapshot (for example `com.apple.TimeMachine.*.local`) keeps every block that existed when it was taken. Files older than the snapshot report a private size of 0; their space returns only when macOS purges the snapshot, which it does automatically under space pressure.

`APFSReclaimEstimator` sums each file's APFS private size (`getattrlist` with `ATTR_CMNEXT_PRIVATESIZE`) into `minimumReclaimableBytes`, a **lower bound on immediately freed space**. Every `Recommended` item is estimated, plus `Review` Simulator and XCTest devices. The UI shows allocated size together with "at least X freed right away"; `removedBytes` in results uses the lower bound. On volumes that do not report private size the estimate is nil and allocated size is used.

### 3.2.3 Homebrew (`.homebrewCleanup`)
- **Discovery**: Only `/opt/homebrew/bin/brew` or `/usr/local/bin/brew`. The analyzer runs `brew cleanup --dry-run -s --prune=all` with auto-update, analytics, and hints disabled, and parses Homebrew's "would free approximately" summary (binary multiples).
- **Cleanup**: `brew cleanup -s --prune=all`. The executor accepts only the two standard executable paths, so an item can never name an arbitrary program. Homebrew keeps pinned formulae. The result reports what Homebrew says it freed. `~/Library/Caches/Homebrew` is not listed separately in Developer Storage, so the space is not counted twice.
- **Xcode**: Independent; never blocked by a running Xcode.

### 3.3 Simulator Runtimes (`.simulatorRuntimes`)
- **Discovery**: Ingested via `xcrun simctl runtime list --json` and `xcrun simctl list runtimes --json`.
- **Mounted Disk Image Nuance**: Simulator runtimes in modern macOS versions are mounted disk images (`.dmg`). Traversing the runtime's file bundle traverses the entire simulated root filesystem and can take several minutes. LittleTidy inspects the volume's used byte capacity (`volumeTotalCapacity - volumeAvailableCapacity`) for instant sizing.
- **Cleanup Mechanism**: Executed via:
  ```bash
  xcrun simctl runtime delete <RuntimeIdentifier>
  ```
  LittleTidy inspects all configured simulator devices before deletion. If any device depending on this runtime is currently `Booted`, deletion is blocked. If dependent devices are shutdown, the user is warned that those devices will become unavailable until the runtime is re-downloaded.

### 3.4 Xcode Archives (`.archives`)
- **What it is**: `~/Library/Developer/Xcode/Archives/*/*.xcarchive`.
- **Safety**: Contains the release binaries, dSYM symbol files, and bitcode/debug maps for apps previously built for distribution or App Store submission.
- **Policy**: Classified as `Protected`. It is **never** preselected.
- **User Opt-in**: A user can manually inspect individual archives by date/project and opt to move obsolete ones to the Trash.

### 3.5 AI Models, Caches, and Generated Artifacts
LittleTidy separates modern AI storage by recoverability instead of treating an entire product directory as disposable.

#### AI Models (`.aiModelsAndAgents`)

- **Ollama**: `~/.ollama/models` (model manifests and multi-gigabyte blobs).
- **Hugging Face**: `~/.cache/huggingface/hub` (model snapshots and weights).
- **PyTorch Hub**: `~/.cache/torch/hub` (downloaded weights and checkpoints).
- **MLX**: `~/.cache/mlx` (Apple Silicon optimized models).
- **LM Studio**: `~/Library/Application Support/LM Studio/models`.
- **Jan AI**: `~/Library/Application Support/jan/models`.

Models are classified under `Review` with consequence `redownloadRequired` and are removed via `.trash`.

#### AI Caches & Logs (`.aiCaches`)

Only exact regenerable subpaths are eligible. Examples include Claude cache/debug logs, Codex logs/temp data, Cursor `Cache`, `Code Cache`, `GPUCache`, `CachedData`, logs and crash reports, Continue indexes, and Gemini cache. These are `Recommended`, but remain Trash-restorable by default. Settings, credentials, memory files, and product roots are never included through prefix matching.

#### AI Sessions & Artifacts (`.aiGeneratedArtifacts`)

Claude project sessions, Codex active/archived sessions, and Cursor workspace storage can accumulate transcripts, screenshots, documents, tool results, and indexes. They are surfaced as `Review` with `dataLossRisk`, are never preselected, and can only be moved to Trash after explicit selection. LittleTidy does not scan arbitrary project documents merely because an AI tool may have created them.

### 3.6 Critical Protected Boundary: CoreDevice Filesystems
Inside `~/Library/Developer/CoreDevice/` resides macOS device connection mounts.
- **Warning**: These directory entries may represent mounted remote filesystems on connected physical iPhones, iPads, or Apple Watches.
- **Policy**: [`DeveloperStorageAnalyzer`](file:///Users/federicotrevisani/LittleTidy/Sources/LittleTidyCore/Analyzers/DeveloperStorageAnalyzer.swift) explicitly checks for `CoreDevice`. It assigns:
  - `bytes: 0`
  - `activity: .active`
  - `recommendation: .protected`
  - `cleanupMechanism: .unsupported`
  - `reason: "This location exposes mounted device filesystems and must not be traversed or cleaned as ordinary files."`
- **Traversing or deleting inside `CoreDevice` is strictly prevented.**

### 3.7 CoreSimulator Remainder
CoreSimulator maintains global logs, launch caches, daemon caches, and image assets in `~/Library/Developer/CoreSimulator` that are not owned by any individual device. LittleTidy calculates:
$$\text{Remainder Bytes} = \max(0, \text{Total CoreSimulator Size} - \sum \text{Device Bytes})$$
If this remainder exceeds 1 MB, it is surfaced under `Other Developer Data` as `CoreSimulator Support Data` with recommendation `unclassified`.

---

## 4. Active-Work Protection (Fail-Closed)

Before any developer storage cleanup operation begins, LittleTidy invokes [`DeveloperToolActivityChecker`](file:///Users/federicotrevisani/LittleTidy/Sources/LittleTidyCore/Execution/DeveloperToolActivityChecker.swift):

```swift
public actor DeveloperToolActivityChecker: DeveloperToolActivityChecking {
    public func isXcodeRunning() async -> Bool {
        do {
            _ = try await commandRunner.run(
                executable: URL(fileURLWithPath: "/usr/bin/pgrep"),
                arguments: ["-x", "Xcode"]
            )
            return true
        } catch DeveloperToolCommandError.failed(_, let exitCode, _) where exitCode == 1 {
            return false // pgrep exited with 1: process not found
        } catch {
            return true // Fail-closed on unexpected errors
        }
    }
}
```

### Fail-Closed Principle
If `pgrep` exits with anything other than code 1 (indicating no matching process), the checker assumes Xcode **is** running.

### Per-item rule while Xcode runs
The executor rechecks Xcode before **every** item and applies `DeveloperStorageItem.xcodeActivityRule`:

| Rule | Categories | While Xcode runs |
|---|---|---|
| `independent` | Homebrew cleanup | Proceeds. |
| `openFileCheck` | Per-project DerivedData, Simulator devices, XCTest clones | Proceeds only if a fresh `lsof -n -P -F n` snapshot shows no open file inside the item. If the snapshot fails or is empty, the item is skipped. Simulator and XCTest devices are additionally revalidated as not booted by simctl. |
| `requiresXcodeQuit` | Everything else (Device Support, runtimes, archives, package caches, AI data, …) | Skipped: *"Quit Xcode before cleaning this item."* |

A skipped item never stops the batch; each later item is evaluated on its own. One `lsof` snapshot of all open files takes about half a second, unlike `lsof +D`, which walks the whole tree.

## 5. Post-cleanup verification
- Trash and permanent removals check that the path no longer exists; otherwise the item is reported as failed. A failed permanent delete reports that part of the item may remain.
- simctl removals check that the device folder is gone after `simctl delete`.
- `DeveloperStorageCleanupResult` records volume free space (`volumeAvailableCapacityKey`) before and after the batch (`measuredFreedBytes`) and the bytes moved to the Trash (`bytesInTrash`), which are freed only when the Trash is emptied. The measured change is an observation: other processes write to the same volume.
