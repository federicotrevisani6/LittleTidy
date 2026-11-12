# Spec: Low-space and reminder alerts (and optional menu bar)

Status: draft, 2026-11-12. Builds on [smart-care-spec.md](smart-care-spec.md).

## 1. Goal

Tell the user when it matters (disk nearly full, a long time since a cleanup) even when LittleTidy is not in the foreground, without turning it into a background scanner. Some commercial cleaners do this with a separate menu bar app. We start smaller.

## 2. Non-goals

- Background scanning, background cleanup, or deleting from a notification or the menu bar.
- Monitoring RAM, CPU, battery, network or drive temperature.
- Telemetry. Nothing leaves the Mac.
- On by default. Everything here is opt-in.

## 3. Phases

**Phase A: notifications from the running app.** Uses the notification setup already in the app. Works while LittleTidy is open or running in the background.

**Phase B: menu bar presence.** A `MenuBarExtra` showing free space and the Smart Care headline from the last scan. Whether it runs when the main window is closed, and whether it starts at login, is an open question below, because it adds an always-running process.

## 4. Alerts

| Alert | Trigger | Limit |
|---|---|---|
| Low disk space | Available space for important usage below a threshold (default: under 10% of the volume or under 20 GB, whichever is lower) | At most once every 7 days |
| Cleanup reminder | History exists and the last cleanup is older than 30 days | At most once every 30 days |

Rules:

- The only background work is reading the volume's available capacity, which is cheap and needs no scan.
- A notification opens Smart Care. It never starts a scan or a cleanup by itself.
- The text states what is true now ("12 GB free of 494 GB") and never promises a number it has not measured. After a scan it may add the last known safe total, labelled with its date.
- The user can turn each alert off, change the threshold, and snooze.

## 5. Acceptance criteria

1. Both alerts are off until the user enables them, and enabling asks for notification permission only at that moment.
2. No alert fires more often than its limit, including after relaunch (the last-sent date is persisted).
3. The disk check reads capacity only; it never enumerates files.
4. Tapping a notification opens Smart Care and does not scan or delete.
5. Without notification permission nothing is sent and Settings says why.
6. The cleanup reminder never fires for a user with no cleanup history.
7. Disabling an alert cancels any pending notification of that kind.
8. A figure shown from an old scan always shows its date.

## 6. Open questions

1. Phase B: a login item (`SMAppService.mainApp` or a helper) that keeps a menu bar icon alive needs a new target and project changes (`Package.swift` and `project.xcproj`). Is the always-running cost acceptable, or does Phase A suffice?
2. Should the menu bar offer "Scan" or only open the app? Proposal: only open the app.

## 7. Code touchpoints

`AppUninstallNotificationManager` (generalize or add an alerts manager), `ScanPreferencesStore` (opt-ins, thresholds, last-sent dates), `CleanupHistoryStore`, `SettingsView` (new Alerts tab), later a `MenuBarExtra` scene.

## 8. Change log

- 2026-11-12: first draft.
