# LittleTidy — System Data Master Plan

Status: product and engineering plan

Date: 2026-07-11

North star: reveal, explain, and safely recover storage that macOS hides inside “System Data”, beginning with Apple developer tooling.

## 1. Executive decision

LittleTidy should not compete as another general-purpose cache cleaner. Its strongest product opportunity is to become the trustworthy specialist for storage that users cannot explain through Finder or macOS Storage Settings.

The first wedge is Apple developer storage because it can consume tens or hundreds of gigabytes, is poorly explained by macOS, and contains a mix of disposable, reinstallable, historical, and actively required data.

The product promise becomes:

> LittleTidy shows where hidden System Data is going, explains what each item is, and provides the safest supported way to recover it.

CleanMyMac remains the quality benchmark for simplicity, confidence, progress, and finish. LittleTidy differentiates through deeper diagnosis, greater transparency, Apple-development expertise, and conservative cleanup.

## 2. Problem statement

The current product detects duplicates, large files, unused apps, per-app caches, Xcode DerivedData, and a small number of developer-tool caches. It does not inventory the largest Apple developer storage sources, including CoreSimulator, XCTestDevices, DeviceSupport, archives, result bundles, or installed simulator runtimes.

This creates three problems:

1. The app may advertise a small cache cleanup while missing more than 200 GB of relevant storage.
2. All developer data is conceptually flattened into “Caches”, even when its safety and cleanup mechanism differ.
3. The headline “space that can be freed” can include items that are not actually recommended, weakening trust.

## 3. Product principles

1. **Explain before cleaning.** Every result must say what it is, why it exists, why it is large, and what happens after removal.
2. **Use supported mechanisms.** Simulator devices and runtimes must be managed through Apple-supported commands or APIs where available, not by blindly moving internal directories.
3. **Never equate found space with safe space.** Report `recommended`, `review`, `protected`, and `unclassified` totals separately.
4. **Protect active work.** Running devices, current runtimes, recent archives, active build products, and ambiguous data are not automatically selected.
5. **Make uncertainty visible.** Unknown ownership or incomplete metadata lowers confidence; it must never be hidden behind optimistic copy.
6. **Stay reversible where possible.** Normal files use the Trash. Irreversible command-driven removal requires an explicit final confirmation and a clear reinstall/recovery explanation.
7. **Fast diagnosis first.** A user should learn the top storage causes before a full file-by-file scan completes.
8. **Local-first privacy.** Inventory and classification happen on-device. No file paths or inventory data leave the Mac without explicit consent.

## 4. Target users and primary jobs

### Primary audience

- iOS/macOS developers using one or more Xcode versions.
- Developers running many Simulator runtimes or device configurations.
- QA engineers using XCTest devices and automated testing environments.
- Indie developers who periodically discover unexpectedly large System Data.

### Core jobs

- “Tell me why System Data is so large.”
- “Find old simulators and runtimes I no longer need.”
- “Show me what Xcode data is safe to rebuild.”
- “Let me recover space without breaking active projects.”
- “Help me understand the cost of deleting something before I confirm.”

### Secondary audience

General Mac users still benefit from duplicates, large files, app caches, unused apps, and storage exploration, but those tools should support the core positioning rather than define it.

## 5. Information architecture

Recommended top-level navigation:

1. **Overview** — system storage diagnosis and recommended action.
2. **Developer Storage** — Xcode, Simulator, XCTest, archives, device support, build artifacts.
3. **General Cleanup** — app caches, duplicates, large files, unused apps.
4. **Storage Map** — exploration and unclassified large folders.
5. **History** — completed operations, recovered space, failures, and recovery guidance.

The current cache category remains, but Xcode developer storage is removed from the generic cache mental model.

## 6. Storage taxonomy

### 6.1 Regenerable build data

Examples:

- `~/Library/Developer/Xcode/DerivedData`
- Xcode indexes and build intermediates
- SwiftPM build directories and selected caches
- module caches

Default classification: `recommended` when not in active use.

