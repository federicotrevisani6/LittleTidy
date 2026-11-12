# Releasing LittleTidy

A release is published automatically when a pull request that bumps the app version is merged into `main`. Merging a pull request that does not bump the version runs the tests only.

## What happens on a merge to `main`

The `CI & Release` workflow (`.github/workflows/ci.yml`) runs three jobs.

1. **Build & Test**: `swift build` and `swift test`.
2. **Detect release**: reads the version and build number from `LittleTidy.xcodeproj/project.xcproj` (`script/release_info.py`) and decides:
   - the tag `v<version>` already exists: no release;
   - no tag and no `release-notes/<version>.md`: the job fails, so a half-prepared bump is noticed;
   - the build number is not greater than the latest one in `appcast.xml`: the job fails, because Sparkle only offers higher build numbers;
   - otherwise: release.
3. **Release** (only when a release is due), through `script/package_release.sh`:
   - archives a universal app, adds the privileged helper, and signs everything with Developer ID with the hardened runtime;
   - notarizes and staples the app, and Gatekeeper-checks it;
   - builds the DMG, signs, notarizes and staples it;
   - generates the Sparkle appcast with the EdDSA signature;
   - creates the GitHub release `v<version>` on the built commit, with the release notes as its description and these assets: `LittleTidy-<version>-build-<build>.dmg`, `LittleTidy.dmg` and `LittleTidy.zip` (the file the appcast points to);
   - commits the updated `appcast.xml` to `main` (`[skip ci]`). Updates are offered only after the assets exist.

The workflow never cancels a run on `main`, so a second merge cannot interrupt a release.

## Shipping a version

In the pull request:

1. Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `LittleTidy.xcodeproj/project.xcproj`. The build number must increase by at least one.
2. Add `release-notes/<version>.md`. Write it as a changelog: a plain headline sentence, the main change in short prose, then "Other Changes" with one fix per bullet.
3. Merge. Nothing else is needed: no tag, no local packaging, no appcast commit.

`script/build_and_run.sh` reads the same version, so there is nothing to keep in sync by hand.

## One-time setup

Repository secrets (Settings, Secrets and variables, Actions). They are only used by the `release` environment job:

| Secret | Content |
|---|---|
| `DEVELOPER_ID_CERT_P12` | Developer ID Application certificate with its private key, exported as `.p12`, base64 encoded |
| `DEVELOPER_ID_CERT_PASSWORD` | Password of that `.p12` |
| `APPLE_API_KEY_P8` | App Store Connect API key (`.p8`), base64 encoded |
| `APPLE_API_KEY_ID` | Key ID of that API key |
| `APPLE_API_ISSUER_ID` | Issuer ID of the App Store Connect team |
| `SPARKLE_ED_PRIVATE_KEY` | Sparkle EdDSA private key, as exported by `generate_keys -x` |

Create a GitHub environment named `release`. Adding required reviewers there makes every release wait for a manual approval; leaving it empty releases right after the merge.

Optional repository variables:

- `RELEASE_RUNNER`: a runner label. Default `xcode-27`, GitHub's hosted image with Xcode 27.
- `RELEASE_XCODE`: the Xcode version to select. Default `27.2`, which reads the JSON project.

The project uses Xcode's JSON project format, which needs Xcode 27, so the release job does not run on the plain `macos-26` image. If the hosted image is unavailable or too old for the project, point `RELEASE_RUNNER` at a Mac that has the right Xcode.

If `main` is protected, allow the `github-actions` bot to push, or the appcast commit will fail.

## If a release fails

- **Before the GitHub release exists** (build, signing, notarization): nothing was published. Fix the cause and re-run the failed job; the tag still does not exist, so the gate passes again.
- **After the release exists but the appcast commit failed:** the release is live but Sparkle does not offer it. Commit the generated `appcast.xml` by running `script/package_release.sh` on a Mac, or fix the push permission and re-run.
- **A bad release:** delete the GitHub release and its tag, revert the appcast commit, and ship a new version with a higher build number. Never reuse a version or a build number.

## Running it locally

```bash
./script/package_release.sh --notary-profile <profile>   # full, notarized
./script/package_release.sh --skip-notarization          # signed only, for checking
```

This rewrites `appcast.xml` and writes to `dist/release/`. Do not commit an appcast produced from a signed-only build.
