# gRPC Config Parity Audit & Spec

**Totals: 84 fields in the gRPC `GenerationConfiguration` schema — 6 surfaced in the Focus Room drawer (main), 15 modeled-but-hidden, 63 not-modeled.** (After `fix/dashboard-parity-round-2` merges: 13 surfaced / 8 hidden / 63 not-modeled.)

- **Audited at:** DT-gRPC-Swift-Client revision `c8f8493` (upstream main tip), read via `git show` — main's pin is `9218530`; the bump is parked on `chore/bump-drawthings-client` pending verification.
- **Schema difference between the two pins: none.** `config_generated.swift` is byte-identical at `9218530` and `c8f8493` (verified by full-file diff). The bump changes *encoding behavior*, not the field set: `cd5a7ca` fixes seedMode 2/3 wire values, `a564321` switches tile params to raw pixels with ÷64 at encode, `f1cc454` sanitizes empty-string `upscaler`/`faceRestoration`/`refinerModel` to nil, `12b223d` drops the implicit echo-override. Dependencies flagged in §4.
- **Cross-checks:** TS `DrawThingsGRPCClient.convertConfig` → client `DrawThingsConfiguration` (the request-building path); `DrawThingsGenerationConfig` (TS model, `DrawThingsProvider.swift`); `DTProjectBrowser`'s `DTProjectDatabase.swift` FBReader. **Caveat:** `DTProjectDatabase` decodes DT's *project-database* table (prompts at VT 200/202, tensor/preview ids, wall clock) — a different, larger FlatBuffer than the gRPC config table; field *names* corroborate, byte offsets do not.
- **UI policy (Ned, 2026-07-18):** gRPC-surface parity is the goal; settings live in existing collapsed category sections; **enabled means functional** — unwired fields render as disabled rows with a "not yet wired" tooltip, never as live controls that discard input.

Status legend — **S** surfaced (Focus Room drawer control binds it, file noted) · **S\*** surfaced on pending `fix/dashboard-parity-round-2`, hidden on main · **M** modeled-but-hidden (on `DrawThingsGenerationConfig` and encoded into requests; no drawer binding) · **N** not-modeled (TS has no field).

## 1–2. Field universe & status matrix