Recovery: automatically rebuilt; first subsequent build may be slower.

Removal: Trash when it is a normal directory and no active process is using it.

### 6.2 Simulator devices

Examples:

- devices reported by `xcrun simctl list devices --json`
- unavailable devices
- shutdown devices associated with obsolete runtimes
- device data stored beneath CoreSimulator

Default classification:

- unavailable/orphaned device: `recommended` after validation;
- old shutdown device: `review`;
- booted or active device: `protected`;
- ambiguous/unmatched directory: `unclassified`.

Removal: supported `simctl` operation. Never delete arbitrary device directories directly.

### 6.3 Simulator runtimes

Examples:

- installed iOS, watchOS, tvOS, visionOS runtimes
- runtimes referenced by installed Xcode versions
- obsolete or unused runtime versions

Default classification:

- current/default runtime: `protected`;
- runtime used by an existing device: `review` or `protected`;
- older unused runtime: `review`;
- unsupported/unavailable runtime residue: `recommended` only when confidently identified.

Removal: supported Xcode/simctl mechanism where available. Clearly state download size and that reinstalling requires network access.

### 6.4 XCTestDevices

Location: `~/Library/Developer/XCTestDevices` and related metadata.

Default classification:

- active/recent test device: `protected`;
- old, stopped, confidently disposable environment: `review`;
- incomplete or ownership-unknown data: `unclassified`.

This area requires dedicated research and fixtures before any automatic recommendation. Phase one may be diagnosis-only.

### 6.5 Device Support

Examples:

- `~/Library/Developer/Xcode/iOS DeviceSupport`
- symbols and support data for connected OS versions

Default classification: `review`, ordered by OS version and last use.

Recovery cost: regenerated or downloaded when a matching device reconnects; symbolication/debugging may be affected until then.

### 6.6 Archives and symbols

Examples:

- `~/Library/Developer/Xcode/Archives`
- `.xcarchive`
- exported `.dSYM`

Default classification: never automatically selected.

Risk: archives and symbols may be required for crash symbolication, re-export, notarization records, or release investigation.

UI must show app, version, build, creation date, size, and whether the archive appears to have been uploaded or exported when metadata can be determined.

### 6.7 Test and diagnostic artifacts

Examples:

- `.xcresult`
- `.resultbundle`
- test videos, attachments, screenshots, logs
- Instruments traces and diagnostics

Default classification: recent items `protected`; older items `review`; temporary derived copies may be `recommended` when confidently detected.

### 6.8 Xcode downloads and additional components

Examples:

- platform downloads
- documentation caches
- previews and support components

Default classification varies by recoverability and ownership. Initial release should inventory these sources but avoid automatic cleanup until each mechanism is verified.

### 6.9 General app and tool caches

Existing sources remain supported:

- `~/Library/Caches`
- npm, Yarn, pip, Gradle and similar caches
- browser and application caches

These stay under General Cleanup and must not dominate the System Data product narrative.

## 7. Risk and recommendation model

Every candidate receives independent values rather than a single vague confidence score:

- `recoverability`: trashRestorable, recreatable, reinstallable, irreversible, unknown
- `activity`: active, recentlyUsed, inactive, unavailable, unknown
- `ownership`: knownTool, knownApp, inferred, unknown
- `cleanupMechanism`: trash, simctl, xcodeManaged, manual, unsupported
- `consequence`: negligible, temporarySlowdown, redownloadRequired, debuggingImpact, dataLossRisk
- `recommendation`: recommended, review, protected, unclassified

Automatic selection is allowed only when:

- ownership is known;
- activity is inactive or unavailable;
- cleanup mechanism is supported;
- consequence is negligible or a clearly stated temporary rebuild;
- no active process, mounted runtime, booted simulator, or lock is detected.

An internal `RecommendationReason` must make every decision explainable in the UI and testable in unit tests.

## 8. Technical architecture

### 8.1 New core models

