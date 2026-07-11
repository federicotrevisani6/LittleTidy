# LittleTidy product audit — 2026-07-11

## Scope

Live macOS flow: launch, scan setup, QA fixture scan, scan progress, result overview, duplicate review, and final cleanup plan. Cleanup was not executed.

## Captured steps

1. `01-launch.png` — first-run/home state.
2. `02-scan-setup.png` — folders, permissions, and advanced settings.
3. `03-scan-results.png` — scan in progress.
4. `04-results-overview.png` — category summary and current safe selection.
5. `05-duplicates-review.png` — duplicate review.
6. `06-cleanup-plan.png` — final pre-Trash review.

## Verdict

LittleTidy already has a credible safety foundation: explicit selection, confidence language, Finder reveal, a final plan, and Trash-based recovery. The main gap versus a mature benchmark is not the number of modules; it is the product narrative. The current interface exposes scanner configuration and list mechanics more strongly than a simple, personalized answer to three questions: what is wrong, what is safe, and what should I do now?

## Highest-impact findings

1. Critical — the headline opportunity and selected amount conflict. The overview says up to 8.94 GB can be freed, while only 13.6 MB is selected. Make `Recommended cleanup` the primary number and show `More opportunities` separately, with reasons why those items require review.
2. High — first-run setup is configuration-led. Replace the expanded settings-heavy journey with a short readiness checklist and defer thresholds to Settings.
3. High — categories lack decision context. Add benefit, risk, and recommendation copy to every category, especially caches and unused apps.
4. High — selection safety is expressed repeatedly but not explained as a consistent policy. Introduce an inspectable `Why this is safe` model and persistent exclusions/ignore list.
5. High — QA controls are visible in the product and their relative path depends on process working directory. Gate them behind a debug build or hidden developer mode and resolve fixture paths from a stable repo/config source.
6. Medium — the review screen uses a dense horizontal control strip. Move secondary sort/filter controls into compact menus and keep search plus one primary scope control visible.
7. Medium — cleanup plan is safe but visually uniform. Group items by confidence and consequence, surface the largest/riskier exceptions first, and collapse routine safe rows.
8. Medium — after cleanup, the product needs a durable sense of progress: reclaimed-space history, last scan health, avoided-risk explanation, and a clear next recommendation.

## Accessibility limits

The accessibility tree exposes meaningful labels for navigation, selection, reveal, and removal. Screenshot inspection cannot confirm keyboard focus order, VoiceOver announcement timing, contrast ratios, reduced-motion behavior, or behavior at larger accessibility text sizes; those require dedicated runtime tests.
