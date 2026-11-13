# Writing Desk spike

Labs → Writing Desk. A 3D den where you type on a steampunk machine, built to answer one question: is writing this way any good? It is a spike, not a feature.

Status on 2026-11-11: it works end to end and has been driven in the running app. Branch `spike/writing-desk`. Focus zoom and the painted look were added the same day and are described in their own section below.

## What was built

The camera sits at a dark wood desk. On the desk is a brass and copper machine with six meshed gears, five glowing bulbs, three breakers, copper wiring, a keyboard and a glass screen. Typing appears on the screen in amber IBM Plex Mono. The left wall is bookshelves; the far wall is a two-storey window onto a painted valley.

- **Close things are modelled, far things are painted.** The desk, machine, lamp and lower shelves are RealityKit geometry built in code, with no downloaded models. The city and the upper shelves are images on planes.
- **macOS 15 and later.** `RealityView` needs macOS 15, so the tab is hidden on macOS 14. The app's deployment target is still 14.0.
- **One existing file changed:** `Dashboard/DashboardLabsPage.swift` gains the tab. Everything else is in `DrawThingsStudio/WritingDesk/` (12 files, about 2,500 lines). No SwiftData changes and no Story Studio wiring.

| File | What it holds |
|---|---|
| `WritingDeskView.swift` | The tab, toolbar, status line, key handling and the fps readout |
| `WritingDeskSession.swift` | The draft (shared, so it survives leaving the tab), save, new sheet, reveal |
| `DenScene.swift` | Room, desk, lamp, shelves, windows, backdrops, lights, camera |
| `SteamComputer.swift` | The machine, its materials and its per-frame animation |
| `ScreenTextRenderer.swift` | 48×16 word wrap and the amber screen image |
| `BackdropLoader.swift` | Loads `city.png` and `shelves.png`; paints stand-ins and the light environment |
| `MeshBuilder.swift`, `GearMesh.swift`, `TubeMesh.swift` | Low-poly shapes, gears, wires |
| `MachineFittings.swift` | Pulsing tubes, wires that heat and cool, gauges, pipes and rivets |
| `PaintedLook.swift` | The oil-paint filter applied to each finished frame |
| `DeskSounds.swift` | Generated key click, gear tick and breaker clunk |

### Using it

- **Type** with the desk focused. Return starts a new line and throws a breaker. The screen shows the last 16 lines.
- **Save** writes `sheet-yyyy-MM-dd-HHmmss.md`; saving again updates the same file. **New sheet** asks first if there is unsaved writing.
- **Backdrops** go in the app's sandbox container, because the app is sandboxed:
  `~/Library/Containers/tanque.org.TanqueStudio/Data/Library/Application Support/TanqueStudio/WritingDesk/Backdrops/`
  Use the **Backdrops folder** button to open it, drop in `city.png` (about 21:9) and `shelves.png` (about 2:3), then press **Reload backdrops**. Saved sheets are one folder up.
- **Esc**, or the **Focus** button, zooms in on the screen and back out.
- **Painted** steps through fine, bold and off (macOS 26 and later).
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

### Delete did nothing

Found on 2026-11-12. The Delete key arrives as U+007F, and the handler matched only SwiftUI's `.delete`, which is U+0008, so the press was dropped. It failed zoomed in and zoomed out alike. The handler now accepts both. Checked in the running app in both views.

The first pass recorded Backspace as working. That check was made a day earlier on the same machine and was not re-run after later changes; why it passed then is not known.

## Focus zoom and the painted look

Both were added after the first pass, and both were driven in the running app with the real backdrops.

### Focus zoom

Esc, or the Focus button, glides the camera in until the screen fills 84% of the view's height. The type becomes about four times larger, with gears, breakers and a strip of window left at the edges. Esc glides back. The glide takes 0.9 seconds and eases in and out.

It is built to be reused. `DenScene.focus(on:)` takes a `Viewpoint` (where the camera sits and what it looks at), and `nil` returns to the seat. `viewpoint(facing:size:)` makes one for any flat thing in the room, so a future feature can zoom into a book, a painting or the window by describing where it is. Head parallax is damped while focused, and Look around is suspended.

The screen image was raised from 1152×832 to 1728×1248 so the enlarged type is sharper.

### Painted look

Each finished frame is repainted before it is shown. The filter picks, for every pixel, the calmest of four neighbouring patches and uses its average colour (a Kuwahara filter), with the patches stretched along edges so dabs follow forms. It then adds uneven paint, a little canvas texture and richer colour. The glass screen is left unpainted so the type stays sharp.

