# Score this clip (YuE2 and TanqueLoops) — spec (v1.1)

Agreed 2026-11-04 (decisions at the end). Origin: after 0.9.51 Ned asked about audio features, perhaps using YuE2 Studio, the local
song generator that already runs on this Mac. Of the options discussed, scoring a finished clip
needs the least new plumbing, because every movie export already muxes a soundtrack.

**v1.1, 2026-11-04:** TanqueLoops loops added as a second source (Ned). A loop renders offline in
well under a second, tiles to any length and needs no server, so the phases now build the sheet
against loops first and add YuE2 second.

## What it is

When a movie is exported, Tanque Studio can give it a soundtrack from one of two **sources**:

- **YuE2:** ask YuE2 Studio for an instrumental and cut an excerpt to the clip's length.
- **Loop:** render a TanqueLoops loop and repeat it to the clip's length (see the
  TanqueLoops section below).

The source is a picker at the top of the sheet. Everything after it is shared by both
sources: the Draw Things audio slider, the fades, ▶ preview, the metadata record and the
export. The rest of this section describes the YuE2 source.

- **Where:** beside **Export Movie** in the Focus Room (a video series), and on the DT Project
  Browser's clip export. Both already call `VideoAssembler.assemble(…audio:…)`; this feature
  only changes what goes into `audio`.
