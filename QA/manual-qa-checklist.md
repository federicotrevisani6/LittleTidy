# LittleTidy Manual QA Checklist

Use the generated fixture folder before scanning real user folders.

## Create Fixture

```bash
cd /Users/federicotrevisani/LittleTidy
./script/create_qa_fixture.sh
```

Fixture path:

```text
/Users/federicotrevisani/LittleTidy/QA/LittleTidyFixture
```

## Expected Fixture Contents

- `Downloads/duplicate-copy-a.bin`
- `Documents/duplicate-copy-b.bin`
- `Documents/unique-same-size.bin`
- `Movies/large-video-fixture.mov`
- `Downloads/installer-fixture.dmg`
- `Applications/OldFixtureApp.app`
- `Library/Developer/Xcode/DerivedData/FixtureProject`
- `Library/Developer/Xcode/iOS DeviceSupport/18.4`
- `Library/Developer/Xcode/Archives/2026-07-11/Fixture 11-07-26.xcarchive`
- `Library/Developer/XCTestDevices`
- fixture Simulator device and runtime directories

## App QA Steps

Run the automated fixture audit first:

```bash
cd /Users/federicotrevisani/LittleTidy
swift run LittleTidyQA
```

Expected output:

```text
scannedFiles=10
duplicates=1
largeFiles=5
unusedApps=1
developerItems=6
developerBytes=1310720
```

1. Open the Xcode project:

   ```bash
   open /Users/federicotrevisani/LittleTidy/LittleTidy.xcodeproj
   ```

2. Run the `LittleTidy` scheme.

3. In a Debug build, expand `Scan Settings & Folders`, then click `Use QA Fixture`.

4. Confirm the overview shows this file root:

   ```text
   /Users/federicotrevisani/LittleTidy/QA/LittleTidyFixture
   ```

5. Confirm the overview shows this app root:

   ```text
   /Users/federicotrevisani/LittleTidy/QA/LittleTidyFixture/Applications
   ```

6. Quit and relaunch the app, then confirm the fixture file root and app root are still selected.

7. Confirm `Duplicate minimum`, `Large file threshold`, `Hidden files`, and `System folders` settings were restored.

8. Confirm `Large file threshold` is `1 MB`.

9. Confirm `Access Readiness` shows selected folders as accessible and includes the Full Disk Access action.

10. Click `Refresh` in `Access Readiness` and confirm the readiness rows remain consistent.

11. Click `Start Scan`.

12. While scanning, verify the overview shows the scan phase, current root path, root count, and live file/byte/skipped/permission counters.

13. Verify the overview shows scanned files and bytes after the scan completes.

14. If a selected folder contains unreadable or excluded entries, expand `Scan Issues` and verify the skipped path and reason are shown.

15. Verify `Duplicates` shows one duplicate group for the two duplicate `.bin` files.

16. Expand the duplicate group.

17. Verify one copy is marked `Keep`.

18. Select and deselect the removable copy, and verify the selected byte count changes.

19. Use the review search field to search for `duplicate` and confirm the duplicate rows filter down.

20. Change the review filter from `All` to `Selected` and confirm only selected candidates remain visible.

21. Change the review filter to `High` and confirm high-confidence rows remain visible.

22. Verify `Large Files` shows the generated `.mov` and `.dmg` files.

23. Use a row menu to `Preview` a duplicate or large file and confirm a Quick Look preview opens without selecting the item.

24. Use a duplicate copy row menu to `Preview` an individual duplicate copy.

25. Change the review sort control between `Largest`, `Name`, and `Location`, then verify visible review rows reorder.

26. Verify `Unused Apps` shows `Old Fixture App`.

27. Open `Cleanup Plan` with nothing selected and confirm the validation card says no items are selected and `Move Selected to Trash` is disabled.

28. Select candidates from at least two categories, open `Cleanup Plan`, and confirm selected items are grouped by category.

29. Confirm the validation card says the plan is ready and shows any safety warnings for duplicates or unused apps.

30. Confirm each cleanup category group shows the selected count and byte total.

31. Use `Reveal in Finder` before cleanup to verify the selected item.

32. Only move generated fixture items to Trash during QA.

33. After cleanup, verify `Cleanup Report` lists each moved, skipped, or failed source path with its status.

## Developer Storage QA

