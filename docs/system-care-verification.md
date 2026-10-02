# System Care implementation verification — 1 October 2026

## Implemented

System Diagnosis measures known user and system storage locations and exports
JSON. Access errors remain unknown; sizes are not presented as reclaimable space.
Developer Storage recognizes Claude temporary DerivedData by Xcode metadata and
adds Xcode Preview environments for review. No blanket Git worktree deletion.
Maintenance inventories startup services, Spotlight status, and local snapshots.
A signed optional helper exposes fixed DNS refresh and Spotlight rebuild actions.
Protection checks Gatekeeper, FileVault, SIP, and firewall status and assesses app
trust with Gatekeeper. Malware scanning and real-time monitoring are not implemented.

## Crash fix

The development app bundle lacked the Sparkle runtime path. After embedding the
framework, hardened runtime also rejected its vendor signature against the app's
team. The build script now embeds resources and Sparkle, sets the runtime path,
signs nested Sparkle code and the helper with the app's Developer ID, verifies the
complete signature, and checks the process after launch.

## Validation

- Final SwiftPM test run: 54 tests in 10 suites passed.
- Final complete bundle build and launch verification passed.
- Deep, strict bundle signature verification passed outside the restricted sandbox.
- Shell syntax, helper plist, and git whitespace checks passed.
- System Diagnosis and Protection visually inspected in dark mode with real scan
  results. Scan completed without a crash. Gatekeeper, FileVault, and SIP were
  enabled; firewall was reported disabled.
- SwiftFairy reviewed four app files plus automatically supplied declarations.
  Extracted focused section/operation views, migrated the new model to Observation,
  and added meaningful equality to observed value models.
- Remaining SwiftFairy considerations were checked manually: the reported model
  content is a Swift concurrency Task handle, not a View; appearance refresh is
  short and repeat-safe; formatting and sorting cover a bounded set of locations;
  remaining nested composition has a cohesive section responsibility.

## Still to verify

The computer-use native connection closed during Maintenance and window-size
inspection and remained unavailable after resetting the session. That visual
coverage is incomplete. No new LittleTidy crash report appeared at that time.
The final bundle launch check subsequently passed.

Administrator registration and user approval were verified after the user enabled
the service. The real signed app successfully triggered its first launch and
received seven protected measurements over authenticated XPC. The read-only debug
verification completed: shared developer tools 4,387,516,416 bytes; Spotlight index
1,240,625,152 bytes; archived temporary work 0 bytes. Other system locations returned
macOS access errors and remained unknown. Administrator privileges do not grant
unrestricted access to every protected system directory.

Actual DNS refresh, Spotlight rebuilding, and service removal have not been
exercised; the verification never runs maintenance tasks.
The universal release archive/notarization flow has not been run. Direct Xcode Run
currently lacks helper embedding; the complete build script embeds it.

This implementation is a foundation for broader system care, not full CleanMyMac
feature parity. Protected system cleanup and a malware engine remain future work.

## Reproducible administrator connection check

Run `./script/build_and_run.sh --verify-admin` in Debug after approving the service.
The real signed app writes its result to
`~/Library/Application Support/LittleTidy/Diagnostics/admin-verification.json`.
The diagnostic launch entry point is excluded from release builds. The bundle's
app and helper both satisfy the exact signing requirements used by XPC.

A later attempt to complete the Maintenance visual pass reproduced the crash in
SkyComputerUseService (`Array.remove(at:)` assertion); LittleTidy stayed running.
Visual verification of that page and small-window layouts remains incomplete.

## Follow-up — 2 October 2026

The Maintenance accessibility crash was resolved in the observed workflow by
replacing its two GroupBox status containers with focused MaintenanceStatusCard
views. They use the same surfaces as the rest of the app and combine their title
and value for accessibility. The administrator-enable instruction is now shown
only when the service is not enabled.

Visual checks completed in dark mode at a large window size, at the minimum
supported width, and in the minimum window layout using macOS Move & Resize:

- Maintenance cards and startup entries, including long executable paths.
- Protection checks and the application trust card.
- System Diagnosis with actual sizes and the capacity bar.
- DNS confirmation dialog and cancellation (no maintenance executed).
- Scan from Maintenance completed, showing Spotlight indexing enabled, snapshot
  status, fourteen startup plist entries, and enabled administrator access.

