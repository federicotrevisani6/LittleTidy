# Smart Care: SwiftUI handoff

Pixel values are points at 1x. The mockups use web approximations of system colours. In code, always use the dynamic colours below, never the hex shown in the HTML.

## 1. Colour tokens

Existing tokens in `CleanerPalette.swift` stay. Four new text tokens are needed, because system green, orange, blue and red as text on a white card fail 4.5:1 (green and orange measure about 2.2:1). Use the system colour for glyphs, bars and tinted fills; use the text token only when the colour carries words.

| Semantic role | Used for | Fill / glyph | Text token (new) | Text contrast (light / dark card) |
|---|---|---|---|---|
| Safe | check glyph, green tier bar, safe tile | `cleanerSuccess` | `cleanerSuccessText` | 5.1 / 9.4 |
| Review | eye glyph, blue tier bar, review tile | `cleanerInfo` | `cleanerInfoText` | 6.1 / 7.3 |
| Attention (needs access, blocked, skipped, snapshot) | lock, hand, tile | `cleanerWarning` | `cleanerWarningText` | 6.7 / 9.6 |
| Danger (failed, permanent, Empty Trash) | triangle, trash, panel edge | `cleanerDanger` | `cleanerDangerText` | 5.9 / 7.2 |
| Protected | lock in tier line, grey bar | `Color(nsColor: .systemGray)` | `.secondary` | n/a |

Proposed values for the new text tokens (dynamic, light / dark): success `#1B7F3B` / `#4BDE76`; info `#0A5FC4` / `#6CB0FF`; warning `#8F4A00` / `#FFB84D`; danger `#C0261B` / `#FF8A80`. Define them as `Color(nsColor: NSColor(name:…){ appearance in … })` so they follow the appearance, and so they pick up the high-contrast appearance variants.

Neutral roles, all existing:

| Role | Token |
|---|---|
| Window background | `Color(nsColor: .windowBackgroundColor)` |
| Card surface | `cleanerInteractiveSurface()` (`.controlBackgroundColor`, 0.5 pt `.separatorColor` at 0.7) |
| Inset tile / skeleton | `Color(nsColor: .quaternaryLabelColor).opacity(0.08)` (same as `cleanerSubtleSurface`) |
| Primary text | `.primary` |
| Secondary text | `.secondary` |
| Tinted fill (tiles, chips, notices) | role colour at 14 to 20% opacity over the card |
| Sheet background | system sheet material, no custom fill |

White on the prominent button is 4.0:1 in light mode. That is the system `borderedProminent` look, so it is left to the system.

## 2. Type

All system fonts, SwiftUI text styles where one exists, so any system text size support applies.

| Style | Spec | SwiftUI |
|---|---|---|
| Window title | 26 pt bold | `.largeTitle.bold()` |
| Headline total | 34 pt semibold, tabular | `.system(size: 34, weight: .semibold)` with `@ScaledMetric`, `.monospacedDigit()` |
| Result number | same as headline total | same |
| Card number | 26 pt semibold, tabular | `.system(size: 26, weight: .semibold)` `@ScaledMetric`, `.monospacedDigit()` (current code uses `.title`; fine to keep that and drop to 22) |
| Group heading | 15 pt semibold | `.title3.weight(.semibold)` |
| Card title, row title | 13 pt semibold / regular | `.headline` / `.body` |
| Stat label | 13 pt medium | `.body.weight(.medium)` |
| Tier line, messages, button text | 12 pt | `.callout` |
| Explanation, help text, footnotes, reasons | 11 pt | `.subheadline` (the current `.caption` is 10 pt; use 11) |
| Sheet title | 17 pt semibold | `.title2.weight(.semibold)` |

Layouts must not use fixed heights for text blocks. Card `minHeight` is the only fixed height (see 3).

## 3. Layout and spacing

Spacing scale: 4, 6, 8, 10, 12, 14, 16, 20, 24, 28.

