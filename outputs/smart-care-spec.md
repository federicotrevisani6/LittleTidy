# Spec: Smart Care (goal-based home for everyday cleanup)

Status: draft, 2026-11-12. Nothing here is implemented.
Supersedes the scope of [downloads-ios-backups-mail-spec.md](downloads-ios-backups-mail-spec.md), which becomes Phase 2 of this spec.
Origin: comparison with CleanMyMac 5.7.4 (screens and module names only). We borrow the idea of a goal-based home, not its wording, art or behavior.

If this spec disagrees with the safety invariants in [AGENTS.md](../AGENTS.md), the invariants win and this spec gets fixed.

## 1. Problem

LittleTidy is strong on developer storage and weak everywhere else. Concretely:

- The home screen ("System Storage Overview", "Storage Breakdown", "Categories", "Largest Folders") explains where space is, not what the user can free or with which action.
- The sidebar is organised by tool (Duplicates, Large Files, Unused Apps, Caches), not by what the user wants.
- Everyday space (system and app caches, logs, trash, installers, Mail attachments, iOS backups, orphan app data) is either buried in one flat cache list or not reported.
- The developer area has cards, explanations and one-gesture actions. The rest has none of that.

## 2. Goal

One scan from the home screen produces a small set of cards, each with a name a normal person understands, one number, a tier breakdown and one obvious action. Everything keeps LittleTidy's guarantees: explained, tiered, reversible, fail-closed.

## 3. Non-goals

- Malware scanning, browser privacy cleanup, app updates, network tools.
- "Performance boosters": freeing RAM, repairing permissions, periodic scripts. Existing maintenance operations (`flushDNS`, `rebuildSpotlight`) stay available as optional tools and never count toward any total.
- Removing CPU architectures from app binaries (breaks code signatures).
- Any automatic or scheduled deletion.
- A new engine. Cards are built from existing and specified analyzers. No analyzer may weaken an invariant to fill a card.
- A total labelled "junk" that includes anything not `recommended`.

## 4. Principles

1. **One number per card, honestly named.** "Caches you can safely clear" is fine. "Junk" is not, unless every byte is `recommended`.
2. **Two totals, never merged.** The headline shows `recommended` bytes ("clean safely") and `review` bytes ("review first") separately. `protected` and `unclassified` are never in a total.
3. **Count once.** A path or file belongs to exactly one card (precedence in section 6). Hard links and clones use `APFSReclaimEstimator` so the headline matches what the volume actually gains.
4. **Unknown is not zero.** A card that cannot read its location shows "Needs access" with the fix, never "0 bytes".
5. **Clean means Recommended only.** A card's Clean button acts only on `recommended` items. Anything with a `review` tier opens the review list.
6. **Same engine underneath.** Execution goes through `TrashPlanBuilder`, `TrashExecutor`, `DeveloperStorageCleanupExecutor` and the existing mechanisms. Smart Care adds no new way to delete.

## 5. Experience

### Home

- Default sidebar entry, replacing Overview. The old Overview content (Storage Breakdown, Largest Folders, permission banner) moves into the existing Storage section.
- Before the first scan: one prominent Scan button and one line saying what it reads.
- During the scan: a live line with the card currently being scanned and the path being read, plus progress and Cancel. Cancel keeps the cards already finished.
- After the scan: headline "X you can clean safely · Y to review", then three groups of cards.

### Groups and cards

| Group | Card | Source | Notes |
|---|---|---|---|
| **Cleanup** | System and app caches | `CacheAnalyzer` (user caches, containers, logs, saved state, HTTP storages) | Split from the flat cache list |
| | Developer | `DeveloperStorageAnalyzer` | One card, total plus tier split, opens `DeveloperStorageView` |
| | AI tools | `DeveloperStorageAnalyzer` (`aiCaches`, `aiModelsAndAgents`, sessions) | Models are `review`; caches `recommended` only when the open-file rule passes |
| | Trash | `~/.Trash` | Has an Empty action; see section 5a. Always `review`, never in the "safe" total |
| | Installers and downloads | New, Phase 2 (Downloads spec, area A) | |
| | Mail attachments | New, Phase 2 (Downloads spec, area C) | |
| | iOS backups | New, Phase 2 (Downloads spec, area B) | Always `review` |
| **Apps** | Unused apps | `AppUsageAnalyzer` | |
| | Leftovers of removed apps | New, Phase 3 | Exact bundle ID only, never Group Containers |
| **Maintenance** | Time Machine snapshots | `LocalSnapshotInventory`, `LocalSnapshotReleaser` | Release via `tmutil thinlocalsnapshots` only |
| | Login and background items | `SystemCareAnalyzer.startupEntries()` | Read-only in Phase 1 |

