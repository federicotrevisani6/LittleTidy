# Mac Cleaner UI Spec

## UI Goal

The interface should make disk cleanup feel inspectable and reversible. The first UI should be a review console, not a marketing dashboard. The user should always know:

- What was found.
- Why it was found.
- How much space can be recovered.
- What is currently selected.
- What will happen if they continue.

## Window Model

Use one primary `WindowGroup` for the main app and one native `Settings` scene for preferences. The main window should launch directly into a sidebar-detail workflow.

Primary layout:

- Native macOS sidebar for scan categories.
- Detail pane for tables, summaries, and selected-item review.
- Optional inspector later for file metadata and safety warnings.

## Navigation

Sidebar items:

1. Overview
2. Duplicates
3. Large Files
4. Unused Apps
5. Cleanup Plan

Each sidebar row should stay lightweight: one icon, one title, and one secondary detail line. Category totals and detailed warnings belong in the detail pane.

## Detail Surfaces

### Overview

Purpose: show scan state and category totals.

Controls:

- Start Scan
- Choose Folders
- Cancel Scan when scanning

Content:

- Total reclaimable space estimate.
- Duplicate reclaimable estimate.
- Large file estimate.
- Unused app estimate.
- Permission gaps if present.

### Duplicates

Purpose: review duplicate groups.

Rows should show:

- Representative filename.
- Group count.
- Reclaimable bytes.
- Confidence.
- Recommended keep path.

Actions:

- Select suggested duplicates.
- Reveal in Finder later.
- Preview group later.

Safety:

- Never allow every copy in a group to be selected.
- Show hash confidence.

### Large Files

Purpose: rank large files that the user may no longer need.

Rows should show:

- Filename.
- Size.
- Last opened or modified date.
- Reason.
- Location.

Actions:

- Select item.
- Open location later.

Safety:

- Protected libraries should not appear as cleanup candidates.
- Package-like items should require explicit confirmation later.

### Unused Apps

Purpose: identify apps that appear stale.

Rows should show:

- App name.
- Version.
- App size.
- Last opened date or unknown.
- Confidence.

Actions:

- Select app bundle for Trash.
- Related app data is not selected in v1.

Safety:

- System apps are excluded.
- Unknown usage should be visibly less confident.

### Cleanup Plan

Purpose: final review before moving anything to Trash.

Content:

- Selected item count.
- Total selected bytes.
- Grouped list by cleanup category.
- Warnings and blocked items.

Primary action:

- Move Selected to Trash.

This action should remain disabled until the plan validates.

## Visual Direction

Use native macOS materials and semantic colors. Avoid a decorative hero screen. This is a utility app, so the information density should be moderate and scannable.

Component choices:

- `NavigationSplitView` for root layout.
- `List(selection:)` with `.sidebar` for navigation.
- Tables or table-like rows for review data.
- Toolbar icon buttons for scan, folder selection, refresh, and inspector.
- Progress indicator while scanning.
- Confirmation dialog before cleanup.

## Prototype Scope

The first prototype target should compile and display mock data wired to the same categories as `MacCleanerCore`. It should not scan or delete live files yet. Live scanning comes after the UI flow is stable.