| # | Field (VT) | Type | Wire semantics | Default | St | Where / notes |
|---|---|---|---|---|---|---|
| 1 | id (4) | Int64 | config identity, not generation input | 0 | N | no UI planned — metadata, not a setting |
| 2 | startWidth (6) | UInt16 | canvas width, **pixels ÷ 64** | 0 | M | encoded from `config.width`; drawer shows read-only on Home tile only |
| 3 | startHeight (8) | UInt16 | canvas height, **pixels ÷ 64** | 0 | M | as above |
| 4 | seed (10) | UInt32 | RNG seed | 0 | S | ParametersSection slider, DashboardFocusPanels.swift |
| 5 | steps (12) | UInt32 | denoise steps | 0 | S | ParametersSection slider |
| 6 | guidanceScale (14) | Float | CFG | 0 | S | ParametersSection "CFG" slider |
| 7 | strength (16) | Float | img2img denoise strength 0–1 | 0 | S | Img2ImgMoodboardSection slider |
| 8 | model (18) | String | model filename | nil | S | ModelSection picker list |
| 9 | sampler (20) | SamplerType(Int8) | sampler enum, 18 cases | dpmpp2mkarras | M | TS maps name→enum in `mapSampler`; no drawer control |
| 10 | batchCount (22) | UInt32 | sequential renders | 1 | S\* | Renders stepper, parity branch `6128ad8` |
| 11 | batchSize (24) | UInt32 | images per batch | 1 | M | encoded; no UI anywhere (Ned 2026-07-18: keep model-only for now) |
| 12 | hiresFix (26) | Bool | enable two-pass hires fix | false | N | — |
| 13 | hiresFixStartWidth (28) | UInt16 | first-pass width, px ÷ 64 | 0 | N | — |
| 14 | hiresFixStartHeight (30) | UInt16 | first-pass height, px ÷ 64 | 0 | N | — |
| 15 | hiresFixStrength (32) | Float | second-pass strength | 0.7 | N | — |
| 16 | upscaler (34) | String | upscaler model filename | nil | N | bump's `f1cc454` sanitizes empty→nil |
| 17 | imageGuidanceScale (36) | Float | pix2pix image CFG | 1.5 | N | — |
| 18 | seedMode (38) | SeedMode(Int8) | 0 legacy · 1 torchCpu · 2 scaleAlike · 3 nvidia | legacy | S\* | Seed Mode picker, parity branch `68142bc`; bump's `cd5a7ca` fixes 2/3 wire encoding |
| 19 | clipSkip (40) | UInt32 | CLIP layers to skip | 1 | N | — |
| 20 | controls (42) | [Control] | ControlNet sub-table vector (file, weight, guidance window, mode, input type) | [] | N | TS moodboard uses request-level *hints*, not config controls |
| 21 | loras (44) | [LoRA] | LoRA sub-table vector (file, weight, mode) | [] | S | LoRAsSection, DashboardFocusPanels.swift |
| 22 | maskBlur (46) | Float | inpaint mask blur radius | 0 | N | — |
| 23 | faceRestoration (48) | String | face-restore model | nil | N | `f1cc454` note as №16 |
| — | *(50, 52)* | — | absent from schema — deprecated slots | — | — | gap noted for completeness |
| 24 | clipWeight (54) | Float | CLIP embedding weight | 1.0 | N | — |
| 25 | negativePromptForImagePrior (56) | Bool | Kandinsky image-prior neg prompt | true | N | — |
| 26 | imagePriorSteps (58) | UInt32 | Kandinsky prior steps | 5 | N | — |
| 27 | refinerModel (60) | String | SDXL refiner filename | nil | M | encoded (empty→nil in TS); no drawer control |
| 28 | originalImageHeight (62) | UInt32 | SDXL size-conditioning, px | 0 | N | — |
| 29 | originalImageWidth (64) | UInt32 | SDXL size-conditioning, px | 0 | N | — |
| 30 | cropTop (66) | Int32 | SDXL crop-conditioning, px | 0 | N | — |
| 31 | cropLeft (68) | Int32 | SDXL crop-conditioning, px | 0 | N | — |
| 32 | targetImageHeight (70) | UInt32 | SDXL target-size conditioning | 0 | N | — |
| 33 | targetImageWidth (72) | UInt32 | SDXL target-size conditioning | 0 | N | — |
| 34 | aestheticScore (74) | Float | SDXL refiner aesthetic cond. | 6.0 | N | — |
| 35 | negativeAestheticScore (76) | Float | SDXL negative aesthetic | 2.5 | N | — |
| 36 | zeroNegativePrompt (78) | Bool | zero out neg-prompt embedding | false | N | — |
| 37 | refinerStart (80) | Float | refiner handoff fraction 0–1 | 0.7 | M | encoded; no drawer control |
| 38 | negativeOriginalImageHeight (82) | UInt32 | SDXL neg size-conditioning | 0 | N | — |
| 39 | negativeOriginalImageWidth (84) | UInt32 | SDXL neg size-conditioning | 0 | N | — |
| 40 | name (86) | String | config display name | nil | N | no UI planned — metadata |
| 41 | fpsId (88) | UInt32 | video playback fps | 5 | S\* | FPS field, parity branch (TS `fps`, 0→sentinel 5 at encode) |
| 42 | motionBucketId (90) | UInt32 | SVD motion amount | 127 | N | — |
| 43 | condAug (92) | Float | SVD conditioning noise aug | 0.02 | N | client names it `guidingFrameNoise` |
| 44 | startFrameCfg (94) | Float | SVD first-frame CFG | 1.0 | N | client names it `startFrameGuidance` |
| 45 | numFrames (96) | UInt32 | video frame count | 14 | S\* | Frames field, parity branch (0→sentinel 14 at encode; free-form by design, server accepts >121) |
| 46 | maskBlurOutset (98) | Int32 | inpaint mask outset, px | 0 | N | — |
| 47 | sharpness (100) | Float | sharpness conditioning | 0 | N | — |
| 48 | shift (102) | Float | sigma/timestep shift | 1.0 | S\* | Shift slider, parity branch; RDS-computed override preserved |
| 49 | stage2Steps (104) | UInt32 | 2nd-stage steps (cascade/Wurstchen) | 10 | N | — |
| 50 | stage2Cfg (106) | Float | 2nd-stage CFG | 1.0 | N | client names it `stage2Guidance` |
| 51 | stage2Shift (108) | Float | 2nd-stage shift | 1.0 | N | — |
| 52 | tiledDecoding (110) | Bool | tile the VAE decode | false | N | — |
| 53 | decodingTileWidth (112) | UInt16 | decode tile W, **px ÷ 64** | 10 (=640px) | N | bump `a564321`: client now takes raw px, converts | 
| 54 | decodingTileHeight (114) | UInt16 | decode tile H, px ÷ 64 | 10 | N | — |
| 55 | decodingTileOverlap (116) | UInt16 | decode overlap, px ÷ 64 | 2 | N | — |
| 56 | stochasticSamplingGamma (118) | Float | SSS gamma | 0.3 | S\* | SSS slider, parity branch |
| 57 | preserveOriginalAfterInpaint (120) | Bool | keep unmasked pixels verbatim | true | N | — |
| 58 | tiledDiffusion (122) | Bool | tile the diffusion pass | false | N | — |
| 59 | diffusionTileWidth (124) | UInt16 | diffusion tile W, px ÷ 64 | 16 (=1024px) | N | — |
| 60 | diffusionTileHeight (126) | UInt16 | diffusion tile H, px ÷ 64 | 16 | N | — |
| 61 | diffusionTileOverlap (128) | UInt16 | diffusion overlap, px ÷ 64 | 2 | N | — |
| 62 | upscalerScaleFactor (130) | UInt8 | upscale multiplier, 0 = model default | 0 | N | — |
| 63 | t5TextEncoder (132) | Bool | use T5 encoder (SD3/Flux family) | true | M | TS derives per model family; explicit override possible in model, no UI |
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
| 81 | cfgZeroStar (168) | Bool | CFG-Zero* guidance | false | M | TS heuristic (model name contains "turbo") + explicit override; no UI |
| 82 | cfgZeroInitSteps (170) | Int32 | CFG-Zero* zero-init steps | 0 | N | — |
| 83 | compressionArtifacts (172) | CompressionMethod(Int8) | simulated-compression conditioning | disabled | N | — |
| 84 | compressionArtifactsQuality (174) | Float | compression quality knob | 43.1 | N | — |

