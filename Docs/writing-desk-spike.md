# Writing Desk spike

Labs → Writing Desk. A 3D den where you type on a steampunk machine, built to answer one question: is writing this way any good? It is a spike, not a feature.

Status on 2026-11-11: it works end to end and has been driven in the running app. Branch `spike/writing-desk`.

## What was built

The camera sits at a dark wood desk. On the desk is a brass and copper machine with six meshed gears, five glowing bulbs, three breakers, copper wiring, a keyboard and a glass screen. Typing appears on the screen in amber IBM Plex Mono. The left wall is bookshelves; the far wall is a two-storey window onto a painted valley.

- **Close things are modelled, far things are painted.** The desk, machine, lamp and lower shelves are RealityKit geometry built in code, with no downloaded models. The city and the upper shelves are images on planes.
- **macOS 15 and later.** `RealityView` needs macOS 15, so the tab is hidden on macOS 14. The app's deployment target is still 14.0.
- **One existing file changed:** `Dashboard/DashboardLabsPage.swift` gains the tab. Everything else is in `DrawThingsStudio/WritingDesk/` (10 files, about 1,840 lines). No SwiftData changes and no Story Studio wiring.

| File | What it holds |
|---|---|
| `WritingDeskView.swift` | The tab, toolbar, status line, key handling and the fps readout |
| `WritingDeskSession.swift` | The draft (shared, so it survives leaving the tab), save, new sheet, reveal |
| `DenScene.swift` | Room, desk, lamp, shelves, windows, backdrops, lights, camera |
| `SteamComputer.swift` | The machine, its materials and its per-frame animation |
| `ScreenTextRenderer.swift` | 48×16 word wrap and the amber screen image |
| `BackdropLoader.swift` | Loads `city.png` and `shelves.png`; paints stand-ins and the light environment |
| `MeshBuilder.swift`, `GearMesh.swift`, `TubeMesh.swift` | Low-poly shapes, gears, wires |
| `DeskSounds.swift` | Generated key click, gear tick and breaker clunk |

### Using it

- **Type** with the desk focused. Return starts a new line and throws a breaker. The screen shows the last 16 lines.
- **Save** writes `sheet-yyyy-MM-dd-HHmmss.md`; saving again updates the same file. **New sheet** asks first if there is unsaved writing.
- **Backdrops** go in the app's sandbox container, because the app is sandboxed:
  `~/Library/Containers/tanque.org.TanqueStudio/Data/Library/Application Support/TanqueStudio/WritingDesk/Backdrops/`
  Use the **Backdrops folder** button to open it, drop in `city.png` (about 21:9) and `shelves.png` (about 2:3), then press **Reload backdrops**. Saved sheets are one folder up.
- **Look around: on** turns your head with the pointer. Off, the pointer only shifts your head a few centimetres.

## What was checked in the running app

All of this was driven in a Debug build on an M1 Pro with a 120 Hz display.

| Check | Result |
|---|---|
| Typing | Works. Text is the right way up, wraps at 48 columns, scrolls past 16 lines; Backspace, Return and shifted characters work |
| Save | Wrote a 17-byte file for a 16-character sheet; the status line names the file |
| New sheet | Clean sheet: clears at once. Unsaved text: dialog appears. Cancel keeps the text, "Save, then new sheet" wrote a second file, "Discard this sheet" wrote none |
| Reveal in Finder | Finder opened the sheets folder with the saved file selected |
| Backdrops folder | Finder opened the Backdrops folder inside the container |
| Reload backdrops | Pressed with both images present; both stayed loaded |
| Look around | Pointer left shows the book wall, right the side wall, up the top of the windows |
| Sound button | Toggles between on and off; the audio engine started without error |
| Backdrops | `city.png` and `shelves.png` loaded from the real app's container |

Not checked:

- **Whether the sounds are audible or pleasant.** Nobody listened. The gear tick plays continuously while sound is on.
- **macOS 14.** The tab is hidden there in code only; no macOS 14 machine was tried.
- **A second display or a 60 Hz display.**

