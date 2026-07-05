# Learnability — Specification

**Status:** approved design, ready for implementation
**Decided:** 2026-07-04 (Ned) — make TS learnable for newcomers: welcome flow, in-app help, just-in-time coaching. Tour/coach-marks explicitly rejected (brittle against layout churn). TipKit deferred to a follow-on phase.

## 1. Goal

A Draw Things user who has never seen Tanque Studio should get from launch to first generated image without outside help, and should be able to discover the app's hidden surface (gestures, paste targets, Labs panes) from inside the app. The #1 newcomer wall is the DT connection (address + shared secret + why-is-my-model-list-empty) — the welcome flow leads with it.

## 2. Scope — Phase 1 (this session)

### 2a. First-run welcome sheet

- Shown once on launch (persisted flag `tanqueStudio.welcomeSeen` via `AppSettings`), skippable at any point, reopenable via **Help → Welcome to Tanque Studio**.
- Four pages, TanqueDS styling, image-light (SF Symbols + short copy; no screenshots to maintain):
  1. **Connect** — server address (LAN IP vs localhost), shared secret (paste DT's spaced format as-is), Test Connection, "empty model list = connection or secret problem." Button: *Open Settings*.
  2. **Generate** — model picker, the 49 bundled config presets, prompt → Generate, gallery strip (green = generated, gray = imported).
  3. **Canvas modes** — View / Paint (inpaint) / Crop / Color Draw; the gesture cheat-sheet: pinch zooms, ⌥-drag pans, double-click resets (view mode), ⌘Z undo strokes.
  4. **Explore** — DT Project Browser (⌘-click multi-select, bulk export), StoryFlow, Story Studio, and where Help lives. Button: *Open Help*.

### 2b. In-app Help window (markdown-driven)

- **Help → Tanque Studio Help** opens a dedicated window (SwiftUI `Window` scene, `openWindow(id:)`): topic sidebar + rendered page.
- Content = bundled markdown files at `DrawThingsStudio/Resources/Help/*.md`, one per topic, with a tiny front-matter header (`title`, `order`). Topics (all with real content — seed from README.md and the Docs/ specs, no placeholders):
  1. Connecting to Draw Things (incl. shared secret + troubleshooting empty inventory)
  2. Generate workspace (four columns, config basics, Advanced section)
  3. Canvas modes & gestures
  4. Presets, LoRAs & pasted configs (incl. `{"numFrames":450}`-style overrides)
  5. img2img & Moodboard
  6. DT Project Browser (multi-select, bulk export, send to Generate)
  7. StoryFlow (Labs)
  8. Story Studio (Labs)
  9. Troubleshooting (no-image causes, zero-image errors, request_log.txt location)
- Rendering: a small custom block renderer (~100–150 lines: split into heading / paragraph / bullet / code-block segments, render with TanqueDS type styles). Do **not** add a markdown dependency; `AttributedString(markdown:)` per-paragraph for inline styles is fine. Keep the renderer dumb — content is controlled, not arbitrary.
- Deep-linking: `openHelp(topic:)` so other views can open the window at a specific topic.

### 2c. Empty-state coaching

- Empty model list (Generate left panel): extend the existing refresh hint with a *"Connection help…"* link → Help topic 1.
- Blank canvas empty state: add one line pointing at presets + the welcome sheet ("New here? Help → Welcome").
- StoryFlow and Story Studio panes: a one-paragraph "What is this?" intro in their empty states with a *"Learn more…"* link → their Help topics.
- DT Project Browser empty state already explains folder selection — add the default DT documents path copy button if not present.

### 2d. Tooltip audit

- Pass over Generate panels, canvas toolbars, browser, and settings: every interactive control gets a `.help()`. Specifically verify the hidden-gesture surfaces mention their gestures (mode buttons, zoom chip, gallery cells, moodboard, dice button).

## 3. Scope — Phase 2 (separate, later; NOT this session)

TipKit (macOS 14+) anchored tips for invisible affordances: ⌥-drag pan in edit modes, ⌘-click multi-select in the browser, Paste Config target, dice + randomize-each-run, RDS under Advanced. One tip per feature, show-once. Future feature phases add their own tips.

## 4. Maintenance rule (add to future specs)

Every future feature phase's exit criteria must include: **update the relevant `Resources/Help/*.md` topic**. (Video Generations, in flight, will need a "Video" section in topic 2 or its own topic when it merges — add it during integration.)

## 5. Verification (exit criteria)

- Build green + launch smoke test green.
- With `tanqueStudio.welcomeSeen` cleared: launch → welcome sheet appears once; relaunch → doesn't. Reopenable from Help menu. All four pages render; Open Settings / Open Help buttons work.
- Help window: every topic renders with real content; deep-link from each coached empty state lands on the right topic.
- Tooltip audit: spot-check the listed hidden-gesture controls.
- Stills generate flow regression-checked (welcome/help additions must not disturb it).

## 6. Hard rules & sequencing

- Same base rules as `Docs/story-studio-v2-spec.md` §8 (no pbxproj edits — Resources/Help files auto-sync; additive-only on ported files; `tanqueStudio.*` keys; conventional commits). **No SwiftData schema changes.**
- **Sequencing:** this feature edits `ContentView.swift` / `TanqueStudioApp.swift` (Help menu commands, welcome-sheet hook), which `feature/story-studio-v2` also touches. Branch `feature/learnability` off main in a dedicated worktree; keep ContentView/App edits minimal (menu + sheet presentation only) so the eventual merge with Story Studio is trivial. Do not touch StoryStudio*/StoryFlow* files beyond their empty-state text — and if their empty states have materially changed on the feature branch, coach via Help topics only and leave their files alone (note it in the summary).
