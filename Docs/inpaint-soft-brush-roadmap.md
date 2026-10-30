# Inpaint brush: roadmap back to a soft brush

Status: proposal, 2026-10-30. Nothing here is built. It follows
[canvas-inpainting-spec.md](canvas-inpainting-spec.md), whose Phase 1 (the hard-edged mask painter)
shipped, and `4368ed7`, which put **Edge** (`maskBlur`) and **Grow** (`maskBlurOutset`) in the paint
toolbar.

Everything about Draw Things' behaviour below was read from its source
(`draw-things-community`, `LocalImageGenerator.swift` around lines 6040–6560 and
`ImageConverter.swift` around 2050). Line numbers drift; the function names are `imageWithMask`
and the mask decoder just above `generateImageWithMask2`.

## Where the mask is today

1. **Strokes.** `GenerateViewModel.MaskStroke` holds normalized points, a radius and an erase flag.
   There is no hardness, opacity or kind.
2. **Raster.** `rasterizeMask(for:)` fills an RGBA bitmap opaque, then clears round-capped strokes
   to alpha 0. Erase strokes paint opacity back.
3. **Encode.** `DrawThingsGRPCClient` (around line 485) calls the client library's
   `ImageHelpers.createMaskFromAlpha`, which writes one byte per pixel: **2** where alpha < 255,
   **0** everywhere else. The anti-aliased edge pixels become 2 as well, so the hole is about a
   pixel wider than the stroke.
4. **Send.** The bytes go to the low-level service as the request's mask.

So Draw Things receives a mask of 0s and 2s with every alpha bit zero.

**One useful fact:** Tanque Studio already owns step 3's call site and hands the service raw
`Data`. Replacing the encoder needs **no change to DT-gRPC-Swift-Client**. Earlier notes said it
did; that was wrong.

## How Draw Things reads the mask byte

Each byte is bit-packed:

| bits | meaning |
|---|---|
| low 3 (`& 7`) | mode: 0, 1, 2 or 3 (4 is read as 2) |
| top 5 (`& 0xf8`) | alpha, 32 levels from 0 to 248 |

**What the modes do.** Draw Things builds two latent masks. A cell that is 0 in `mask2` is kept
until step − tEnc, which is the Strength cut-in. A cell that is 0 in `mask3` is kept to the end.

| mode | latent masks it sets | effect | who writes it |
|---|---|---|---|
| 3 | neither | kept, always | Draw Things, for opaque canvas pixels |
| 2 | `mask3` | **repainted at Strength**: img2img inside the region | us, today |
| 1 | `mask2` and `mask3` | **generated from scratch**, ignoring Strength ("nothing there") | Draw Things, for transparent canvas pixels |
| 0 | depends on which other modes are present | see the warning below | us, today, for "keep" |

⚠️ **Mode 0 is ambiguous.** Draw Things' own truth table:

- With only 0 and 2 (our case), 0 means keep.
- **With only 0 and 1, 0 means *repaint at Strength*.** The whole unpainted image would be
  img2img'd.

The moment we send a mode-1 pixel, "keep" has to be written as **3**, which is what Draw Things'
own encoder does.

**What the alpha bits do:**

- **Not the denoise mask.** `mask2` and `mask3` are binary, one value per *latent cell*: 8×8 pixels
  for most models. A cell is in if any pixel in it is painted. Alpha never reaches them, so
  **there is no per-pixel denoise strength.** Strength is one number for the whole render.
- **What the model is shown.** The alpha-weighted pixel masks (`imageNegMask2`/`3`) multiply the
  source image before it is VAE-encoded. They also become the mask channel of
  inpainting-specific models and the mask handed to control hints. This applies only on the
  inpainting, editing and double modifier paths. A plain model never sees them.
- **The final composite, for mode 1 only.** With *Preserve original after inpaint* on, a mode-1
  pixel with alpha `a` blends the original back in by `a²`, per pixel. That is the one place a
  soft mask produces a visibly soft blend on every model. Mode-2 alpha is not read by the
  composite.

**What Edge and Grow do.** They are scalars, not per pixel.

- **Edge** blurs a *binary* keep map (modes 3 and 0, plus 1 on transparent models) and blends
  original against generated through it after the render.
- **Grow** (positive outset) erodes that keep map, so the repaired area spreads outward. Positive
  outset **also dilates the latent masks**, so Grow widens what gets *generated* as well as the
  seam. Our earlier notes said it only affected the composite.

## What "soft brush" can actually mean

People expect three different things from the phrase, and Draw Things supports them unevenly:

| wanted | supported? | route |
|---|---|---|
| A feathered blend at the edge of the repair | yes, globally | **Edge** today; per pixel only for mode-1 strokes |
| Some areas changed less than others | **two tiers only** | mode 2 (at Strength) vs mode 1 (from scratch). No gradient |
| Softer guidance for inpainting models | yes | alpha bits on mode-2 pixels |