- `DeveloperStorageCategory`
- `DeveloperStorageItem`
- `DeveloperStorageInventory`
- `StorageRecommendation`
- `Recoverability`
- `ActivityState`
- `CleanupMechanism`
- `CleanupConsequence`
- `SystemDataSummary`
- `CleanupCapability`

Do not overload `CacheCandidate`. Developer storage needs its own semantics.

### 8.2 Analyzer boundary

Create a `DeveloperStorageAnalyzer` coordinator backed by focused scanners:

- `DerivedDataScanner`
- `CoreSimulatorScanner`
- `SimulatorRuntimeScanner`
- `XCTestDevicesScanner`
- `DeviceSupportScanner`
- `XcodeArchivesScanner`
- `TestArtifactsScanner`
- `DeveloperBuildArtifactsScanner`

Each scanner returns inventory only. Recommendation policy is applied by a separate `DeveloperStoragePolicy` so discovery, classification, and UI remain independently testable.

### 8.3 Command boundary

Introduce a narrow injectable command client:

- `DeveloperToolCommandClient`
- runs absolute-path tools through `Process`;
- captures stdout, stderr, exit status, duration, and cancellation;
- never invokes a shell string;
- supports timeouts;
- parses versioned JSON defensively;
- is fully replaceable by fixtures in tests.

Initial commands to evaluate:

- `xcrun simctl list --json`
- `xcrun simctl list devices --json`
- supported delete/uninstall commands discovered from the installed toolchain
- `xcode-select -p`
- Xcode installation discovery through filesystem metadata rather than broad shell parsing

No cleanup command should be shipped until verified against the installed Xcode versions supported by LittleTidy.

### 8.4 Size accounting

Use allocated size rather than only logical file size. Requirements:

- cancelable traversal;
- permission errors retained as first-class results;
- symbolic-link boundaries enforced;
- package directories handled intentionally;
- APFS clones and hard links not misleadingly double-counted where detectable;
- parent/child candidates deduplicated to avoid inflated totals;
- fast top-level estimates delivered before deep enumeration.

### 8.5 Capability detection

At launch or before Developer Storage scan, compute capabilities:

- Xcode installed and selected;
- `simctl` available;
- Full Disk Access status or observed access gaps;
- supported runtime-management operations;
- Trash availability;
- active Simulator/Xcode processes;
- app distribution restrictions, signing, sandbox, and helper availability.

The UI must degrade to diagnosis-only when safe cleanup is not available.

### 8.6 Cleanup execution

Split the current Trash-only executor into mechanism-specific executors behind a common plan:

- `TrashCleanupExecutor`
- `SimulatorDeviceCleanupExecutor`
- `RuntimeCleanupExecutor`
- `ManualCleanupInstruction`

A `CleanupPlan` may contain multiple operations but must group them by reversibility. Irreversible operations receive a separate confirmation rather than being bundled into a generic “Move to Trash” action.

### 8.7 Active-use protection

Before planning and again immediately before execution:

- refresh simulator/device state;
- block booted or transitioning devices;
- detect Xcode/Simulator processes when relevant;
- revalidate paths and sizes;
- reject candidates whose identity or metadata changed;
- stop safely on partial failure and report exactly what completed.

## 9. UX plan

### 9.1 Overview

Primary question: “Why is System Data large?”

Proposed hierarchy:

- **Recommended cleanup** — the only primary reclaimable number.
- **Review opportunities** — potentially recoverable but not selected.
- **Protected and active** — visible proof that LittleTidy is deliberately leaving data alone.
- **Unclassified storage** — honest accounting for what could not be safely explained.

Example:

- Recommended: 42 GB
- Review: 168 GB
- Protected: 31 GB
- Unclassified: 4 GB

Avoid a headline such as “244 GB can be freed” unless all 244 GB are genuinely recommended.

### 9.2 Developer Storage dashboard

Cards in priority order:

1. Simulators
2. XCTest Devices
3. Runtimes
4. Derived Data
5. Archives & Symbols
6. Device Support
7. Test Results
8. Other Developer Data

