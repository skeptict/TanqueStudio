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

## Notes

Test suite: 529 passed, 8 skipped, 0 failures. New tests cover the Composer's prompt
assembly and its library files, the `/v1` address handling, and the model warnings.

**Not yet tried in the app:** the model warnings. They are covered by tests, but nobody has
yet run a render with a model missing from Draw Things' list to see the notices.
