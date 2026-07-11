# Developer Storage visual QA — 2026-07-11

Build under test: LittleTidy 0.3.0 (build 4), Debug, compiled with Xcode 27 and Swift 6.

## Verified

- The live scan completes without freezing the window and identifies 73.37 GB on the test Mac.
- Summary totals remain separate: 7.52 GB Recommended, 49.22 GB Review, 9.15 GB Protected, and 7.48 GB Unclassified.
- Booted Simulator devices are visibly Protected and cannot be selected.
- Shutdown devices and Simulator runtimes are visibly Review items and are not preselected.
- DerivedData is Recommended and preselected; the cleanup bar states that selected items move to the Trash.
- The confirmation dialog reports the selected count and size and explains rebuild cost and irreversible `simctl` operations.
- The action was cancelled. No developer storage was removed during visual QA.
- Long device and runtime inventories remain scrollable, with size, state, recommendation, rationale, and Finder reveal controls visible.

## Evidence

- `04-final-dashboard.jpeg`: completed live inventory and recommendation summary.
- `05-final-confirmation.jpeg`: cleanup confirmation before cancellation.
- `06-runtime-list.jpeg`: lower inventory with shutdown devices and installed runtimes.

The earlier `01`–`03` captures document the first implementation pass; `04`–`06` are the final post-concurrency-audit build.
