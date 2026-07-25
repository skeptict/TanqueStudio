# Intel / macOS 15 hang — TEST BUILD B

**Status: NOT fixed. Build A was tried and failed. Build B is shipped in 0.9.29 and is unverified.**
Paste this into a Claude Code session on the Intel iMac. Self-contained — no Open Brain,
no memory files needed.

**Your job is to test Build B, not to re-diagnose from scratch.** A great deal is already
established; the "already ruled out" section below is load-bearing.

---

## First: confirm the machine

A previous session was told it had moved to this machine and had not. Verify before
anything else:

```bash
uname -m; sw_vers; hostname
```

Expect `x86_64` and `15.7.7`. **If you see `arm64` or macOS 26, stop and say so** — the
bug's entire trigger condition is being on this machine, so a run on the wrong host
produces confidently meaningless results.

Also record this, because it may be the real discriminator:

```bash
system_profiler SPDisplaysDataType | grep -iE "resolution|retina"
```

The hang bottoms out in backing-scale rounding, so a **1× (non-Retina)** display is the
suspected trigger. Note what this machine has.

## Get the build

```bash
cd ~/Documents/GitHub/TanqueStudio    # clone if absent
git pull origin main
git log --oneline -1
xcodebuild -project TanqueStudio.xcodeproj -scheme TanqueStudio \
           -configuration Debug -derivedDataPath .build build
```

If `/Applications/Tanque Studio.app` is also running, by-name AppleScript will land on the
wrong instance — launch the built binary directly so the PID is unambiguous.

## The story so far

**The captured evidence (still valid, don't re-gather).** A `sample` taken during the hang
put **7,288 of 7,288 samples — 100% of a 10s window** — on one unbroken main-thread stack,
2,400+ frames deep, actively recursing `AG::Subgraph::update` → `AG::Graph::update_attribute`
→ `AG::Graph::UpdateStack::update` and bottoming out in AppKit backing-store geometry
(`NSViewGetTransformToBacking`, `convertSizeToBacking:`, `+[NSScreen _backingScaleFactorForScreen:]`).
A genuine non-terminating SwiftUI layout cycle. Other threads idle in `mach_msg`.

**Build A — bounded picker widths — FAILED.** The theory was that the drawer's `.menu`
Pickers used `.fixedSize()`, demanding their ideal width unconditionally inside a drawer
pinned to `.frame(width: 320)` + `.clipped()`. Replaced with `.frame(maxWidth: 210)` on all
three pickers (`3844289`, widened from 170 in `ca6909f`). **This did not fix the hang on
this machine.** So the `.fixedSize()` conflict was not the cause, or not the only one. The
change is still on `main` — it's harmless and prevents a real truncation risk — but it is
not the fix.

**Build B — the seed slider — is what you are testing** (`98e3303`). The seed control was a
`Slider` bounded `-1...99_999` with `step: 1`: **100,001 discrete positions, where every
other slider in that section has ≤150**. Meanwhile real seeds come from
`Int(UInt32.random(in: 0...UInt32.max))` and reach 4.29 billion, so the bound value sat
~43,000× outside its own range. Slider knob positioning converts to device pixels, and the
captured hang bottoms out in exactly that code. It is now a numeric `TextField` + dice
button, matching what the classic `GenerateLeftPanel` has always used.

**Why this was previously "ruled out" and why that was wrong:** an earlier measurement
(164ms vs 80ms, ~2×, "not a hang") appeared to clear the seed slider. That measurement was
taken **on macOS 26 — the OS that does not hang** — so it never applied to this machine.
Do not let the old note talk you out of this hypothesis.

## What to verify

1. **The hang.** Open a Focus Room, expand **Parameters**. Previously this pinned the main
   thread at 100% forever, needing Force Quit. Report plainly whether it still does.
2. **If it still hangs**, capture a fresh sample:
   ```bash
   sample "Tanque Studio" 10 -file ~/Desktop/tanque-hang-B.txt
   ```
   Report whether it's the same `AG::Subgraph::update` / backing-store cycle or something
   new. **If it is still the same cycle, the next suspects are the four remaining `Slider`s
   in `ParametersSection`** — steps (`:474`), guidance scale (`:477`), shift (`:624`),
   stochastic gamma (`:642`) — plus five more elsewhere in the drawer. Build B removed only
   the seed slider, so it tests "a 100,001-step slider is pathological" but **not** "any
   Slider in this constrained drawer is pathological." That distinction is the whole value
   of a negative result here.
3. **The seed control works.** Type a seed, confirm it sticks and isn't clamped or
   comma-grouped. Roll the dice, confirm a large seed (billions) displays in full.
4. **The pickers still look right.** Sampler, Seed Mode and Refiner are capped at 210pt.
   Check the longest sampler name — **"Euler Ancestral Trailing"** — is not truncated.
5. **Model rows respond to clicks.** Expand Model, search, click a result. Expected to be a
   *downstream* symptom of the pinned main thread rather than its own bug; if the hang is
   gone and clicks still don't work, that's a separate real bug.
6. **Nothing else in the drawer regressed** — expand every section once.

## Already ruled out — do not re-propose

- *Eager construction of the nine accordion sections / non-lazy `ModelSection` ForEach* —
  zero `ForEach` / `ModelSection` / `DisclosureGroup` frames anywhere in the 14k-line
  sample, on any thread. This also explains why expanding the section is the trigger:
  `DisclosureGroup` **builds** its content while collapsed but does not **lay it out**, and
  this is a layout cycle, not a construction cost.
- *Removing the drawer's 320pt frame* — that frame is itself the fix for a real overflow
  bug in 0.9.27 (a long prompt blowing the drawer wide). Don't undo it.
- *The `.fixedSize()` picker conflict* — that was Build A, and it failed. See above.

## Separately: two loose ends (not blockers)

- **Symptom 3, white-on-light text**, is fixed on `main` (`.preferredColorScheme(.light)` on
  `DashboardRootView`; Dark Mode measured 1.19:1 contrast against a WCAG floor of 4.5:1). It
  needs an *eyeball in Dark Mode*, which you can do here regardless of architecture:
  ```bash
  defaults write -g AppleInterfaceStyle Dark    # remember to undo afterwards
  ```
  Confirm the drawer stays readable. **Undo with `defaults delete -g AppleInterfaceStyle`.**
- The **tester's own** Dark Mode setting is still unconfirmed — that needs the tester, not
  this machine.

## Report back

Whether the hang is gone; if not, whether the sample shows the same cycle; whether the seed
field behaves; whether the pickers truncate; whether model clicks work; the display's
backing scale; and the Dark Mode eyeball.

**0.9.29 shipped Build B as an explicitly unverified fix** — the release notes say so. If it
worked, that gets confirmed in the 0.9.30 notes. If it didn't, we keep going with the
slider list above.