- **Input:** a style line ("ambient synth pad, slow, warm"), as YuE2 takes it: genre,
  instruments, mood and tempo tags. An optional ✨ button drafts it from the clip's prompt with
  the configured LLM (an `LLMOperations` file, same shape as Compose's prose operation).
- **The job:** `POST /api/jobs` with `kind: "create"`, preset `fast`, and lyrics made only of
  section tags (`[Intro]\n\n[Verse]\n\n[Outro]`). YuE2 renders a lyric of only tags as an
  instrumental. The seed is random unless the user pins one, and is recorded either way.
- **Waiting:** progress from `GET /api/jobs/{id}/events` (SSE, stages `load` → `plan` →
  `semantic` → `synthesize` → `decode` → `save`), falling back to polling `GET /api/jobs/{id}`
  if the stream drops. A Cancel button sends `POST /api/jobs/{id}/cancel`.
- **Fitting it to the clip:** download `/api/songs/{id}/audio.flac` (48 kHz stereo, 24-bit,
  the same rate as Draw Things' clip audio). Decode it with `AVAudioFile`, take an excerpt as
  long as the clip (`frames / fps`) from a start time, fade in and out (default 0.5 s each),
  and hand it to the exporter as `VideoAssembler.Audio`.
- **Choosing the excerpt:** a start-time field (default 0 s), a **+5 s** nudge because YuE2
  songs open with a quiet `[Intro]`, and ▶ to play just the excerpt before exporting. No
  waveform in v1.
- **Draw Things' own audio:** when the clip already has a soundtrack (LTX), a **Draw Things
  audio** volume slider appears. At 0% the score replaces it; above 0% the two are mixed. Both
  are 48 kHz stereo, so mixing is a sum of the two sample buffers with a gain on Draw Things'
  side, then a clamp, done in `ScoreFitter`. A rate or channel mismatch is converted with
  `AVAudioConverter` first, never assumed away. No slider when the clip is silent.
- **Filing and reuse:** every score is filed in a YuE2 project named **Tanque Studio scores**,
  one track per exported clip, each score a take on it (`POST /api/jobs` with `track_id`).
  **Use an existing score** lists that project's finished jobs
  (`GET /api/jobs?status=done&project=…`), so a score can go on another clip, or be re-cut at a
  new start time, without a new job. Tanque Studio keeps no score list of its own; the project
  id is cached in settings and looked up by name if it is missing. The scores also show as an
  album in YuE2's own UI.
- **Records:** for YuE2, the movie's metadata comment gets the YuE2 job id, seed, style, start time and
  Draw Things audio level, so a
  score can be found and re-cut later. The job and its song stay in YuE2's library;
  **Tanque Studio never deletes YuE2 jobs or songs.**

## What YuE2 can and can't do (facts that shape the design)

- **No duration parameter.** Section tags set the length, and songs come out far longer than a
  clip. Measured on this Mac (n = 1, 2026-09-30): the fast preset took 62.2 s to make 47.2 s of
  audio. A 5–10 s LTX clip therefore always gets an excerpt; the excerpt step is the feature,
  not a workaround.
- **The instrumental LoRA** makes songs of 3–5 minutes whatever the plan says, and wants untimed
  bare tags and cfg 1.5–3. None is installed here (`/api/loras` → `adapters: []`), so v1
  relies on tags-only lyrics and doesn't send LoRAs.
- **One job at a time.** A second submit queues (the job reports `position`). The UI shows the
  queue position rather than assuming it starts now.
- **Memory.** On this 16 GB Mac YuE2 runs low_memory with a 12 GiB budget. It shouldn't run
  alongside a local Draw Things render: big models already exhaust this Mac's memory on their own.
  Scoring happens after the clip exists, so the only clash is scoring while another render is
  going. v1 runs YuE2 on this Mac (Ned, 2026-11-04) and doesn't try to prevent the clash; the
  address setting allows moving YuE2 to the M4 Max later with no code change.
- **Errors** come back as `{"error": {"code", "message"}}`: 503 `engine_unavailable`
  (models missing or still loading), 409 `conflict`, and connection refused when the service
  is stopped. The message for the last one gives the start command:
  `launchctl kickstart gui/$(id -u)/com.tanque.yue2-studio`.
- **Licence.** YuE2's weights are CC BY-NC 4.0. The button's help text and the release notes
  say scores are for non-commercial use.

## Source 2: a TanqueLoops loop

TanqueLoops is Ned's 16-step, 7-track step sequencer (iOS first, with a macOS build), in the
private repo `skeptict/TanqueLoops`. Its `TanqueLoopsCore` package already has everything this
needs:
- the loop model (`LoopDocument`);
- lenient import of untrusted files (`LoopDocument.importing(_:)`);
- the kits;
- a pure-DSP offline renderer, `LoopRenderer.renderMono(document:source:muted:normalize:sampleRate:)`.

- **Getting loops in:** loops are shared as `<name>.tanque.json` files, over AirDrop or Files
  from the phone, or saved from TanqueLoops' Mac build.
  - **Import Loop…** (an open panel, or a drop onto the sheet) runs `importing`, then copies
    the file into `Application Support/TanqueStudio/Loops/`.
  - The sheet's loop menu lists that folder.
  - A file that won't parse is refused with its name. Bad fields fall back the way the core
    already handles them.
- **Choosing:** the loop menu, plus pattern or chain (`ExportSource.pattern` / `.chain`),
  shown with the loop's BPM and its length in bars and seconds.
- **Rendering:** `renderMono` at the export's rate (48 kHz) with `normalize: false`, then
  copied to both channels. No `AVAudioConverter` step is needed, because the renderer takes
  the rate.
- **Repeating to length:** one pass lasts `bars × 16 steps × (60 / bpm / 4)` seconds. The
  renderer starts notes 20 ms in and appends a 0.6 s decay tail. The fitter therefore adds
  each repeat into the buffer at multiples of the pass length (overlap-add), so the tail of
  one pass rings into the next instead of being cut. Normalization happens once, after
  repeating, because overlapping tails can raise the peak. The end gets the shared fade-out;
  the start needs no fade-in, because the loop starts on its own downbeat.
- **Start time** works as for YuE2, but is in whole bars, which are where a loop can sensibly
  begin.
- **Records:** the metadata comment carries the loop's name, BPM, kit, source, and the loop's
  own JSON. A loop file is a few kilobytes, so the movie alone is enough to re-render its
  soundtrack exactly.
- **Speed and safety:** the renderer is deterministic and fast. Its own tests use it as a
  fixture. It needs no network or server, and nothing in YuE2's memory or licence section
  applies to it.

**Packaging: a shared public package (Ned, 2026-11-04).** `TanqueLoopsCore` moves out of the
private app repo into its own **public** repo, `skeptict/TanqueLoopsCore`. Both apps depend on
it, so there is one copy of the loop model, kits and renderer, and new kits, schema bumps and
the Loopra beds reach Tanque Studio as a version bump.

That replaced an earlier plan, the same day, to copy 8 render files into Tanque Studio. Copying
was only the answer while TanqueLoops had to stay private. A core-only repo was chosen over
making the whole app repo public:
- SwiftPM needs `Package.swift` at the repo root, and the core sits two folders down in the
  app repo.
- The app repo also holds the design handoffs, `CLAUDE.md` and the TestFlight script. That
  script carries the App Store Connect key ID and team ID: identifiers, not secrets, and the
  `.p8` was never committed. None of that needs publishing.

- **Creating it:** `git subtree split --prefix=TanqueLoops/TanqueLoopsCore` from TanqueLoops'
  `main`. That keeps the core's 11 commits of history, including the sample-exact VoicePatch
  check. The result is pushed to the new public repo and tagged `1.0.0`. The split comes from
  `main`, not the checked-out `spike/loopra-ambient`, whose `LoopraAmbient` target becomes a
  second product when that spike lands.
- **Changes in the new repo:**
  - platforms lowered to `.macOS(.v14)`, keeping `.iOS("26.0")`. The whole package built at
    macOS 14 in a scratch copy (2026-11-04; build only, tests not run);
  - the SIL Open Font License files added for Atkinson Hyperlegible and IBM Plex Mono;
  - a README;
  - the MIT licence (Ned, 2026-11-04).
- **Status 2026-11-04:** published at <https://github.com/skeptict/TanqueLoopsCore>, public,
  MIT, tag `1.0.0` = `132c33d` (12 commits on `main`). It has 71 tests, all passing on macOS
  (this Mac runs macOS 27; nothing has run on macOS 14). `xcodebuild` for generic iOS
  succeeds, the README's example compiles and runs, and a fresh package pinned
  `exact: "1.0.0"` resolves from GitHub, builds and runs.
- **TanqueLoops app:** its local package reference is swapped for the repo URL. While both are
  being worked on, Xcode's local-checkout override stands in for the remote package. The app's
  own deployment target stays at 26. Its `TanqueLoopsCore` folder is removed from the app repo
  only once the app builds, tests pass and it runs on the phone against the URL.
- **Tanque Studio:** an `XCRemoteSwiftPackageReference` pinned to an exact version, as the
  Draw Things client is pinned. Bumping it is a deliberate commit that names what changed
  upstream.
- **What Tanque Studio uses:** only the loop model, the lenient import and `LoopRenderer`. The
  real-time `AudioEngine`, the design tokens and the fonts are linked but not called. If that
  ever matters, they can split into a second product.
- **Type names:** none of the core's types clash with Tanque Studio's today. The package has
  its own module either way.

## Settings

**Settings → Audio** (new section): YuE2 server address, default `http://127.0.0.1:8765`, with
a history menu like `llmHostHistory`, so it can point at the M4 Max if YuE2 is installed there.
Plus a **Test** button calling `GET /api/status` that reports engine state and
`models_present`. The app's existing `com.apple.security.network.client` entitlement covers
it, but a LAN address will trigger the Local Network privacy prompt the first time, as Draw
Things did.

## Contract

**New:**
- `YuE2Client.swift`: an `actor` that submits, streams events, polls, cancels and downloads.
  It has no UI, and an injectable `URLSession` so tests can stub it.
- `ScoreFitter.swift`: a pure function from FLAC data, clip duration, start time, fades, and
  optionally Draw Things' audio plus its level, to `VideoAssembler.Audio`.
- `ScoreClipSheet.swift`: the source picker. For YuE2: the style field, ✨, seed, start time
  with +5 s, Use an existing score, and progress. For Loop: Import Loop…, the loop menu,
  pattern or chain, and the start bar. Shared: the Draw Things audio slider, ▶ preview,
  Cancel and Use.
- `LoopScoreSource.swift`: loop import into `Loops/`, the listing, and render-and-repeat.
- In the new `skeptict/TanqueLoopsCore` repo: the macOS 14 floor, licences and README. In
  TanqueLoops: the switch to the URL dependency.
- `Resources/LLMOperations/08-clip-to-score-style.md`.
- Tests: `LoopScoreSourceTests`:
  - a repeated buffer's length matches the clip;
  - the tail overlap-adds rather than being cut;
  - a single pass matches `renderMono` sample for sample;
  - a malformed file is refused;
  - a loop round-trips through the metadata JSON.

  Also `ScoreFitterTests` (length, fades, short-song padding, 24-bit decode, mix at 0% equals
  replace, mix clamps, rate mismatch converted) and `YuE2ClientTests` (request body with
  `track_id`, project lookup by name, error decoding, SSE framing).

**Modified:**
- `GenerateViewModel.swift`: `runVideoExport` takes the fitted audio.
- `DTProjectBrowserViewModel.swift`: the same for clip export.
- `DashboardFocusPanels.swift` and the browser's export UI: the button.
- `AppSettings.swift`: three keys (all YuE2), `tanqueStudio.yue2BaseURL`, `tanqueStudio.yue2HostHistory`
  and `tanqueStudio.yue2ScoresProjectID`.
- The Settings view.
- `project.pbxproj`: an `XCRemoteSwiftPackageReference` for `skeptict/TanqueLoopsCore`, at an
  exact version.
- `Resources/Help/generate.md`.

**Not touched:**
- `VideoAssembler`: it already takes WAV data.
- The Draw Things client and `RenderAudio`.
- StoryFlow, the Render Queue and Story Studio, until later phases.

**Rollback:** revert. YuE2's library keeps any songs made in the meantime, which is harmless.

## Phases

Reordered in v1.1: the loop source needs no server, so the sheet, fitter and export are built
and verified against it first.

0. **Packaging and the loop source.**
   - Split out and publish `skeptict/TanqueLoopsCore` (done 2026-11-04, `1.0.0`).
   - Switch TanqueLoops to it and verify the app on the phone.
   - Add the package to Tanque Studio, then
   `LoopScoreSource` with its tests. Verified by rendering a real loop shared from the phone,
   repeated to a clip length, and *listening* to the WAV, so you hear any click at the seams.
1. **Focus Room with loops.** The sheet (source picker, Loop side), `ScoreFitter`, the Draw
   Things audio slider and the export. Verified by exporting a real LTX series with a loop at
   0% and at about 40% Draw Things audio and *listening* to both. A green build doesn't count
   here; the movie has to be opened and played.
2. **YuE2 source.** `YuE2Client` and Settings → Audio with Test, then the YuE2 side of the sheet.
   Verified live against the local server:
   - the scores project and a track created;
   - one tags-only job submitted as a take, streamed, downloaded and decoded, with the timing
     recorded (n = 1, said so);
   - confirmation that `AVAudioFile` reads YuE2's 24-bit FLAC (fallback `audio.mp3`);
   - an export *listened* to;
   - the same score put on a second clip through Use an existing score.
3. **DT Project Browser** clip export, both sources.
4. **Later, not scoped:**
   - **Clips timed to the music:** offer a frame count that makes a clip exactly N bars of
     the chosen loop (at 112 bpm a bar is 2.14 s, about 54 frames at LTX's 25 fps), snapped
     to a count the model accepts. Also Story Studio and StoryFlow cuts on bar lines.
   - Per-voice mutes for a loop (`renderMono` already takes `muted:`).
   - Loopra ambient beds, from the `spike/loopra-ambient` branch, once that spike lands.
   - A Story Studio soundtrack across scenes.
   - A waveform with a draggable clip-length window, if the start field proves annoying.
   - YuE2 on the M4 Max, and a guard against scoring during a local render.
   - Music-first video: a song's sections drive Render Queue prompts.

## Design constraints (from past bugs)

- **Audio files under the sandbox:** the downloaded FLAC goes to the app's own temp/container
  folder, never next to a user-chosen output. The sandbox has eaten a `.wav` on the render
  audio path three times.
- **Sample rate from the file:** read the rate and channel count from the decoded file, never
  assume them. The library's 16 kHz default once played LTX audio 3× too slow.
- **The progress view animates with `TimelineView`**, not `repeatForever`, which slid the
  Compose sheet.
- **The export says what it did:** "with YuE2 score (job …, 0:42–0:50)", "with loop dusk
  loop 04 (chain, 112 bpm, ×3.2)", "+ Draw Things audio at 40%", or "no audio", so a silent or wrong soundtrack is never found later in a player.
- **Cancel is honest:** cancelling the sheet cancels the YuE2 job. Closing the sheet without
  cancelling leaves the job running in YuE2 and says so.

## Decisions (Ned, 2026-11-04)

1. **Draw Things' audio:** a volume slider, 0% = replace, above 0% = mix. (My first draft
   claimed mixing needed a gain stage `VideoAssembler` lacks; it doesn't, since both tracks are
   48 kHz stereo and the mix is a sample sum in `ScoreFitter`.)
2. **Excerpt:** start-time field, +5 s nudge and ▶ preview. Waveform later if needed.
3. **Host:** this Mac for now; the address setting covers the M4 Max later.
4. **Reuse:** a YuE2 project, Tanque Studio scores, read back through YuE2's API. No
   Tanque-side score library.
5. **Packaging TanqueLoopsCore:** its own public repo, shared by both apps (not copied files,
   and not the whole TanqueLoops repo made public). Code licence: MIT.
