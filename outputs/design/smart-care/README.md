# Smart Care: visual design

Status: design proposal, 2026-11-12. Nothing here is implemented. Specs it follows: [smart-care-spec.md](../../smart-care-spec.md), [clean-all-safe-spec.md](../../clean-all-safe-spec.md), [cleanup-result-screen-spec.md](../../cleanup-result-screen-spec.md), [permissions-onboarding-spec.md](../../permissions-onboarding-spec.md). Implementation details are in [HANDOFF.md](HANDOFF.md). The independent critique and what changed because of it is in [CRITIQUE.md](CRITIQUE.md).

All sizes, paths and numbers in the screens are invented. None come from a real Mac.

## Screens

Each file exists as `-light.png` and `-dark.png` (2x) in `screens/`.

| Screen | File prefix |
|---|---|
| Smart Care home after a scan (full length) | `home-ready` |
| Home at the minimum window, 980 x 640 | `home-min-window` |
| Home while scanning | `home-scanning` |
| Home before the first scan | `home-before-scan` |
| Every card state on one sheet | `card-states` |
| "Clean 26.4 GB safely?" sheet | `confirm-clean-safely` |
| Result view after a cleanup, with problems | `cleanup-result` |
| "Empty the Trash?" sheet | `empty-trash-confirm` |
| Trash emptied (sheet result) | `empty-trash-done` |
| Home with one card that needs access | `home-needs-access` |
| Home with a safe total of 0 | `home-nothing-safe` |
| Home after cancelling a scan | `home-scan-cancelled` |
| Home while a cleanup runs | `cleanup-running` |
| Result when every item failed | `cleanup-result-all-failed` |
| Home with Increase Contrast on (light) | `home-ready-increased-contrast-light.png` |

Source: `source/screens.html` (one file, all screens, `?screen=<name>&theme=light|dark`). Re-render with `tools/render.mjs`. The SF Symbols are generated locally by `tools/render-symbols.swift` and are not committed; see the header of each tool.

## Direction

Smart Care is a calm checkup sheet, not a dashboard. The window already uses native Tahoe surfaces, so the design keeps them and adds only what the product's promises need:

1. **Meaning has a fixed colour, and colour is never alone.** Safe is green with a filled check. Review is blue with an eye. Protected is grey with a lock. Needs access and blocked are orange with a lock or hand. Failed and permanent are red with a triangle or trash. Every state also has a glyph and a word, so it reads without colour.
2. **Colour is spent in small places.** Surfaces stay neutral. Colour appears in the tier glyphs, the 4 pt tier bar, the two headline tiles and the permanent-action panels. A screen full of tinted cards would make every number look like a warning or a promise.
3. **One number per card, and Clean carries the number it acts on.** The big number is everything found. The tier line splits it. The Clean button says `Clean 24.6 GB…`, so nobody has to guess that it ignores the review part.
4. **Two totals, two blocks, never summed.** The header shows "26.4 GB you can clean safely" and "42.9 GB to review first" as separate equal blocks. The Clean button lives in the safe block, because it acts only on that number. A footnote says the Trash is in neither total.
5. **Reversible and irreversible look different.** Anything permanent sits in a red-edged panel with a warning glyph and the words "cannot be restored". Red fill is used on exactly one button: Empty Trash, where the whole action is permanent. The mixed "Clean" sheet keeps an accent button, but its label states the permanent part. A red button on a mostly reversible action would teach people to ignore red.
6. **Honest words.** "Moved to the Trash" and "Freed now" are different numbers on different tiles. Nothing is called junk.

## Decisions I made that the specs left open

- **Header layout.** The title and Scan / Scan Again / Cancel move into the window toolbar, as a native app would. The Clean button sits in the safe block, with two lines under it: how much goes to the Trash (restorable) and how much is removed for good.
- **Trash is a full-width row,** not a fourth card. It is the only card with a permanent action and the only red button, and a full-width row also stops it from sitting alone in the grid.
- **Tier bar** width is the card's share of the largest card, and its colours are the safe/review split. The tier line is its legend.
- **Blocked items** (for example Xcode running) are left out of the totals and the card says so. The rest of the card can still be cleaned, as the clean-all-safe spec says.
- **Card total.** The card number is the full total (safe + review + protected), as in the current code. Clean repeats the safe amount to remove the ambiguity. If you prefer the number to be only the safe part, the tier line still works.
- **Result view lives in the detail pane,** not a sheet, with a "Smart Care" back link and a footer button. Restore All, Open Trash and Empty Trash sit under the "In the Trash" number, because they act on it. There is no destructive button next to the footer button.
- **Skipped and failed** are two separate lists, skipped first, each row with its reason. "Nothing was changed" is stated for skipped items.
- **"Held by a snapshot"** appears only when the spec threshold is met (the mock shows it met).
- **Empty cards** collapse to one line with the card name as a link, so they can still be opened.
- **Result title** says "finished with problems" with an orange glyph whenever anything failed or was skipped, and the all-failed result has no success wording at all.
- **Waiting state.** While a scan runs, cards that are queued show "Waiting to scan", dimmed. This is new, small, and optional.

## Open points for the owner

1. The result view's "Restore only works for items that are still in the Trash" line is a design suggestion, not in the spec.
2. The Increase Contrast render shows rules, not the final result. Check it with the real setting.
3. Card radius goes from 10 to 12 pt. It is one parameter in `cleanerSurface`.
4. Secondary text (`.secondary`) is about 4:1 on white in light mode, below 4.5:1 at 11 to 12 pt. The handoff defines a stronger secondary text token. The existing text colours for warning and danger (system orange and red used as text) fail contrast on white (about 2.2:1 for orange). The design uses darker text tokens and keeps the system colour for glyphs and fills. See HANDOFF.md.

## Not drawn

Empty Trash while it runs, Restore with conflicts (item stays in the Trash and is listed with its path), and the first-launch permissions screen (see the permissions spec).

## What does not carry over from the mobile design process

The process behind this was written for iPhone and Android apps. For a desktop utility these parts did not apply, and I say so plainly:

- Phone frames, status bars, home indicator, 3x renders, store screenshots, app icons, launch reels and a paywall: not applicable, not made.
- The three-direction exploration on the core screen was not run as three renders. The owner fixed the identity (native Tahoe, SF Symbols, system fonts), so I wrote the concept and the two rejected alternatives instead (below), and spent the time on states and the handoff.
- The history check across other apps and the multi-round external critique were not run. I reviewed the renders myself and fixed what I found. A fresh pair of eyes on the real build is still worth doing.
- Dynamic Type is mobile-first. macOS has no full equivalent for third-party apps today, so the design uses SwiftUI text styles and avoids fixed heights, which is what makes any system text size setting work. I could not verify this on a Mac with a changed text size.
- Touch-target rules (44 pt) become pointer sizes. Small controls here are 22 pt tall, the macOS default.

Alternatives considered and not chosen:

- **A full-bleed colour per area.** Looks lively, but every card would read as a different promise, and colour could not carry "safe" versus "review". Rejected for the meaning-first rule above.
- **A single big dial with one total.** Simple, but it merges safe and review, which the product forbids.