Each card shows size, recommendation, largest contributor, cleanup consequence, and a `Review` action.

### 9.3 Review screen

Visible primary controls:

- search;
- recommendation scope;
- total selected;
- cleanup consequence summary.

Secondary sorting and technical filters move into menus. Rows should prioritize human information:

- “iPhone 16 Pro — iOS 18.4” rather than an opaque UUID;
- last used/created date;
- size;
- state;
- reason for recommendation;
- reinstall/rebuild impact.

Technical paths and identifiers remain available in an inspector or disclosure area.

### 9.4 Final plan

Present operations in separate sections:

- Moves to Trash — reversible
- Recreated automatically — temporary slowdown
- Removed through Simulator tools — not undoable, reinstall may be required
- Kept for safety — active or ambiguous

The final button label must reflect the operation. Do not label a mixed plan “Move Selected to Trash”.

### 9.5 Completion

Completion should communicate:

- space recovered;
- items successfully removed;
- items skipped or changed;
- failures with retry/reveal guidance;
- expected next effects, such as slower first build or runtime redownload;
- new available disk space;
- next recommended action.

### 9.6 Developer/debug UI separation

- `Use QA Fixture` must not appear in release builds.
- Fixture mode should be enabled through a compile flag, launch argument, or explicit hidden developer mode.
- Fixture paths must be absolute or injected; they must never depend on the app process working directory.

## 10. Safety policy

### Never auto-select

- booted simulator devices;
- runtime used by a booted or protected device;
- recent archives and symbols;
- unknown XCTest data;
- paths outside known roots;
- symlink targets outside the candidate root;
- data whose owner or cleanup consequence cannot be determined;
- any source that requires an unsupported/private deletion mechanism.

### Required confirmation language

Confirmation must state:

- exact size and item count;
- reversible versus irreversible operations;
- what must be redownloaded or rebuilt;
- what workflows may be temporarily affected;
- which active or protected items are excluded.

### Failure behavior

- partial success is reported item by item;
- no silent fallback from supported commands to raw directory deletion;
- interrupted operations leave a recoverable audit trail;
- inventory refreshes after cleanup before reporting final space.

## 11. Testing strategy

### Unit tests

- parser fixtures for multiple `simctl` JSON shapes;
- recommendation-policy matrix;
- parent/child size deduplication;
- active-device protection;
- runtime dependency protection;
- archive metadata extraction;
- permission-denied and partial inventory states;
- command timeout, cancellation, stderr, and nonzero exits;
- cleanup-plan reversibility grouping;
- path containment and symlink protection.

### Fixture tests

Extend `LittleTidyQA` with a synthetic developer-storage tree containing:

- multiple DerivedData projects;
- available and unavailable device metadata;
- multiple runtime versions;
- old/recent archives;
- test results and diagnostic bundles;
- unreadable and malformed directories;
- nested candidates that would otherwise double-count.

Command outputs must be fixture-driven; tests must never delete real Simulator data.

### Integration tests

- inventory-only run against the real machine;
- compare reported category sizes with `du` and Xcode/simctl state;
- verify zero mutation during scan;
- create and delete a disposable simulator created specifically for the test;
- verify cancellation and app relaunch recovery;
- verify multiple installed Xcode versions.

### Manual QA

- no Xcode installed;
- Command Line Tools only;
- one and multiple Xcode installations;
- Simulator running during scan;
- simulator state changes between plan and confirmation;
- missing Full Disk Access;
- huge directories and long scans;
- external volumes and unavailable paths;
- light/dark mode, keyboard navigation, VoiceOver, reduced motion, and large text.

## 12. Telemetry and privacy

If analytics are added, collect only aggregate product events with explicit documentation:

- scan started/completed/cancelled;
- analyzer duration and failure category;
- category present, without paths or filenames;
- recommendation accepted/changed;
- cleanup success/partial failure;
- bytes bucketed into coarse ranges rather than exact sensitive inventory where possible.

Never collect filenames, user paths, project names, simulator names, bundle identifiers, archive metadata, or command output by default.