- **It needs macOS 26 or later.** That is when `RealityView` gained custom post-processing. On macOS 15 to 25 the room is shown unpainted and the button is hidden.
- **Fine** is the default. **Bold** uses larger dabs and loses the machine's detail.
- **Frame rate is unchanged:** 110–120 fps with the filter on, on the same machine.
- **If the shader fails to build, the status line says so.** The first version failed silently and showed the unpainted room, which looked like a filter that was too subtle.

Checked: Esc and the Focus button both zoom in and out; typing works while focused (99 fps during a burst, slowest frame 36 ms); the paint setting cycles through all three; the screen stays sharp in every case.

Not checked:

- **Whether the paint shimmers in motion.** Only still frames were looked at. The gears, the flickering bulbs and Look around are the places to watch.
- **Resizing the window while focused.**
- **macOS 15 to 25,** where the filter is switched off in code only.

## More detail on the machine

Added after the painted look, and checked in the running app:

- **Three glass tubes** to the right of the keyboard (amber, aqua, ember). Each swells and fades at its own pace, over 5.5 to 9.5 seconds.
- **A copper feed wire to each tube** that glows near the top of the tube's swell and cools as it fades.
- **The older wires heat up too.** A breaker's wire runs hot when Return throws it and cools over a few seconds. The bulb wiring and the wing wire warm with typing.
- **Two pressure gauges** to the left of the keyboard. One needle rises with typing; the other follows the hottest wire and the brightest tube.
- **Pipework, about 60 rivets and two more meshed gears** (eight in all).

The glow uses a run of 20 ready-made materials from cold to lit, and an object is given a new one only when its level moves to the next step. That keeps the lesson from the filaments: no materials are built per frame. The scene is now 82,566 triangles and still runs at 119 fps.

Weak points: the gauges sit low and their needles are hard to read from the seat; the glowing columns in the tubes read as flat bars; nothing here casts light on its surroundings, because only the lamp and the bulbs are real lights.

## Chiaroscuro light

A **Light** button switches between two moods; chiaroscuro is the default.

- **Chiaroscuro:** one warm spotlight high to the writer's left lights the machine and casts real shadows across the desk. The room's ambient light is cut hard, the city and painted shelves are dimmed so they sit back in the dark, and the corners of the picture fall into shadow.
- **Dusk:** the even light the room began with.
- **The tubes now light what is beside them,** through one small light whose colour follows whichever tubes are brightest.
- **The window light was removed.** It never had a visible effect. There are four lights: key, desk lamp, bulbs, tubes.
- **The glass skin over the screen was thinned,** because under the key light it fogged the type.

Checked in the running app: both moods, switching between them, zoom while in chiaroscuro, 112–120 fps. Not checked: either mood with the paint filter off, and anything in motion.

The keys and gauge faces first ran close to white under the key light. The ivory is now a darker, rougher aged bone (0.86/0.80/0.66 → 0.60/0.53/0.40, roughness 0.38 → 0.55), checked from the seat in chiaroscuro only.

The key light now has a source: a brass floor lamp behind the writer's left shoulder, its copper shade turned on the machine. It is out of frame from the seat, as the light is in most Rembrandts, and in view with Look around on and the pointer to the left. Its face glows in chiaroscuro and is dark in dusk. The shade is marked as casting no shadow, because the light sits inside it; the light on the desk is unchanged.

Weak points: the bookshelves almost vanish; the floor lamp's shade is cut off by the top of the view when looking left; the brass deck has a small white highlight at its front right corner; the gauge needles are still hard to read.

## Surface textures and bevels

Added on 2026-11-12 and checked in the running app: seat and zoomed views in chiaroscuro, paint on and off.

- **Textures made in code** (`SurfaceTextures.swift`): one tiling 512-pixel pair each for metal, wood and ivory. Each pair is a colour image that multiplies the material's tint and a roughness image. Metal has brushing, tarnish patches, pitting and scratches; wood has grain bands, fibre and pores; ivory has yellowing and hairlines. Brass, copper, bronze and iron share the metal pair and differ by tint.
- **Texture scale follows size.** A part built without texture coordinates gets them laid on flat from whichever way each face points, at 0.22 m a repeat (0.33 m for boxes, 0.9 m for the desk and shelf frame), so a rivet and the case show the same grain size.
- **The gears show radial streaks.** Their faces carry one texture repeat per tooth wedge, which reads as a turned finish. It was not planned; it looks right, so it stays.
- **Rounded edges:** the case, plinth, straps, back plate, wing, screen bezel, breaker plate, keyboard base, space bar, desk top and pedestals, all through one light `roundedBox`.
- **Keys are now typewriter keys:** a brass cup with a rolled rim and a dished ivory button set into it.
- **Frame rate:** 106 fps from the seat and 112 zoomed, against 112 to 120 before. The scene is 55,630 triangles, down from 83,222.

