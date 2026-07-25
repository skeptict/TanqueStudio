# Kickoff — reproduce the 0.9.28 Parameters hang on Intel / macOS 15

**Paste this whole file into a fresh Claude Code session on the Intel iMac.** It is
self-contained: no Open Brain, no memory files, no repo history needed to get started.

---

## The situation

Tanque Studio v0.9.28 (macOS app, SwiftUI, Draw Things companion). A beta tester reports
three problems. **They reproduce only on old Intel Macs, never on current Apple Silicon
laptops** — which is why you are on this machine.

1. Clicking **Parameters** in the Focus Room drawer shows the spinning beachball and never
   recovers. Force Quit required.
2. **Model picker**: the search box finds a model by name, but clicking the result does
   nothing.
3. **White text on a light background**, almost impossible to read.

Development happens on an M1 MacBook Pro running macOS 26, where none of this reproduces.
This machine is Intel on macOS 15.7.7.

## Your job

Get a `sample` during the hang, identify the spinning frame, and confirm or kill the two
remaining hypotheses. Symptom 3 is already solved (below) — don't re-investigate it.

---

## Symptom 3 is SOLVED — do not re-investigate

**Cause: the app follows the system appearance, and the tester is in Dark Mode.**

`DashboardDS` is a hardcoded light "paper" palette (`bg #f0ebe0`, `text #1a140c`) and
`Info.plist` pins no appearance key. Under Dark Mode every control that uses a *semantic*
colour — the model search `TextField`, `.menu` `Picker`s, unstyled `Text` — resolves to
near-white and lands on that cream background.

Measured contrast (via `NSAppearance.performAsCurrentDrawingAppearance`):

| | `labelColor` vs `bg` | `controlTextColor` vs `surf2` |
|---|---|---|
| Light | 17.66:1 | 14.00:1 |
| **Dark** | **1.19:1** | **1.50:1** |

WCAG's floor for body text is 4.5:1. Fixed on the dev machine with
`.preferredColorScheme(.light)` on `DashboardRootView` — **that fix is not on this machine
unless you build from a pushed `main`** (see "What's on this machine" below).

Do confirm the tester's setting, since it's one command and it validates the diagnosis:

```bash
defaults read -g AppleInterfaceStyle 2>/dev/null || echo "Light Mode"
```

---

## Two hypotheses already TESTED AND REJECTED — do not re-propose these

Both looked strong. Both were measured with a standalone `NSHostingView` +
`layoutSubtreeIfNeeded()` + `display()` timing harness. Neither survived.

**Rejected — the seed slider's step count.** `ParametersSection` has
`Slider(… in: -1...99_999, step: 1)` = 100,001 discrete steps, where every other slider in
the app is ≤150. Looked like a classic AppKit tick-mark blowup.

| steps | build+layout+display |
|---|---|
| 152 | 80.1 ms |
| 10,001 | 136.8 ms |
| 100,001 | 164.3 ms |

~2×, not a hang.

**Rejected — an out-of-range bound value.** `randomizeSeed` is on by default and rolls
`Int(UInt32.random(in: 0...UInt32.max))`, so after any generate `config.seed` reaches
~4.29 billion, roughly 43,000× the slider's upper bound. Attractive because it's
*state-dependent*, which would explain why the dev machine never sees it.

| bound value | time |
|---|---|
| 500 | 160.9 ms |
| 99,999 | 159.1 ms |
| 100,000 | 159.1 ms |
| 4,294,967,295 | 156.8 ms |

SwiftUI clamps harmlessly. No difference.

**Both were measured on macOS 26 / arm64.** If the `sample` points back at the slider, it
is worth re-running those same measurements *here*, because the whole premise is that this
OS's SwiftUI behaves differently. But don't start there.

---

## Live hypotheses, in priority order

**1. A layout cycle from `.fixedSize()` inside the fixed-width drawer.** The drawer pins
content to `.frame(width: 320)` and `.clipped()` (added in 0.9.27 to fix a long-prompt
overflow). The Sampler `Picker` in `ParametersSection` uses `.fixedSize()` with menu items
as long as `"Euler Ancestral Trailing"`. A `.fixedSize()` child demanding more width than a
fixed-width parent is a known source of repeated layout passes.
`ParametersSection` holds 3 of the drawer's 5 `.fixedSize()` calls — which correlates with
the reported section. **This is the leading theory**: a layout cycle either terminates or
it doesn't, which fits "hangs forever on one OS, fine on another" far better than anything
load-related.

