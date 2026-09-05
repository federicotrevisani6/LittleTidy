# Claude Code & AI Agent Quickstart

This project uses [AGENTS.md](AGENTS.md) as its primary, authoritative architecture and implementation guide.

## Key Rules for AI Assistants
1. **Safety First**: Default deletion mode is `moveToTrash`. Do not bypass `TrashPlanBuilder` or execute permanent deletions without explicit user opt-in.
2. **Developer Storage Invariants**:
   - Simulator devices and runtimes must be managed via `xcrun simctl` through `DeveloperStorageCleanupExecutor`. Never directly prune CoreSimulator internal directories.
   - If Xcode is running, all developer storage deletions fail-closed and are blocked.
   - Active/booted simulator devices are protected and cannot be deleted.
3. **App Leftovers**:
   - Only exact bundle identifier matches (`CFBundleIdentifier`) in standard `~/Library` locations are allowed.
   - Never delete `~/Library/Group Containers` or match on fuzzy application names.
4. **Duplicates**:
   - A duplicate group must always keep at least one copy (`recommendedKeep`). It is forbidden to delete all copies.
5. **Swift Concurrency**:
   - Swift 6.2 strict concurrency.
   - Background engines and analyzers are `actor` or `Sendable`.
   - UI stores and view state are `@MainActor`.

For full technical specifications, file maps, command reference, and data flows, please read:
👉 **[AGENTS.md](AGENTS.md)**
👉 **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)**
👉 **[docs/DEVELOPER_STORAGE.md](docs/DEVELOPER_STORAGE.md)**
👉 **[docs/SAFETY_AND_PERMISSIONS.md](docs/SAFETY_AND_PERMISSIONS.md)**