What went wrong on the way: RealityKit's own rounded box is very dense. Using it for ten parts took the scene to 250,262 triangles and 96 fps. The code-built box does the same job in about 130 triangles.

Not checked: the dusk mood, the first-open pause (painting the textures took about 2.5 seconds in an unoptimised test, on the main thread), and anything in motion.

Weak points: through the paint filter the tarnish patches turn into strong blotches on the back plate; the keys and gauge faces are bright again under the key light; there are no bump (normal) maps, because the code-built meshes have no tangents.

An off-screen renderer was used while the Mac's screen was locked: a standalone program that compiles the scene files with `RealityRenderer` and writes a PNG. Its images had black dashes that the app does not show.

## Contact shade, softer tarnish, darker ivory

Three small fixes to weak points from the textures pass.

- **Pools of shade** sit under the machine's plinth, under its body and keyboard where they stand on the plinth, and under the desk lamp. Each is a flat see-through quad with a soft dark edge painted in code (`SurfaceTextures.contactShadow`). The key light's real shadows only exist in chiaroscuro, so in dusk nothing was grounded before.
- **Tarnish is softer.** The patches fade over a wider band and darken the metal less, because the paint filter turned the old hard-edged patches into blotches.
- **Ivory is darker and duller** (0.50, 0.44, 0.32), so keys and gauge faces sit further from white under the key light.

Checked in the running app on 2026-11-12: seat view in chiaroscuro and dusk, zoomed in at dusk, paint on fine. 111 to 120 fps, 55,638 triangles. Not checked: paint off, anything in motion, and how long the first open pauses while the textures are painted.

## Reflections from the city painting

The image the room is lit by used to paint its windows as a mauve and orange stand-in, so the desk and floor took a purple cast that the real view does not have. It now draws a heavy blur of `city.png` there (`BackdropLoader.reflections(city:)`), with the blur's brightness evened to the old level so a bright or dark painting does not change the exposure. Reload backdrops rebuilds it. With no `city.png` the stand-in is used as before.

Checked in the running app on 2026-11-13, seat view, paint on fine, 116 fps: the purple cast is gone in both moods and the desk reads as neutral wood. Chiaroscuro is a little darker overall, and the bookshelves, already faint there, are fainter. Not checked: Reload backdrops with a different painting, and the no-file stand-in.

## Daylight, a darker machine, desk props

Ned supplied two reference images on 2026-11-13: a daylit study with a dark, worn bronze machine, open gears on a black panel, filament bulbs and a lived-in desk. He wants that level of detail, tone and technology, not a copy. This is the first step toward it.

- **Daylight mood.** The Light button now cycles chiaroscuro, dusk, daylight. Daylight is a far, narrow spot through the windows from high on the right, with shadows, plus a brighter room light and a dimmer desk lamp. The glass and the painted backdrops no longer cast shadows, so they do not block it.
- **Darker machine.** The casing and keyboard base are a new dark bronze. Brass and copper are less orange and kept for gears, bezel, straps and trim. The gear plate and wing are near-black, and the plate sits inside a raised frame so the gears work in a recess. The rivets moved onto the frame.
- **Spoked gears.** Gears of 12 teeth and up are a rim, a hub and five arms (`GearMesh.add(spokes:)`).
- **Filament bulbs.** A socket and screw cap, pear-shaped glass, a looped glowing wire on two posts, and a faint bloom that swells with the flicker. The bulbs' light is half as strong and less orange, so it no longer floods the gears.
- **Props.** Two stacked books, a notebook with a pen, and a cup of pens, each with a pool of shade.

Checked in the running app on 2026-11-13, paint on fine, 60,940 triangles: chiaroscuro at the seat (102 fps), dusk at the seat (120), daylight at the seat (117) and zoomed in (118). Readings taken while the app was behind another window showed 64 to 69 fps; that is background throttling, not the scene.

