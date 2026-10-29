# Tanque Studio 0.9.49

**Your subject, in 414 styles.** A new **Style Browser** in Labs renders one subject of
your choosing across a library of 414 art-style prompts, and lays the results out as a
grid you can browse, compare and send to Generate. Also: screens now move as you switch
between them, with a choice of transition in Settings, and a batch of buttons that only
responded on their text now respond across their whole frame.

## Style Browser (Labs)

Type a subject — *"a lighthouse on a rocky headland at dusk"* — and render it in any of
414 styles across ten traditions: Photography, 3D Render, Anime, Painting, Drawing,
Comics, Cover Art, Cartoon, Digital Painting and Design. Render one card, a filtered
section, or the whole library.

- **A set is one subject, rendered with one model, one set of settings and one seed.**
  The settings are a snapshot of Generate's at the moment you create the set, and the
  seed is shared by every style — so the previews differ only in style, and can be
  compared side by side. A new subject or new settings is a new set; old sets stay in
  the menu.
- **Describe the subject only.** Leave out "photo of" or "oil painting of" — every style
  brings its own medium, and a medium in the subject fights all 414 of them.
- **Search, filter by tradition, or show only what's rendered.** Click an unrendered card
  to render just that style.
- **Render visible** renders every unrendered style in the current filter. Above 50 it
  asks first, with a time estimate from the renders so far. **Pause** finishes the style
  in flight and stops; **Resume** carries on; **Cancel** stops now. A style that fails
  never stops the rest — it shows its error and is retried on the next run.
- **A batch keeps running when you leave Labs**, and its controls are still there when
  you come back.
- **Open a rendered card** for the full image and the style's prose: **Copy style**,
  **Copy prompt**, **Re-render**, and **Send to Generate**, which carries the prompt,
  model, size and seed to the Focus Room so you can reproduce or develop that preview.
  Drag the image out to get the PNG, with its prompt and settings embedded.
- **Previews never touch your gallery.** They live in Tanque Studio's own folder, not
  your Generate folder, and never appear in Recent Generations or the filmstrip.
- **Video models are refused** with an explanation — previews are stills.

**How long it takes:** each style is one full render on your Draw Things server. Measured
at roughly 75 seconds a style with Krea 2 Turbo (8-bit) on a remote server — about
25 minutes for the 19 Design styles, and most of a working day for all 414.

The style library was compiled by **u/Dear-Spend-2865** and is curated in
[clio-style-preview](https://github.com/lumenastrum/clio-style-preview) by lumenastrum
(MIT), whose prompt template Tanque Studio uses unchanged.

**Verified in the app against a live Draw Things server:** creating a set; a single
card; the full Design section; pause, resume and cancel; leaving Labs mid-batch and
coming back; quitting and relaunching (sets and renders reload); Send to Generate,
checked by first changing Generate's model, size and seed and watching them come back;
Recent Generations unchanged after a batch; and a Focus Room render during a batch —
Draw Things queued the two, and both finished. **Not yet tried by hand: dragging a
preview into Draw Things, and the confirmation shown above 50 styles.** If either
misbehaves — for instance a dropped image without its prompt and settings — please
report it.

## Screen transitions

Switching between the Dashboard, Generate, the Project Browser, Labs and Settings now
animates. Choose **Push** (the default), **Slide**, **Fade** or **Off** in **Settings →
Appearance**. Screens move in the order of the top bar, so going right and going back
read as opposites.

## Bigger click targets

Several buttons responded only on their text or icon, not the space around them, so a
click that visibly landed on the button could do nothing. Fixed for the Dashboard's plain
and outlined buttons, Generate's button, the Focus Room's mode toolbar, the Labs tabs,
and the model and LoRA rows. **The model and LoRA rows were fixed with Draw Things
offline, so their new hit areas haven't been clicked against a live model list.**

## Known issue

**Render Queue: leaving Labs while a run is going orphans it.** The run carries on in the
background, but when you come back its Pause and Stop buttons no longer reach it, and
**Run** starts a second run alongside the first. Until this is fixed, stay in Labs while
a Render Queue run is going, or let it finish. (The Style Browser is built differently
and isn't affected.)

## Notes

**A stray developer file no longer ships.** Releases since 0.9.19 bundled
`settings.local.json`, the permission list of the coding assistant used to build the
app, inside `Contents/Resources`. It held no credentials or keys — only local file
paths, command lines and old commit messages — and the app never read it. It's now
excluded from the build.

Test suite: 474 passed, 8 skipped, 0 failures. New tests cover the style library (414 entries, ten
sections, the prompt template, unique filenames), on-disk sets, and the render
controller — ordering, skipping finished styles, per-style failures, pause, resume,
cancel, the shared seed, and refusing video models.