- Window minimum 980 x 640, sidebar 220. Content padding 24. Vertical gap between header, summary, groups 24.
- Group: heading, 12 pt gap, grid. Grid `GridItem(.adaptive(minimum: 300), spacing: 14)`. At 980 wide this gives 2 columns, at 1280 it gives 3.
- Applications and Maintenance cards sit side by side in the same adaptive grid when they fit (mock `row3`); a plain `VStack` per group is also fine.
- Card: padding 16, corner radius 12 continuous, `minHeight` 196, internal spacing 10. Head row: 26 x 26 tile (radius 7, SF Symbol 13 pt, `.secondary`), 9 pt gap, title. Tier bar 4 pt high, 2 pt gaps, 2 pt radius. Buttons bottom-trailing, 8 pt apart, `.controlSize(.small)`.
- Summary panel: two equal columns, padding 20 x 22, hairline divider, radius 14. Tile 34 x 34 radius 10, SF Symbol 17 pt. Clean button `.controlSize(.large)`, `.borderedProminent`, capsule.
- Result view: three equal panels, 14 pt gap, padding 18, `minHeight` 198. By-card, Skipped, Failed lists are one panel each, rows padded 10 x 16, hairline separators.
- Sheets: 600 pt wide (Clean sheet), 480 pt wide (Trash sheet), padding 24, 14 pt between blocks, radius 20 (system sheet). Blocks radius 12. Row padding 8 x 14.
- Collapsed empty line: 12 pt, `checkmark.circle` glyph in tertiary, card names as plain buttons in accent colour.

## 4. Component states

Card (`SmartCareCardView`). Header row is the same in every state.

| State | Body | Chip (right of title) | Buttons |
|---|---|---|---|
| ready, two tiers | number, tier line with glyphs, tier bar, explanation | none | Review, Clean `<safe>…` (prominent) |
| ready, review only | same, no safe part | none | Review |
| ready, count only (startup items) | count as number, one sentence, explanation | none | Review |
| scanning | spinner and "Scanning…", two skeleton bars, explanation | none | none |
| waiting | "Waiting to scan" tertiary, one skeleton bar, dimmed title | none | none |
| needsAccess | lock glyph and message (primary text, never `0 B`), explanation | "Needs access" orange chip | Allow Access… (bordered) |
| blocked | number and tiers as ready, plus orange notice box with hand glyph and the reason | none | Review, Clean disabled |
| failed | red triangle and message, explanation | "Failed" red chip | none; header Scan Again retries |
| empty | not a card; one collapsed line per group | n/a | name is a link that opens the review list |
| trash (ready) | number, `<n> items`, explanation | none | Open Trash, Empty Trash… (red text, `trash` glyph, bordered, never prominent) |

Tier line order is fixed: safe, review, protected. Each item is glyph plus text: safe `checkmark.circle.fill`, review `eye`, protected `lock`. The bar is `accessibilityHidden`; the text carries the meaning.

Header states: before scan (Scan prominent, three reassurance lines), scanning (Cancel, progress panel with "Scanning n of N", live path line, 6 pt progress bar, one reassurance line), ready (two stat blocks, trash footnote, Scan Again bordered). The live path is one line, middle truncated, 12 pt secondary. Clean is disabled while scanning, and hidden at 0 bytes.

Confirm sheet: blocks in this order. (1) Moved to the Trash, green check, can be restored. (2) Removed for good, red-edged panel with red-tinted rows, warning triangle, "These cannot be restored." (3) Skipped, not included, with a reason on every row. Then one fine-print line. Buttons: Cancel (escape), then the confirm button. When anything permanent is included the label is `Clean <total> (<permanent> permanent)`; when everything is reversible it is `Clean <total>`. Block (2) is omitted when empty. Cancel never changes anything.

Empty Trash sheet: 44 pt round red tile with `trash.fill`, title, bold line `<n> items, <size>. This cannot be undone.`, red-edged panel for "Includes N items LittleTidy moved here in its last cleanup. Emptying removes your only way to restore them." (shown only when N > 0), list of the first 12 items with last-cleanup items first and a "last cleanup" tag, "and N more", the skipped-items line, then Cancel (default, focus ring) and Empty Trash (`role: .destructive`, red prominent fill, `trash` glyph). In progress: spinner, buttons disabled. Done: green check, `<n> items removed, <size> freed.`, skipped and failed counts, one Done button. In this sheet "freed" is correct because the removal is permanent.

