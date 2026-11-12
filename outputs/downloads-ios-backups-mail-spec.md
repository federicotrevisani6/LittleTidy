# Spec: Downloads, iOS Backups and Mail Downloads cleanup

Status: draft, 2026-11-12. Nothing here is implemented.
Origin: a review of the everyday-cleanup areas that commercial Mac cleaners cover. We take three of them and fit them to LittleTidy's rules, in our own wording and behavior.

If this spec disagrees with the safety rules in [docs/SAFETY_AND_PERMISSIONS.md](../docs/SAFETY_AND_PERMISSIONS.md), those rules win and this spec gets fixed.

## 1. Goal

Find three kinds of space that macOS and Apple apps leave behind and that LittleTidy does not report today, explain each one, and let the user reclaim it with the same guarantees as the rest of the app: explained, tiered, reversible, fail-closed.

## 2. Non-goals

- Cleaning Mail's trash, mailboxes or envelope index. Those live inside Mail's own database; touching them from outside can corrupt it. We may show a hint to empty Mail's trash from Mail itself.
- Deleting or "archiving" anything inside `~/Library/Mail/V*` other than what section 5 names.
- Reading backup contents (messages, photos). We read only the backup's `Info.plist` metadata.
- Any automatic or scheduled deletion. Every deletion stays user-initiated.
- Permanent delete as a default. Trash first, as everywhere else.
- Photo similarity, menu bar alerts, cloud unsync: separate specs.

## 3. Shared rules (apply to all three areas)

- Every candidate carries path, plain-language reason, byte size, confidence, tier and consequence, like existing items.
- Deletion mode is `moveToTrash` unless the user has enabled the existing permanent-delete toggle.
- Symlinks are never traversed or deleted. A symlink found at a candidate path makes it `unclassified`.
- Candidates must sit under an approved root (Downloads) or under a fixed, named system location (backups, Mail Downloads). Nothing outside those paths can enter a plan.
- Sizes use allocated bytes, measured without following links.
- If a read fails for lack of Full Disk Access, the item appears as an access issue, not as zero bytes.
- Any error while checking safety conditions blocks the item.

## 4. Area A: Downloads clutter

Scope: `~/Downloads`, only when the user has approved it as a scan root. If it is not approved, the area shows an "approve Downloads" prompt and reports nothing.

### Detection

| Kind | Rule | Tier |
|---|---|---|
| Installer images and packages | `.dmg`, `.pkg`, `.iso`, `.xip` older than 30 days (last opened, falling back to modified date) | Review |
| Installer whose app is installed | Same as above, and an app with the same name exists in `/Applications` or `~/Applications` | Review, listed first, reason says so |
| Expanded archives | `.zip` older than 60 days next to a folder of the same base name | Review |
| Duplicates | Handled by the existing `DuplicateAnalyzer`; Downloads copies are already deprioritized as keepers by the `smart` strategy | unchanged |

No Downloads item is `recommended` in the first release. Promotion to `recommended` needs QA evidence (section 8, question 1).

### Blocks

- A `.dmg` that is currently mounted or has any open file in the fresh `lsof` snapshot is `protected` ("in use") and cannot be selected. A missing snapshot blocks the item.
- A file modified in the last 7 days is not listed, whatever its type.
- Items inside a `.photoslibrary`, `.xcodeproj` or other protected package are excluded, same as `LargeFileAnalyzer`.

### Consequence shown to the user

"You can download it again from its original source." Where the source is unknown, say that plainly rather than implying it can be re-downloaded.

## 5. Area B: iOS device backups

Location: `~/Library/Application Support/MobileSync/Backup/<folder>/`. Needs Full Disk Access.

### Detection

- Each direct child folder is one backup.
- Read `Info.plist` for device name, product type, iOS version and last backup date. Read `Manifest.plist` only for the `IsEncrypted` flag.
- Folders without a readable `Info.plist` are `unclassified` (size shown, deletion disabled).

### Tiers

- Every backup is `review`. None is preselected. None is `recommended`.
- The newest backup for a given device name is marked "most recent backup for this device" and shows a stronger warning, but is not blocked: the user may legitimately want it gone.
- Encrypted backups show "Encrypted. Deleting it removes your only way to restore from it unless you have another backup."

### Blocks

- A backup folder with any open file (fresh `lsof` snapshot) is blocked. This covers Finder or Apple Devices syncing at that moment. A missing snapshot blocks it.
- The app does not run any command that talks to a device.

### Consequence

`dataLossRisk`. Reason text: "This is a copy of your iPhone or iPad data. If the device is lost or broken and no other backup exists, this data cannot be recovered." Trash makes the deletion reversible until the Trash is emptied; the UI must say that emptying the Trash makes it final.

## 6. Area C: Mail Downloads

Location: `~/Library/Containers/com.apple.mail/Data/Library/Mail Downloads/`. This holds copies of attachments the user opened from Mail. Needs Full Disk Access.