A Photoshop-style brush, where 50% opacity means "change this half as much", **is not possible**
through this API. The roadmap builds what is possible and labels it honestly.

## Phases

### Phase 0: own the encoder (no behaviour change)

- Add `DTMaskEncoder`, a pure function that takes a per-pixel mode and coverage and returns the
  68-byte header plus bytes.
- Its first version reproduces today's output exactly (0 and 2, alpha zero). Unit-test it
  byte-for-byte against `createMaskFromAlpha` on a few rasters, then swap the call site.
- Add a test helper that ports Draw Things' decoder truth table (the `exists0…3` and `overwrite0`
  logic), so tests can assert *which generation path* a mask will take. That is the class of bug
  the mode-0 trap would cause, and no render would explain it.

Small, safe, and everything after it depends on it.

### Phase 1: write "keep" as 3

- Change "keep" from 0 to 3. On paper this is equivalent for our masks: with 2 and 3 present and
  no 1, it takes the same path and the composite treats 3 and 0 alike.
- It removes the mode-0 ambiguity before mode 1 ever appears.
- **Verify live**, since a change that is "equivalent on paper" still deserves a look. Renders
  are not bit-reproducible, so compare the 0-keep vs 3-keep difference against a same-config
  repeat baseline rather than hashing.

### Phase 2: two brush kinds, Repaint and Replace

This is the tiering Draw Things really has.

- **Repaint** (mode 2): today's brush. It honours Strength.
- **Replace** (mode 1): generates the region from scratch, whatever Strength says. Good for
  removing an object outright while Strength stays low for touch-ups elsewhere.
- **Strokes:** `MaskStroke` gains a `kind`. Erase sets pixels back to keep (3).
- **UI:** a two-way toggle in the paint toolbar, and a distinct overlay colour per kind so a
  mixed mask reads at a glance.
- **Verify live:** a mask with both kinds renders both tiers. Measure the region-by-region
  difference from the source at a low Strength: the Replace region should change far more.
- **Caveat:** on a *transparent-decoder* model (layer-diffuse), Draw Things drops mode 1 from
  `mask3`. Either disable Replace for those models or say what it does there.

### Phase 3: hardness

- **Strokes:** `MaskStroke` gains `hardness` (0–1).
- **Raster:** the rasterizer stops drawing hard round caps. It renders each stroke's coverage
  with a radial falloff into a single-channel 8-bit coverage map, max-combined across strokes
  (erase subtracts). The mode map stays separate.
- **Encode:** the encoder writes `alpha = (255 − coverage) & 0xf8` into the top bits, so
  "painted" means low alpha, which matches Draw Things' convention that alpha is how much of the
  original survives. Any coverage above 0 marks the pixel with the stroke's mode.
- **What the user will see:**
  - **Replace strokes:** the soft edge shows on every model, through the `a²` composite (needs
    *Preserve original after inpaint*).
  - **Repaint strokes:** hardness changes only what inpainting models are shown. On a plain
    model the visible softness still comes from Edge.
  - The slider's help text must say this. Otherwise it reads as broken.
- **Overlay:** the canvas preview draws the same falloff, so what you see is what is sent.
- **Quantization:** 32 levels, and the maximum is 248, not 255. A fully kept mode-2 pixel can't
  carry alpha 1.0. That doesn't matter, because a kept pixel is written as 3.

### Phase 4: keep the mask (optional)

- Save the mask as a grayscale PNG (coverage) beside the generation, with the mode in the
  metadata, so a result can be re-run or tweaked with the same mask.
- Add **Load Mask…** to import a grayscale image as a mask.
- Write the mask's mode counts into `RequestLogger`. That makes "which path did this take?"
  answerable from the log.

### Phase 5: upstream (optional)

Offer a `createMask(modes:coverage:)` to DT-gRPC-Swift-Client, so other clients stop thresholding.
Tanque Studio doesn't need to wait for it.

## Verification, throughout

- **Unit tests:** encoder bytes, round-trips, and the truth-table helper asserting the path for
  0/2, 2/3, 1/3, 1/2/3 and the 0/1 trap.
- **Live tests** (`TS_LIVE_DT=1`, which needs the `TEST_RUNNER_` prefix): render pairs and compare
  *regional* difference magnitudes against a repeat baseline. Never compare two renders by hash.
- **Look at it.** Every phase from 2 on changes something visible: open the app, paint, render
  and look before calling it done.
- `dtcli` (the `/draw-things-render` skill) doesn't send masks today, so it can't be the oracle
  here unless it gains a mask option.

## Open questions

- Where does Draw Things' own app write mode 2? Its alpha-carrying writes I found use modes 1
  and 3 only. If nothing in Draw Things produces mode 2 with alpha, that read path has had little
  real-world use. Phase 3's Repaint-hardness result should be treated as unproven until measured.
- Is the latent cell 8 px for every model family Ned uses, or 16 for some? It sets how coarse the
  generated region can be, and how much Edge has to hide.
