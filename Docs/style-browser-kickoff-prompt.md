# Kickoff prompt — Style Browser in Tanque Studio Labs (paste into a fresh Claude Code session)

> Working directory: `/Users/skeptict/Documents/GitHub/TanqueStudio`
> Branch: create `feature/style-browser` from `main`. At kickoff `main` was checked out, clean apart from untracked `.claude/` folders. Leave those uncommitted.

---

A new **Style Browser** tab in Labs. It shows a library of 414 art-style prompts as a grid of preview cards. Ned types his own subject and renders the previews on the Draw Things server — one style, a filtered set, or the whole library — using the Focus Room's current model and settings. It's a native take on [clio-style-preview](https://github.com/lumenastrum/clio-style-preview) (MIT), whose web gallery hard-codes a single subject.

Everything in "How it works today" was checked against the tree on 2026-10-28. Line numbers are from `main`.

**Setup:** this prompt is already in the working tree as `Docs/style-browser-kickoff-prompt.md` (untracked). After branching, commit it on its own (`docs: style browser kickoff prompt`), like the other kickoff prompts in `Docs/`.

## The source library

- `styles.json` from the upstream repo, pinned: `https://raw.githubusercontent.com/lumenastrum/clio-style-preview/f5680ca8a8da62ec3d5ff055582a3086f00d0916/styles.json` (commit of 2026-09-30). If you can't fetch it, stop and ask Ned to drop the file in.
- A JSON array of 414 objects, each exactly `{ "name", "prompt", "section" }`. `prompt` is 250–1,230 characters of style prose. `section` is one of ten traditions: Photography 70, 3D Render 70, Anime 59, Painting 47, Drawing 39, Comics 35, Cover Art 29, Cartoon 26, Digital Painting 20, Design 19. File order is the upstream gallery's order — keep it.
- Upstream prompt template: `Style: {name}: {style}. Subject: {prompt}`. The name is in there on purpose: many proses never name their own style.
- Upstream's subject advice: keep it **medium-silent** (no "photo of", "oil painting of"). Every style claims its own medium, and a medium word in the subject fights all 414.
- Credit: the code is MIT; the style prose is community-shared text compiled by u/Dear-Spend-2865, credit requested. Do **not** bundle the upstream 512 px demo thumbnails (23 MB).

## How it works today

| | |
|---|---|
| Labs tabs | `DashboardLabsPage.swift:21` — `private enum LabsTab: String, CaseIterable` (StoryFlow, Cast & Staging, Story Studio, Render Queue at `:25`). The `switch` hosts each tab's view (Render Queue at `:66–67`); pill tabs at `:74`. A new tab is one case plus one `switch` arm. |
| Labs lifetime | `DashboardRootView.swift:154` — `content` switches on `mode` and is keyed `.id(mode)`, so leaving Labs destroys `DashboardLabsPage` and all of its `@State` (`castVM` survives tab switches *within* Labs only). Long-lived state lives in the root: `generateVM` `:50`, `storyFlowVM` `:51`. The Labs page is built at `:171–172` and already gets `generateVM` and `onNavigateToGenerate`. |
| Batch precedent | `RenderQueueController.swift` — `@MainActor @Observable`. `run(…)` `:45` makes one direct `client.generateImage` call per job inside its own try/catch (one bad job can't stop the rest). Client from `AppSettings.shared.createDrawThingsClient()` `:53`, injectable for tests. Resolves seed `-1` before rendering. `CancellationError` = stop, not failure (`:139`). `pause()` `:169`, `cancel()` `:173`. Owned by `RenderQueueView` as `@State` (`RenderQueueView.swift:20`). |
| Provider API | `DrawThingsProvider.swift:841` — `generateImage(prompt:sourceImage:mask:config:onProgress:)`, plus a txt2img convenience overload in the extension below it. |
| The gallery | Every `TSImage` (`DataModels.swift`) shows up in Recent Generations and the filmstrip — unfiltered `@Query`s at `DashboardHomeView.swift:45`, `FocusRoomView.swift:532`, `GalleryStripView.swift:10`, `RenderQueueImagePicker.swift:114`. Render Queue saves through `ImageStorageManager.createAndInsert` (`:113`). A 414-style batch saved that way would bury Ned's real generations. |
| File writing | `ImageStorageManager.writePNG(_:to url:config:prompt:)` `:63` writes a PNG with Draw Things metadata embedded. `makeThumbnailData(from:maxDimension:)` `:89`. |
| Live Generate session | `GenerateViewModel`: `prompt` `:13`, `config` `:18`, `isGenerating` `:33`. Batches derive per-image seeds (`:421–448`). |
| Send to Generate precedent | `StorySceneRenderPanel.swift:205` writes prompt and config fields into `generateVM` (from `:220`), then navigates. |
| Bundled JSON precedent | `DTConfigImporter.swift:48–52` loads `community_models_configs.json` via `Bundle.main.url(forResource:withExtension:)`. `DrawThingsStudio/Resources` is a file-system-synchronized group (`project.pbxproj:106`) with a membership exception set (`:40`). |
| Settings, sandbox, platform | `AppSettings`: `@Observable` singleton writing `UserDefaults` under `tanqueStudio.*`; the codebase does not use `@AppStorage`. The app is sandboxed (`TanqueStudio.entitlements`). Ned's image folder may be a custom override (`AppSettings.swift:216`, `generatedImagesFolderURL`). Deployment target macOS 14.0. |
| Test seams | `RenderQueueControllerTests.swift:13` — a `FakeClient: DrawThingsProvider`. |
| README | `### Render Queue (Labs)` at `:140`; `## Acknowledgments` at `:400`. |

## Decisions (made in planning — follow them; if one proves wrong at runtime, stop and report rather than improvising)

1. **Home:** a fifth Labs tab, `case styleBrowser = "Style Browser"`, after Render Queue. Nothing else in Labs, the Dashboard or the Focus Room changes, apart from the root wiring in decision 6.
2. **Library:** commit the upstream file **unmodified** as `DrawThingsStudio/Resources/StyleLibrary/clio-styles.json` and confirm it lands in the app bundle. New `StyleLibrary.swift`:
   - `struct StyleEntry: Codable, Identifiable, Hashable` — `name`, `prompt`, `section`; `id` is `name`.
   - `StyleLibrary.load(from: URL) -> [StyleEntry]` — never throws, `[]` on failure (same shape as `DTConfigImporter.load`) — plus `loadBundled()`.
   - `sections(of:)` in first-appearance order.
   - `static func styledPrompt(style: StyleEntry, subject: String) -> String` — the upstream template, exactly.
3. **A set is one subject.** `StyleBrowserSet: Codable`:
   - `id: UUID`, `subject`, `createdAt`.
   - `seed: Int` — concrete. Rolled at creation if the snapshot's seed is `-1`, then shared by every style in the set; one seed for all styles is what makes the previews comparable.
   - `configJSON` — a snapshot of `generateVM.config`, taken when the set is created and never changed afterwards.
   - `renders: [String: StyleRender]`, keyed by style name; `StyleRender` holds `file`, `thumb`, `renderedAt`, `errorMessage?`.
   - A new subject, or new model/settings, means a **new set**. Old sets stay browsable.
4. **Storage outside SwiftData.** Sets live under the container's `Application Support/TanqueStudio/StyleBrowser/<set-id>/`:
   - `set.json`, rewritten after every render (crash-safe; a re-run skips styles whose file exists).
   - `images/<safe name>.png` via `writePNG(_:to url:config:prompt:)`, so each file carries its prompt and config and drags straight into Draw Things.
   - `thumbs/<safe name>.jpg`, 512 px.
   - Resolve the root with `FileManager.urls(for: .applicationSupportDirectory, …)` like the default branch of `generatedImagesFolderURL` — never Ned's custom image folder. The root is injectable for tests.
   - Safe filename: upstream's rule (keep alphanumerics, space, `-`, `_`, `(`, `)`). Test that all 414 names map to unique filenames.
   - No `TSImage`, no new `@Model`, no schema change.
5. **Rendering:** `StyleBrowserController` (`@MainActor @Observable`), modeled on `RenderQueueController`:
   - `render(_ styles: [StyleEntry], in set: …)` runs sequentially, skips styles already rendered, isolates failures per style (records `errorMessage`, carries on).
   - `pause()` / `cancel()`; exposes `isRunning`, `isPaused`, `currentStyle`, `completed`, `total`.
   - Every call is txt2img: no source image, no mask, the set's config with the set's seed, and batch count/size forced to 1 (find the field names in Phase 0).
   - If the snapshot is a video config (more than one frame), refuse with a clear message instead of rendering clips.
6. **Ownership:** the controller is `@State` in `DashboardRootView`, next to `storyFlowVM`, and passed through `DashboardLabsPage` into `StyleBrowserView`. A batch then keeps running, and stays visible, when Ned leaves Labs and comes back. That plus the extra parameter is the only change to `DashboardRootView`.
7. **UI** — `StyleBrowserView.swift`, DashboardDS/TanqueDS styling on the paper palette:
   - **Set bar:** a menu of saved sets (newest first, subject snippet as the label) and **New set** — a multi-line subject field with the muted hint *"Describe the subject only. Each style brings its own medium."*; creating snapshots the live Generate config. Below it, read-only: model, size, steps, seed of the selected set.
   - **Filters:** search (name and prose), section pills (All + the ten, same look as the Labs pills), a "Rendered only" toggle.
   - **Grid:** `LazyVGrid` of cards — thumbnail if rendered, a named placeholder if not, an error state if it failed. Label: style name + section. Thumbnails load lazily and are cached; nothing reads 414 files up front.
   - **Render controls:** **Render visible** (unrendered styles in the current filter, count on the button). Above 50, confirm first, with a time estimate from the average of renders so far. Pause/Resume, Cancel, and a progress line ("37 / 47 · Baroque Painting"). Clicking an unrendered card renders just that style.
   - **Detail** (sheet or side panel — your call, report which): the large image, the full style prose, and **Copy style**, **Copy prompt** (the full styled prompt), **Re-render**, **Send to Generate**. Send to Generate sets `generateVM.prompt` to the styled prompt and `generateVM.config` to the set's config (seed included), then calls `onNavigateToGenerate()` — mirroring `StorySceneRenderPanel.sendToGenerate`.
   - **Credit line** at the foot of the tab: "Style library by u/Dear-Spend-2865 · via lumenastrum/clio-style-preview".
8. **Out of scope:** the split-slider compare view (a later session), style-strength blending (upstream's ConditioningAverage has no Draw Things equivalent), editing styles or importing another `styles.json`, the upstream demo thumbnails, Render Queue integration, a "Save to gallery" action, and any change to how the Focus Room generates.

## Phase 0 — read-only, then STOP

1. Confirm the table above still matches the tree; list any drift.
2. Fetch the library (don't commit yet). Confirm 414 entries, unique names, and the section counts. Confirm a file under `Resources/StyleLibrary/` will be bundled — check the exception set, and if needed build and look inside the `.app`.
3. In `DrawThingsGenerationConfig`, find the fields for batch count/size and frame count, and how the app recognises a video config elsewhere (e.g. Render Queue's clip path).
4. **Lifetime check:** what happens to a running Render Queue when Ned leaves Labs mid-run? Its view and `@State` go away, but the task holds `self`. Report it — it's the reason for decision 6, and a separate bug report if Render Queue misbehaves (don't fix it here).
5. **Timing baseline:** how long does one render take with Ned's current Generate config? Ask him for one Focus Room render time, or read it from the logs. Project the time for the smallest section (Design, 19), the largest (70) and all 414.
6. **Stop.** Post the drift list and findings. Wait for Ned's go before writing code.

## Phase 1 — library and storage

Commit 1: the library resource, `StyleLibrary.swift`, `StyleBrowserSet` and its storage, and the tests for them.

## Phase 2 — render controller

Commit 2: `StyleBrowserController` and its tests, against a fake client.

## Phase 3 — the tab

Commit 3: `StyleBrowserView`, the Labs tab, the root wiring and the credit line. Commit 4: README — a `### Style Browser (Labs)` section after Render Queue and an Acknowledgments entry for the style library (u/Dear-Spend-2865) and clio-style-preview (lumenastrum).

## Rules you must not break

- **Style renders never create `TSImage` records and never touch Ned's image folder.** After a batch, Recent Generations and the filmstrip must look exactly as before.
- No SwiftData model changes, no `@AppStorage`. No new `AppSettings` keys unless unavoidable — report it if so.
- The only writes to `generateVM` are in Send to Generate. Snapshotting its config is a read.
- No locking between the Style Browser and the Focus Room — Draw Things queues requests, and Render Queue already relies on that. Do report what happens if Ned generates in the Focus Room mid-batch.
- The template is exact: `Style: {name}: {style}. Subject: {prompt}`, name included.
- The library file stays byte-identical to upstream.
- Tests never write to the real Application Support folder — use a temp directory through the injectable root. If anything touches `UserDefaults.standard`, save and restore exactly as `GenerateTimeoutTests.swift:293–301` does.

## Verify

- `xcodebuild test -project TanqueStudio.xcodeproj -scheme TanqueStudio -only-testing:TanqueStudioTests -derivedDataPath .build -parallel-testing-enabled NO` — read the `Executed …` line. It stalls in teardown about half the time; the results are already written when it does.
- New `TanqueStudioTests/StyleLibraryTests.swift`: the bundled library loads 414 entries; names are unique; ten sections in first-appearance order with the counts above; `styledPrompt` gives the exact expected string for one known style; safe filenames are unique across all 414; `StyleBrowserSet` round-trips through JSON; the to-do list excludes rendered styles.
- New `TanqueStudioTests/StyleBrowserControllerTests.swift`, with a fake client: renders in order; skips rendered styles; one failing style doesn't stop the rest and records its error; cancel stops cleanly and isn't recorded as a failure; every request uses the set's seed and a batch of 1; a video config is refused.
- **Runtime:** create a set; render one card; render the Design section; pause and resume; cancel mid-run; leave Labs mid-batch and come back (progress continued); quit and relaunch (the set and its renders reload); Send to Generate fills the Focus Room's prompt, model, seed and size; drag a rendered PNG into Draw Things (metadata present); Recent Generations unchanged.
- **This is a UI feature: a green build and passing tests verify nothing visual.** If you can't run the app and look, say so plainly rather than letting a green build imply it works.
- Report the runtime checks as a table (check | ✅/❌), plus anything you had to change from the Decisions above.
