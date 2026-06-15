# LittleTidy Design Audit

Date: 2026-06-15
Mode: Wireframe-level UX + visual system review
Destination: Local folder

## Scope

Audited the native macOS LittleTidy review and cleanup flow using the QA fixture:

1. Ready overview
2. Scan settings
3. Scan results overview
4. Duplicate review
5. Expanded duplicate group
6. Selected duplicate state
7. Cleanup plan

Screenshots are saved beside this file.

## Step Notes

### 1. Ready Overview

Screenshot: `01-ready-overview.png`

Health: Mixed.

Strengths:
- The top-level promise is clear: review before cleanup.
- The empty state avoids fear-based copy and explains the first action.
- Access readiness and safety rules are present before scanning.

UX risks:
- The primary path is split between toolbar actions, overview buttons, disclosure groups, and a sometimes-hidden sidebar.
- Safety information is visible, but it competes with setup controls rather than forming a guided first-run sequence.
- The app begins in a visually heavy dark canvas with many custom surfaces, which makes it feel more like a prototype shell than a native macOS utility.

Accessibility risks:
- Icon-only toolbar actions are not self-evident from screenshots.
- Screenshot review cannot confirm keyboard focus order, VoiceOver labels, or whether toolbar buttons expose clear accessibility names.

### 2. Scan Settings

Screenshot: `02-scan-settings.png`

Health: Functional but too exposed.

Strengths:
- Important safety defaults are visible: system folders off, deep uninstall off, caches explicit.
- The QA fixture control is useful for internal testing.

UX risks:
- The settings disclosure sits inside the main task path and remains expanded after use, pushing more important review information down.
- Numeric steppers are precise but not very explanatory. A wireframe should probably separate "What am I scanning?" from "Advanced thresholds."
- "Deep uninstall" is a high-risk concept but appears as one checkbox in a dense grid.

Accessibility risks:
- Checkboxes have visible labels, but the risk level of "System folders" and "Deep uninstall" may not be communicated strongly enough to assistive tech users.

### 3. Scan Results Overview

Screenshot: `03-scan-complete-overview.png`

Health: Good summary, weak next-step funnel.

Strengths:
- Category totals are scannable and map well to the cleanup mental model.
- Access readiness still reassures the user after scanning.
- The app does not auto-select anything by default.

UX risks:
- The result tiles are clickable but not visually framed as the next step in a workflow.
- "Caches" dominated the result set and later became part of a large suggested selection. That needs stronger review friction.
- The sidebar can be hidden, which makes the app depend on both tiles and toolbar icons for navigation.

Accessibility risks:
- Result tiles need clear button names including category and reclaimable amount.

### 4. Duplicate Review

Screenshot: `04-duplicates-review.png`

Health: Structurally sound, inefficient layout.

Strengths:
- Search, filters, sort, confidence, size, location, and actions are all present.
- The duplicate reason is transparent.

UX risks:
- The screen spends a lot of space on controls and empty canvas while the actual review row is comparatively small.
- The selected byte total is not visible in this screen once the sidebar is hidden.
- The row checkbox and expand chevron are close together and can be confused.

Accessibility risks:
- The row has multiple small targets: expand, checkbox, more menu. Keyboard and VoiceOver behavior should be checked.

### 5. Expanded Duplicate Group

Screenshot: `05-duplicates-expanded.png`

Health: Strong safety model, needs clearer hierarchy.

Strengths:
- The "Keep" copy is clearly protected.
- The removable copy is visible with path and size.
- The copy-level controls support the "never remove all duplicates" rule.

UX risks:
- The group title says the kept file name, while the removable row is a sibling below it. This is correct but can be hard to parse quickly.
- The "Keep" label is good, but the removable row could benefit from an explicit "Remove" or "Move to Trash" role label.

Accessibility risks:
- Disabled keep checkbox needs a clear explanation, not just disabled state.

### 6. Selected State

Screenshot: `06-duplicate-selected.png`

Health: Clear in-row state, weak global state.

Strengths:
- Selection state is visible and consistent.
- The keep row remains unselected.

UX risks:
- The toolbar checkmark action selected many suggested items when used accidentally. Its icon-only presentation is too risky for a destructive workflow.
- Suggested selection needs a named button or a confirmation/undo affordance because it can change dozens of rows at once.

Accessibility risks:
- Bulk selection changes should announce what changed.

### 7. Cleanup Plan

Screenshot: `07-cleanup-plan-ready.png`

Health: Strong final review, but too easy to over-select.

Strengths:
- The final plan summary is clear: item count, filesystem entries, size, exclusions.
- "Move Selected to Trash" is explicit and reversible.
- The warning about duplicate groups is well placed before the item list.
- Grouped selected items make the plan auditable.

UX risks:
- The plan showed 68 selected items because the toolbar suggested-select action was easy to trigger. This undermines the "nothing auto-selected" trust model, even if technically user-triggered.
- The primary action sits far from the plan validation copy. It is visible, but the relationship between summary, warnings, and final action could be tighter.
- Caches account for most selected bytes; high-volume cache cleanup should probably get a separate confirmation block or category-specific review.

Accessibility risks:
- The final destructive action needs strong keyboard focus visibility and a clear confirmation dialog. Screenshot review cannot verify that.

## Liquid Glass Assessment

Current state: not Liquid Glass.

Evidence:
- `Sources/LittleTidy/Support/CleanerSurface.swift` uses `.regularMaterial` and `.thinMaterial` inside custom rounded rectangles.
- The app uses many opaque/dim custom surfaces rather than relying on system sidebar, toolbar, and scroll-edge glass behavior.
- Search is embedded in each review view instead of being attached at the split-view or toolbar level.
- The toolbar contains icon-only actions that do not benefit from a clearer system grouping model.

Direction:
- Keep `NavigationSplitView`, but let the sidebar and toolbar carry more of the native macOS material behavior.
- Reduce custom card surfaces in the main scroll views.
- Move global search/filter affordances into native placement where possible.
- Use semantic glass only for high-value custom summary surfaces, not every section.
- Rework toolbar groups with explicit labels or clearer grouped actions before applying more visual treatment.

## Recommendations

1. Redraw the flow as a simple wireframe sequence: Setup -> Scan -> Results Overview -> Category Review -> Selected Plan -> Trash Confirmation -> Report.
2. Make the sidebar always available at the minimum supported window size, or make the overview tiles the unmistakable primary navigation.
3. Replace the icon-only global checkmark with a labeled "Select Suggested" action that explains how many items it will affect.
4. Separate basic scan setup from advanced thresholds.
5. Treat caches as a separate review path when selected byte count is high.
6. Add explicit copy-level labels for duplicate decisions: Keep, Move to Trash.
7. Adopt Liquid Glass structurally first: system sidebar/toolbar/search, fewer custom surfaces, then targeted glass effects.

## Evidence Limits

- This audit used screenshots and macOS accessibility snapshots from a local run.
- It did not verify VoiceOver output, full keyboard traversal, contrast ratios, zoom/reflow, or the final Trash confirmation dialog.
- The Figma destination was not used because no Figma placement tool was available in this session.
