# Tanque Studio 0.9.51 (draft)

**Build a prompt from parts.** Generate's new **Compose** button assembles a prompt from
sections such as subject, lighting and camera, as comma-separated tags or as sentences written
by your LLM. Also: the Style Browser can show a preview in Finder, and the LLM settings work
with Msty Nexus.

## Generate: Prompt Composer

**Compose** sits beside **Assist** in Generate's prompt section. It opens a sheet where you
build the prompt from sections instead of one text box.

- **Sections:** add them from **+ Add Section**: Subject, Character details, Wardrobe,
  Setting, Lighting, Color palette, Composition, Camera / lens, Art style, Mood, Rendering
  details, Negative, or Custom. Reorder them, switch them on and off, or remove them.
- **Library:** each section has a menu of ready-made phrases, and picking one adds it to that
  section. The menus are plain text files you can edit. They live in Tanque Studio's
  Application Support folder under `PromptFragments`, one file per section, one phrase per
  line.
- **Positive or negative:** a section marked negative goes into the negative prompt, never
  the positive one.
- **Tags or Prose:**
  - **Tags** joins the sections with commas, which suits SD 1.5 and SDXL.
  - **Prose** sends them to the LLM set in Settings, which writes them up as sentences for
    models that read whole descriptions, such as FLUX, Z Image, Qwen, Krea and video models.
    The draft can be edited. Change a section afterwards and the sheet tells you the draft is
    out of date until you press **Rewrite**.
  - **Auto** picks between the two from Generate's current model.
- **Apply** replaces Generate's prompt rather than adding to it. If the prompt holds text the
  Composer didn't write, Apply asks first. The negative prompt is only replaced when a
  negative section has something in it.
- **Model menu:** in Prose mode the sheet shows the same LLM model menu as Assist, and a
  choice in either place applies to both.
- **Your sections stay put:** they last until you quit, even if you close the sheet or leave
  Generate.

**Verified in the app:** against Msty Nexus with `qwen3.5:9b`, Write Prose drafted a paragraph
from a one-line subject in about 20 seconds, including loading the model. Editing the subject
raised the out-of-date warning, Rewrite redrafted from the new text in about 14 seconds and
cleared it, and Apply put the draft into Generate's prompt. Adding, reordering and removing
sections, the library menus, negative sections, Apply's confirmation and Clear All were checked
in October. **Not yet tried:** Auto and Tags with an SD 1.5 or SDXL model selected.

## LLM settings: Msty Nexus, and base URLs ending in /v1

Tanque Studio's LLM features (Assist, Compose, StoryFlow's enhance) work with
**Msty Nexus**, which serves local models to other apps and tracks their usage. In
**Settings → LLM Assist**, keep the provider on **Ollama**, set the address to
`http://127.0.0.1:3939`, and paste a token created in Msty Nexus into the key field, which now
reads **API key or token (Jan, Msty Nexus)**. Nexus doesn't start its engines by itself: if every
request fails at once with HTTP 502, start Ollama in the Msty Nexus app.

Separately, an address copied with the API version on the end, such as
`http://127.0.0.1:3939/v1`, used to make every request fail with HTTP 404, because Tanque
Studio added a second `/v1`. Both forms now work.

## Style Browser: Show in Finder

A style's detail view has a new **Show in Finder** button, which opens Finder with that
preview's PNG selected. The previews live in folders named by ID inside Tanque Studio's own
Application Support folder, so finding one by hand was hard.

This matters most for Draw Things. Each preview carries its prompt and settings in Draw
Things' own format, but dragging an image onto Draw Things' canvas brings in the image only.
Draw Things loads embedded settings only when you open the file with **Select From Files**.
Show in Finder gets you to the file: drag it from Finder into that panel to jump straight to
it. The detail view's tooltip used to promise that dragging carried the settings; it now
says what actually happens.

**Verified in the app:** on a rendered card, Show in Finder opened the set's `images` folder
with that style's PNG selected.

## Generate: Copy CLI Command

A new **Copy CLI Command** menu in Generate's Actions column copies a `draw-things-cli`
command carrying the current prompt, negative prompt, model and settings. Paste it into a
terminal to run the same generation without either app. The menu offers three places to run
it:

- **Through Draw Things' server** sends it to the Draw Things app's own server, addressed as
  `localhost`, so **paste it on the Draw Things Mac**. It can't reach Draw Things from another
  Mac: the CLI checks the server's certificate against the address it was given, and Draw
  Things' certificate names only `localhost`, so a LAN address fails with "Remote echo timed
  out." even when the server is running. From another Mac, an SSH tunnel works:
  `ssh -N -L 7859:127.0.0.1:7859 <draw-things-mac>`, then run the command as copied.
- **With local models** runs it on the Mac you paste it on, loading that Mac's Draw Things
  models itself, without the Draw Things app.
- **On Cloud Compute** runs it on Draw Things' cloud, from any Mac. Sign in once with
  `draw-things-cli auth login`.

The command reproduces what Generate would send. Dimensions are snapped to multiples of 64,
and with Randomize on, a seed is rolled into the command so the result can be repeated. The
CLI fills anything left unstated from the model's recommended settings, so the command spells
out the switches that are off, such as Hires Fix and tiling, and always passes the negative
prompt, even an empty one.