### Detection

- Direct children (folders named by UUID, containing attachment copies).
- A copy whose modification date is later than its creation date by more than 2 seconds may have been edited by the user: the item is `protected` ("may contain your edits").
- Everything else is `review`.

### Blocks

- Applies the same rule as `requiresXcodeQuit`, for Mail: while Mail is running (`/usr/bin/pgrep -x Mail`) or the check fails, items are skipped and the UI says to quit Mail. Never weakened to "probably fine".
- Open-file snapshot required, same as above.

### Consequence

"Mail can fetch the attachment again from the message as long as the message is still on the server or on this Mac." Show that caveat for accounts known to be local-only ("On My Mac").

## 7. Acceptance criteria

Numbered and falsifiable. Each is covered by a test in `LittleTidyCoreTests` unless marked QA.

**Shared**
1. No candidate from these areas is ever outside the approved Downloads root or its fixed system path. A path that resolves outside through `..` or a symlink is rejected by `TrashPlanBuilder`.
2. A symlink at a candidate path produces `unclassified`, and a plan containing it is refused.
3. With Trash mode on, execution calls `trashItem` and never `removeItem`.
4. When the open-file snapshot returns `nil`, every item of these areas is blocked.
5. Without Full Disk Access, areas B and C report an access issue and `bytes` is not reported as 0.
6. Cancelling a scan stops each analyzer within one directory entry (`Task.checkCancellation()` in the loops).

**Downloads**
7. A `.dmg` modified 31 days ago is listed as `review`; one modified 29 days ago is not listed.
8. A `.dmg` with an open file in the snapshot is `protected` and cannot enter a plan.
9. A `.zip` is listed only when a sibling folder of the same base name exists and the zip is older than 60 days.
10. A file in a `.photoslibrary` or `.xcodeproj` package is never listed.
11. If Downloads is not an approved root, nothing is scanned and no bytes are reported.
12. The duplicate invariant still holds: a duplicate group is never fully deleted through this area.

**iOS backups**
13. A folder with a valid `Info.plist` shows device name, iOS version and last backup date taken from it.
14. A folder without a readable `Info.plist` is `unclassified` and its delete control is disabled.
15. No backup is ever `recommended` or preselected.
16. For several backups with the same device name, exactly one (the newest) carries the "most recent" warning.
17. An encrypted backup (`IsEncrypted = true`) shows the encrypted warning.
18. The scanner never opens any file inside a backup other than `Info.plist` and `Manifest.plist`.

**Mail Downloads**
19. While `pgrep -x Mail` succeeds, or fails to run, Mail Downloads items are skipped and the result says Mail must be quit.
20. A file whose modification date is more than 2 seconds after its creation date is `protected`.
21. Nothing under `~/Library/Mail` is ever a candidate. Only the Mail Downloads path is.
22. The Mail trash is never offered for deletion; the UI shows a hint to empty it from Mail.

**UI and QA**
23. Each area shows reason, size, tier and consequence for every item before the user confirms (QA checklist).
24. The cleanup report records bytes freed per area in `CleanupHistoryStore` (QA).
25. `./script/create_qa_fixture.sh` gains fixtures for each area, and `swift run LittleTidyQA` reports their counts without touching real user data.

## 8. Open questions

1. Can installer `.dmg`/`.pkg` files whose app is already installed become `recommended` after QA? Proposal: only if the app is installed with a version at least as new as the installer's. Needs a way to read the version from the image without mounting it; unresolved.
2. Should the newest backup for a device be blocked outright instead of warned? Current choice is warn, because users with a full disk often want exactly that backup gone.
3. Do we need a user-facing "keep forever" list, so a chosen item never reappears?

## 9. Code touchpoints

- `Models/DeveloperStorageModels.swift` and `Models/Models.swift`: new categories (or a `SystemCareCategory` extension, see `SystemCare/SystemCareModels.swift`).
- New analyzers under `Analyzers/`: `DownloadsClutterAnalyzer`, `iOSBackupAnalyzer`, `MailDownloadsAnalyzer`, each `Sendable` and cancellation-aware.
- `Policies/`: a pure policy mapping each kind to tier, recoverability and consequence, like `DeveloperStoragePolicy`.
- `Execution/`: reuse `TrashPlanBuilder`, `TrashExecutor`, `DeletionPreflight` and the open-file snapshot; add a `Mail` activity rule next to the Xcode one in `DeveloperToolActivityChecker`.
- UI: one new review list per area in `Features/ReviewList` and an entry in `SidebarView`. No new settings except the Downloads approval prompt.
- Docs: update `docs/FILE_MAP.md`, `docs/SAFETY_AND_PERMISSIONS.md` and record the new rules in `docs/SAFETY_AND_PERMISSIONS.md` after review.

## 10. Change log

- 2026-11-12: first draft.