## 13. Success metrics

### Product metrics

- median hidden developer storage identified;
- percentage of scans where top cause is successfully explained;
- recommended cleanup acceptance rate;
- review-to-clean conversion rate;
- cleanup completion and partial-failure rates;
- repeat scan rate after 30/90 days;
- percentage of inventory remaining unclassified.

### Trust metrics

- zero known deletion of active simulator/runtimes;
- zero silent irreversible operations;
- cleanup-plan selection change rate;
- support reports involving unexpected data loss;
- percentage of candidates with a visible, specific explanation.

### Performance budgets

- top-level category estimate should begin appearing within seconds;
- UI remains responsive throughout traversal;
- all scans and commands are cancelable;
- memory use remains bounded and does not require retaining every filesystem URL when aggregation is sufficient.

## 14. Delivery roadmap

### Phase 0 — Foundations and research

Goal: lock safety boundaries before adding cleanup.

Deliverables:

- inventory of actual developer-storage locations on supported macOS/Xcode versions;
- documented supported commands and their behavior;
- new domain models and recommendation policy;
- injectable command client;
- fixture format and risk matrix;
- release/debug separation for QA controls.

Exit criteria:

- every planned category has an owner, cleanup mechanism, consequence, and default recommendation;
- unknown areas default to diagnosis-only;
- architecture review confirms no raw deletion fallback for Simulator-managed data.

### Phase 1 — Read-only Developer Storage diagnosis

Goal: reliably explain the missing hundreds of gigabytes.

Deliverables:

- DerivedData, CoreSimulator, runtimes, XCTestDevices, DeviceSupport, archives, and test-artifact inventory;
- new Developer Storage dashboard;
- recommended/review/protected/unclassified accounting;
- readable names, sizes, states, dates, and explanations;
- permission and capability diagnostics;
- no new deletion behavior.

Exit criteria:

- real-machine comparison accounts for the major storage sources within an agreed tolerance;
- parent/child totals do not double-count;
- active simulator data is correctly protected;
- the user can identify the reason for large System Data without Terminal.

### Phase 2 — Safe regenerable cleanup

Goal: clean high-confidence, rebuildable developer data.

Deliverables:

- DerivedData and verified build-cache cleanup;
- Trash-based reversibility;
- active-process checks;
- separated recommended number;
- completion report and history.

Exit criteria:

- cleanup is reversible;
- first-build consequence is clearly explained;
- interrupted and partial operations are recoverable and auditable.

### Phase 3 — Simulator device cleanup

Goal: remove unavailable and explicitly selected obsolete devices through supported mechanisms.

Deliverables:

- simulator device inventory tied to runtimes;
- unavailable-device recommendation;
- supported command execution;
- state refresh immediately before deletion;
- irreversible-operation confirmation and result report.

Exit criteria:

- disposable-device integration tests pass;
- booted/current devices are always blocked;
- no raw CoreSimulator directory deletion exists.

### Phase 4 — Runtime and XCTest management

Goal: address the largest remaining sources conservatively.

Deliverables:

- runtime usage/dependency view;
- verified supported runtime removal;
- redownload cost and compatibility warning;
- XCTestDevices classification and cleanup only where evidence supports it.

Exit criteria:

- multiple-Xcode compatibility matrix passes;
- dependent devices/runtimes are protected;
- XCTest cleanup ships diagnosis-only if safe automation remains uncertain.

### Phase 5 — Archives, symbols, and diagnostics

Goal: help advanced users review historical developer data without unsafe defaults.

Deliverables:

- archive metadata browser;
- old test result and trace discovery;
- retain/ignore rules;
- export/reveal paths;
- no automatic archive selection.

Exit criteria:

- release archives and symbols are never auto-selected;
- users can understand app/version/build provenance before removal.

### Phase 6 — General System Data expansion

Goal: broaden beyond developers only after the specialist workflow is trustworthy.

Candidates:

- local Time Machine snapshots;
- device backups;
- Mail attachments;
- application support leftovers;
- package-manager downloads;
- logs and diagnostic reports;
- cloud placeholders and local copies, with extreme caution.

Each category requires the same ownership, recoverability, consequence, and supported-mechanism analysis before implementation.

## 15. Initial implementation backlog

### Epic A — Domain foundation

- Add developer-storage models and enums.
- Implement `DeveloperStoragePolicy` as a pure, unit-tested component.
- Add capability and consequence descriptions.
- Prevent the current cache models from representing non-cache developer data.

### Epic B — Command and discovery foundation

- Implement injectable `DeveloperToolCommandClient`.
- Add `simctl` fixture parser.
- Discover selected and installed Xcode versions.
- Add cancellation, timeout, and structured command errors.

### Epic C — Read-only inventory

- Implement focused scanners.
- Add allocated-size traversal and deduplication.
- Stream partial category results to the store.
- Record access gaps rather than silently returning zero.

### Epic D — Store integration

- Add developer inventory state to `ScanReviewStore` or introduce a dedicated `DeveloperStorageStore` if ownership becomes too broad.
- Keep scan state, cleanup plan, and history explicit.
- Support refresh of individual categories.

### Epic E — UX

- Replace the current cache-led headline with System Data diagnosis.
- Add Developer Storage navigation and dashboard.
- Separate recommended, review, protected, and unclassified totals.
- Add consequence-aware review rows and final plan sections.
- Remove QA controls from release UI.

### Epic F — Verification

- Build synthetic fixture tree and command fixtures.
- Add parser, policy, safety, integration, and UI tests.
- Create an updated manual QA checklist.
- Verify using SwiftPM tests, QA executable, Xcode build, and controlled runtime checks.

## 16. Release gates

### Gate 1 — Diagnosis beta

- read-only;
- major sources measured accurately;
- no false “safe to remove” claims;
- clear access gaps;
- responsive and cancelable scan.

### Gate 2 — Reversible cleanup beta

- only Trash-restorable, high-confidence data;
- complete history and error recovery;
- no data outside approved roots;
- explicit rebuild consequences.

### Gate 3 — Simulator cleanup beta

- only supported command mechanisms;
- active-state revalidation;
- dedicated irreversible confirmation;
- disposable-device integration coverage.

### Gate 4 — Public release

- multi-Xcode and current macOS compatibility verified;
- accessibility pass complete;
- privacy documentation accurate;
- notarization/signing verified;
- no debug/QA controls in release;
- product copy distinguishes diagnosis, recommended cleanup, and review opportunities.

## 17. Explicit non-goals for the first release

- malware detection;
- antivirus or real-time protection;
- RAM/CPU/battery monitoring;
- generic “speed up Mac” claims;
- automatic archive deletion;
- raw deletion inside CoreSimulator;
- automatic cleanup of unknown System Data;
- copying every CleanMyMac module before the core storage diagnosis is excellent.

## 18. Key decisions still to validate

These are research tasks, not reasons to block the read-only foundation:

1. Minimum supported macOS and Xcode compatibility matrix.
2. Exact supported mechanism for removing installed runtimes across Xcode versions.
3. Reliable last-used signals for simulator devices and runtimes.
4. Safe classification boundaries inside XCTestDevices.
5. App Store versus direct-distribution capability differences.
6. Whether privileged helper functionality is required for later system-wide categories.
7. How APFS clones affect size presentation in targeted developer directories.

## 19. Definition of the first successful outcome

On a Mac with more than 200 GB of simulator and developer data, LittleTidy should, without changing anything:

1. find the major storage sources;
2. account for them without double-counting;
3. name the responsible tools, runtimes, and devices;
4. distinguish what is active, rebuildable, reinstallable, historical, or unknown;
5. recommend only genuinely low-risk cleanup;
6. explain why the rest requires review;
7. make the user feel informed even if they choose to delete nothing.

Only after this read-only outcome is reliable should LittleTidy automate removal of Simulator-managed data.
