# Intel / macOS 15 hang — RESOLVED

**Status: fixed in v0.9.29 and confirmed by a tester on an older Intel Mac (2026-07-26).**

This was an active investigation brief. It is now a closed record — there is nothing here to
run. Kept for the postmortem, because the way this bug was chased is more instructive than
the bug itself.

---

## The symptom

On older Intel Macs running macOS 15, expanding the **Parameters** section of the Focus Room
drawer pinned the main thread at 100% indefinitely. Force Quit was the only way out. It never
reproduced on Apple Silicon or macOS 26, which is what made it hard to chase.

A second reported symptom — model rows not responding to clicks — was almost certainly
downstream of the pinned main thread rather than its own bug. Not separately re-tested.

## The cause

**The seed `Slider`'s step count.** It was bounded `-1...99_999` with `step: 1` — **100,001
discrete positions, where every other slider in that section has ≤150** — while real seeds
come from `Int(UInt32.random(in: 0...UInt32.max))` and reach 4.29 billion, roughly 43,000×
outside the slider's own range.

Slider knob positioning converts to device pixels, and that is exactly where the captured
hang lived.

## The evidence

A `sample` taken on the affected machine during the hang put **7,288 of 7,288 samples — 100%
of a 10-second window — on one unbroken main-thread stack over 2,400 frames deep**. Not
blocked on a syscall: actively recursing `AG::Subgraph::update` →
`AG::Graph::update_attribute` → `AG::Graph::UpdateStack::update`, with a ~10-frame SwiftUICore
motif repeating hundreds of times and bottoming out in AppKit backing-store geometry
(`NSViewGetTransformToBacking`, `convertSizeToBacking:`,
`+[NSScreen _backingScaleFactorForScreen:]`). Other threads idle in `mach_msg`. A genuine
non-terminating SwiftUI layout cycle.

That backing-store bottom is also the likeliest explanation for why it was machine-specific:
old Intel iMacs are typically non-Retina (1× backing scale) where the development machines
are 2×, and a width that rounds cleanly at 2× can oscillate between two values at 1×.
**Plausible but unproven** — the affected machine's display scale was never recorded.

## The fix

`ParametersSection`'s seed control is now a numeric `TextField` plus a dice button, matching
what the classic `GenerateLeftPanel` has always used. The 100,001-step control is gone.

This also fixed a real bug affecting **every** machine: the readout showed the true seed while
the knob sat pinned at maximum, and nudging the slider silently clamped the seed to ≤99,999,
destroying that render's reproducibility.

**Standing constraint**: do not reintroduce a high-step-count `Slider` in this drawer. ≤150
steps is the norm here.

## What was tried and did not work

**Bounding the drawer's `.menu` Picker widths** (0.9.28): they used `.fixedSize()`, demanding
their ideal width unconditionally inside a drawer pinned to `.frame(width: 320)` + `.clipped()`
by the 0.9.27 overflow fix. Plausible, well-evidenced, and **wrong** — tested on the affected
Intel Mac, the hang persisted. The width cap remains in the code because it prevents genuine
truncation of the longest sampler name, but it did not fix the hang and should not be cited as
having done so.

**Do not "fix" anything here by removing the drawer's 320pt frame** — that frame is itself the
fix for a real overflow bug.

Also ruled out, from the sample: eager construction of the nine accordion sections and the
non-lazy `ModelSection` ForEach. Zero `ForEach` / `ModelSection` / `DisclosureGroup` frames
appear anywhere in the 14,000-line sample, on any thread. That also explains why *expanding* a
section was the trigger — `DisclosureGroup` builds its content while collapsed but does not lay
it out, and this was a layout cycle, not a construction cost.

## The lesson worth keeping

**The correct hypothesis had been explicitly ruled out, on bad evidence.** The seed slider was
measured at ~164ms against ~80ms for an ordinary slider — "2×, not a hang" — and dismissed.
That measurement was taken on the arm64 / macOS 26 development machine: **the configuration
that does not exhibit the bug.** It was never evidence about the machine that does, and it
cleared the actual root cause.

Worse, the exclusion was written into this very document under *"already ruled out — do not
re-propose,"* where it would have steered the next investigation away from the right answer
indefinitely. It cost a full build-and-ship cycle, recovered only because the tester reported
back on the failed first attempt.

**For any bug specific to a machine, OS, or display: measure on the affected configuration, or
record the hypothesis as untested. Never write "ruled out" from an off-target measurement — a
wrong exclusion is more expensive than an open question.**

A related rule, earned the same way: **don't record a machine-specific fix as fixed until that
machine confirms it.** The 0.9.28 attempt was written up as confirmed before any Intel machine
had run it, and then failed. "Shipped, awaiting verification" is the honest state.

## Still open

- Whether the inert-model-click symptom cleared (expected, not re-tested).
- The affected machine's display backing scale, which would settle the 1×-vs-2× theory.
- The tester's own Dark Mode setting, which would close out the separate white-on-light text
  issue fixed in 0.9.28 (`.preferredColorScheme(.light)` on `DashboardRootView`).
