# Intel / macOS 15 hang — VERIFY THE FIX

**Status: diagnosed and fixed on `main`. This document is now a verification brief.**
Paste it into a Claude Code session on the Intel iMac. Self-contained — no Open Brain,
no memory files needed.

The original diagnosis run is complete; its findings are summarised below as context.
**Your job is to confirm the fix works, not to re-diagnose.**

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

Also worth recording, because it may be the real discriminator:

```bash
system_profiler SPDisplaysDataType | grep -iE "resolution|retina"
```

The hang bottoms out in backing-scale rounding, so a **1× (non-Retina)** display is the
suspected trigger. Note what this machine has.

## Get the build

`main` is pushed and current. Pull and build Debug:

```bash
cd ~/Documents/GitHub/TanqueStudio    # clone if absent
git pull origin main
git log --oneline -1                  # expect ca6909f or later
xcodebuild -project TanqueStudio.xcodeproj -scheme TanqueStudio \
           -configuration Debug -derivedDataPath .build build
```

If `/Applications/Tanque Studio.app` is also running, by-name AppleScript will land on the
wrong instance — launch the built binary directly so the PID is unambiguous.

## What to verify

1. **The hang is gone.** Open a Focus Room, expand **Parameters**. It should render
   immediately. Previously this pinned the main thread at 100% forever, needing Force Quit.
2. **If it still hangs**, capture a fresh sample and compare against the old stack:
   ```bash
   sample "Tanque Studio" 10 -file ~/Desktop/tanque-hang-after.txt
   ```
   Report whether it's the same `AG::Subgraph::update` / backing-store cycle or something
   new. Do **not** start over from scratch — see "already ruled out" below.
3. **The pickers still look right.** Sampler, Seed Mode (Parameters) and Refiner (Model)
   are now capped at 210pt instead of `.fixedSize()`. Check the longest sampler name —
   **"Euler Ancestral Trailing"** — is not truncated, and nothing overflows the drawer.
   This is the specific regression risk of the fix: 170pt was measured to clip it, hence
   210. Screenshots welcome if permissions allow.
4. **Model rows respond to clicks again.** Expand Model, search, click a result — the row
   should highlight. This is expected to have been a *downstream* symptom of the pinned
   main thread rather than its own bug; confirming it closes that question.
5. **Nothing else in the drawer regressed** — expand every section once.

## What was already established — don't redo this

**Confirmed cause.** A sample taken during the hang put **7,288 of 7,288 samples (100% of a
10s window)** on one unbroken main-thread stack, 2,400+ frames deep, actively recursing
`AG::Subgraph::update` → `AG::Graph::update_attribute` → `AG::Graph::UpdateStack::update`
and bottoming out in AppKit backing-store geometry (`NSViewGetTransformToBacking`,
`convertSizeToBacking:`, `+[NSScreen _backingScaleFactorForScreen:]`). A genuine
non-terminating SwiftUI layout cycle. Other threads idle.

**The fix.** The drawer's `.menu` Pickers used `.fixedSize()`, demanding their ideal width
unconditionally inside a drawer pinned to `.frame(width: 320)` + `.clipped()` (the 0.9.27
overflow fix). A long entry wants more than the parent can give, and on this machine the
reconciliation never converges. Replaced with a bounded `.frame(maxWidth: 210)` on all
three pickers, so the demand is always satisfiable and there is nothing left to oscillate.

**Do not "fix" this by removing the drawer's 320pt frame** — that frame is itself a fix for
a real overflow bug.

**Already ruled out — do not re-propose:**
- *Eager construction of the nine accordion sections / non-lazy `ModelSection` ForEach* —
  zero `ForEach` / `ModelSection` / `DisclosureGroup` frames anywhere in the 14k-line
  sample, on any thread.
- *The seed slider's 100,001 steps* — measured 164ms vs 80ms for a normal slider. ~2×, not
  a hang.
- *An out-of-range slider value* (seeds reach 4.29 billion against a 99,999 bound) —
  measured 156.8ms. SwiftUI clamps harmlessly.

## Separately: two loose ends (not blockers)

- **Symptom 3, white-on-light text**, is diagnosed and fixed on `main`
  (`.preferredColorScheme(.light)` on `DashboardRootView`; Dark Mode measured 1.19:1
  contrast against a WCAG floor of 4.5:1). It needs an *eyeball in Dark Mode*, which you
  can do here regardless of architecture:
  ```bash
  defaults write -g AppleInterfaceStyle Dark    # remember to undo afterwards
  ```
  Confirm the drawer stays readable. **Undo with `defaults delete -g AppleInterfaceStyle`.**
- The **tester's own** Dark Mode setting is still unconfirmed — that needs the tester, not
  this machine.

## Report back

Whether the hang is gone; whether the pickers truncate; whether model clicks work; the
display's backing scale; and the Dark Mode eyeball. **A release is gated on this** — 0.9.29
is staged but deliberately not cut until the fix is confirmed, so that the release notes
don't claim a fix that was never tested.
