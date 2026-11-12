# Spec: Leftovers of apps that are already gone

Status: draft, 2026-11-12. Builds on [smart-care-spec.md](smart-care-spec.md) (Phase 3 card "Leftovers of removed apps"). Today leftovers are found only when the user trashes an app while LittleTidy is watching (`AppTrashWatcher`).

## 1. Goal

Find app data in `~/Library` whose app is no longer installed, explain the evidence, and let the user review it. The risk is high: a wrong match deletes another app's data. The design is built around never guessing.

## 2. Non-goals

- Fuzzy or name-based matching. Exact bundle identifiers only.
- `~/Library/Group Containers`, ever (see the "No Group Containers in Leftovers" invariant).
- Anything with a `com.apple.` identifier.
- Preselecting or labelling anything `recommended`. All results are `review`.
- Looking outside the current user's `~/Library`.

## 3. Detection

Candidate locations, matched by exact folder or file name equal to a bundle ID (with the usual extensions): `Application Support`, `Caches`, `Preferences` (`.plist`), `Containers`, `Saved Application State` (`.savedState`), `HTTPStorages`, `WebKit`, `Logs`.

An identifier counts as **installed** when any of these is true:

- A bundle with that exact ID exists in `/Applications`, `~/Applications`, `/System/Applications`, or any user-approved app root.
- It is the ID of any bundle nested inside an installed app (helpers, login items, XPC services, plug-ins), collected by walking each app bundle.
- It starts with an installed ID plus a dot (helpers and extensions named `<app id>.<suffix>`).
- A process with that ID is running.
- Spotlight reports an app with that ID anywhere on a mounted volume.

Otherwise it is an **orphan candidate**, and is listed only when its newest modification is older than 90 days.

## 4. Presentation

- Card "Leftovers of removed apps" with count and bytes, always `review`.
- Each item shows the identifier, the folder, size, last modified date and the evidence: "No app with this ID was found in: <roots checked>".
- Live line while scanning shows the location being read.
- Moves to the Trash only, through the normal plan builder. No permanent deletion.

## 5. Acceptance criteria

1. Matching is by exact identifier. A folder named only similarly to an app is never listed.
2. `com.apple.*` identifiers and anything under `Group Containers` are never listed.
3. An ID that equals, or is a dot-suffix of, any installed or nested bundle ID is treated as installed.
4. An ID belonging to a running process is treated as installed.
5. Nothing modified in the last 90 days is listed.
6. Every result is `review`, none preselected, and the card never counts in the "safe" total.
7. Each result states the roots that were checked for the app.
8. Without Full Disk Access, protected folders (such as `Containers`) report `needsAccess` rather than "no leftovers".
9. A fixture with an app installed outside the standard roots (approved app root) is not reported.
10. Cleanup goes through `TrashPlanBuilder`: symlinks refused, approved-root rules respected.
11. A leftover found here and later claimed by the uninstall prompt appears once.

## 6. Open questions

1. Apps on external volumes or removed disks look uninstalled. Proposal: skip results if any removable volume is mounted or was recently mounted, or say so in the evidence line.
2. Is 90 days the right age? Proposal: setting, default 90.
3. Homebrew cask apps in non-standard locations: covered by the Spotlight check, to be verified.

## 7. Code touchpoints

`AppUsageAnalyzer.relatedAppData` (reuse its location list), a new `OrphanLeftoverAnalyzer`, `SmartCareCardID` (new card, after unused apps), `TrashPlanBuilder`.

## 8. Change log

- 2026-11-12: first draft.