Images aren't included, because the CLI takes them as files: a source image, mask or
moodboard is listed in the button's tooltip so you can add `--image` yourself. You need a
recent `draw-things-cli`; the Homebrew formula is months behind, so get it from Draw Things'
[GitHub releases](https://github.com/drawthingsai/draw-things-community/releases).

**Verified in the app:** all three menu items copied a command naming the right backend, with
width 1000 snapped to 960 and an apostrophe in the prompt quoted correctly. With `--estimate`
added, the CLI parsed the command and priced it, but `--estimate` never connects to anything,
so that proves the command's syntax only. **Not yet tried:** a full render from a copied
command.

**Audio input runs locally only.** `draw-things-cli --audio`, which drives MiniMax H3 and
LongCat-Video-Avatar with a sound file, refuses `--remote` and `--cloud-compute` with "--audio
currently supports only local generation."

## Warnings when Draw Things may not have your model

Ask Draw Things for a model it can't provide and it doesn't refuse. It renders with a
different model and says nothing, and the result is saved labelled with the model you asked
for. Generate, inpainting and the Render Queue already warned about this. StoryFlow, Story
Studio and the Style Browser now do too.

- **StoryFlow** logs a warning the first time a run uses a model missing from Draw Things'
  list, and shows an orange notice above the results. A run that finishes with such a model
  ends "Completed" with the warning rather than "Run complete".
- **Story Studio** shows the same notice under the render progress.
- **The Style Browser** shows it under a set's render controls.

These are warnings, not refusals. Draw Things' list covers only the files on its own disk, and
Bridge Mode can still fetch a model that isn't there. If the list can't be read at all, nothing
is shown.

Also fixed: StoryFlow's warning about renders that came back empty used to carry over into
every later run, even ones where nothing went wrong.

## Fixed: the Style Browser sent video models as videos

The Style Browser renders stills and is meant to refuse video models, but it only knew
some of them. With MiniMax H3 selected, it sent a 328-frame video request for each
style, and Draw Things crashed while decoding the first one. Tanque Studio now recognises
every video model Draw Things ships: SkyReels, Stable Video Diffusion, ChronoEdit, MiniMax
and LongCat were all missing, which was 24 of Draw Things' 82 official video models plus
MiniMax and LongCat. A test now checks all of them.

The same check decides Generate's default frame count when none is set, and whether
Copy CLI Command names its output `.mp4`, so those models are handled correctly there too.

## Fixed: image models inherited a video frame count

Switching Generate from a video model to an image model kept the old frame count. Most image
models ignore it, but Krea 2 and Qwen Image decode through the same 3D decoder as Wan video,
so they don't. A Style Browser set on Krea 2 that had picked up MiniMax's 328 frames spent six
and a half minutes sampling a clip for its first style. That set also crashed Draw Things,
but the frames weren't the cause: see the tiled decoding note below.

- **Picking an image model** in Generate's model list now resets Frames to 0, the model's
  default. Moving between video models keeps your frame count.
- **Generate warns** in its Parameters section, in orange, when an image model holds more
  than one frame, which a pasted or loaded config can still bring in.
- **The Style Browser always asks for one frame**, whatever Generate held, including sets
  created before this fix.

## Known issue: Tiled Decoding crashes Draw Things on Krea 2

With **Tiled Decoding** on, Krea 2 almost always fails to decode, and on Draw Things
26.1020.0 it crashes the app. That applies whenever the tile is smaller than the image, so it
does not apply when the tile covers the whole picture. In Tanque Studio's request log, Krea 2
decoded 546 of 703 renders with tiling off, but with tiling engaged it decoded only with
full-width 1920×704 tiles (25 of 27). Draw Things' default 640 px tile went 0 for 11, and a
256 px tile left over from a MiniMax H3 config went 0 for 4. Every one of today's crashes
stopped in the same place in Draw Things' Wan decoder. The same Krea 2 settings with only
Tiled Decoding switched off rendered normally.

Turn Tiled Decoding off for Krea 2. A still doesn't need it: Draw Things decodes stills of any
practical size in one piece. Tanque Studio now warns, in orange, whenever Krea 2 would be sent
tiles smaller than the image, but it still sends what you set:

- **Generate** shows the warning under **Tiling**, and again when you press Generate, since
  the Tiling section is usually collapsed.
- **The Style Browser** shows it on a set that has tiling on, and in the New Set panel before
  you create one. A set's settings are fixed, so the fix is to turn tiling off in Generate
  and use **New from this set**. Its **Changes** line now lists tiled decoding, so that set
  isn't reported as a repeat of the old one.
- **The Render Queue** lists it with the notices above **Expand** when any job it would
  create sends Krea 2 with tiling, including Krea reached through a model axis. It's listed
  once, however many jobs are affected.
- **StoryFlow and Story Studio** log it at the first such render in a run, show it as a
  notice beside the results, and end the run "Completed" with the warning rather than "Run
  complete". There the fix is `"tiledDecoding": false` in the config.

Qwen Image uses the same decoder but hasn't been tested, so it gets no warning.

## Notes

Test suite: 555 passed, 8 skipped, 0 failures. New tests cover the Composer's prompt assembly and its library files,
the `/v1` address handling, the model warnings, the CLI command, every official video model,
the Style Browser's one-frame request, the frame reset when picking a model, and the Krea 2 tiling warning in Generate, the Style Browser, the Render Queue and StoryFlow configs.

**Not yet tried in the app:** the model warnings. They are covered by tests, but nobody has
yet run a render with a model missing from Draw Things' list to see the notices.