Cards with nothing to show collapse into a single line ("Nothing to clean here") instead of an empty tile. The user can still open them.

### Card anatomy

Title, one number, tier split ("12.4 GB safe · 3.1 GB review"), a one-sentence explanation, and up to two buttons:

- **Review** always, opening the existing review list filtered to the card.
- **Clean** only when the card has `recommended` bytes and no blocking condition. It opens one confirmation sheet with item count, bytes, "Moved to Trash, restorable until you empty it" and the Confirm button.

States: `scanning`, `ready`, `needsAccess`, `blocked` (for example "Quit Xcode to clean this"), `empty`, `failed`.

## 5a. Emptying the Trash (decided 2026-11-12)

Decision: the Trash card has an Empty action. This is the one place where Smart Care deletes permanently, so it is an explicit, narrow exception to the "Trash Over Permanent Delete" invariant, and it needs the AGENTS.md amendment below before it ships.

**Why it is acceptable:** the user (or LittleTidy, on their request) already moved these items to the Trash. Emptying it is the macOS action users expect, and without it a cleanup never frees the space it promised.

**Rules**

- Scope is the direct children of the user's own `~/.Trash` only. External volumes' `.Trashes` and any other folder are out of scope.
- Empty is never part of another card's Clean action and is never preselected. It has its own button and its own confirmation sheet.
- It is independent of the permanent-delete toggle in Settings. Turning that toggle on or off does not enable or disable Empty, and Empty never turns it on.
- The confirmation sheet states: number of items, total bytes, "This cannot be undone", and, when applicable, "Includes N items LittleTidy moved here on <date>". Items LittleTidy trashed in its last cleanup run are listed first, because they are the user's only undo for that run.
- Symlinks are removed as links, never followed. Nothing outside `~/.Trash` can be reached through one.
- Items with an open file in a fresh `lsof` snapshot are skipped and reported. A missing snapshot blocks Empty entirely (fail-closed).
- Files the user cannot delete without administrator rights (foreign owner, immutable flag) are found first with `DeletionPreflight`, skipped, and reported; Empty never asks for elevated rights.
- No shell, no `rm`. Removal uses `FileManager` on each child with an explicit item list, and a failure on one item does not stop the rest. The result lists removed, skipped and failed items.
- Without Full Disk Access the card shows `needsAccess` and Empty is disabled.

**Proposed AGENTS.md invariant (add to the table after review):**

| Invariant | Implementation Rule |
|---|---|
| **Empty Trash Only On Request** | Permanent removal is allowed in exactly one place: the Smart Care Trash card, for direct children of `~/.Trash`, after its own confirmation that states the action cannot be undone. It is not governed by the permanent-delete toggle, is never combined with another action, never follows symlinks and fails closed on a missing open-file snapshot. |

## 6. Precedence (count once)

When two analyzers could claim the same path, the first in this order owns it:

1. Developer and AI items (`DeveloperStorageAnalyzer`)
2. Mail attachments, iOS backups, installers (Phase 2)
3. System and app caches
4. Trash
5. Unused apps and leftovers
6. Duplicates and large files (stay in their own review lists, outside the headline total)

A path claimed by a higher card is removed from lower cards before sizes are computed.

## 7. Acceptance criteria

Each is covered by a test in `LittleTidyCoreTests` or `LittleTidyTests` unless marked QA.

**Totals and counting**
1. The headline "safe" figure equals the sum of `recommended` item bytes over all cards, and the "review" figure the sum over `review` items. `protected` and `unclassified` bytes appear in neither.
2. No path appears in more than one card. A fixture where the same folder matches two analyzers shows it only in the higher-precedence card.
3. Two hard links to the same file count once in the headline.
4. A card whose location is unreadable shows `needsAccess` and contributes nothing to the headline; its bytes are not reported as 0.

