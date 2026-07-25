# Beta report triage — v0.9.28 (2026-07-25)

Three symptoms reported by Ned's beta tester on a different Mac:

1. Clicking **Parameters** shows the spinning beachball and never recovers; requires Force Quit.
2. **Model picker**: search finds the name, but clicking a result does nothing.
3. **White text on a light background**, almost impossible to read.

---

## 3. Unreadable text — CONFIRMED, FIXED (`c2abc49`)

**Cause: the tester is running macOS in Dark Mode.**

`DashboardDS` is a hardcoded light "paper" palette (`bg #f0ebe0`, `text #1a140c`) and
`Info.plist` pins no appearance key, so the app follows the system. Any control we don't
explicitly style uses a *semantic* colour, which resolves to near-white under Dark Mode
and then renders on that hardcoded cream background.

Measured with `NSAppearance.performAsCurrentDrawingAppearance`, contrast against the real
`DashboardDS` surfaces:

| | `labelColor` vs `bg` | `controlTextColor` vs `surf2` |
|---|---|---|
| Light | 17.66:1 | 14.00:1 |
| **Dark** | **1.19:1** | **1.50:1** |

WCAG's minimum for body text is 4.5:1. At 1.19:1 the text is effectively invisible — this
is not a subjective complaint.

Worst-affected controls, all semantic-coloured: the **model search `TextField`** (added in
0.9.27 — note the tester specifically mentions the search box), the `.menu` `Picker`s for
Sampler and Refiner, `Stepper` labels, and any unstyled `Text`.

**Fix:** `.preferredColorScheme(.light)` on `DashboardRootView`. This matches existing
precedent — `SettingsView`, `HelpWindow`, `WelcomeSheet`, `GenerateRightPanel` and
`DTProjectBrowserView` all pin `.dark` for their own themes. Making `DashboardDS`
appearance-aware is the better long-term answer but is a design project, not a hotfix.

**Not visually verified** — screen capture is unavailable in this environment. Worth
eyeballing in Dark Mode before release.

---

## 1 & 2. The hang and the dead model rows — UNRESOLVED

Two plausible theories were tested and **both rejected**. Recording them so they aren't
re-proposed.

### Rejected: the seed slider's step count

`ParametersSection` has `Slider(… in: -1...99_999, step: 1)` — 100,001 discrete steps,
where every other slider in the app is ≤150. Looked like a classic AppKit tick-mark blowup.

Measured build+layout+display of that exact slider:

| steps | time |
|---|---|
| 152 | 80.1 ms |
| 10,001 | 136.8 ms |
| 100,001 | 164.3 ms |

About 2×, not a hang. **Rejected.**

### Rejected: an out-of-range bound value

`randomizeSeed` is on by default and rolls `Int(UInt32.random(in: 0...UInt32.max))`, so
after any generate `config.seed` is up to 4,294,967,295 — roughly 43,000× the slider's
upper bound. This was attractive because it's *state-dependent*, which would explain why
Ned doesn't see it and the tester does.

| bound value | time |
|---|---|
| 500 (in range) | 160.9 ms |
| 99,999 (at max) | 159.1 ms |
| 100,000 (just over) | 159.1 ms |
| 4,294,967,295 | 156.8 ms |

SwiftUI clamps harmlessly. **Rejected.**

### Still-live hypotheses, untested

- **Layout cycle from `.fixedSize()` inside the fixed-width drawer.** The drawer pins its
  content to `.frame(width: 320)` and `.clipped()` (the 0.9.27 overflow fix), while the
  Sampler `Picker` inside `ParametersSection` uses `.fixedSize()` with menu items as long
  as "Euler Ancestral Trailing". A `.fixedSize()` child demanding more width than a fixed
  parent is a known source of repeated layout passes. `ParametersSection` holds three of
  the five `.fixedSize()` calls in the drawer, which correlates with the reported section.
- **Eager construction of all nine sections.** `DisclosureGroup` builds its content closure
  even while collapsed, and the sections sit in a plain `VStack`, so toggling any one
  invalidates and rebuilds all of them — including `AssistTabView` and `ModelSection`,
  whose `ForEach` over `vm.models` is **not** lazy. With a large model inventory this could
  make every drawer interaction expensive, which would explain symptoms 1 and 2 together:
  a blocked main thread makes model clicks look inert.

### What's needed to settle it

A spindump or sample from the tester **while it is hung** — that names the spinning frame
directly and ends the guessing:

```bash
sample "Tanque Studio" 10 -file ~/Desktop/tanque-hang.txt
```

Also worth collecting, since both live hypotheses are load- or environment-dependent:

- macOS version, Mac model, and whether Dark Mode is on (expected: yes, per §3)
- how many models the Draw Things server reports (`vm.models.count`) — the non-lazy
  `ForEach` scales with this
- whether the hang happens with the drawer's other sections too, or only Parameters
- whether it still reproduces on a build with the §3 fix

---

## Adjacent bug found while investigating (not fixed — needs a design call)

The seed `Slider` is bounded `-1...99_999`, but real seeds run to 4,294,967,295. The
numeric readout (`fieldRow("Seed", …)`) shows the true value while the slider sits pinned
at its maximum, and **touching the slider silently destroys the seed**, clamping a
4-billion value down to ≤99,999. Reproducibility of a previous render depends on that seed.

Not fixed here because the obvious repair is wrong: widening the range to the full UInt32
would create a 4-billion-step slider. The right answer is probably a numeric field with a
dice button rather than a slider at all — which is a UI decision, not a bug fix.