**Modeled-but-hidden (15):** startWidth, startHeight, sampler, batchSize, batchCount†, seedMode†, shift†, stochasticSamplingGamma†, resolutionDependentShift†, numFrames†, fpsId†, t5TextEncoder, cfgZeroStar, refinerModel, refinerStart. († = surfaced on pending parity branch.)

**Not-modeled plumbing surfaces** (every N field's wiring task touches all four): `DrawThingsGenerationConfig` struct + Codable in `DrawThingsProvider.swift` · gRPC request encoding in `DrawThingsGRPCClient.convertConfig` (+ client `DrawThingsConfiguration` init if the client wrapper lacks the parameter) · metadata v2 in `ImageStorageManager` · config import/export in `DTConfigImporter`.

**Reverse direction — TS-only, no gRPC config counterpart (not gaps):** `negativePrompt` (request argument, not a config field) · `randomizeSeed` (GenerateViewModel behavior) · `LoRAConfig.mode` string mapping (client maps to LoRA sub-table `mode`) · sentinel semantics `fps`/`numFrames` = 0 meaning "model default" (TS convention; wire has its own defaults) · client wrapper's `enableInpainting` (adds an inpaint control server-side; TS drives inpainting via image+mask instead).

## 3. Category assignment (unsurfaced fields → drawer sections)

Existing sections: Prompt · Assist · Model · Parameters · LoRAs · img2img & Moodboard · Actions. Classic-panel sections portable to the drawer: Canvas Size. Proposed new sections marked ▲ (cribbed from DT's own groupings).

| Section | Fields |
|---|---|
| **Canvas Size** (port from classic) | startWidth, startHeight |
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

**Batch A — surface all modeled-but-hidden (pure UI, one session).** Canvas Size port (width/height), sampler picker, refinerModel + refinerStart rows, cfgZeroStar toggle, t5TextEncoder toggle, batchSize stepper (policy note: Ned previously scoped "Renders only" for the parity branch — confirm before adding). *Depends on `fix/dashboard-parity-round-2` merging first* (it already surfaces the other 7; duplicating would conflict).

**Batch B — inpainting group** (maskBlur, maskBlurOutset, preserveOriginalAfterInpaint): all four plumbing surfaces; natural home img2img section; disabled-with-tooltip first if wiring trails UI.

**Batch C — Hires Fix group** (4 fields): new section; plumbing + UI.

**Batch D — Tiling group** (8 fields): **depends on the parked client bump** — `a564321` changed the client to accept raw pixels (÷64 at encode); wiring against the old pin would bake in unit-of-64 values that silently change meaning when the bump lands. Land `chore/bump-drawthings-client` first.

**Batch E — Text Encoders + SDXL Conditioning** (13 + 10 fields): plumbing-heavy, mostly niche; disabled rows acceptable long-term per policy.

**Batch F — Video extras + Performance** (motionBucketId, condAug, startFrameCfg, stage2\*, causal\*, teaCache\*): lowest priority; SVD-era and perf knobs.

Batches B, C, E, F have no dependency on the client bump (schema identical across pins). Batch A depends on the parity branch; Batch D depends on the bump. Upscaler/faceRestoration rows (Batch A/Model) get cleaner empty-string semantics after the bump (`f1cc454`) but TS already nil-maps empties itself, so no hard dependency.

## 5. Investigation: search box (`DashboardTopBar.submitSearch`, lines 138–149)

The query is lowercased and whitespace-trimmed, then substring-matched (`String.contains`) against a **hardcoded five-entry list of nav destination names**: "dashboard", "focus room", "projects", "labs", "settings". On first match (array order, not best match): navigates to that mode and clears the field. On miss: **silent no-op** — no feedback, text stays. It searches nothing else — not projects, models, prompts, or gallery content, despite the generic "Search…" placeholder. Quirk: single letters navigate surprisingly ("s" → Dashboard, because "da**s**hboard" contains "s" and is checked first). Decision for Ned: clarify (rename placeholder to e.g. "Go to…", add miss feedback) vs. remove vs. grow into real content search.

## 6. Sanity count

**84 schema fields = 6 surfaced (main) + 15 modeled-but-hidden + 63 not-modeled.** Post-parity-branch: 13 + 8 + 63. Schema delta between pins `9218530` → `c8f8493`: **0 fields** (behavioral changes only).
