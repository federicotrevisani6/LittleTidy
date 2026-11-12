# Spec: Cleanup result screen (and Restore)

Status: draft, 2026-11-12. Builds on [smart-care-spec.md](smart-care-spec.md) and [clean-all-safe-spec.md](clean-all-safe-spec.md).

## 1. Goal

After any cleanup, show an honest summary: what was removed, what space is actually free now, what is waiting in the Trash, what was skipped and why, and how to undo it. Today the result lives inside the Cleanup Plan view and the Developer Storage view separately.

## 2. The honesty problem

Moving to the Trash frees no disk space until the Trash is emptied, and a Time Machine local snapshot can hold blocks of deleted data. The screen must never say "X GB freed" for bytes that are only in the Trash. It reports three numbers:

- **Freed now:** removed for real (simctl deletions, brew cleanup, Trash emptied) and not held by a snapshot.
- **In the Trash:** moved there; freed when the Trash is emptied.
- **Held by a snapshot:** the existing `bytesNotYetFreed` figure, shown only when meaningful.

## 3. Non-goals

- A chart, a share image or any telemetry.
- Persisting full item lists beyond the existing history entry.
- Restoring items removed for real (simctl, brew, emptied Trash). That data is gone.

## 4. Content

- Headline with the three numbers above.
- Per-card breakdown (bytes and counts), using the same card names as Smart Care.
- "Skipped" and "Failed" lists with the reason for each (Xcode running, files open, needs access, locked).
- Actions: **Open Trash**, **Empty Trash** (opens the Trash card's own confirmation; never runs directly), **Restore all**, **Back to Smart Care**.
- The result is written to `CleanupHistoryStore` per card (not only per `CleanupCategory`).

## 5. Restore

`TrashedItem` records both the original URL and the Trash URL. Restore moves items back with `FileManager.moveItem`.

Rules:

- Restore only items still present at their Trash URL. Anything missing is reported, not an error.
- Never overwrite: if the original path now exists, the item stays in the Trash and is reported with its path.
- If the original parent folder no longer exists, it is not recreated; report it.
- Symlinks are never followed; the item is moved as a link.
- Restore is Trash-only. It must not touch simctl or brew items and must not offer them.
- Restoring items that LittleTidy listed first in a later Trash emptying sheet is unaffected.

## 6. Acceptance criteria

1. The screen never counts Trash-held bytes as "freed now".
2. "Held by a snapshot" appears only when the existing threshold (100 MB, or 10% of the run) is met.
3. Skipped and failed items each show a reason, and none is silently dropped.
4. Empty Trash from this screen opens the Trash card's confirmation sheet; it never empties directly.
5. Restore puts back an item whose original path is free, and leaves the Trash copy gone.
6. Restore never overwrites an existing file or folder; a conflict leaves the item in the Trash and is listed.
7. Restore of an item already removed from the Trash reports "no longer in the Trash".
8. Irreversible items (simctl, brew, emptied Trash) show no Restore control.
9. A run with only failures still shows the screen, with no success wording.
10. The history entry records bytes per card, and existing history entries still load.

## 7. Open questions

1. Keep the Cleanup Plan's own result or replace it with this screen everywhere? Proposal: replace.
2. How long to keep the Restore option after leaving the screen? Proposal: until the app quits or a new cleanup starts, since the list is in memory only.

## 8. Code touchpoints

`CleanupPlanView` and `DeveloperStorageView` result sections, `CleanupReportItem`, `TrashedItem`, `CleanupHistoryEntry` and `CleanupHistoryStore` (add per-card bytes, keep decoding old entries), a new `Features/CleanupResult/` view, a small restore helper in `LittleTidyCore/Execution`.

## 9. Change log

- 2026-11-12: first draft.
