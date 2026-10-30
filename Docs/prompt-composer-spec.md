# Prompt Composer — spec (v1)

Agreed 2026-10-04. Origin: a Perplexity-drafted web page ("Prompt Atelier") that built a
prompt from a base idea, colour dropdowns and free-text sections. This is the native version,
scoped to fix what that draft got wrong and to reuse what Tanque Studio already has.

## What it is

A **Compose** button beside ✨ Assist in the Generate prompt section opens a sheet where a
prompt is built from ordered sections, previewed, and applied to the prompt fields.

- **Sections** — each has a title, free text, an enabled toggle, a placement (positive or
  negative), up/down buttons and remove. `+ Add section` lists the library categories plus
  Custom.
- **Library** — each section offers a menu of stock options from its category file; picking
  one appends it to the section's text.
- **Negative placement** — negative sections build `negativePrompt`. They are never joined
  into the positive prompt (the draft's bug).
- **Style** — Auto / Tags / Prose.
  - **Tags**: deterministic, comma-joined, in code.
  - **Prose**: positive sections are sent labelled ("Lighting: …") to the configured LLM
    through the `07-tags-to-prose` operation; the result is an editable draft with Rewrite.
    Negative sections are still assembled as tags.
  - **Auto** resolves from `config.modelFamily`: SD 1.5, SDXL and AnimateDiff (CLIP text
    encoders) → Tags; everything else, including unrecognised names such as Krea or Qwen →
    Prose.
- **Apply replaces, never merges.** The positive prompt is replaced. The negative prompt is
  replaced only when an enabled negative section has text; otherwise it is left alone. If
  either field holds text that Apply did not write, Apply asks before replacing it.
- **State** lives on `GenerateViewModel.composition` (Ned, 2026-10-04): it survives closing the
  sheet, collapsing the Prompt section and leaving the Focus Room, and is not persisted
  across launches.

## Library files

`~/Library/Containers/…/Application Support/TanqueStudio/PromptFragments/*.md`, one file per
category. Same shape as LLM operations:

```
---
name: Lighting
placement: positive        (optional; positive | negative; default positive)
---
golden hour sunlight
# lines starting with # are comments
soft overcast light
```

Body = one option per line; blank lines and `#` lines are skipped. Built-ins ship in
`Resources/PromptFragments/` and are seeded **per file** with `LLMOperationLoader.filesToSeed`
against `AppSettings.promptFragmentSeededFiles`, so a new built-in reaches existing users and a
deleted one stays deleted. An existing file is never overwritten.

⚠️ Adding a built-in fragment file needs **two** project edits, like LLMOperations: the file is
copied by the `PromptFragments` folder reference, and it must also be listed in the synchronized
group's `membershipExceptions`, or it is copied flat into the bundle root as well.

## The prose operation

`Resources/LLMOperations/07-tags-to-prose.md` is an ordinary Assist operation, so it also
rewrites any tag prompt from the Assist section. Compose looks it up by id in the user's
operations folder and falls back to the bundled copy if the user has deleted or renamed it.
Prose uses the shared Settings → LLM model; Compose has no model setting of its own. In Prose
mode the sheet shows `LLMModelPicker` — the MODEL row extracted from Assist (2026-10-05, Ned) —
bound to that same setting, so a pick in Compose or Assist changes both. Assist now reads the
setting live instead of copying it in on appear.

## Contract

**New:** `PromptComposer.swift` (pure model + assembly), `PromptFragmentLibrary.swift`
(loader + seeding), `PromptComposerSheet.swift` (UI), `Resources/PromptFragments/*.md`,
`Resources/LLMOperations/07-tags-to-prose.md`, `TanqueStudioTests/PromptComposerTests.swift`,
`TanqueStudioTests/PromptFragmentLibraryTests.swift`.

**Modified:** `Dashboard/DashboardFocusPanels.swift` (`PromptSection`: button + sheet),
`GenerateViewModel.swift` (one additive property), `AppSettings.swift` (one new key
`tanqueStudio.promptFragmentSeededFiles`), `TanqueStudio.xcodeproj/project.pbxproj` (folder
reference + exceptions), `Resources/Help/generate.md`.

**Added 2026-10-05:** `LLMModelPicker.swift` (shared MODEL row); `AssistTabView.swift` now uses
it in place of its private copy.

**Not touched:** `StoryPromptAssembler`, `LLMService`, `LLMOperationLoader`
(its existing `filesToSeed` is called, not changed), Render Queue, Story Studio.

**Rollback:** revert the branch. Seeded library files left in Application Support are inert.

## Design constraints (from past bugs)

- Sections render in a `ScrollView`/`VStack`, not a `List` — a text field in a `List` row can
  fail to take focus.
- `ForEach` binds by section identity, never by index — an index binding crashes on removal.
- Section text editors bind straight to the model with no filtering transform, so Return
  always inserts a newline.
- The sheet pins `.environment(\.colorScheme, .light)` and paints the `DashboardDS` palette,
  so system-drawn controls resolve against the paper theme.
- A failed Prose run shows its error and offers the Tags result; it never leaves a stale
  draft looking current. A prose draft written from different sections is marked stale.
- Removing a section with text, and Clear All, ask first.

## Deliberately later

Saved recipes on disk · send a section's library options to Render Queue as an axis ·
character sections drawn from Cast & Staging (binding attributes to a named character) ·
approximate CLIP token count in Tags mode · Compose in Story Studio.
