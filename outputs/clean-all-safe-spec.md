# Spec: Clean all safe (one gesture from the Smart Care header)

Status: draft, 2026-11-12. Builds on [smart-care-spec.md](smart-care-spec.md). If this disagrees with the safety rules in [docs/SAFETY_AND_PERMISSIONS.md](../docs/SAFETY_AND_PERMISSIONS.md), those rules win.

## 1. Goal

One button in the Smart Care header, "Clean X safely", that acts on everything LittleTidy classes as `recommended` across cards, after a single confirmation. Today each card has its own Clean, which only selects items and opens the Cleanup Plan or Developer Storage.

## 2. Non-goals

- Touching `review`, `protected` or `unclassified` items, or the Trash. The Trash keeps its own Empty action.
- Skipping the confirmation, or running automatically or on a schedule.
- Changing what counts as `recommended`. Caches stay `review`.
- A new way to delete. It runs through the existing executors.

## 3. Behavior

- The button shows the headline's safe total and is disabled at 0 bytes, while a scan runs, or while another cleanup runs.
- It opens one sheet that lists, per card: item count, bytes and mechanism (Trash, `simctl`, Homebrew cleanup). Items a safety rule blocks right now (for example Xcode running) are listed separately as "skipped, and why" and never included.
- The sheet states plainly what is reversible and what is not: Trash items can be restored until the Trash is emptied; `simctl` deletions and `brew cleanup` cannot. If any irreversible item is included the Confirm button label says so.
- On Confirm, developer items go through `DeveloperStorageCleanupExecutor` and file items through `TrashExecutor`. Each executor re-applies its own checks at execution time (Xcode lock guard, simctl revalidation, approved roots, symlink protection). The sheet's list is a preview, not a permission.
- Afterwards a rescan refreshes the cards and the result screen opens ([cleanup-result-screen-spec.md](cleanup-result-screen-spec.md)).

## 4. Acceptance criteria

1. The button's byte figure equals the headline safe total at the moment the sheet opens.
2. No `review`, `protected`, `unclassified` or Trash entry is ever in the plan.
3. Cancelling the sheet changes nothing on disk.
4. If Xcode is running, items that require it are listed as skipped with the reason, and the rest still run.
5. If the open-file snapshot cannot be taken, items that need it are skipped, never run.
6. With Trash mode on, no file item is removed with `removeItem`.
7. A `simctl` or Homebrew item is never run without the sheet naming it as irreversible.
8. The result lists removed, skipped and failed items separately; a failure does not stop the remaining items.
9. Pressing the button twice, or during another cleanup, starts only one run.
10. Every safety rule (Xcode lock guard, simctl revalidation, approved roots, symlink protection, system apps, duplicate keep) holds on this path (tests exercise it with fixtures).

## 5. Open questions

1. Should irreversible items (simctl, brew) be allowed in the one-tap path, or require expanding the sheet and ticking them? Proposal: included, but listed first and named.
2. With caches as `review`, the safe total is mostly developer and AI items. Is the button still worth showing for users with no developer data? Probably hide it at 0.

## 6. Code touchpoints

`SmartCareView` header, `ScanReviewStore+SmartCare` (plan assembly across both pipelines), `DeveloperStorageCleanupExecutor`, `TrashPlanBuilder`, `TrashExecutor`. Tests in `LittleTidyTests` and `LittleTidyCoreTests`.

## 7. Implementation status (first version)

- Done: header button, one confirmation sheet with per-card totals, an irreversible-items warning, skipped items with reasons, and a short result. Execution goes through `DeveloperStorageCleanupExecutor`, which rechecks every rule per item.
- Today the safe total consists of developer and AI items only, because caches and apps are `review`. The file (Trash) pipeline is therefore not wired: it is added when a card produces `recommended` file entries.
- Criterion 1 holds when every recommended item has an automatic mechanism. Recommended items without one (for example a manual cleanup) count in the headline but not in the button; the sheet does not list them yet.
- Not done: a history entry per run, and the full result screen (see the result screen spec).

## 8. Change log

- 2026-11-12: first draft.
- 2026-11-12: first implementation, see section 7.
