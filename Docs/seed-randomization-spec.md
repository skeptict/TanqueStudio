# Seed Randomization Redesign — Feature Branch Spec

**Status:** draft, not started · **Drafted:** 2026-06-10
**Goal:** eliminate the `-1` seed sentinel from the UI layer and reach Draw Things batch-seed parity in one pass.

---

## Motivation

The `-1` sentinel ("randomize each run") has caused one shipped crash (seed:-1 in PNG metadata SIGILLs Draw Things on paste — fixed 0.9.17) and required serialization floors in two places (`ImageStorageManager`, `DTConfigExporter`, 2026-06-10). DT's own UX has no sentinel: the seed field always holds a concrete value, a dice button rolls a new one, and batches derive per-image seeds deterministically from the base seed. Matching that removes the leak class entirely and gives reproducible batches.

## Prerequisite — empirical test (do FIRST)

DT's exact batch seed derivation is unknown. Before writing code:

1. In Draw Things: set a fixed seed (e.g. 1000), batch count 3, generate.
2. Read the three seeds DT records in its own metadata / project DB.
3. Determine the scheme: sequential +1? offset? hash? (Open Brain note 2026-05-24 left this open.)
4. Record the answer in this file and in Open Brain before implementation.

If the scheme is not simply derivable, fall back to: TS rolls a random base seed, then applies DT's observed derivation for the batch; whole-batch reproducibility from the base seed is the acceptance bar.

### Result — 2026-06-11

**DT derives per-image seeds using xorshift32, chained from the base seed.**

Empirical test: batch of 3, base seed 1000. Seeds recorded in each PNG's metadata:
- Image 0: 1000 (base seed)
- Image 1: 266172694 = xorshift32(1000)
- Image 2: 3204629577 = xorshift32(266172694)

Algorithm (Marsaglia xorshift32):
```swift
func xorshift32(_ x: UInt32) -> UInt32 {
    var x = x
    x ^= x << 13
    x ^= x >> 17
    x ^= x << 5
    return x
}
```

Each image in the batch uses a distinct seed; the full sequence is deterministically reproducible from the base seed. Note: the project DB (`tensorhistorynode`) stores only the base seed — per-image seeds are internal to DT's generation pipeline and only surface in each PNG's embedded metadata.

**Implementation:** In `generate()`, derive per-iteration seeds by chaining xorshift32 from `cfg.seed`. Each `iterCfg.seed` carries the concrete derived seed for that image (existing plumbing in `ImageStorageManager` already records it). Whole batch reproducible from base seed with randomize OFF.

## Design

### State
- `config.seed` (ported type, unchanged) always holds a concrete value `>= 0` after this change. The UI never writes -1.
- New `randomizeSeed: Bool` lives in `GenerateViewModel` with an `AppSettings` persistence proxy (`tanqueStudio.randomizeSeed`, default true) — NOT in `DrawThingsGenerationConfig` (ported file; no schema change).

### UI (GenerateLeftPanel)
- Seed row: numeric field (always shows the concrete seed) + dice button (`die.face.5` SF Symbol) that rolls `UInt32.random` immediately + "Randomize each run" toggle bound to `vm.randomizeSeed`.
- After every generation, the field shows the seed actually used for the LAST image of the batch (or the base seed — decide during implementation; display both if cheap).

### generate() (GenerateViewModel)
- If `randomizeSeed`: roll a new base seed at the start of the run, write it back to `config.seed` (visible in UI).
- Batch: derive per-iteration seeds from the base via the scheme determined in the prerequisite. Each `iterCfg` carries its concrete seed (existing 098c3b7 plumbing unchanged: iterCfg → gRPC + metadata writer).
- Whole batch reproducible: re-running with the same base seed and randomize OFF must reproduce the full set.

### Incoming -1 handling (all five config-application paths)
An incoming seed of -1 (or any negative) means "the source wanted randomize":
set `randomizeSeed = true` and roll a fresh concrete seed into `config.seed`.

Paths: `applyDTConfig` (custom_configs import) · `DTConfigExporter.mergeDTClipboard` (paste) · `applyMetadataToConfig` / Send Config (Actions tab) · DT Project Browser "Send to Generate" · `GalleryStripView`/immersive metadata loads (these load recorded seeds, always concrete — verify only).

### Serialization floors — KEEP
The floors in `ImageStorageManager` (buildDTMetadataJSON + encodeConfig) and `DTConfigExporter.encodeDTClipboard` stay as defense in depth, even though post-redesign nothing should produce a negative seed.

### StoryFlow
`StoryFlowEngine` merges seed from config variables and does NOT currently resolve negatives before generation (gRPC accepts -1 as server-side random, so no crash — but metadata for StoryFlow outputs then lacks the actual seed). In-scope decision: resolve negatives in `executeGenerate` with the same roll-and-record pattern so StoryFlow outputs are reproducible too.

## Out of scope
- Changing `DrawThingsGenerationConfig.seed` to `UInt32?` (ported type; Codable/FlatBuffer/UI blast radius not justified).
- Upstream DT report for the SIGILL (separate task, still open — see Open Brain 2026-05-24).

## Acceptance checklist
- [ ] No code path can place a negative seed in `config.seed`
- [ ] Dice button rolls visibly; toggle persists across launches
- [ ] Batch of N with randomize ON: N distinct seeds, all recorded in metadata, whole set reproducible from the base seed with randomize OFF
- [ ] Seeds match DT's derivation for the same base seed + batch count (parity test against DT itself)
- [ ] Importing/pasting a config with seed -1 enables randomize and shows a concrete seed
- [ ] grep audit: no remaining `seed = -1` / `seed < 0` writes outside the defensive floors
