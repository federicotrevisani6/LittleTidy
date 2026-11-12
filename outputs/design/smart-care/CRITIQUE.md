# Critique log

One fresh critic reviewed the renders over several rounds, reading the PNGs, README, HANDOFF and the specs. The scoring rubric comes from a mobile design process. Lines for brand identity, richness, signature interaction, motion, paywall and feature-worthiness were skipped, because the owner fixed the identity (native Tahoe, system fonts, SF Symbols) and this is a desktop utility. Three lines were added for what matters here: A trust and safety legibility, B state coverage, C accessibility. Scores are the critic's, not mine.

Stop rule used: no line below 3, at least 80% of lines at 4 or above, and lines 9 (finish), 10 (native fluency) and 12 (copy) at 4 or above.

## Scores

| Line | R1 | R2 | R3 |
|---|---|---|---|
| 2 Not the category average | 3 | 3 | 4 |
| 4 Hierarchy | 4 | 4 | 4 |
| 5 Typography | 3 | 4 | 4 |
| 6 Colour | 4 | 4 | 4 |
| 8 Rhythm and space | 3 | 3 | 3 |
| 9 Finish and craft | 3 | 3 | 4 |
| 10 Native fluency | 3 | 4 | 4 |
| 12 Copy | 3 | 3 | 4 |
| A Trust and safety legibility | 3 | 4 | 4 |
| B State coverage | 3 | 4 | 4 |
| C Accessibility | 3 | 4 | 4 |

Round 1: 2 of 11 lines at 4 or above. Round 2: 7 of 11. Round 3: 10 of 11, and lines 9, 10 and 12 at 4, so the stop rule is met. The one line still at 3 is rhythm and space.

## Round 1: what the critic found and what I did

Taken:
- Reversible versus irreversible was invisible on the home. Added the two lines under the hero button, the red line on the card, and listed "Removed for good" first in the sheet.
- The window looked like a web page: title and Scan moved into a toolbar, inset sidebar, shadows removed, one control shape per size.
- Rhythm: Trash became a full-width row, the hero's right block lists the review amounts, cards stretch to equal height.
- Contrast: stronger secondary text token, units at 58% size, larger card glyphs, readable disabled buttons.
- States: added all-failed result, needs-access home, cleanup running, orange "finished with problems".
- Data: the Trash figures did not reconcile (3.1 GB Trash versus 19.3 GB moved in), a failed item did not change any total, item counts did not add up, and the blocked-card amount disagreed with the sheet. All reworked so every total adds up (see the figures at the end).
- Spec points: Clean disabled during a scan, before-scan reduced to one button and one sentence, single-tier cards no longer repeat the number.
- Strings it quoted: "Files apps and macOS can rebuild." (read as a typo), "Recommended items only. Most are rebuilt by the tools that made them.", "2 groups", "0 items could not be removed", `simctl` and `brew cleanup` in user text.

Declined:
- Renaming or merging sidebar entries: existing product structure, outside this task.
- A non-blue accent: the accent is the user's setting. The design never relies on colour alone, and the HANDOFF now warns about red, orange and green accents.
- A pixel-exact glass sidebar and toolbar: not possible in HTML. The HANDOFF names the real components.
- A stacked strip under the hero numbers: the per-card proportional bar stays the single bar idea.

## Round 2: what the critic found and what I did

Taken: layout defects (hero lines breaking into columns at the minimum window, a wrapped "Needs access" chip, misaligned tops in the Applications and Maintenance row), a reversibility bar under the hero Clean, bordered per-card Clean buttons, 12 pt explanations, darker header glyphs, a neutral before-scan tile, a lifted dark review tile, drawn scan-cancelled and nothing-safe homes, an "Open System Settings" button on the all-failed result.

Strings and data it caught: the needs-access footnote said the Trash was left out of totals (it never is in them), a running string named an item that was blocked elsewhere, "2 items" with one row, the Empty Trash list not matching "and 72 more", "skipped" versus "left out", all-failed text saying "move to the Trash" when some items are permanent removals. All fixed.

Declined:
- Digit tracking tweak on system type.
- Removing equal-height card stretching: ragged card tops look worse.
- Criterion 17 for the Login, Unused apps and AI tools cards (explanations describe contents, not consequence): the strings are the owner's, in the model file. Left as an open copy point in the README.

## Round 3: what the critic found and what I did

Landed: one-line hero at the minimum window, clean needs-access states, aligned Maintenance row, the reversibility bar as the product's one ownable idea, triangle on the card Clean and the sheet confirm, bordered card buttons.

Fixed after the critic's last scoring (these changes are **not re-scored**):
- Scan-cancelled screen said "3 of 7" but showed fewer cards and had two Scan Again buttons. Now 3 finished and 4 "Not scanned" cards, one button, toolbar subtitle "Scan stopped at 3 of 7".
- Empty Trash was live while a cleanup ran. Now disabled, and the Trash row says it is updating.
- The hero bar used grey for the Trash part, but grey means protected elsewhere. Now a softened safe green.
- The hero Clean button now carries the same triangle as the card and sheet buttons.
- Strings: "Nothing qualifies for one-tap cleaning. You can still review each card." (the old line read as "unsafe"), "(can be restored)" instead of "restorable", skipped Xcode items labelled "(in use)" so they do not look like the 12 moved ones, Developer notice shortened to one line, toolbar subtitle 12 pt.

Not done, still open: the 150 to 190 pt of empty space beside the tall Developer card (the one line still scored 3), a lone card in a group rendered as a slim row, an Empty Trash in-progress frame, an Increase Contrast render of the new bar. A real build is the only route to a 5 on native fluency.

## Figures used across screens (all invented)

Hero safe 26.4 GB = 24.6 (developer) + 1.8 (AI) = 19.3 to the Trash + 7.1 permanent. Review 42.9 GB = 13.6 + 7.6 + 14.9 + 6.8. Result: 3.0 freed now + 19.3 in the Trash + 2.6 held by a snapshot = 24.9 = 26.4 minus the 1.5 GB item that failed. Items: 36 planned = 22 + 4 + 1 + 9; 35 done, 1 failed, 2 more skipped. Empty Trash: 47 old + 31 new = 78 items, 3.1 + 19.3 = 22.4 GB.

## Not verified

Nothing here was checked on a real Mac build. Not drawn: Empty Trash while running, Restore with conflicts, first-launch permissions screen. The mock's sidebar and toolbar only imitate Tahoe's.