### Inventory
1. Launch LittleTidy and open `Developer Storage` from the sidebar.
2. Confirm the scan runs without blocking navigation or window interaction.
3. Confirm the summary keeps `Recommended`, `Review`, `Protected`, and `Unclassified` totals separate.
4. Confirm `Recommended` shows "At least X freed right away" when part of it is shared with clones or held by a local snapshot.
5. Confirm booted Simulator devices are `Protected` and cannot be selected.
6. Confirm ordinary shutdown Simulator devices are `Review`, are not preselected, and can be explicitly selected with a native macOS checkbox.
7. Confirm DerivedData shows one `Recommended`, preselected row per project, named after the project. A folder without `info.plist` (for example one holding only `SourcePackages`) is still named after the project; `ModuleCache.noindex` and similar show "Shared Xcode build data".
8. Confirm Archives are `Protected`, never preselected, and can be explicitly selected for Trash-restorable cleanup.
9. Confirm each filesystem-backed row can be revealed in Finder.
10. Confirm `~/.swiftpm/cache` (a link to `~/Library/Caches/org.swift.swiftpm`) is not listed; no symbolic link appears as a row.

### XCTest clones
11. With no test running, confirm XCTest clones listed by `xcrun simctl --set testing list devices` appear as `Recommended`, preselected, with the clone reason. Folders simctl does not list stay `Unclassified`.
12. Start a parallel test run in Xcode. Rescan while a clone is booted and confirm every clone of the set, including shutdown ones, is `Protected` with "An Xcode test session is using clones from this set".
13. While `xcodebuild test` runs from Terminal, select a shutdown clone, confirm cleanup, and confirm it is skipped with an `xcodebuild` reason.

### Xcode open
14. With Xcode open on one project, confirm the banner says projects and Simulators in use are protected, and `Review & Clean` stays enabled unless every selected item waits for Xcode.
15. Clean the build data of a project that is not open and confirm it is removed; confirm the open project's build data is skipped with "In use by Xcode…".
16. Confirm Device Support, archives, runtimes, and package caches are skipped with "Quit Xcode before cleaning this item" while Xcode runs.

### Homebrew
17. With outdated Homebrew versions present (for example after `brew upgrade`), confirm a `Homebrew Old Versions & Downloads` row appears under Package Manager Caches with the `brew cleanup --dry-run` estimate.
18. Clean it and confirm the result reports the size Homebrew says it freed. Confirm it is never blocked by Xcode.

### Cleanup, results, and settings
19. Select only disposable developer data and open `Review & Clean`. Confirm the dialog states the item count, size, consequence, and whether operations are irreversible.
20. Cancel and confirm nothing changes.
21. In Settings › Deletion & Safety, switch to `Permanently Delete` without relaunching. Confirm the cleanup bar says "Selected items will be deleted permanently, skipping the Trash" and the dialog offers `Delete Permanently`. Switch back to the Trash and confirm the wording returns.
22. After a cleanup, confirm removed rows leave the list immediately, before the rescan finishes.
23. Confirm the result shows the total removed, "At least X freed right away", the measured change in free space, and any bytes still in the Trash.
24. If anything was skipped or failed, expand "Why N items were not removed" and confirm each item shows its reason.
25. For destructive QA, use only disposable fixtures and a simulator created specifically for the test; never use a real development device.

### Claude sessions and AI app caches
26. With a closed Claude session in `/private/tmp/claude-<uid>`, confirm one `Claude session · <project>` row appears, `Recommended` when untouched for an hour, with the session ID prefix and last-used time. The current session and any session listed alive in `~/.claude/sessions` must not appear as a whole session.
27. Reopen (resume) a listed session, then clean it without rescanning, and confirm it is skipped as running again.
28. Confirm Codex and Antigravity caches appear under AI Caches & Logs; with the app open, cleaning a cache that has files open is skipped with an open-files reason.
29. Confirm the duplicated-looking Simulator rows now read "<model> · <OS version>" and empty XCTest clones are not preselected.

### Time Machine local snapshots
30. With a local snapshot present (`tmutil listlocalsnapshots /`), confirm the banner names the latest snapshot time and how much recommended data it holds.
31. After a cleanup in permanent-delete mode (or after emptying the Trash), confirm the snapshot panel offers `Release X…` only when at least 100 MB did not come back.
32. Confirm the release dialog explains that local restore points are lost and Time Machine disk backups are unaffected, and mentions the Trash when items are still there.
33. Release and confirm the panel reports snapshots removed and the measured free space; check with `tmutil listlocalsnapshots /` that the oldest snapshots were removed.

## Known QA Gaps

- macOS does not expose a simple Full Disk Access boolean; `Access Readiness` surfaces selected-root readability and opens the Privacy settings pane.
- Runtime removal is review-only and uses the installed Xcode's supported `simctl runtime delete` command after revalidating the runtime and its device dependencies.
- XCTest folders not registered with `simctl --set testing` remain diagnosis-only.
- `LittleTidyTests` (app-target tests) run only from the Xcode project, not with `swift test`.
- Snapshot release asks macOS to thin by amount; macOS decides how many snapshots to remove, oldest first.
