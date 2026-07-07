# Kickoff prompt — Layout Forks Spike Phase (paste into a fresh Claude Code session)

> Working directory should be `/Users/skeptict/Documents/GitHub/TanqueStudio`.

---

## Why this is a "spike," not the full build in `design_handoff_layout_forks/README.md`

That README (already in the repo, do read it in full first) proposes three permanent
branches — Command Deck, Workbench Tabs, Dashboard + Focus Rooms — each built to full
production parity (100% of the current-functionality checklist in its "Common Ground"
section), then lived-with on the real app before picking a winner.

Full production parity on all three before comparing is too expensive for what this
decision needs. Two of the three forks are view-layer only; the third — Workbench Tabs —
is a real data-model change (`GenerateViewModel` → `[GenerateSession]`), and that
model is reached directly from at least three other files beyond the Generate tab itself:
`StorySceneRenderPanel.swift` (Story Studio's "Send to Generate"), `DTProjectBrowserView.swift`,
and `GalleryStripView.swift`. Building that model change to full parity is a bigger and
riskier lift than the original README's "budget more time here" caveat suggests — it's
not isolated to Generate's own view files.

**This kickoff scopes a cheaper first pass:** build each fork's chrome and core
interactions wired to *real* `GenerateViewModel` state (real prompt, real model list,
real generate calls, real progress) — but skip corner cases, animations-as-described-to-the-pixel,
and the full parity checklist. Good enough to click around in for a day and get a gut
read on which spatial/navigation model fits how this app is actually used (chaptered
Story Studio work, not just single hero-image generation). Once a winner is picked,
*that* branch gets hardened to full parity; the other two get deleted, unhardened.

## Setup — worktrees, not the primary tree

```bash
git -C /Users/skeptict/Documents/GitHub/TanqueStudio worktree add \
    -b spike/command-deck /Users/skeptict/Documents/GitHub/TanqueStudio-spike-deck main
git -C /Users/skeptict/Documents/GitHub/TanqueStudio worktree add \
    -b spike/dashboard-focus /Users/skeptict/Documents/GitHub/TanqueStudio-spike-dashboard main
```

Do the Workbench Tabs spike (see "Sequencing" below) only after the other two are
already clickable — its model change makes it the one most worth deferring or dropping
if the first two already surface a clear preference.

Note: a prior session in this repo hit a `.git/index.lock` permission error when running
git status/commands against the primary tree from a sandboxed shell. If you hit the same,
run git commands from a real terminal against the actual paths above, not through a
sandboxed mount.

## Prerequisite for all forks: bundle the real fonts

`TanqueDS.swift` currently has a TODO — IBM Plex Mono isn't actually bundled; it falls
back to `.system(design: .monospaced)`. Atkinson Hyperlegible was never added either.
The original design handoff's font section assumes both are "already required per the
DS-alignment handoff" — that isn't true in the current tree. Before any fork will look
like its prototype:

1. Download IBM Plex Mono (OFL) and Atkinson Hyperlegible (OFL, Braille Institute) — regular/medium/semibold weights, italic for Atkinson.
2. Add to `DrawThingsStudio/Resources/Fonts/`, register in `Info.plist` (`UIAppFonts`-equivalent for macOS is `ATSApplicationFontsPath` or per-font `NSFontManager` registration — check how `Resources/Fonts` is currently wired, if at all).
3. Update `TanqueDS.Font` to use `Font.custom("IBMPlexMono-Regular", size:)` etc., remove the TODO fallback.

Do this once, on `main` or as a shared first commit cherry-picked into each spike branch — not redundantly three times.

## Fork-specific notes

Read `design_handoff_layout_forks/README.md` in full for each fork's layout structure,
colors, and interaction table — that content is accurate and doesn't need restating here.
For the spike, build:

- **Command Deck**: the floating command bar, params/LoRA/img2img panel toggles, and the
  circular generate button with real progress. Command palette (⌘K) can be a stub (opens,
  filters a hardcoded nav list) — its real value is felt after a few real generations, not
  from the palette itself. Skip draggable panel positioning.
- **Dashboard + Focus Rooms**: the Dashboard view with real "Continue" state (last session
  from `GenerateViewModel`, not mocked) and Focus Room with the accordion drawer
  (`DisclosureGroup`, per the handoff's own recommendation — don't hand-roll it). Quick
  Start preset copy is genuinely undefined — use 2–3 placeholder presets clearly marked
  `// TODO: confirm wording with Ned`, do not invent final copy. Paper light theme: build
  it, this fork's whole point partly is testing dark-vs-light, don't skip it to save time.
- **Workbench Tabs**: only attempt after the other two are clickable and reviewed. If
  attempted, keep the new `GenerateSession` model additive and behind this branch only —
  do not refactor `GenerateViewModel`'s existing consumers (`StorySceneRenderPanel`,
  `DTProjectBrowserView`, `GalleryStripView`) to the array model as part of the spike;
  wrap/adapt at the boundary instead so a "no" verdict on this fork doesn't leave main's
  merge target destabilized. One tab, one working session, is enough signal — the
  multi-session value is the harder thing to fake, so at least prove the tab bar +
  progress-ring-per-tab concept even with only one real concurrent session.

## What "done" looks like for the spike

Not the README's full parity checklist. Instead: each spike branch should let Ned type a
prompt, pick a real model, hit Generate, watch real progress, and see a real image land —
in that fork's chrome. That's enough to compare against how a real Story Studio /
StoryFlow session actually feels, which the original HTML prototypes' fake-progress
click-through can't tell him.

## Sequencing

1. Font bundling (shared prerequisite, ~1 commit).
2. Command Deck spike.
3. Dashboard + Focus Rooms spike.
4. Ned reviews both against real work for a few days.
5. Decide whether Workbench Tabs' session-model question is even still live — if one of
   the first two already wins clearly, skip it rather than building it just for completeness.
6. Winner gets hardened to the original README's full parity checklist on its own branch;
   losers' worktrees get removed (`git worktree remove`), branches deleted.

## What Not to Change (same as original handoff)

gRPC/LLM/Draw Things backend logic, `ImmersiveOverlay`, metadata parsing/PNG embedding,
`StoryFlow*` engine and storage — only chrome around it changes.
