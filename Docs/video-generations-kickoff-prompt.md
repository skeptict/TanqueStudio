# Kickoff prompt — Video Generations (paste into a fresh Claude Code session)

> Working directory should be `/Users/skeptict/Documents/GitHub/TanqueStudio`.

---

Implement the **Video Generations** feature per the approved spec at `Docs/video-generations-spec.md` — read it fully first. Both phases (A: capture & represent, B: export) are in scope for this session.

**⚠️ Setup — do this before anything else.** The primary working tree is occupied by a parallel Story Studio session on `feature/story-studio-v2`. Do not run git commands or edit files in the primary tree. Instead:

```bash
git -C /Users/skeptict/Documents/GitHub/TanqueStudio worktree add \
    -b feature/video-generations \
    /Users/skeptict/Documents/GitHub/TanqueStudio-video main
cd /Users/skeptict/Documents/GitHub/TanqueStudio-video
```

Do ALL work in `/Users/skeptict/Documents/GitHub/TanqueStudio-video`. When finished, push the branch (`git push -u origin feature/video-generations`) and leave the worktree in place — do not merge to main and do not remove the worktree; the coordinating session handles both.

Context you need:

- macOS SwiftUI + SwiftData app, `TanqueStudio.xcodeproj`, scheme `TanqueStudio`, sources in `DrawThingsStudio/` (files auto-join the target — never edit `project.pbxproj`).
- The core bug you're fixing: `GenerateViewModel.generate()` keeps `images.first` and drops all other returned frames. The spec's detection rule (sent `numFrames > 1` AND multiple images returned) decides when the full set is kept — apply it exactly; it protects against DT's occasional multi-image still responses.
- `TSImage.batchID`/`batchIndex` already exist — group frames with them. **No SwiftData schema changes** and **no edits to StoryStudio\*/StoryFlow\* files** (parallel session owns them).
- Port `VideoAssembler` from `/Users/skeptict/Documents/GitHub/DTS-AppleTV/DTS-AppleTV/DTS-AppleTV/Services/VideoAssembler.swift` (109 lines, AVAssetWriter) — adapt UIImage → NSImage, keep its structure.
- Reuse the export UX pattern from `DTProjectBrowserViewModel.startExport` (non-blocking NSOpenPanel, detached writes, cancellable, summary alert).
- Ned's explicit requirement: frame count is a **free-form field with no cap** — DT's server accepts values beyond the DT client UI's 121 (e.g. 450), and pasted configs like `{"numFrames":450}` must flow through unclamped (the importer already handles this; don't break it).
- Live-verify against Draw Things at `192.168.1.34:7859` — the app's saved settings already hold the shared secret. Use a small frame count (16–25) for test renders. AX automation via System Events works if screenshots are denied (see the Phase 1 notes pattern: `select` for List rows, `entire contents` + `AXPress` for unnamed sheet buttons).

Exit criteria are spec §4 — all of them, including the 450-frame paste check and the stills regression check. Conventional commits, one per coherent milestone. When done and verified: push the branch, stop, and summarize — do not merge.
