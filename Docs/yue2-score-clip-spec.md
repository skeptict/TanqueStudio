# Score this clip (YuE2) — spec (v1)

Agreed 2026-11-04 (decisions at the end). Origin: after 0.9.51 Ned asked about audio features, perhaps using YuE2 Studio, the local
song generator that already runs on this Mac. Of the options discussed, scoring a finished clip
needs the least new plumbing, because every movie export already muxes a soundtrack.

## What it is

When a movie is exported, Tanque Studio can ask YuE2 Studio for an instrumental, cut it to the
clip's length, and put it in the movie as the soundtrack.

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
- **Records:** the movie's metadata comment gets the YuE2 job id, seed, style, start time and
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
- `ScoreClipSheet.swift`: style field, ✨, seed, start time with +5 s, ▶ preview, Draw Things
  audio slider, Use an existing score, progress, Cancel and Use.
- `Resources/LLMOperations/08-clip-to-score-style.md`.
- Tests: `ScoreFitterTests` (length, fades, short-song padding, 24-bit decode, mix at 0% equals
  replace, mix clamps, rate mismatch converted) and `YuE2ClientTests` (request body with
  `track_id`, project lookup by name, error decoding, SSE framing).

**Modified:**
- `GenerateViewModel.swift`: `runVideoExport` takes the fitted audio.
- `DTProjectBrowserViewModel.swift`: the same for clip export.
- `DashboardFocusPanels.swift` and the browser's export UI: the button.
- `AppSettings.swift`: three keys, `tanqueStudio.yue2BaseURL`, `tanqueStudio.yue2HostHistory`
  and `tanqueStudio.yue2ScoresProjectID`.
- The Settings view.
- `project.pbxproj`.
- `Resources/Help/generate.md`.

**Not touched:**
- `VideoAssembler`: it already takes WAV data.
- The Draw Things client and `RenderAudio`.
- StoryFlow, the Render Queue and Story Studio, until later phases.

**Rollback:** revert. YuE2's library keeps any songs made in the meantime, which is harmless.

## Phases

0. **Client and settings.** `YuE2Client` and Settings → Audio with Test. Verified live against
   the local server: the scores project and a track created, one tags-only job submitted as a
   take, streamed, downloaded and decoded, with the timing recorded (n = 1, said so). Also confirms that `AVAudioFile` reads YuE2's 24-bit
   FLAC. If it doesn't, the fallback is `audio.mp3`, which YuE2 transcodes on request.
1. **Focus Room.** The sheet, the excerpt, the mix and the export, verified by exporting a real
   LTX series with sound at 0% and at about 40% and *listening* to both, then putting the same
   score on a second clip through Use an existing score. A green build doesn't count here; the movie has to be opened
   and played.
2. **DT Project Browser** clip export.
3. **Later, not scoped:**
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
- **The export says what it did:** "with YuE2 score (job …, 0:42–0:50)", "with Draw Things
  audio" or "no audio", so a silent or wrong soundtrack is never found later in a player.
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
