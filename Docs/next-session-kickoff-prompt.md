# Kickoff prompt — next session (paste into a fresh Claude Code session)

> Working directory: `/Users/skeptict/Documents/GitHub/TanqueStudio`
> Branch: `feature/podcast-auditions` — **20 commits ahead of `origin/main`, nothing pushed.**

---

The Cast & Staging pane is built, tested and used. **The job this session is to get 0.9.39 out**,
and — if the server cooperates — to finally run the two-phase project end to end.

Read `Docs/release-notes-0.9.39.md` first; it is drafted and current. Then
`Docs/podcast-auditions-run-procedure.md`, which is the staged test plan and is accurate as of
2026-08-11.

## State you are inheriting

- **Suite: 331 passed, 7 skipped, 0 failures.** Run it with
  `xcodebuild test -scheme TanqueStudio -destination 'platform=macOS' -parallel-testing-enabled NO`
  and read the `Executed …` line. The run stalls in teardown sometimes; retry rather than diagnose.
- Version is **0.9.38**. The bump to 0.9.39 / build 32 is step 2 of `Docs/release-checklist.md`.
- The notarization keychain profile was **confirmed working** on 2026-08-11 (`xcrun notarytool
  history --keychain-profile TanqueStudio-Notarization`), so the API-key fallback in older notes is
  not needed. Run `Scripts/notarize.sh` with `dangerouslyDisableSandbox`.
- `main` and `origin/main` are both at `6d94a5b`. The checklist wants a `--no-ff` merge before the
  bump.

## Decide these before running the checklist

1. **`Projects/TanqueStudioTest01/` and `TanqueStudioTest02/` are untracked inside a tracked
   directory.** Ned's scratch projects from testing the pane. Delete, gitignore, or commit one as a
   worked example — but decide, because a careless `git add -A` sweeps them into the release.
2. **Whether the end-to-end render blocks the tag.** It has never completed. The release notes'
   Known Gaps says so plainly, so shipping without it is defensible — it is Ned's call, not yours.

## The run, if the server is healthy

`Docs/podcast-auditions-run-procedure.md`, stage 1 first (both loops set to `1`, about ten
minutes). Do **not** start with a full pass.

**Before blaming anything else, check the Draw Things+ session.** On 2026-08-11 a stale DT+ session
produced three different symptoms in one afternoon — a DT crash (`SIGTRAP` in
`TextEncoder.encodeLTX2`), a 20-minute hang (`STALLED in textEncoding`, 7,614 progress events with
the stage never changing), and `Draw Things returned 0 image(s)` — and signing out of DT+ and back
in fixed it each time, for about an hour. **Bridge Mode being ON does not rule it out.** This has
now been the answer three times while models, samplers and memory ceilings were wrong every time.

The diagnostic file is `~/Library/Containers/tanque.org.TanqueStudio/Data/Library/Application
Support/TanqueStudio/request_log.txt` — inside the sandbox container, not the obvious location. It
records each request's config and the stage sequence Draw Things reported.

**What a good stage-1 result looks like:** a `.mp4` plus a sibling frame folder in
`~/Desktop/Studio Generate/StoryFlow/<Project>/<timestamp>/`. That has happened exactly once, on
2026-08-11 at 14:49 — 217 frames, 8.68 s — which is the only live verification `04d51c2` has.

## Known, deliberately not done

Log these or fix them, but do not let them delay the tag:

- **The test suite writes into the production `request_log.txt`.** All 23 historical `STALLED`
  entries are synthetic (`for 0s`, one timestamp) from `GenerateTimeoutTests`. They look exactly
  like real stalls apart from the duration. Tests should point `RequestLogger` at a temp path.
- **There is no in-app way to reveal `request_log.txt`**, despite it being the only diagnostic that
  exists when a render misbehaves.
- **The watchdog's idle allowance inherits the whole-render budget** (`3e85df2`). As a *total*
  budget 2.3 h for a 217-frame clip is right; as a tolerance for *silence* it is far too long. Ned's
  `defaults write tanque.org.TanqueStudio tanqueStudio.dtGenerateTimeoutMinutes -int 20` is doing
  real work. The allowance should be a small multiple of the observed inter-stage gap.
- **Save Source normalizes the source files' hand formatting** — content, keys and key order are
  byte-identical, only alignment changes (~22 cosmetic lines on `configs.json`). Listed in the
  README's Upcoming.

## Working style

Conventional commits. **A green build verifies nothing visual** — open the app and look, or say
plainly that you did not. Four visual defects were found that way in this feature and every one
would have shipped otherwise. When two engines are supposed to agree, treat a deliberate asymmetry
as a bug wearing a rationale.