The fresh signed bundle build, deep strict signature check, launch check, and git
whitespace check passed. This resolves the previously incomplete visual coverage
of these three pages and the compact window layout. No changes to scanner or
cleanup execution logic were made in this follow-up. Actual DNS refresh,
Spotlight rebuild, and service removal remain untested.


## Read-only folder exploration — 2 October 2026

System Diagnosis now offers Explore for each measured location. The sheet lists
one folder level at a time, updates sizes progressively, sorts measured entries
by size, and supports Back, Stop, Refresh, and Close. It recognizes Git repository
and worktree metadata without running Git commands, known cache paths, and build
output metadata. Application/personal data and unclassified entries retain review
labels. There is no delete action and no new privileged arbitrary-path endpoint.

Traversal validates approved roots and rejects symlinks, redirected child paths,
and CoreDevice paths. Packages are not navigable. Each level has a 250-entry limit,
a one-minute measurement budget, and a five-second command timeout. Access errors
remain unknown; the UI reports partial or stopped results explicitly.

Validation:

- All 57 tests in 11 suites passed. New real-filesystem fixtures verify root
  containment, symlink replacement before measurement, exclusion of CoreDevice,
  conservative classification, actual byte measurement, and preserved files.
- Complete signed debug bundle build and launch verification passed.
- SwiftFairy review of StorageFolderBrowser completed with no findings.
- Dark-mode visual inspection of the sheet passed: paths, badges, sizes, buttons,
  and scrolling fit the compact window. Real Xcode data showed DerivedData at
  18.31 GB and recognized project build outputs. Back navigation and Escape close
  worked; Codex measurement Stop showed partial results and Refresh restarted it.

The Git labels identify metadata only: uncommitted changes, owning processes, and
worktree activity are not assessed. They do not imply that a worktree is disposable.
Protected folder exploration uses the app's existing user access; unavailable
locations report errors instead of requesting arbitrary root traversal.


## Agent worktree review — 2 October 2026

System Diagnosis now has Agent Worktrees, and folder exploration has Review
Worktrees. Default discovery is scoped to ~/.codex/worktrees; Choose Folder
explicitly changes that scope for Claude or other repositories. Only registered
linked worktrees inside the chosen root are listed. Main checkouts are excluded.
Discovery searches at most four folder levels and 2,000 folders, with a one-minute
budget. It does not prune missing registrations or remove arbitrary directories.

Individual review shows the branch, disk size, tracked/untracked/ignored status,
and a bounded lsof open-file snapshot. Xcode activity checks fail closed. Locked,
prunable, detached, dirty, ignored, hidden-index, and submodule worktrees are
protected. Repository content filters block status/removal instead of executing
repository programs. Git runs with a restricted environment, disabled hooks and
fsmonitor, disabled untracked cache, and optional index locks disabled.

Removal requires the existing permanent-deletion opt-in (now with an explicit
worktree toggle in Deletion & Safety), confirmation that the owning tools are
stopped, and a final destructive confirmation. Fresh inspection verifies the
same registration, HEAD, and branch; file status is checked again after activity
and size probes. Git worktree remove is invoked without force. It permanently
removes the checkout/local worktree metadata, retains the named branch, and does
not use Trash. The operation never fetches, pushes, deletes branches, or prunes.

Open-file checks are snapshots, not a guarantee that a background agent cannot
resume. Users must stop the owning agent and preserve associated task state.
Removal through Git does not archive task records in Codex or other owning apps.

Validation:

- All 61 tests in 12 suites passed. Four new integration tests use real temporary
  Git repositories to verify discovery boundaries, main-checkout exclusion,
  preservation of dirty/untracked/ignored files, locks, detached HEAD, index flags,
  refusal to execute configured filters, activity/permission rejection, late-data
  revalidation, and actual Git removal with preserved branch/main checkout.
- Complete signed debug bundle build and launch verification passed.
- Dark-mode visual pass inspected inventory and individual review in the compact
  window. Actual PetroCheck worktree was found at 86.4 MB, with no open files
  observed at inspection. Removal remained disabled with opt-in off.
- Open Settings reached Deletion & Safety; the new worktree toggle was present
  and off, while the normal deletion default remained Move to Trash.
- No real user worktree was removed. GUI destructive confirmation has not been
  executed; actual removal was exercised only through the core integration test.
- SwiftFairy rejected this new audit because no active scroll content was
  available. No trial was started. The previous folder-browser audit remains a
  separate completed pass; it does not cover this new view.
