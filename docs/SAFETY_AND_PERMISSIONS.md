# LittleTidy — Safety, Permissions & Privacy

This document details the security posture, macOS sandbox/TCC permissions model, filesystem boundaries, and real-time app uninstall monitoring in **LittleTidy**.

---

## 1. The Permissions & Privacy Model

macOS enforces strict Transparency, Consent, and Control (TCC) rules around user folders, application containers, and system metadata. LittleTidy operates with a staged, user-empowered permission model:

### 1.1 Full Disk Access (FDA) Detection
To scan caches in `~/Library/Caches`, application containers in `~/Library/Containers`, and developer artifacts in `~/Library/Developer`, LittleTidy checks whether Full Disk Access has been granted.

[`FullDiskAccess`](file:///Users/federicotrevisani/LittleTidy/Sources/LittleTidyCore/Policies/FullDiskAccess.swift) detects FDA non-intrusively without prompting an unprompted system alert by attempting to read known TCC-protected directories:

```swift
let probePaths = [
    "~/Library/Safari",
    "~/Library/Mail",
    "~/Library/Suggestions"
]
```

- If `contentsOfDirectory(atPath:)` succeeds, Full Disk Access is active.
- If it throws an error with `NSCocoaErrorDomain` code `257` (`NSFileReadNoPermissionError`) or `NSPOSIXErrorDomain` code `1` (`EPERM`), FDA is absent.
- The UI exposes a direct link to the System Settings privacy pane:
  ```swift
  x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles
  ```

### 1.2 Security-Scoped Bookmarks
When the user approves folders to scan (e.g. via `NSOpenPanel`), LittleTidy preserves these permissions across launches via [`FolderBookmarkStore`](file:///Users/federicotrevisani/LittleTidy/Sources/LittleTidy/State/FolderBookmarkStore.swift):
- Creates a bookmark with `options: .withSecurityScope`.
- Restores and resolves the bookmark at startup with `URL(resolvingBookmarkData:options:bookmarkDataIsStale:)`.
- Activates security scope using `startAccessingSecurityScopedResource()` when accessing the resource and releases it with `stopAccessingSecurityScopedResource()`.

---

## 2. Hard Filesystem Boundaries & Exclusions

To prevent unintended changes to operating system components or user data, LittleTidy enforces strict boundaries in [`FileInventoryScanner`](file:///Users/federicotrevisani/LittleTidy/Sources/LittleTidyCore/Analyzers/FileInventoryScanner.swift) and [`TrashPlanBuilder`](file:///Users/federicotrevisani/LittleTidy/Sources/LittleTidyCore/Execution/TrashPlanBuilder.swift):

### 2.1 System Path Blocklist
Unless the user explicitly enables `includeSystemFolders` in preferences, scanning and cleanup are strictly prohibited within:
- `/System`
- `/Library` (root library; note that user `~/Library` subfolders are scanned via explicit targeted analyzers)
- `/private`
- `/usr`
- `/bin`
- `/sbin`

### 2.2 Protected Application Packages
[`LargeFileAnalyzer`](file:///Users/federicotrevisani/LittleTidy/Sources/LittleTidyCore/Analyzers/LargeFileAnalyzer.swift) automatically ignores files inside opaque packages and database bundles:
- `.photoslibrary` (Apple Photos database)
- `.musiclibrary` (Apple Music library)
- `.xcodeproj` / `.xcworkspace` (Xcode projects)
- `.vmwarevm` / `.pvm` (Virtual machines)

### 2.3 Symbolic Link Safety
- **Scanner**: Symlinks are ignored by default (`followSymbolicLinks = false`) to prevent infinite recursion and escaping approved root folders.
- **Trash Builder**: Any item identified as a symbolic link (`isSymbolicLink == true`) is rejected by `TrashPlanBuilder` with `TrashPlanError.symbolicLinkBlocked`.
- **Caches**: `CacheAnalyzer` verifies `url.resolvingSymlinksInPath() == url.standardizedFileURL` before marking a cache candidate as valid, avoiding trashing external symlinked directories.

### 2.4 Duplicate Group Keep Invariant
`TrashPlanBuilder` verifies that no action can delete all copies in a `DuplicateGroup`:
```swift
if selectedIDs == groupIDs {
    throw TrashPlanError.duplicateGroupWouldRemoveAllCopies
}
```
At least one file in every duplicate group must remain untouched.

---

## 3. Real-Time App Leftover Detection (`AppTrashWatcher`)

When a user drags an application to the macOS Trash in Finder, macOS leaves behind associated application support files, caches, container folders, preferences, and state directories in `~/Library/`.

LittleTidy includes a background watcher, [`AppTrashWatcher`](file:///Users/federicotrevisani/LittleTidy/Sources/LittleTidyCore/Watchers/AppTrashWatcher.swift), which detects this event and provides an opt-in cleanup prompt.

### 3.1 Architecture of the Trash Watcher
1. **FSEvents Stream**:
   - `FSEventTrashFolderMonitor` opens an `FSEventStreamRef` targeting `~/.Trash`.
   - Events are delivered asynchronously onto a dedicated serial utility queue (`com.littletidy.trashwatcher`).
2. **Cold Start Filtering**:
   - On startup, the watcher enumerates existing `.app` bundles in `~/.Trash` and adds them to `processedAppPaths`. It does not prompt for apps that were already in the Trash prior to launch.
3. **New App Discovery**:
   - When a new `.app` bundle appears in `~/.Trash`, `AppTrashWatcher.inspectAppInTrash` reads the bundle's `Contents/Info.plist`.
   - Extracts `CFBundleIdentifier` (e.g. `com.example.MyApp`), `CFBundleDisplayName`, and version.
4. **Targeted Leftover Search**:
   - Queries `AppUsageAnalyzer.relatedAppData(bundleIdentifier:)` to search `~/Library/`.

### 3.2 Strict Leftover Matching Rules
To guarantee that data belonging to other applications is never removed, matching is restricted to **exact bundle identifiers**:

| Location | Matching Pattern | Kind Label |
|---|---|---|
| `~/Library/Application Support/<bundleID>` | Exact directory name | Application Support |
| `~/Library/Caches/<bundleID>` | Exact directory name | Caches |
| `~/Library/Containers/<bundleID>` | Exact directory name | Container |
| `~/Library/HTTPStorages/<bundleID>` | Exact directory name | HTTP storage |
| `~/Library/WebKit/<bundleID>` | Exact directory name | WebKit data |
| `~/Library/Logs/<bundleID>` | Exact directory name | Logs |
| `~/Library/Preferences/<bundleID>.plist` | Exact file name | Preferences |
| `~/Library/Saved Application State/<bundleID>.savedState` | Exact directory name | Saved state |
| `~/Library/LaunchAgents/<bundleID>*.plist` | Prefix match on plist | Launch agent |

#### Explicit Non-Goals / Exclusions
- **Group Containers (`~/Library/Group Containers/`)**: Excluded. Group containers are keyed by Team ID or suite name (e.g. `group.com.example.app`) and often shared between multiple applications or app extensions.
- **Fuzzy / Display Name Matches**: Excluded. Searching for folders named after the app's display name (e.g. `Slack` or `Discord`) is prone to collisions with user documents or other tools.

### 3.3 Prompt & Execution
- When leftovers are found, LittleTidy posts a macOS system notification (`AppUninstallNotificationManager`) and presents `AppLeftoverPromptView`.
- The user can uncheck individual items before confirming.
- Deletion is staged via `TrashPlan` and moves the leftovers to the Trash.

---

## 4. Deletion Safety: Trash vs. Permanent Delete

LittleTidy is built on the invariant that **operations must be reversible wherever possible**:

### 4.1 Moving to Trash (Default)
All file deletions default to `DeletionMode.moveToTrash`.
```swift
var resultingURL: NSURL?
try fileManager.trashItem(at: url, resultingItemURL: &resultingURL)
```
- Files reside in the user's standard macOS Trash.
- Users can inspect or restore them using Finder's "Put Back" command.
- The destination URL in Trash is captured in `CleanupReportItem` for user reference.

### 4.2 Permanent Deletion (Strictly Opt-In)
- By default, the option to permanently delete is hidden and disabled (`allowPermanentDeletion = false`).
- If enabled in Settings, the user can toggle `deletionMode = .permanentDelete`.
- When active, the UI displays clear warnings indicating that files will bypass the Trash and cannot be recovered.
