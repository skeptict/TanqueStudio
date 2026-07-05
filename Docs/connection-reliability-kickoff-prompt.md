# Kickoff prompt — Connection Reliability (paste into a fresh Claude Code session)

> Working directory should be `/Users/skeptict/Documents/GitHub/TanqueStudio`.

---

Fix the connection-reliability bug cluster per the approved spec at `Docs/connection-reliability-spec.md` — read it fully first, especially §1 (the confirmed root cause chain) and §2 (scope). This is a bug-fix phase, not a new feature — smaller and more contained than the last few phases.

**Setup:** check whether the primary tree is free (`git status`, `git branch --show-current` — should be clean on `main`). If another session is active in the primary tree, create your own worktree instead:
```bash
git -C /Users/skeptict/Documents/GitHub/TanqueStudio worktree add \
    -b fix/connection-reliability \
    /Users/skeptict/Documents/GitHub/TanqueStudio-connfix main
cd /Users/skeptict/Documents/GitHub/TanqueStudio-connfix
```
If the primary tree is free, you may work directly in it on a branch (`git checkout -b fix/connection-reliability`) — this fix is small enough not to require worktree isolation by default, but isolate if anything else is running.

Context you need:

- macOS SwiftUI app, `TanqueStudio.xcodeproj`, scheme `TanqueStudio`, sources in `DrawThingsStudio/`.
- The three files at the center of this: `DrawThingsStudio/DrawThingsGRPCClient.swift` (no timeout on `fetchModels`/`fetchLoRAs`), `DrawThingsStudio/GenerateViewModel.swift:1012` (`loadAssets()` — the reentry guard that gets permanently stuck), `DrawThingsStudio/SettingsView.swift:362-375` (`testConnection()` — missing `sharedSecret:`, weak success criterion).
- Before writing a manual timeout race, check whether `DT-gRPC-Swift-Client`'s `CallOptions` (used in `DrawThingsService`/`DrawThingsClient`) already exposes a deadline/timeout — prefer that over hand-rolled `Task.sleep` racing if it exists. The local checkout of that package is at `/Users/skeptict/Documents/GitHub/DT-gRPC-Swift-Client` (read-only reference — this phase should not need to modify it).
- `DrawThingsGRPCClient.swift` is NOT one of the "ported, do-not-modify" files (that list is: DrawThingsProvider, DrawThingsAssetManager, CloudModelCatalog, PNGMetadataParser, RequestLogger — see README) — normal edits to it are fine.
- Settings via `AppSettings.shared`, `tanqueStudio.*` UserDefaults keys. No SwiftData schema changes. Don't touch StoryStudio*/StoryFlow* files.
- To actually test a hang/timeout, you'll need to simulate one — spec §4 suggests pointing at an unreachable IP or blocked port briefly. Draw Things itself runs at `192.168.1.34:7859` with a shared secret already in the app's settings — don't disrupt that; test the timeout path against a *different*, deliberately-unreachable address, then confirm the real server still works normally afterward.

Exit criteria are spec §4. Conventional commits, one per coherent milestone (e.g., one commit for the timeout mechanism, one for `loadAssets()` resilience, one for `testConnection()` fix, one for the real health signal + error wording). Build green + launch smoke test (`xcodebuild test -scheme TanqueStudio -destination 'platform=macOS'`) green. When done and verified: push the branch (or, if you worked directly on main because the tree was free, just leave it committed on main — check which applies to your session), stop, and summarize.
