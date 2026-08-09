# Kickoff prompt — Podcast Auditions generator (paste into a fresh Claude Code session)

> Working directory should be `/Users/skeptict/Documents/GitHub/TanqueStudio`.

---

Build the generator that produces the **Podcast Auditions** StoryFlow project, following `Docs/podcast-auditions-storyflow-plan.md` — read it fully before writing any code, especially §2 (format rules), §3 (architecture), §4 (worked examples and escaping) and §5 (gotchas).

This is a **Python** task in a Swift repo. You are not touching `DrawThingsStudio/` or the Xcode project at all.

Context you need:

- **StoryFlow is CutsceneArtist's JSON workflow format**, not a Tanque Studio concept. You are emitting the **Editor project format**: `{projectName, items:[{type,value}], promptTriggers, configShortcuts, poseJSONShortcuts, wildcardShortcuts}`. All four shortcut maps must be present even when empty.
- **The authority is `misc/StoryflowPipeline_260802/StoryflowPipeline.js` and `StoryflowEditor.html`** — read the `allowedKeys` table (~`:59-113`), the executor switch (~`:955-1300`) and `ITEM_CONFIGS` (`StoryflowEditor.html:1351`). Two real author-supplied projects are in `misc/StoryflowPipeline_260802/projects/`; `CharacterSheet_3x2_1920x1280.json` is the closest structural precedent. Where the plan and the source disagree, the source wins — say so.
- **Draw Things is the primary target.** The deliverable must run in `StoryflowPipeline.js`. Tanque Studio compatibility is secondary and is being addressed separately (`Docs/storyflow-multiloop-kickoff-prompt.md`).
- `Scripts/verify_vtable_offsets.py` is the precedent for standalone Python in this repo: no dependencies beyond the stdlib.

Create `Projects/PodcastAuditions/` (new tracked top-level folder) containing:

1. **`bible.json`** — the character table, the single source of truth. Six entries, each with `name`, `identity`, `wardrobe`, `slate`, `line`, `voice`, `seed`. **Ship it with placeholder content and a schema comment block, clearly marked `TODO: Ned`.** Do not invent the characters — the creative content is Ned's, and a plausible-looking placeholder that gets mistaken for finished copy is worse than an obvious one. Make the placeholders obviously placeholder.

2. **`build_project.py`** — reads `bible.json` + a config file, emits `Podcast Auditions.json`. Requirements:
   - Two sequential loop blocks per plan §3, with the trim-line `note` between them.
   - **Every per-character wildcard must be `wild: "loop"`** — plan §2.1 explains why the architecture depends on it. Assert this rather than assuming it.
   - IDENTITY and WARDROBE card lists appear in **both** phases, emitted from the same bible rows so they cannot drift.
   - Correct triple escaping per plan §4.3: object-valued items are JSON **strings** containing JSON; the slate and line cards contain literal `"` characters that must survive into the model's prompt, because `framesDialog` counts words inside `"…"` spans only. Build with `json.dumps` twice, never string concatenation.
   - `frames`, `frames8`, `moodboardRemove` are the only three item types stored as JSON **numbers**. Everything else is string or bool.
   - Emit `padding: 48`, not the Editor's default of 49 — plan §5.1 has the modular arithmetic.
   - The shared `concat` fragments carry load-bearing leading/trailing spaces (the pipeline appends with no separator). Make the spacing explicit and visible in the source, not accidental.

3. **`configs.json`** — the two DT configs (Krea 2 stills, LTX-2 video) held separately from the builder. **Placeholders, marked `TODO: Ned`** — real model filenames, integer `sampler`/`seedMode` enums and tiling fields have to come from actual renders pulled via Tanque Studio's Import from DT. Document the required keys and where they come from; do not guess values.

4. **`verify_project.py`** — plan §4.3's checks, expanded into a real script. Must fail loudly on: any object-valued item whose `value` doesn't parse; any wildcard not in `loop` mode; card counts that aren't all equal across the per-character wildcards; zero quoted spans in the slate/line cards (the silent-failure mode — every clip would render at exactly `padding` frames); any `type` not in the 52-key `allowedKeys` set; `padding` not a multiple of 8. Print the computed `numFrames` per character alongside its spoken word count, and flag anything over 257 (Tanque Studio's cap; the JS has none, so past that the two engines diverge silently).

5. **`README.md`** — the share package doc. What to install (`StoryflowPipeline.js` version, models), the `~Pictures/PodcastAuditions/anchors/` folder to create before the first run, how to swap in your own characters by editing `bible.json`, and how to trim to characters-only.

Verify:

- `python3 Projects/PodcastAuditions/build_project.py` then `python3 Projects/PodcastAuditions/verify_project.py` — clean, with the placeholder bible in place.
- **Round-trip the output through Tanque Studio's own codec** rather than trusting your own emitter. Add the generated file to `TanqueStudioTests/Fixtures/` and assert the same properties `StoryFlowPipelineExportTests` asserts on the bundled projects: decodes, re-encodes deep-equal, projects through `toWorkflow`/`toProject` deep-equal, and exports with no unknown keys and no type mismatches against `allowedKeys`. **Put these in a new `PodcastAuditionsFixtureTests.swift` rather than editing `StoryFlowPipelineExportTests.swift`** — fixtures there are referenced by explicit name, not auto-discovered, and a parallel session may be editing the same test target. That is the strongest available correctness signal short of running it, and it catches exactly the escaping and value-typing errors this task is prone to. `xcodebuild test -scheme TanqueStudio -destination 'platform=macOS'` must stay green.
- Diff the structure of your phase-A block against `misc/StoryflowPipeline_260802/projects/CharacterSheet_3x2_1920x1280.json` — same shape, same value conventions.

Out of scope, and do not attempt: writing the six characters; sourcing real config values; running Draw Things; anything in `DrawThingsStudio/`.

Work on branch `feature/podcast-auditions` off `main`. Conventional commits. When the generator runs clean and the fixture sweep is green, stop and summarize — list precisely what Ned must fill in (`bible.json` rows, `configs.json` keys) for the project to become runnable.
