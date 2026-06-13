# MacCleaner Manual QA Checklist

Use the generated fixture folder before scanning real user folders.

## Create Fixture

```bash
cd /Users/federicotrevisani/MacCleaner
./script/create_qa_fixture.sh
```

Fixture path:

```text
/Users/federicotrevisani/MacCleaner/QA/MacCleanerFixture
```

## Expected Fixture Contents

- `Downloads/duplicate-copy-a.bin`
- `Documents/duplicate-copy-b.bin`
- `Documents/unique-same-size.bin`
- `Movies/large-video-fixture.mov`
- `Downloads/installer-fixture.dmg`
- `Applications/OldFixtureApp.app`

## App QA Steps

Run the automated fixture audit first:

```bash
cd /Users/federicotrevisani/MacCleaner
swift run MacCleanerQA
```

Expected output:

```text
scannedFiles=5
duplicates=1
largeFiles=5
unusedApps=1
```

1. Open the Xcode project:

   ```bash
   open /Users/federicotrevisani/MacCleaner/MacCleaner.xcodeproj
   ```

2. Run the `MacCleaner` scheme.

3. Click `Use QA Fixture` in the overview's `Scan Settings` section.

4. Confirm the overview shows this file root:

   ```text
   /Users/federicotrevisani/MacCleaner/QA/MacCleanerFixture
   ```

5. Confirm the overview shows this app root:

   ```text
   /Users/federicotrevisani/MacCleaner/QA/MacCleanerFixture/Applications
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

## Known QA Gaps

- macOS does not expose a simple Full Disk Access boolean; `Access Readiness` surfaces selected-root readability and opens the Privacy settings pane.
