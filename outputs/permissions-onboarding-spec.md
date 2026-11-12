# Spec: Permissions guide (first launch and "needs access" states)

Status: draft, 2026-11-12. Builds on [smart-care-spec.md](smart-care-spec.md).

## 1. Goal

Explain, before the user hits a wall, what each macOS permission unlocks in LittleTidy, and take them to the right Settings pane with one click. Today there is detection (`FullDiskAccess` probes, `PermissionReadinessItem`) and a banner, but no guided step, and several Smart Care cards show "needs access" with no way forward.

## 2. Non-goals

- Granting permissions or bypassing consent prompts. Only the user can allow them.
- Requiring any permission to use the app. Everything works in a reduced mode.
- Requesting the optional administrator helper. That stays separate, in System Care.
- Telemetry on who grants what.

## 3. Behavior

- **First launch:** one screen, skippable. For each permission, say in a sentence what it unlocks and which Smart Care cards depend on it. Initially: Full Disk Access (Trash, Mail, backups, some caches), notifications (alerts, app-removal prompts).
- **Never automatic:** the app never opens System Settings by itself. Each permission has a button that does.
- **Detection by probe, not by guess:** Full Disk Access is "granted" only when the existing probe of protected locations succeeds. A failed or ambiguous probe shows "not confirmed", never "granted".
- **Recheck on return:** when the app becomes active again, probes re-run, and cards in `needsAccess` refresh without a manual rescan.
- **Cards link here:** a `needsAccess` card shows a button "Allow access" that opens the same step for that permission.
- **Not now is remembered:** dismissing does not nag again at launch. The state stays reachable from Settings and from the cards.

## 4. Acceptance criteria

1. The guide never opens System Settings without a click.
2. "Granted" is shown only when the probe succeeds; an error or timeout shows "not confirmed".
3. Returning to the app after granting access updates cards from `needsAccess` to their real state without a manual rescan.
4. Every `needsAccess` card names the permission it needs and links to its step.
5. Dismissing the first-launch screen does not show it again until the user opens it.
6. With no permission granted, Smart Care still runs and every unreadable card says why, never "0 bytes".
7. The text states plainly that LittleTidy reads these locations on this Mac and sends nothing out.
8. The screen scales with Dynamic Type and works with VoiceOver (QA).

## 5. Open questions

1. Where does it live when not first launch: a sidebar entry, or inside Settings? Proposal: Settings, plus the card links.
2. Add Automation or Accessibility? No, nothing needs them today.

## 6. Code touchpoints

`FullDiskAccess.swift`, `FullDiskAccess+AppKit.swift`, `PermissionReadinessItem`, `ScanReviewStore.refreshPermissionReadiness`, `AppUninstallNotificationManager.requestAuthorizationIfNeeded`, a new `Features/Permissions/` view, `SmartCareView` cards.

## 7. Implementation status (first version)

- Done: a guide sheet that opens once at launch when something is not confirmed and from every "Allow Access…" button, with "Not Now" remembered; "Allowed" only when the probe succeeds, otherwise "Not confirmed"; cards refresh when the app becomes active again, without a rescan; it never opens System Settings by itself.
- Only Full Disk Access is covered. Notifications join when the alerts spec lands, because nothing needs them before.
- Not done: an entry in Settings to reopen the guide (it is reachable from the cards), and a check in the running app of the step after granting access.

## 8. Change log

- 2026-11-12: first draft.
- 2026-11-12: first implementation, see section 7.
