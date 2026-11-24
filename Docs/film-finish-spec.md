# Film Finish — halation + .cube LUT (prototype)

**Status:** prototype on `feature/film-finish-prototype`, started 2026-11-23. Not yet built or run on a Mac.

## Why

From the Draw Things Discord (#experiments, 2026-11-22/23). ラD. ran an edit-model shootout (Klein 9B KV,
Qwen Image 2.1, Fibo 2.0, prompt "make her look photorealistic"). ianiv pointed out that the edit took out
some of the halation, and that it can be added back. ラD.'s own finishing chain for AI video is DaVinci's
film look creator (grain, a bit of glow and halation, vignette, film colour off), then a LUT. ianiv said
that's why he added LUT support to his app.

Takeaway for Tanque Studio: edit models remove film character, so the film look goes **last**:

    generate → edit-model pass → upscale → Film Finish → LUT

## What the prototype has

| File | What |
|---|---|
| `FilmFinish/CubeLUT.swift` | `.cube` parser (TITLE, LUT_3D_SIZE, DOMAIN_MIN/MAX, LUT_3D_INPUT_RANGE, comments) → `CIColorCubeWithColorSpace` in **sRGB**, with a strength dissolve |
| `FilmFinish/HalationFilter.swift` | luminance → highlight ramp → two-scale Gaussian bloom → core protection → tint → screen/add, in CI's linear space |
| `FilmFinish/FilmFinish.swift` | the stack (halation, then LUT), shared `CIContext`, preview downscale, PNG export that copies the source's metadata |
| `FilmFinish/FilmFinishLabView.swift` | Labs → Film Finish test bench: drop/open image or `.cube`, sliders, hold-for-Before, halation-only view, export |
| `TanqueStudioTests/FilmFinishTests.swift` | parser, LUT colour-space, halation behaviour, resolution independence, stack order |

Also a Labs tab and a Dashboard tile ("Film Finish").

## Decisions

- **LUT lookup in sRGB, not linear.** `.cube` files are authored against gamma-encoded values.
  `testLUTOperatesInSRGBEncodedValues` guards this.
- **Halation in linear.** It's light; adding it in linear is the physically right place.
- **Radius is a fraction of the short side** (default 0.012), so the 1600 px preview matches a full-size export.
- **Core protection** subtracts part of the unblurred mask, so the glow shows as a fringe *around* highlights
  rather than turning them pink.
- **LUTs with a non-0–1 domain are refused**, not mis-graded. 1D LUTs are refused too.
- **Assumes opaque input** (Draw Things renders always are).
- **Non-destructive.** `FilmFinish` is a value type, ready to store next to a `TSImage` later.

## Next

1. Build, run the tests, try it on real renders (the cowboy-style edit-model outputs are the right test case).
   Tune the defaults by eye.
2. Grain (resolution-scaled), glow (untinted halation, smaller radius), vignette, all before the LUT.
3. Saved presets ("film looks"), applied across a batch, for consistent graphic-novel pages.
4. Store a `FilmFinish` on `TSImage`; render it at export and from the Focus Room / gallery.
5. Possibly a StoryFlow / Render Queue step so a finish runs as part of a pipeline.