**2. Eager construction of all nine accordion sections.** `DisclosureGroup` builds its
content closure even while collapsed, and the nine sections sit in a plain `VStack`, so
toggling any one invalidates and rebuilds all of them. `ModelSection`'s `ForEach(vm.models)`
is **not** lazy. With a large model inventory every drawer interaction gets expensive —
which would explain symptoms 1 and 2 together, since a blocked main thread makes model
clicks look inert.

Relevant files (all under `DrawThingsStudio/Dashboard/`):
- `DashboardFocusPanels.swift` — `FocusRoomDrawer` (~line 33), `section()` helper (~line 77),
  `ModelSection` (~161), `ParametersSection` (~430)
- `DashboardDS.swift` — the palette
- `DashboardRootView.swift` — app root

---

## What to run

**First, confirm the machine** (the last session was told it had moved and hadn't):

```bash
uname -m; sw_vers; hostname
```

Expect `x86_64` and `15.7.7`. If you see `arm64` or macOS 26, stop and say so.

**Then get the sample.** This is the single most valuable artifact — it names the spinning
frame and ends the guessing. Launch the app, click Parameters to trigger the hang, then:

```bash
sample "Tanque Studio" 10 -file ~/Desktop/tanque-hang.txt
```

Read the result and look for a deep repeating frame stack — repeated
`layoutSubtreeIfNeeded` / `NSView` layout / SwiftUI `AG::Graph` frames indicate a cycle
(hypothesis 1); heavy `ForEach`/view-construction frames indicate hypothesis 2.

Also worth collecting:

```bash
defaults read -g AppleInterfaceStyle 2>/dev/null || echo "Light Mode"   # symptom 3 check
defaults read tanque.org.TanqueStudio 2>/dev/null | grep -i "dtHost\|dtPort"
```

And ask Ned: does the hang hit other drawer sections, or only Parameters? How many models
does his Draw Things server report?

---

## What's on this machine

**The dev machine's `main` was NOT pushed as of this handoff.** Everything from 2026-07-25
— four branch merges, a StoryFlow passthrough fix, the Dark Mode fix, the triage docs — is
local to the M1. So:

- **To reproduce only:** you want the **released 0.9.28** from GitHub Releases. That's what
  the tester has, and an unfixed build is *better* for reproduction. No repo needed.
- **To test fixes:** the repo must be cloned/pulled *after* Ned pushes `main`. Confirm with
  him before assuming a clone here is current — an older clone will not have any of it.

Note the released build is notarized and hardened; if you need to attach a debugger or run
an instrumented build, build locally instead.

## Gotchas from previous sessions on this project

- **Building locally while `/Applications/Tanque Studio.app` is also running** makes
  by-name AppleScript land on the wrong instance. Use a distinct
  `PRODUCT_BUNDLE_IDENTIFIER` override plus a dedicated `-derivedDataPath .build`, and
  launch the binary directly so the PID is known.
- **A fresh build can take ~15s to show its first window** (SwiftData setup against a large
  store). `sample` showing the main thread in `App.main()` at that stage is normal, not a
  hang. Don't conclude "broken" before ~15s.
- **The UI smoke test** (`xcodebuild test -only-testing:TanqueStudioUITests`) frequently
  fails with "Timed out while enabling automation mode" — an automation-permission issue,
  not a code failure.
- **`screencapture` and System Events may be permission-blocked**, and System Events can
  hang rather than error. Don't build a plan that depends on screenshots without checking
  first.
- The test target is `TanqueStudioUITests`; the *directory* is `DrawThingsStudioUITests`.

## Report back

The `sample` output (or the key repeating frames), which hypothesis it supports, the Dark
Mode answer, and the model count. If the sample is inconclusive, the next step is bisecting
the drawer — comment out sections in `FocusRoomDrawer` until the hang stops.
