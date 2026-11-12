# Roadmap: ideas from commercial Mac cleaners

Status: 2026-11-12. Index of the specs that came out of a review of commercial Mac cleaners. Smart Care Phase 1 is in [pull request 6](https://github.com/federicotrevisani6/LittleTidy/pull/6).

| # | Idea | Spec | Size | Depends on |
|---|---|---|---|---|
| 0 | Smart Care home, Trash with Empty | [smart-care-spec.md](smart-care-spec.md) | done in PR 6 (phases 2 and 3 open) | |
| 1 | One gesture to clean everything safe | [clean-all-safe-spec.md](clean-all-safe-spec.md) | M | Smart Care |
| 2 | Result screen and Restore | [cleanup-result-screen-spec.md](cleanup-result-screen-spec.md) | M | |
| 3 | Installers, iOS backups, Mail attachments | [downloads-ios-backups-mail-spec.md](downloads-ios-backups-mail-spec.md) | L | permissions guide helps |
| 4 | Permissions guide | [permissions-onboarding-spec.md](permissions-onboarding-spec.md) | S | |
| 5 | Low-space and reminder alerts, optional menu bar | [menu-bar-alerts-spec.md](menu-bar-alerts-spec.md) | S (alerts) / L (menu bar) | |
| 6 | Manageable login and background items | [startup-items-spec.md](startup-items-spec.md) | S (read-only) / M (disable) | |
| 7 | Leftovers of removed apps | [orphan-leftovers-spec.md](orphan-leftovers-spec.md) | M | permissions guide |

## Suggested order

1. Items 1 and 2 together: they change how the app feels without new analyzers.
2. Item 4: small, and it unblocks the "needs access" cards.
3. Item 3 (Phase 2 of Smart Care): the largest new space found.
4. Items 6 (read-only first) and 7.
5. Item 5, alerts first; the menu bar waits for a decision on an always-running process.

## Ideas not specced yet

- **Explanation panel per card:** a "what we found and why" view with the first items, their reasons and consequences. This is where LittleTidy can be better than cleaners that mostly show a number and a sentence.
- **Similar photos:** needs Vision or perceptual hashing; the costliest feature, so last.
- **Cloud "unsync":** reversible with `evictUbiquitousItem`; worth a spec after Phase 2.

## Deliberately not taken

App updates, malware scanning, "boost" maintenance tasks presented as recommended, stripping architectures from app binaries, browser privacy cleanup. Reasons are in [smart-care-spec.md](smart-care-spec.md) section 3.

## Change log

- 2026-11-12: first version.