Result view: title row with `checkmark.circle.fill` tile (use `exclamationmark.triangle.fill` red and no success wording when everything failed). Three panels:

| Panel | Glyph and tile | Text | Actions |
|---|---|---|---|
| Freed now | `checkmark.circle.fill`, green | "Removed for good and available on your disk now." | none |
| In the Trash | `trash`, neutral | "Moved, not freed yet. The space comes back when you empty the Trash." | Restore All (`arrow.uturn.backward`), Open Trash, then Empty Trash… in red text, separated from the others |
| Held by a snapshot | `clock.arrow.circlepath`, orange | "Time Machine still keeps a copy of these removed files. macOS releases it when it needs the space." | none |

Shown only when the threshold is met for the third panel; the grid becomes two columns without it. Restore All is absent when nothing is in the Trash. By-card rows show per card: `<size> in the Trash` with a `trash` glyph, `<size> removed` with `checkmark.circle.fill`. Only items still in the Trash can be restored; irreversible rows show no restore control. Skipped list (`hand.raised`, orange) and Failed list (`exclamationmark.triangle.fill`, red) have a count and a reason on every row. Footer: fine-print note and `Back to Smart Care` (prominent, large).

## 5. SF Symbols

| Use | Symbol |
|---|---|
| Developer storage | `hammer` |
| AI tools | `brain` |
| System and app caches | `shippingbox` |
| Trash card, trash actions | `trash`, `trash.fill` (sheet) |
| Unused applications | `square.grid.2x2` |
| Time Machine snapshots, held tile | `clock.arrow.circlepath` |
| Login and background items | `power` |
| Smart Care (sidebar) | `sparkles` |
| Scan, Scan Again, Cancel | `sparkle.magnifyingglass`, `arrow.clockwise`, `xmark.circle` |
| Safe total tile | `checkmark.shield` |
| Review | `eye` |
| Safe tier, freed, success | `checkmark.circle.fill`; collapsed line `checkmark.circle` |
| Protected, needs access | `lock` |
| Blocked, skipped | `hand.raised` |
| Failed, permanent warning | `exclamationmark.triangle.fill` (`exclamationmark.triangle` in chips) |
| Restore | `arrow.uturn.backward` |
| Back | `chevron.left` |
| Footnote | `info.circle` |

Symbol weight: semibold in tiles, regular in text lines. Rendering mode: monochrome, tinted by the token for that role.

## 6. Accessibility

- Every tier, state and permanent warning has a glyph and words in addition to colour. The tier bar is hidden from VoiceOver.
- Each card is one `accessibilityElement(children: .contain)`. Its label reads: title, number, tier split in words, state. The number and tier line are combined into one phrase such as "Developer storage, 38.2 gigabytes, 24.6 safe, 13.6 to review".
- Buttons repeat their target: `Clean 24.6 GB` needs the card name as accessibility label ("Clean Developer storage, 24.6 GB").
- Headline stat blocks are one element each: "26.4 gigabytes you can clean safely".
- Live scan path: update the label at most every second, not per file.
- Sheets: Cancel is the escape action. In the Empty Trash sheet Cancel is the default button and Empty Trash is not the return-key action.
- Increase Contrast: separators and borders become opaque 1 pt, secondary text is darker, tints are not relied on (the glyph and word already carry the meaning). The mock `home-ready-increased-contrast-light.png` shows the intent.
- Reduce Motion: no skeleton shimmer, spinner stays. No other animation is specified.
- Dark Mode: cards are darker than the window (system behaviour), so the border and tint tokens must be checked there, not assumed.

## 7. Wording used in the mocks

These are proposals for the ux-writing pass; wording in the specs wins where they differ.

- Header: "you can clean safely", "to review first", footnote "The Trash (3.1 GB) is not counted in either total."
- Buttons: `Clean 26.4 GB Safely…`, `Review`, `Clean 24.6 GB…`, `Open Trash`, `Empty Trash…`, `Allow Access…`, `Restore All`, `Back to Smart Care`.
- Confirm: "Clean 26.4 GB safely?", "Moved to the Trash", "Removed for good", "These cannot be restored.", "Skipped, not included".
- Result: "Cleanup finished", "Freed now", "In the Trash", "Held by a snapshot".
