# Tanque Studio 0.9.45

A small release: one button that looked like it worked and didn't, and the
removal of a dead file that had been quietly collecting edits nobody could see.

## "Send to Generate" now actually sends to Generate

Story Studio's **Send to Generate** wrote a scene's config, prompt and rendered
image into a Generate session that **nothing was displaying**, then navigated
nowhere. Every visible sign said it had worked — no error, no warning, the button
depressed like any other. The Focus Room simply still held whatever it held
before.

The cause was a placeholder from when Labs was a spike tab: it handed Story Studio
a throwaway view model and an empty navigation closure, because at the time Labs
had no Generate destination to reach. Labs is now one of five first-class modes,
and the comment explaining the workaround had outlived the thing it explained.

Labs now receives the app's real Generate session and the mode switch, and passes
both to Story Studio — the same wiring the DT Project Browser one line above it
had all along.

Verified end to end on a real render: rendered a Story Studio scene, pressed Send
to Generate, and the app moved to the Focus Room with the scene's prompt and
negative prompt in the panel and its render loaded as the img2img source.

## Removal of a dead editor

`GenerateLeftPanel.swift` — 1,237 lines — was unreachable from any navigation
path. The live editor is `DashboardFocusPanels.swift`. Two files had drifted apart
over several releases while only one of them was running, which is exactly the
condition where a fix gets applied to the wrong copy and appears not to work.

The one piece still doing real work, the saved-config picker sheet, was lifted out
into `ConfigPickerSheet.swift` unchanged and is now the only caller of
`DTConfigImporter.loadBuiltIn()`.

Nothing about this changes what the app does. It changes which file you edit when
you want to change the Focus Room.

## Notes

The release checklist's stale-version check now uses `grep -F`. Without it, `.` in
a version string is a regex wildcard, and cutting 0.9.43 the check reported a
phantom stale version by matching a substring of a dependency's commit hash.

## Known gap, unchanged in this release

**Video rendered by Tanque Studio has no audio.** LTX 2.3 generates an audio track
and Draw Things sends it; the app never asks for it, so it is discarded before the
`.mp4` is assembled. This affects Generate's Export Movie, the Render Queue and
StoryFlow.

Movies exported from the **DT Project Browser** do carry audio, because that path
reads the track out of Draw Things' own database rather than from a live render.
The `.mp4` writer has supported an audio track since 0.9.34 — it is the generation
side that has never captured one. Not a regression; it has never worked, and it is
now written down.
