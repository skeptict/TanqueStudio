# gRPC Config Parity Audit & Spec

**Totals: 84 fields in the gRPC `GenerationConfiguration` schema — 34 surfaced in the Focus Room drawer, 1 surfaced-disabled (batchSize, pending encoding verification), 0 modeled-but-hidden, 49 not-modeled.** (Recounted 2026-07-26 after Batch D; the previous total was stale — it still counted Batches B, C and D as not-modeled. Surfaced = 12 `S` + 7 `S*` + 3 `✅ B` + 4 `✅ C` + 8 `✅ D`. t5TextEncoder reclassified modeled-but-hidden → not-modeled, see its row.)

- **Audited at:** DT-gRPC-Swift-Client revision `c8f8493` (upstream main tip), read via `git show` — main's pin is `9218530`; the bump is parked on `chore/bump-drawthings-client` pending verification.
- **Bump LANDED on main 2026-07-25** (cherry-picked `9798dd2` as `e855790`; the `chore/bump-drawthings-client` branch itself was stale — branched before v0.9.26/27/28 — so it was never merged). Package resolves and builds clean at `c8f8493`; the app launches and runs.
- **Release-notes item, now traced end-to-end rather than assumed.** TS's `mapSeedMode` (`DrawThingsGRPCClient.swift:599`) returns a raw `Int32` — `2` for Scale Alike, which is also its `default:` fallback. That `Int32` reaches the client's `Configuration.swift:376`, which runs it through `mapSeedModeToEnum`. At the **old** pin that function was `case 0: .legacy; case 1, 2: .torchcpucompatible; default: .torchcpucompatible` — so **seed mode 2 and 3 both collapsed to 1 on the wire**. Meaning: every default-config Tanque Studio render has been sending torchCpuCompatible, not the Scale Alike the UI reported. The bump makes the mapping 1:1, so **same-seed output changes for default-config users** — not just for anyone who picked an exotic mode. **Not yet confirmed at runtime**: no before/after same-seed render comparison has been done (needs Ned's pass; the app was pointed at `localhost` while DT was answering on `192.168.1.34`).
- **Also still owed a manual re-test**: the paint-mode inpaint-cancel flow, since cancellation propagation (upstream PR #19) rides in with this bump.
- **Schema difference between the two pins: none.** `config_generated.swift` is byte-identical at `9218530` and `c8f8493` (verified by full-file diff). The bump changes *encoding behavior*, not the field set: `cd5a7ca` fixes seedMode 2/3 wire values, `a564321` switches **Hires Fix** params to raw pixels with ÷64 at encode (**not** the tile params — see Batch D in §4; that misreading survived into the matrix and was only caught when D was built), `f1cc454` sanitizes empty-string `upscaler`/`faceRestoration`/`refinerModel` to nil, `12b223d` drops the implicit echo-override. Dependencies flagged in §4.
- **Cross-checks:** TS `DrawThingsGRPCClient.convertConfig` → client `DrawThingsConfiguration` (the request-building path); `DrawThingsGenerationConfig` (TS model, `DrawThingsProvider.swift`); `DTProjectBrowser`'s `DTProjectDatabase.swift` FBReader. **Caveat:** `DTProjectDatabase` decodes DT's *project-database* table (prompts at VT 200/202, tensor/preview ids, wall clock) — a different, larger FlatBuffer than the gRPC config table; field *names* corroborate, byte offsets do not.
- **UI policy (Ned, 2026-07-18):** gRPC-surface parity is the goal; settings live in existing collapsed category sections; **enabled means functional** — unwired fields render as disabled rows with a "not yet wired" tooltip, never as live controls that discard input.

Status legend — **✅ B/C/D** surfaced by that parity batch · **S** surfaced (Focus Room drawer control binds it, file noted) · **S\*** surfaced via `fix/dashboard-parity-round-2` (merged to main 2026-07-18) · **SD** surfaced-disabled (control exists, `.disabled(true)` pending verification) · **M** modeled-but-hidden (on `DrawThingsGenerationConfig` and encoded into requests; no drawer binding) · **N** not-modeled (TS has no field).

## 1–2. Field universe & status matrix

| # | Field (VT) | Type | Wire semantics | Default | St | Where / notes |
|---|---|---|---|---|---|---|
| 1 | id (4) | Int64 | config identity, not generation input | 0 | N | no UI planned — metadata, not a setting |
| 2 | startWidth (6) | UInt16 | canvas width, **pixels ÷ 64** | 0 | S | CanvasSizeSection W field, DashboardFocusPanels.swift (Batch A) |
| 3 | startHeight (8) | UInt16 | canvas height, **pixels ÷ 64** | 0 | S | CanvasSizeSection H field, DashboardFocusPanels.swift (Batch A) |
| 4 | seed (10) | UInt32 | RNG seed | 0 | S | ParametersSection slider, DashboardFocusPanels.swift |
| 5 | steps (12) | UInt32 | denoise steps | 0 | S | ParametersSection slider |
| 6 | guidanceScale (14) | Float | CFG | 0 | S | ParametersSection "CFG" slider |
| 7 | strength (16) | Float | img2img denoise strength 0–1 | 0 | S | Img2ImgMoodboardSection slider |
| 8 | model (18) | String | model filename | nil | S | ModelSection picker list |
| 9 | sampler (20) | SamplerType(Int8) | sampler enum, 18 cases | dpmpp2mkarras | S | Sampler picker, ParametersSection (Batch A); TS maps name→enum in `mapSampler` |
| 10 | batchCount (22) | UInt32 | sequential renders | 1 | S\* | Renders stepper, parity branch `6128ad8` |
| 11 | batchSize (24) | UInt32 | images per batch | 1 | SD | Batch Size stepper, ParametersSection, `.disabled(true)` — verification gate: encoding path unverified end-to-end; enabling = delete one line (Batch A) |
| 12 | hiresFix (26) | Bool | enable two-pass hires fix | false | ✅ C | HiresFixSection toggle |
| 13 | hiresFixStartWidth (28) | UInt16 | first-pass width, px ÷ 64 | 0 | ✅ C | TS stores px; **client** does the ÷64 here |
| 14 | hiresFixStartHeight (30) | UInt16 | first-pass height, px ÷ 64 | 0 | ✅ C | TS stores px; **client** does the ÷64 here |
| 15 | hiresFixStrength (32) | Float | second-pass strength | 0.7 | ✅ C | HiresFixSection slider |
| 16 | upscaler (34) | String | upscaler model filename | nil | N | bump's `f1cc454` sanitizes empty→nil |
| 17 | imageGuidanceScale (36) | Float | pix2pix image CFG | 1.5 | N | — |
| 18 | seedMode (38) | SeedMode(Int8) | 0 legacy · 1 torchCpu · 2 scaleAlike · 3 nvidia | legacy | S\* | Seed Mode picker, parity branch `68142bc`; bump's `cd5a7ca` fixes 2/3 wire encoding |
| 19 | clipSkip (40) | UInt32 | CLIP layers to skip | 1 | N | — |
| 20 | controls (42) | [Control] | ControlNet sub-table vector (file, weight, guidance window, mode, input type) | [] | N | TS moodboard uses request-level *hints*, not config controls |
| 21 | loras (44) | [LoRA] | LoRA sub-table vector (file, weight, mode) | [] | S | LoRAsSection, DashboardFocusPanels.swift |
| 22 | maskBlur (46) | Float | inpaint mask blur radius | 0 | ✅ B | INPAINTING group, Img2ImgMoodboardSection; TS default 1.5 = the client's own, not the schema's 0 |
| 23 | faceRestoration (48) | String | face-restore model | nil | N | `f1cc454` note as №16 |
| — | *(50, 52)* | — | absent from schema — deprecated slots | — | — | gap noted for completeness |
| 24 | clipWeight (54) | Float | CLIP embedding weight | 1.0 | N | — |
| 25 | negativePromptForImagePrior (56) | Bool | Kandinsky image-prior neg prompt | true | N | — |
| 26 | imagePriorSteps (58) | UInt32 | Kandinsky prior steps | 5 | N | — |
| 27 | refinerModel (60) | String | SDXL refiner filename | nil | S | Refiner picker, ModelSection (Batch A); empty→nil in TS |
| 28 | originalImageHeight (62) | UInt32 | SDXL size-conditioning, px | 0 | N | — |
| 29 | originalImageWidth (64) | UInt32 | SDXL size-conditioning, px | 0 | N | — |
| 30 | cropTop (66) | Int32 | SDXL crop-conditioning, px | 0 | N | — |
| 31 | cropLeft (68) | Int32 | SDXL crop-conditioning, px | 0 | N | — |
| 32 | targetImageHeight (70) | UInt32 | SDXL target-size conditioning | 0 | N | — |
| 33 | targetImageWidth (72) | UInt32 | SDXL target-size conditioning | 0 | N | — |
| 34 | aestheticScore (74) | Float | SDXL refiner aesthetic cond. | 6.0 | N | — |
| 35 | negativeAestheticScore (76) | Float | SDXL negative aesthetic | 2.5 | N | — |
| 36 | zeroNegativePrompt (78) | Bool | zero out neg-prompt embedding | false | N | — |
| 37 | refinerStart (80) | Float | refiner handoff fraction 0–1 | 0.7 | S | Refiner Start slider, ModelSection (Batch A) |
| 38 | negativeOriginalImageHeight (82) | UInt32 | SDXL neg size-conditioning | 0 | N | — |
| 39 | negativeOriginalImageWidth (84) | UInt32 | SDXL neg size-conditioning | 0 | N | — |
| 40 | name (86) | String | config display name | nil | N | no UI planned — metadata |
| 41 | fpsId (88) | UInt32 | video playback fps | 5 | S\* | FPS field, parity branch (TS `fps`, 0→sentinel 5 at encode) |
| 42 | motionBucketId (90) | UInt32 | SVD motion amount | 127 | N | — |
| 43 | condAug (92) | Float | SVD conditioning noise aug | 0.02 | N | client names it `guidingFrameNoise` |
| 44 | startFrameCfg (94) | Float | SVD first-frame CFG | 1.0 | N | client names it `startFrameGuidance` |
| 45 | numFrames (96) | UInt32 | video frame count | 14 | S\* | Frames field, parity branch (0→sentinel 14 at encode; free-form by design, server accepts >121) |
| 46 | maskBlurOutset (98) | Int32 | inpaint mask outset, px | 0 | ✅ B | INPAINTING group |
| 47 | sharpness (100) | Float | sharpness conditioning | 0 | N | — |
| 48 | shift (102) | Float | sigma/timestep shift | 1.0 | S\* | Shift slider, parity branch; RDS-computed override preserved |
| 49 | stage2Steps (104) | UInt32 | 2nd-stage steps (cascade/Wurstchen) | 10 | N | — |
| 50 | stage2Cfg (106) | Float | 2nd-stage CFG | 1.0 | N | client names it `stage2Guidance` |
| 51 | stage2Shift (108) | Float | 2nd-stage shift | 1.0 | N | — |
| 52 | tiledDecoding (110) | Bool | tile the VAE decode | false | ✅ D | Tiling section |
| 53 | decodingTileWidth (112) | UInt16 | decode tile W, **px ÷ 64** | 10 (=640px) | ✅ D | **The bump note here was WRONG** — `a564321` made the client take raw px *for Hires Fix only*. Tile values pass through unconverted (`configT.decodingTileWidth = UInt16(decodingTileWidth)`), so **TS stores pixels and divides by 64 itself** in `convertConfig` | 
| 54 | decodingTileHeight (114) | UInt16 | decode tile H, px ÷ 64 | 10 | ✅ D | TS stores px, ÷64 at encode |
| 55 | decodingTileOverlap (116) | UInt16 | decode overlap, px ÷ 64 | 2 | ✅ D | TS stores px, ÷64 at encode |
| 56 | stochasticSamplingGamma (118) | Float | SSS gamma | 0.3 | S\* | SSS slider, parity branch |
| 57 | preserveOriginalAfterInpaint (120) | Bool | keep unmasked pixels verbatim | true | ✅ B | INPAINTING group |
| 58 | tiledDiffusion (122) | Bool | tile the diffusion pass | false | ✅ D | Tiling section |
| 59 | diffusionTileWidth (124) | UInt16 | diffusion tile W, px ÷ 64 | 16 (=1024px) | ✅ D | TS stores px, ÷64 at encode |
| 60 | diffusionTileHeight (126) | UInt16 | diffusion tile H, px ÷ 64 | 16 | ✅ D | TS stores px, ÷64 at encode |
| 61 | diffusionTileOverlap (128) | UInt16 | diffusion overlap, px ÷ 64 | 2 | ✅ D | TS stores px, ÷64 at encode |
| 62 | upscalerScaleFactor (130) | UInt8 | upscale multiplier, 0 = model default | 0 | N | — |
| 63 | t5TextEncoder (132) | Bool | use T5 encoder (SD3/Flux family) | true | N | **Reclassified 2026-07-18 (was M — misclassified):** no `DrawThingsGenerationConfig` property exists; `convertConfig` derives it per model family at encode time. Wiring it is a not-modeled task |
| 64 | separateClipL (134) | Bool | separate CLIP-L prompt on | false | N | — |
| 65 | clipLText (136) | String | CLIP-L prompt text | nil | N | — |
| 66 | separateOpenClipG (138) | Bool | separate OpenCLIP-G prompt on | false | N | — |
| 67 | openClipGText (140) | String | OpenCLIP-G prompt text | nil | N | — |
| 68 | speedUpWithGuidanceEmbed (142) | Bool | distilled-guidance fast path | true | N | — |
| 69 | guidanceEmbed (144) | Float | embedded guidance value (Flux) | 3.5 | N | — |
| 70 | resolutionDependentShift (146) | Bool | derive shift from resolution | true | S\* | Res. Shift toggle, parity branch; TS heuristic when unset |
| 71 | teaCacheStart (148) | Int32 | TeaCache start step | 5 | N | — |
| 72 | teaCacheEnd (150) | Int32 | TeaCache end step (−1 = last) | −1 | N | — |
| 73 | teaCacheThreshold (152) | Float | TeaCache skip threshold | 0.06 | N | — |
| 74 | teaCache (154) | Bool | enable TeaCache | false | N | — |
| 75 | separateT5 (156) | Bool | separate T5 prompt on | false | N | — |
| 76 | t5Text (158) | String | T5 prompt text | nil | N | — |
| 77 | teaCacheMaxSkipSteps (160) | Int32 | TeaCache max consecutive skips | 3 | N | — |
| 78 | causalInferenceEnabled (162) | Bool | causal inference on (video) | false | N | — |
| 79 | causalInference (164) | Int32 | causal window (frames) | 3 | N | — |
| 80 | causalInferencePad (166) | Int32 | causal window pad | 0 | N | — |
| 81 | cfgZeroStar (168) | Bool | CFG-Zero* guidance | false | S | CFG-Zero* toggle, ParametersSection (Batch A); nil = turbo-name heuristic until touched |
| 82 | cfgZeroInitSteps (170) | Int32 | CFG-Zero* zero-init steps | 0 | N | — |
| 83 | compressionArtifacts (172) | CompressionMethod(Int8) | simulated-compression conditioning | disabled | N | — |
| 84 | compressionArtifactsQuality (174) | Float | compression quality knob | 43.1 | N | — |

**Modeled-but-hidden: none remaining after Batch A.** The original 15 resolved as: 7 surfaced via the parity branch (†), 6 surfaced in Batch A (startWidth, startHeight, sampler, cfgZeroStar, refinerModel, refinerStart), batchSize surfaced-disabled, t5TextEncoder reclassified not-modeled.

**Not-modeled plumbing surfaces** (every N field's wiring task touches all four): `DrawThingsGenerationConfig` struct + Codable in `DrawThingsProvider.swift` · gRPC request encoding in `DrawThingsGRPCClient.convertConfig` (+ client `DrawThingsConfiguration` init if the client wrapper lacks the parameter) · metadata v2 in `ImageStorageManager` · config import/export in `DTConfigImporter`.

**Reverse direction — TS-only, no gRPC config counterpart (not gaps):** `negativePrompt` (request argument, not a config field) · `randomizeSeed` (GenerateViewModel behavior) · `LoRAConfig.mode` string mapping (client maps to LoRA sub-table `mode`) · sentinel semantics `fps`/`numFrames` = 0 meaning "model default" (TS convention; wire has its own defaults) · client wrapper's `enableInpainting` (adds an inpaint control server-side; TS drives inpainting via image+mask instead).

## 3. Category assignment (unsurfaced fields → drawer sections)

Existing sections: Prompt · Assist · Model · Parameters · LoRAs · img2img & Moodboard · Actions. Classic-panel sections portable to the drawer: Canvas Size. Proposed new sections marked ▲ (cribbed from DT's own groupings).

| Section | Fields |
|---|---|
| **Canvas Size** (port from classic) | startWidth, startHeight. Now the consolidated home for all size controls: aspect-ratio chips (moved from Prompt, budget-preserving `applyAspectRatio`), Small/Medium/Large tier chips (512²/1024²/1536² pixel budgets at the current ratio, rounded to nearest 64), then the numeric W×H row (grouping separators suppressed) |
| **Parameters** | sampler, batchSize, clipSkip, sharpness, imageGuidanceScale, zeroNegativePrompt, guidanceEmbed + speedUpWithGuidanceEmbed, cfgZeroStar + cfgZeroInitSteps, compressionArtifacts + compressionArtifactsQuality |
| **Model** | refinerModel, refinerStart, upscaler, upscalerScaleFactor, faceRestoration |
| **img2img & Moodboard** | maskBlur, maskBlurOutset, preserveOriginalAfterInpaint, controls (ControlNet UI is its own future project; listed for completeness) |
| ▲ **Hires Fix** | hiresFix, hiresFixStartWidth, hiresFixStartHeight, hiresFixStrength |
| ▲ **Tiling** | tiledDiffusion + 3 tile params, tiledDecoding + 3 tile params |
| ▲ **Video** | numFrames†, fpsId†, motionBucketId, condAug, startFrameCfg, causalInferenceEnabled, causalInference, causalInferencePad, stage2Steps, stage2Cfg, stage2Shift |
| ▲ **Text Encoders** | t5TextEncoder, separateT5 + t5Text, separateClipL + clipLText, separateOpenClipG + openClipGText, clipWeight |
| ▲ **SDXL Conditioning** | aestheticScore, negativeAestheticScore, originalImage W/H, negativeOriginalImage W/H, cropTop/Left, targetImage W/H, negativePromptForImagePrior + imagePriorSteps (Kandinsky; nearest fit) |
| ▲ **Performance** | teaCache, teaCacheStart, teaCacheEnd, teaCacheThreshold, teaCacheMaxSkipSteps |
| *(no UI)* | id, name — metadata, not settings; excluded from parity with justification |

## 4. Phasing

**Batch A — COMPLETE 2026-07-18** on `feat/config-parity-batch-a` (surfacing `abcc3f7`, search removal `42e3bdd`, batchSize `9caab86`). Canvas Size port, sampler picker, refiner rows, cfgZeroStar toggle landed; batchSize shipped as a disabled stepper per the enabled-means-functional policy; t5TextEncoder skipped as misclassified (see its matrix row).

**Batch B — inpainting group** (maskBlur, maskBlurOutset, preserveOriginalAfterInpaint): all four plumbing surfaces; natural home img2img section; disabled-with-tooltip first if wiring trails UI.

**Batch C — Hires Fix group** (4 fields): new section; plumbing + UI.

**Batch D — Tiling group** (8 fields): **COMPLETE 2026-07-26.** New Tiling drawer section (two independent groups: Tiled Diffusion, Tiled Decoding — each a toggle plus tile W×H and overlap), all four plumbing surfaces, plus request-log lines and `TanqueStudioTests/TilingConfigTests`.

**The unit convention here is the opposite of Hires Fix, and the matrix note above was wrong about it.** Verified by reading three sources rather than assuming:

| Layer | Unit |
|---|---|
| Tanque Studio config, DT config JSON, DT metadata, StoryFlow projects | **pixels** |
| Client wrapper (`DrawThingsConfiguration`) and the FlatBuffer wire | **÷64 units** |

`a564321` gave *Hires Fix* raw-pixel inputs with the client doing the division (`configT.hiresFixStartWidth = UInt16(hiresFixWidth / 64)`). Tile values were never included — the client assigns them straight through (`configT.decodingTileWidth = UInt16(decodingTileWidth)`), and its defaults of 10/10/2 and 16/16/2 are themselves ÷64 units. So **TS stores pixels and converts at the gRPC boundary** (`DrawThingsGRPCClient.tileUnits`, floored to ≥1 so a sub-64 value can't encode as "no tile").

Pixels is right for storage independent of that: Draw Things' own JSON multiplies back up (`json["decoding_tile_width"] = decodingTileWidth * 64`, `ImageConverter.swift:1192`), its scripting parameters are pixels (`Invocation.swift:162` divides on the way in), and real StoryFlow projects carry pixels.

Two behaviours worth knowing: DT **skips tiling entirely** unless the canvas exceeds the tile in at least one dimension (`ImageConverter.swift:1187`) — surfaced as an inline hint rather than enforced; and defaults match what the client was already applying implicitly, so surfacing the group changes no existing render.

**Verified end-to-end against a live Draw Things server (2026-07-26).** Six deliberately distinct, non-transposable values were entered, a real render was run, and every layer was read back rather than inferred:

| Layer | Diffusion | Decoding |
|---|---|---|
| UI (pixels) | 512 × 896, overlap 192 | 640 × 704, overlap 128 |
| Request log (wire units) | **8 × 14, overlap 3** | **10 × 11, overlap 2** |
| Saved PNG metadata (pixels) | 512 × 896, overlap 192 | 640 × 704, overlap 128 |

Exact, in the right order, with width and height not transposed — 512→8 and 896→14 could not have swapped unnoticed. Draw Things accepted the request and returned the image, so the values are valid on the wire and not merely well-formed. The request-log lines print both units deliberately, which is what made this checkable from the log instead of by inspection.

**Batch E — Text Encoders + SDXL Conditioning** (13 + 10 fields): plumbing-heavy, mostly niche; disabled rows acceptable long-term per policy.

> **⚠️ Naming: "Batch F" means SDXL Conditioning everywhere except this document.**
> `Docs/storyflow-260723-spec.md` §3.5, the README, and `StoryFlowItemSchema`'s own
> summary string all say "Batch F (SDXL Conditioning)", while the table here assigns
> SDXL Conditioning to **E** and video/performance knobs to **F**. The label is not
> worth renaming — it is referenced from code — but read "Batch F" as *SDXL
> conditioning* unless the surrounding text is about `motionBucketId` and friends.

**SDXL size conditioning — COMPLETE 2026-07-27.** The six fields `xlMagic` needs
(rows 28/29, 32/33, 38/39) are modeled and reach all four plumbing surfaces, plus
`mergeDict`/`sweepableParameters` and a native XL Magic helper in the drawer.

**⚠️ Zero is not "absent" for these fields, and it changes how they must be tested.**
The client substitutes the render's own dimensions for any conditioning field left
at 0:

```swift
configT.originalImageWidth = UInt32(originalImageWidth > 0 ? originalImageWidth : width)
// Configuration.swift:414–419
```

Two consequences. Surfacing the group changes no existing render, because zero
reproduces exactly what Draw Things already received — the same argument tiling
used. And **a wire-level check must use values distinct from the render size**:
against a 512×512 render, a conditioning value of 512 is indistinguishable from
never having been sent. The live test picks sliders 1/4/8 (256×192, 1024×768,
2048×1536) for that reason and asserts the absence of any collision, so it cannot
quietly become a test that passes either way.

**Verified on the wire (2026-07-27)**, not inferred — a real render at 512×512 with
`sdxlOriginalImage 256×192`, `sdxlTargetImage 1024×768`, `sdxlNegativeOriginal
2048×1536` in `request_log.txt`, and Draw Things returned an image rather than
rejecting the request. That run used `z_image_turbo`, so it establishes the
plumbing; the *visual* effect of the parameters on an SDXL model is a separate
claim and is not made here.

**Batch F — Video extras + Performance** (motionBucketId, condAug, startFrameCfg, stage2\*, causal\*, teaCache\*): lowest priority; SVD-era and perf knobs.

Batches B, C, E, F have no dependency on the client bump (schema identical across pins). Batch A depends on the parity branch; Batch D depended on the bump, which has landed (`c8f8493`) — D is complete. Upscaler/faceRestoration rows (Batch A/Model) get cleaner empty-string semantics after the bump (`f1cc454`) but TS already nil-maps empties itself, so no hard dependency.

## 5. Investigation: search box (`DashboardTopBar.submitSearch`, lines 138–149)

The query is lowercased and whitespace-trimmed, then substring-matched (`String.contains`) against a **hardcoded five-entry list of nav destination names**: "dashboard", "focus room", "projects", "labs", "settings". On first match (array order, not best match): navigates to that mode and clears the field. On miss: **silent no-op** — no feedback, text stays. It searches nothing else — not projects, models, prompts, or gallery content, despite the generic "Search…" placeholder. Quirk: single letters navigate surprisingly ("s" → Dashboard, because "da**s**hboard" contains "s" and is checked first). **Resolution: removed, commit `42e3bdd`** (redundant after the persistent nav gained Generate).

## 6. Sanity count

**84 schema fields = 19 surfaced + 1 surfaced-disabled + 0 modeled-but-hidden + 64 not-modeled** (post-Batch A, 2026-07-18). Schema delta between pins `9218530` → `c8f8493`: **0 fields** (behavioral changes only).