**Actions**
5. A card's Clean button is enabled only if it has `recommended` bytes and no blocking condition; it never includes a `review` item.
6. Clean opens one confirmation sheet before any file is touched. Cancelling it changes nothing on disk.
7. Clean runs through the existing plan builders and executors. Every invariant in AGENTS.md section 2 still holds (Xcode lock guard, simctl revalidation, approved roots, symlink protection, system apps, duplicate keep).
8. With Trash mode on, no item is removed with `removeItem`.
9. If Xcode is running, Developer card items that require it show `blocked` with the reason; the Clean button does not include them. If the check fails, the same result.
10. The Time Machine card releases space only via `tmutil thinlocalsnapshots`, after the existing explicit confirmation.
10a. Empty Trash removes only direct children of `~/.Trash`. A fixture containing a symlink inside the Trash that points outside it removes the link and leaves the target untouched.
10b. Empty Trash is never executed by another card's Clean, by the headline action, or without its own confirmation sheet. Cancelling the sheet changes nothing.
10c. The Empty confirmation states the item count, bytes and that it cannot be undone, and lists items from LittleTidy's last cleanup run first.
10d. With a nil open-file snapshot, Empty is blocked. An item with an open file is skipped and reported while the others are removed.
10e. Items needing administrator rights are skipped and reported; no elevation prompt is shown.
10f. The permanent-delete toggle has no effect on Empty, and Empty does not change the toggle.
10g. Trash bytes never appear in the "safe" headline total.
10h. External volumes' `.Trashes` are never read or modified.

**Scan behavior**
11. Cancelling mid-scan stops within one directory entry per analyzer and keeps finished cards.
12. The scan reads fixed system locations without needing approved roots, and general file analysis (duplicates, large files) still uses only approved roots.
13. A second scan while one is running is ignored, not queued.
14. The live line shows the card and path being read and never shows a path outside what that card scans.

**Presentation**
15. Cards use only the words Junk or Clutter in a title when every byte in that card is `recommended`.
16. An empty card collapses to the single "Nothing to clean here" line and can still be opened.
17. Every card shows tier split and a one-sentence explanation of the consequence (QA).
18. The old Overview content remains reachable from the Storage section (QA).
19. All text is available to VoiceOver, scales with Dynamic Type, and meets contrast requirements in light, dark and increased contrast (QA).
20. The completed cleanup records bytes freed per card in `CleanupHistoryStore` (QA).

## 8. Phases

**Phase 1: the shell, no new analyzers.**
Smart Care home, card model, three groups, precedence, headline totals, and cards for what already exists: System and app caches, Developer, AI tools, Trash (with Empty, section 5a), Unused apps, Time Machine snapshots, Login and background items (read-only). Ships on its own and already fixes the "home explains nothing" problem.

**Phase 2: the missing everyday space.**
Installers and downloads, Mail attachments, iOS backups. Defined in the Downloads spec; criteria there apply unchanged.

**Phase 3: apps and startup.**
Leftovers of removed apps (exact bundle ID, scanned in the background as the card text shows), and optional removal of login items through `SMAppService`.

## 9. Open questions

1. **Trash: decided.** Empty action with its own confirmation, see section 5a. Still open: whether the AGENTS.md amendment wording is accepted as written.
2. **External volumes' Trash** (`/Volumes/*/.Trashes`): out of scope for now (criterion 10h). Revisit only with a safe preview.
3. **Naming.** English strings are assumed. Final copy for card titles and explanations needs review through the ux-writing pass, and an Italian localization decision.
4. **Headline wording.** Whether to show the review total on the home or only inside cards.
5. **Visual identity.** CleanMyMac uses a different colored full-screen background per area. LittleTidy should keep its own Tahoe-styled surfaces (`CleanerSurface`) unless a design pass says otherwise.

## 10. Code touchpoints

- `Features/Overview/OverviewView.swift`: replaced by a Smart Care home; old content moves to the Storage section.
- `Features/Sidebar/SidebarView.swift`, `Features/Detail/DetailView.swift`: new default entry and routing; sections regrouped by goal while keeping the existing lists reachable.
- New `SmartCare/` in `LittleTidyCore`: `SmartCareCard`, `SmartCareCardState`, `SmartCareBuilder` (pure, `Sendable`; maps analyzer output to cards, applies precedence and totals).
- `State/ScanReviewStore.swift`: orchestrates the scan phases and publishes cards. Keep the card builder outside the store so it is testable without UI.
- Reuse: `CacheAnalyzer`, `DeveloperStorageAnalyzer`, `AppUsageAnalyzer`, `LocalSnapshotInventory`, `SystemCareAnalyzer`, `APFSReclaimEstimator`, `TrashPlanBuilder`, `TrashExecutor`, `DeveloperStorageCleanupExecutor`, `CleanupHistoryStore`.
- Docs: update `docs/FILE_MAP.md` (it already lags: `SystemCare/` and several analyzers are missing) and `docs/ARCHITECTURE.md`.

## 11. Change log

- 2026-11-12: first draft, written after a side-by-side with CleanMyMac screenshots from the user.
- 2026-11-12: Trash card now has an Empty action (user decision). Added section 5a, criteria 10a to 10h, the proposed AGENTS.md invariant, and resolved open question 1. Trash moves into Phase 1 as a full card, not read-only.
