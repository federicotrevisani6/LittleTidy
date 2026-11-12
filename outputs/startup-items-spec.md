# Spec: Login and background items you can manage

Status: draft, 2026-11-12. Builds on [smart-care-spec.md](smart-care-spec.md). Today the Smart Care card is a count, from `SystemCareAnalyzer.startupEntries()`.

## 1. Goal

Turn the count into a list the user understands, flag entries that point to something missing, and let them disable user-level items reversibly.

## 2. What the current list can and cannot see

It reads launchd property lists in `~/Library/LaunchAgents`, `/Library/LaunchAgents` and `/Library/LaunchDaemons`. It does not see items apps register through the Service Management framework (the "Login Items & Extensions" list in System Settings). So any total must be labelled as launchd items, not "everything that starts with your Mac". Reading the full Background Task Management list needs elevated rights or private tooling, which this spec does not use.

## 3. Non-goals

- Deleting any plist or executable.
- Changing `/Library/LaunchDaemons`, `/Library/LaunchAgents`, or anything with a `com.apple.` label.
- Changing items belonging to a running app without saying so.
- A "boost startup" promise. The card says what an item is, not how much faster the Mac will be.

## 4. Phases

**Phase A, read-only (no new risk).**
- Group by owner: resolve the executable to its app bundle and show the app's name and icon.
- Mark scope: this user or all users. Mark Apple items as protected and collapsed.
- Flag broken items: the executable in the plist no longer exists. Describe them in plain words ("the app it starts was removed").
- Show whether the item is loaded now, when it can be read without privileges.

**Phase B, disable and enable user-level items only.**
- Disable with `/bin/launchctl disable gui/<uid>/<label>` and, if loaded, `bootout`. Enable with the inverse. Both are called through `Process` with an explicit executable and arguments, never a shell.
- Nothing is removed. The plist stays; the change is undone by Enable, and the list shows disabled items with an Enable button.
- Re-read the entry immediately before acting. If the label, path or executable changed since the scan, refuse and refresh.

## 5. Acceptance criteria

1. The card and list state they cover launchd items only.
2. Entries with `com.apple.` labels, anything in `/Library/*`, and symlinked plists are never offered a Disable.
3. A broken item is shown as broken only when its executable path is confirmed missing, not when it cannot be read.
4. Disable never deletes or edits a plist or executable.
5. Disable and Enable use `launchctl` with an explicit argument list; no shell is invoked.
6. The entry is re-read right before the action; a mismatch aborts with a message.
7. A disabled item shows an Enable button and survives a rescan.
8. If `launchctl` fails, the item stays as it was and the error is shown.
9. Reading an unreadable folder reports an access issue, not an empty list.

## 6. Open questions

1. Should Phase B apply to items of apps that are currently running? Proposal: allowed, with a note that it takes effect at next login.
2. Is it worth reading the Background Task Management list by any supported means? Not now.

## 7. Code touchpoints

`SystemCareAnalyzer.startupEntries`, `StartupEntry` (owner app, protected, broken, loaded), `BoundedCommandRunner` for `launchctl`, `SystemCareView` and the Smart Care card.

## 8. Implementation status (first version)

- Done: both phases. The list groups by owner app, marks the scope, collapses Apple's items, flags items whose program is confirmed missing and shows running and off states. User-level items that are not Apple's have a switch: off runs `launchctl disable` and, if the item is running, `bootout`; on runs `launchctl enable`. The item is re-read right before acting and a mismatch aborts.
- Switching on does not start the item now: it takes effect at the next login, and the message says so. This is the open question 1 answer, applied to enabling as well.
- Never changed: Apple's items, anything in /Library, items whose plist cannot be read, and labels with anything but letters, digits, dots, dashes and underscores.
- Not done: a run of the real switch on a real item (tests use a fake `launchctl`), and reading the Login Items & Extensions list.

## 9. Change log

- 2026-11-12: first draft.
- 2026-11-12: first implementation, see section 8.
