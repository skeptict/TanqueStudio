# Kickoff prompt — next session (paste into a fresh Claude Code session)

> Working directory: `/Users/skeptict/Documents/GitHub/TanqueStudio`
> Branch: `main`, clean, **level with `origin/main`**. Nothing is pending.

---

**0.9.39 shipped on 2026-08-12.** There is no release in flight and no half-finished work to
unwind. This session starts from a clean slate, which the last four did not.

Read `Docs/release-notes-0.9.39.md` for what just went out, and
`Docs/podcast-auditions-run-procedure.md` for the staged test plan — its status header is accurate.

## State you are inheriting

- **v0.9.39 released**: build 32, tag `v0.9.39` on `1f96166`, notarized + stapled, confirmed Latest
  via `gh api repos/skeptict/TanqueStudio/releases/latest --jq '.tag_name'`.
- **Suite: 330 passed, 6 skipped, 0 failures.** Run it with
  `xcodebuild test -project TanqueStudio.xcodeproj -scheme TanqueStudio -only-testing:TanqueStudioTests -derivedDataPath .build -parallel-testing-enabled NO`
  and read the `Executed …` line. It stalls in teardown maybe half the time — the results are
  already written when it does, so read the log rather than diagnosing the hang. The six skips are
  all live-Draw-Things gates (`TS_LIVE_DT`), which is correct.
- **`Projects/` now holds exactly one demo project.** The second lives in `TestProjects/`. Do not
  "tidy" it away — see the warning below. `Projects/*` is gitignored except the demo.
- **Draw Things addresses change constantly.** Every IP recorded in memory was stale within a day.
  `defaults read tanque.org.TanqueStudio tanqueStudio.dtHost` is the authoritative answer to what
  the app will dial; `nc -z -w 3 <host> 7859` says whether it answers. Don't ask, and don't trust a
  remembered address.

## What is verified, and what is not

Three stages of the run procedure now pass **on real renders**, so do not re-litigate them:

| Stage | Status |
|---|---|
| 1 — one still + one clip, both phases | ✅ `loopSave`/`loopLoad` verified, 217-frame 8.680 s mp4 |
| 2 — frame count | ✅ `framesDialog → 169 + 48 pad = 217` |
| 3 — cast pairing, 7 anchors | ✅ `anchor_001` is the labradoodle; identity + wardrobe in lockstep |
| **4 — the full seven-clip pass** | ❌ never attempted |
| **6 — Draw Things cross-check** | ❌ never attempted |

## The obvious next piece of work

**Stage 4**, if the server is healthy and you have the hours. Re-emit the project, both loops at 7,
run it once through. Seven clips, 81–449 frames each.

Budget it from measured numbers rather than optimism: **Skep's 217-frame clip took 19.3 minutes**
against `krea_2_turbo_q8p` + `ltx_2.3_22b_distilled_q8p`. Bunny's 449 frames is roughly twice that.
**Raise `dtGenerateTimeoutMinutes` before starting** — the current 20-minute default clears one
217-frame clip by about 40 seconds and will not survive the longer rows:

```bash
defaults write tanque.org.TanqueStudio tanqueStudio.dtGenerateTimeoutMinutes -int 60
```

Stage 6 (paste `Podcast Auditions.pipeline.json` into Draw Things) is the other open one and is
cheap by comparison. It is what earns the phrase "runs in either engine", which the notes currently
decline to claim.

## Traps that cost real time last session — read before repeating them

- **A stage that isn't moving is not a stall.** `imageEncoding` sat unchanged for 11 minutes on a
  healthy render that finished at 19.3. I called it wedged and advised resetting DT+ on the remote;
  that would have killed a working render. The discriminator is the **event count** in the log's
  `stages:` line, not the stage name — 5,700 events in `imageEncoding` is work, where the real
  2026-08-11 hang was 7,614 events in `textEncoding`, a stage that should emit almost none. That
  line is only written on completion, so **mid-run the honest answer is "cannot tell yet"**.
- **Validate any probe you build before believing a negative from it.** My click-test harness
  returned 0/15 and 0/23 clean failures and refuted two hypotheses — then failed the control on a
  field I had already focused another way. It could not focus anything. Point a new harness at a
  known-positive case *first*.
- **`Open…` in StoryFlow lists stale saved workflows with duplicate names.** There were three
  called "Podcast Auditions", all from 2026-08-09, still carrying pre-Aug-11 prompt text. Import
  from the file instead: Variables header → the tray-and-arrow-down icon → the emitted `.json`.
- **Never quit an app with a synthesized Cmd+Q.** `System Events … keystroke "q" using command
  down` goes to the **frontmost** app regardless of which process you addressed it to. I did this
  twice and quit Claude Code both times. Use `kill -TERM <pid>`.
- **Don't delete `TestProjects/PodcastEpisodes-beta/`.** `StoryFlowCastEmitterTests` gates on the
  folder with `XCTSkipUnless`, so removing it makes the byte-for-byte pinning test **skip** rather
  than fail — silently halving the coverage behind the two-emitter claim, with a green suite. It
  also has to stay exactly two levels below the repo root, because the Python generators compute
  `REPO = HERE.parent.parent`.

## Known and deliberately not done

Log or fix these, but they are not urgent:

- **The test suite writes into the production `request_log.txt`.** Every historical `STALLED …
  for 0s` entry is synthetic, from `GenerateTimeoutTests`; four more were added last session. They
  are indistinguishable from real stalls apart from the duration. Tests should point `RequestLogger`
  at a temp path.
- **There is no in-app way to reveal `request_log.txt`**, despite it being the only diagnostic that
  exists when a render misbehaves. It lives at
  `~/Library/Containers/tanque.org.TanqueStudio/Data/Library/Application Support/TanqueStudio/`.
- **The Loop-count field fix is unconfirmed by instrument.** Shipped as "reported better by hand".
  Measured facts: the hit area was 44×15 inside a control painting ~58×23, and a hit test at dead
  centre returns the field, enabled, while focus stays on the enclosing `List`. `.contentShape` and
  an explicit `@FocusState` went in; the root cause of the first-responder failure is still not
  fully explained. If Ned reports it still takes several clicks, that is a live bug.
- **Save Source normalizes the source files' hand formatting** — content, keys and key order stay
  byte-identical, only alignment changes. Listed in the README's Upcoming.

## Working style

Conventional commits, and commit only when asked. **A green build verifies nothing visual** — open
the app and look, or say plainly that you did not. Verify the running binary is the one you just
built (`pgrep -lf`, and compare its start time against the build's mtime); launching by name gets
the installed copy. When two engines are supposed to agree, treat a deliberate asymmetry as a bug
wearing a rationale.
