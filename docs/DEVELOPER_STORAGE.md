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
| **Derived Data** | `~/Library/Developer/Xcode/DerivedData` | `Recommended` | `.trash` | `recreatable` |
| **Simulator Devices** | `~/Library/Developer/CoreSimulator/Devices` | `Review` (or `Recommended` if unavailable) | `.simctl` | `irreversible` |
| **Simulator Runtimes** | `~/Library/Developer/CoreSimulator/Profiles/Runtimes` or disk images | `Review` (Protected if default) | `.xcodeManaged` (`simctl runtime`) | `reinstallable` |
| **XCTest Devices** | `~/Library/Developer/XCTestDevices` | `Unclassified` | `.unsupported` | `unknown` |
| **Device Support** | `~/Library/Developer/Xcode/iOS DeviceSupport` | `Review` | `.trash` | `recreatable` |
| **Package Caches** | `~/Library/Caches/org.swift.swiftpm`, `~/.swiftpm/cache`, CocoaPods, Carthage | `Recommended` | `.trash` | `recreatable` |
| **AI Models & Agents** | `~/.ollama/models`, `~/.cache/huggingface`, Cursor, Claude, etc. | `Review` | `.trash` | `recreatable` / `reinstallable` |
| **Archives & Symbols**| `~/Library/Developer/Xcode/Archives` | `Protected` | `.trash` (explicit user opt-in only) | `trashRestorable` |
| **Android Emulators** | `~/.android/avd/*.avd` | `Review` | `.trash` | `reinstallable` |
| **Test Artifacts** | `~/Library/Developer/Xcode/DerivedData/*/Logs/Test` | `Review` | `.trash` | `trashRestorable` |
| **Other Developer Data**| `~/Library/Developer/*` (unclassified remainder) | `Unclassified` | `.unsupported` | `unknown` |

---

## 3. Deep Dive into Specific Subsystems

### 3.1 Derived Data (`.derivedData`)
- **What it is**: Xcode build products, indexes, intermediate files, and precompiled headers.
- **Safety**: Safe to remove when Xcode is not actively compiling. Xcode automatically rebuilds these artifacts on the next build.
- **Cleanup**: Handled via `.trash` (moving the project's DerivedData folder to Trash).
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

### 3.5 AI Models, Agents & LLMs (`.aiModelsAndAgents`)
LittleTidy recognizes that modern development environments store significant model weights, transcripts, and vector indexes outside traditional developer roots:
- **Ollama**: `~/.ollama/models` (model manifests and multi-gigabyte blobs).
- **Hugging Face**: `~/.cache/huggingface/hub` (model snapshots and weights).
- **PyTorch Hub**: `~/.cache/torch/hub` (downloaded weights and checkpoints).
- **MLX**: `~/.cache/mlx` (Apple Silicon optimized models).
- **LM Studio**: `~/Library/Application Support/LM Studio/models`.
- **Jan AI**: `~/Library/Application Support/jan/models`.
- **Claude Code**: `~/.claude` (agent session logs, tool caches, project transcripts).
- **Cursor AI**: `~/Library/Application Support/Cursor/User/workspaceStorage` (local vector embeddings, indexes, chat storage).
- **Continue**: `~/.continue/index` (codebase vector indexes).
- **Gemini**: `~/.gemini/cache`.

All AI model caches are classified under `Review` with consequence `redownloadRequired` and are removed via `.trash`.

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
When active, `DeveloperStorageCleanupExecutor` aborts immediately:
> *"Quit Xcode before cleaning developer storage. No data was removed for this item."*
If Xcode is launched while a batch operation is halfway through, the executor immediately skips all remaining operations.