## What was found and fixed

### It was far too dark

The brass read as black and the lamp lit almost nothing. Each cause was tested alone:

| Change, alone | Effect |
|---|---|
| Light environment replaced by flat mid-grey | Everything lit properly: brass looked like brass, books had colour |
| Desk lamp ×10 | A larger pool of light on the desk, nothing else |
| Machine bulbs ×10 | The gear plate lit up |
| Window light removed | No visible change |

So the image-based light was working all along. Its source image was nearly black, and metal is lit almost entirely by what it reflects. The earlier attempt raised the lights and the image-based light's strength, which could not help: doubling near-black is still near-black.

Fixes: a brighter, warm environment image with soft-edged window and lamp areas; the lamp raised from 6,000 to 60,000 and the bulbs from 900 to 9,000; and less varnish on the wood (clearcoat 0.6 → 0.15, roughness 0.42 → 0.6) so the desk reads as wood, not as a mirror for the sky.

### The frame rate was lower than it said

The old readout averaged 1/dt, which reads high. A counter of whole frames per second replaced it, and also shows the slowest frame.

| Build | Frames per second (app in front) |
|---|---|
| New filament material every frame (as found) | 62–65 |
| Filament materials left alone | 98–110 |
| Final build | 100–115, slowest frame 17–19 ms |

The suspect was right: building a new material for each of the five filaments every frame cost about 5 ms a frame. The filaments now flicker by changing size, and the bulb light still flickers.

Two things to know when reading the number:

- **In the background the app is throttled** to about 40 fps. Measure with it in front.
- **Frames of 60–70 ms happen** when a dialog opens and now and then while typing. The screen image is redrawn on every keystroke; that was not measured on its own.

## What looked good and what did not

Good:

- With real backdrops the valley through the mullions sells the room. This is the best part.
- The lit gears and bulbs behind the screen, and the lamp's pool of light on the desk.
- Head parallax while seated.

Not good:

- **The type is small.** 48 columns on a screen that fills a fifth of the view is readable but not comfortable for long writing. A closer camera, fewer columns or a "lean in" key would help.
- **The city image has a hard top edge.** Look up and it ends in a curved line against a flat mauve sky, because the painted sky and the generated sky do not match.
- **The room's light does not match the backdrop.** The reflections are mauve from the stand-in dusk, while the real city image is green and gold. The desk and floor pick up a purple cast.
- **The upper shelves do not match the lower ones.** A photographic painting sits above flat-coloured box books, and the painted lampshades float.
- **The right-hand wall is blank,** and the upper bookshelf is black until `shelves.png` is present.
- **The lamp shade reads as near-black,** not banker's green.
- **After "Save, then new sheet" the status line says only "New sheet",** so the saved file's name is never shown.
- **The window light does nothing visible** and could be removed.

## Suggested next steps

1. **Decide whether it is worth continuing.** Write a real page at the desk first. Everything below is only worth doing if that is pleasant.
2. **Make the type bigger:** move the camera in, or zoom to the screen while typing.
3. **Light the room from the backdrop:** build the environment image from `city.png` so the reflections match, and extend or fade the top of the city image into the sky.
4. **A looping waterfall** with `VideoMaterial` over that part of the city image.
5. **A proper machine model.** The coded one is a placeholder; a modelled one needs its licence checked.
6. **Steam or dust particles** in the lamp light.
7. **Real sound samples** in place of the generated tones, and a quieter or optional gear tick.
8. **Story Studio "Send to scene":** write the sheet into `StoryScene.narratorText` or `sceneDescription`. Neither needs a schema change.
9. **Editing:** there is no cursor movement, selection or paste. Typing and Backspace only.

## Rolling it back

Delete `DrawThingsStudio/WritingDesk/` and `Docs/writing-desk-spike.md`, then run `git checkout DrawThingsStudio/Dashboard/DashboardLabsPage.swift`.