Weak points: the notebook reads as a plain cream slab; the filament wire is too fine to see from the seat, so the bulbs still read as glowing blobs; the city painting is a dusk scene, so in daylight the room is brighter than the view; the machine is still the same boxy shape. Not checked: paint off, Look around in daylight, anything in motion.

## Painted room (experiment)

The **Room** button swaps the built room for one painting, `room.png` in the backdrops folder. The desk, its props and the machine stay 3D and are lit as before; the walls, floor, shelves, windows, view and floor lamp are hidden. With no `room.png` the built room stays and the status line says what to add.

- The painting stands upright 9 m ahead of the seat with its eye-level line at eye height. `plateHorizon` in `DenScene` says how far up the image that line is (0.5 now); change it if a painting's horizon sits elsewhere.
- It is a quarter larger than the view needs, so leaning and the focus zoom never show its edge. Compose the image with that margin: the outer eighth on each side is rarely seen, and the lower half is behind the desk.
- Look around turns only about 3.5° in the painted room, because a painting has edges.
- The brass reflects a blur of the painting in place of the city, and the painting is dimmed to 0.35 in chiaroscuro and 0.7 in dusk.

A prompt to start from, about 2.4:1 (for example 2048×832), lit to suit the daylight mood:

> Interior of a Victorian steampunk study in soft daylight, wide straight-on view at seated eye level toward a wall of tall riveted iron-framed windows. Beyond the glass, a retro-futurist city in a steep jungle valley with a waterfall in haze. Dark walnut bookshelves packed with leather books on the left wall, brass pipes, potted ferns, a worn leather armchair, wood floor. Empty foreground, no desk, no people. Level camera, horizon at mid-height, photographic detail.

Tried with three paintings rendered from that prompt (Krea 2 Turbo, 2048×832, about 100 s each on the M4), in an off-screen render from the seat in all three moods and zoomed. The room reads as a photograph and the desk sits in it believably; the chair and ferns are cut off by the desk as real ones would be. The sun is cut to under half in the painted room, because with no window bars in its way it bleached the desk. The 3D machine and desk now look plainer than the room behind them.

Not yet seen in the app: a file cannot be copied into the app's folder from outside, so only the button and the missing-file message were checked there. The paint filter over a painting, frame rate, and how the painting holds up while leaning are unknown.

## What looked good and what did not

Good:

- With real backdrops the valley through the mullions sells the room. This is the best part.
- The lit gears and bulbs behind the screen, and the lamp's pool of light on the desk.
- Head parallax while seated.

Not good:

- **The type is small when seated.** Focus zoom fixes this for writing; seated, 48 columns on a screen that fills a fifth of the view is readable but not comfortable.
- **The enlarged type is slightly soft,** from the phosphor glow more than from resolution.
- **The modelled parts paint less well than the backdrop.** Flat-coloured books and walls give the filter little to work with, so they still read as computer shapes with soft edges. Textured materials would help more than a stronger filter.
- **The city image has a hard top edge.** Look up and it ends in a curved line against a flat mauve sky, because the painted sky and the generated sky do not match.
- **The upper shelves do not match the lower ones.** A photographic painting sits above flat-coloured box books, and the painted lampshades float.
- **The right-hand wall is blank,** and the upper bookshelf is black until `shelves.png` is present.
- **The lamp shade reads as near-black,** not banker's green.
- **After "Save, then new sheet" the status line says only "New sheet",** so the saved file's name is never shown.
- **The window light does nothing visible** and could be removed.

## Suggested next steps

1. **Decide whether it is worth continuing.** Write a real page at the desk first. Everything below is only worth doing if that is pleasant.
2. **Use the focus mechanism for something else:** zoom to the window for the view, or to a shelf to pick a saved sheet.
3. **Light the room from the backdrop:** build the environment image from `city.png` so the reflections match, and extend or fade the top of the city image into the sky.
4. **A looping waterfall** with `VideoMaterial` over that part of the city image.
5. **A proper machine model.** The coded one is a placeholder; a modelled one needs its licence checked.
6. **Steam or dust particles** in the lamp light.
7. **Real sound samples** in place of the generated tones, and a quieter or optional gear tick.
8. **Story Studio "Send to scene":** write the sheet into `StoryScene.narratorText` or `sceneDescription`. Neither needs a schema change.
9. **Editing:** there is no cursor movement, selection or paste. Typing and Backspace only.

## Rolling it back

Delete `DrawThingsStudio/WritingDesk/` and `Docs/writing-desk-spike.md`, then run `git checkout DrawThingsStudio/Dashboard/DashboardLabsPage.swift`.
