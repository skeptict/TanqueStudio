# Video Generations — Specification

**Status:** approved design, ready for implementation (runs in parallel with Story Studio Phase 2)
**Decided:** 2026-07-04 (Ned)

## 1. Problem

Draw Things video models (Wan, LTX, …) return one image per frame. TanqueStudio's generate path keeps `images.first` and **silently discards every other frame** — a 121-frame LTX render loses 120 frames. TS must (a) capture frame series as a single grouped generation, (b) export individual frames, (c) assemble frames into an `.mp4`.

**First-class requirement (Ned):** DT's own client UI caps frame count (121), but the gRPC server accepts more (e.g. 450). TS talks gRPC directly and must NOT inherit the client cap — frame count is a free-form numeric field, and pasted configs like `{"numFrames":450}` pass through untouched (the importer already round-trips `numFrames`; verified).

## 2. What already exists (verified 2026-07-04)

- `DrawThingsGenerationConfig.numFrames` exists, round-trips through `DTConfigImporter` (encode line ~137, decode ~188), and reaches the wire (`DrawThingsGRPCClient.swift:416`, fallback 14 when 0). Several bundled community presets set it (25/16/49).
- **`fps` does NOT exist in TS's config** — not in `DrawThingsProvider.swift`, not in the importer, not in the gRPC call. It must be added end-to-end.
- `TSImage` has `batchID: UUID?` + `batchIndex: Int?` — frame series need **zero schema changes**. Do not bump the SwiftData schema version (Story Studio owns v2; coordinate before any schema change — expected answer: don't).
- A proven AVAssetWriter pipeline exists: `VideoAssembler.swift` (109 lines) in the DTS-AppleTV repo at `/Users/skeptict/Documents/GitHub/DTS-AppleTV/DTS-AppleTV/DTS-AppleTV/Services/VideoAssembler.swift`. Port it (UIImage → NSImage/CGImage); don't redesign it.
- Folder-export UX pattern: `DTProjectBrowserViewModel.startExport` (bulk export, 2026-07-04) — non-blocking `NSOpenPanel.begin`, detached-task writes, cancellable, written/skipped summary alert.

## 3. Design

### Detection rule

A generation is a **video series** iff the *sent* config had `numFrames > 1` AND the response contains more than one image. Multiple images with `numFrames <= 1` (DT sometimes returns extra preview images) keep today's behavior (`images.first`). This rule is load-bearing — don't loosen it.

### Phase A — capture & represent

1. **Config plumbing:** add `fps: Int` to `DrawThingsGenerationConfig` (default 0 = model default; additive change to DrawThingsProvider.swift is sanctioned precedent — see `applyRDSShiftIfNeeded`), wire through `DTConfigImporter` (encode/decode) and the gRPC call (only set when > 0). Metadata (`asPNGMetadata`) includes numFrames/fps when set.
2. **UI:** new "Video" rows in the left panel's **Advanced** section (`GenerateLeftPanel.swift`): `Frames` — free-form numeric TextField (NOT a capped slider; values like 450 are legitimate), 0/1 = still image; `FPS` — numeric TextField, 0 = model default. Show a footnote when Frames > 1: "Video render — N frames will be saved as one gallery series."
3. **Capture:** in `GenerateViewModel.generate()` (and only there — inpaint stays stills-only), when the detection rule fires: save ALL frames via `ImageStorageManager` with one shared `batchID`, `batchIndex` = frame order, source `.generated`; **save frames as JPEG (quality ~0.9), not PNG** — 121+ full-res PNGs per render is a disk problem (note the storage-manager change needed for format choice). Canvas shows frame 0; the existing navigate-away and zero-image guards apply unchanged.
4. **Gallery grouping:** in the gallery strip, collapse entries sharing a `batchID` *whose configJSON has numFrames > 1* into one cell — thumbnail of frame 0, "▶ N" badge. (Plain batch renders — batchCount > 1 stills — stay ungrouped, as today.) Selecting the cell selects the series.
5. **Frame scrubber:** when a series is selected, the canvas gets a bottom overlay: slider (frame index) + frame counter `k / N` + step buttons. Scrubbing loads frames by batchIndex (they're ordinary gallery images — zoom/pan/paint on an individual frame work for free).

### Phase B — export

6. **Export Frames…** on the series (context menu + Actions tab): non-blocking folder picker → writes `«prompt-slug»_f0001.jpg …` — reuse the bulk-export pattern.
7. **Export Video…**: port `VideoAssembler` → `.mp4` (H.264) via `NSSavePanel`; fps = config fps, else per-family default (LTX 24, Wan 16, else 16); frames streamed to the writer one at a time (do NOT hold all NSImages in memory).
8. **Delete series** — deleting the grouped cell asks once and removes all frames.

### Known constraint (document, don't fix now)

The client API returns `[Data]` — all frames in memory at once. 450 frames ≈ 1 GB+ RAM spike during the response. Acceptable on Ned's hardware; if it bites, the fix is a per-frame streaming callback in DT-gRPC-Swift-Client (another upstream PR — note it in code where the array lands).

## 4. Verification (exit criteria)

- Build green; launch smoke test green (`xcodebuild test -scheme TanqueStudio -destination 'platform=macOS'`).
- Live against DT at `192.168.1.34:7859` (shared secret in app settings): render with a bundled video preset (numFrames 16–25 keeps the test fast) → one grouped gallery cell, correct frame count, scrubber works, Export Frames writes all files, Export Video produces an `.mp4` QuickTime can play at the right fps and frame count.
- Paste `{"numFrames":450}` via the config paste path → Frames field shows 450 (no clamping anywhere). A still render (numFrames 0) behaves exactly as before — regression-check a normal generate + batch of 3.
- Existing gallery/stills untouched.

## 5. Hard rules

Same as `Docs/story-studio-v2-spec.md` §8 (ported files additive-only, files auto-sync — never edit pbxproj, `tanqueStudio.*` settings keys, conventional commits), plus: **no SwiftData schema changes**, and **do not touch StoryStudio\*/StoryFlow\* files** — Story Studio Phase 2 is in flight in a parallel session.
