# DT Metadata Protocol Parity — Implementation Spec

**Status:** ready to implement · **Drafted:** 2026-06-10 (Cowork session)
**Goal:** TS-written PNG metadata matches Draw Things' own format exactly: integer sampler/seedMode enums in the `v2` sub-object, no TS-only keys.

## Background

Open Brain 2026-05-24 (bisection session): DT writes `v2.sampler` and `v2.seedMode` as INTEGER enum raw values (e.g. `v2.sampler=17` for UniPC Trailing, `v2.seedMode=2` for Scale Alike), with the top-level `seed_mode` remaining a string. TS currently writes strings in v2 ("DPM++ SDE AYS", "Scale Alike") and also writes a top-level `"scale"` key that DT's own metadata lacks. Strings in v2 did NOT cause the paste crash (seed -1 did, fixed), but Ned wants protocol parity so TS PNGs are indistinguishable from DT's.

The authoritative enum tables are now in the codebase (post fe23a80):
- Sampler ordinal = index into `DrawThingsSampler.builtIn` (order invariant documented there; matches DT SamplerType: dpmpp2mkarras=0 … unipcays=18, tcdtrailing=19).
- SeedMode ordinal = index into `["Legacy", "Torch CPU Compatible", "Scale Alike", "Nvidia GPU Compatible"]` (matches DT SeedMode enum 0–3; same table as `DTConfigExporter.seedModes`).

## Changes

All in `ImageStorageManager.buildDTMetadataJSON` (NOT a ported file):

1. `v2["sampler"]`: write the integer ordinal — `DrawThingsSampler.builtIn.firstIndex { $0.name == config.sampler }`. If the name isn't found, OMIT the key (never guess).
2. `v2["seedMode"]`: write the integer ordinal from the seedModes table; omit if not found.
3. Remove the top-level `"scale"` key (DT's native format doesn't have it; CFG already lives in `v2.guidanceScale`). Keep top-level `"sampler"` and `"seed_mode"` AS STRINGS only if DT's own top-level format has them as strings — verify against a real DT PNG with exiftool before deciding (Open Brain note says top-level seed_mode stays a string in DT's format).
4. `encodeConfig` (configJSON for SwiftData) is UNCHANGED — the app's own gallery metadata path stays string-based.

Consider extracting the seedModes table to one shared location (it now exists in DTConfigExporter and GenerateLeftPanel.seedModes — verify) rather than adding a third copy.

## Must NOT change

- `PNGMetadataParser.swift` (ported): verify only — it already parses DT-native PNGs with integer v2 enums, so it must read the new TS output as-is. Confirm by code inspection, do not modify.
- `TSImage.configJSON` format and all gallery/metadata display paths.
- The seed serialization floor (omit when < 0) — keep.

## Acceptance checklist

- [ ] Generate → save → `exiftool -G1 -a -s` on the new PNG: v2.sampler and v2.seedMode are integers matching the chosen sampler/seedMode's DT ordinal; no top-level `scale`; seed present and positive
- [ ] Structure diff vs a genuine DT-generated PNG (Ned has DT-test.png in iCloud DT-stuff): same keys, same types, modulo expected value differences
- [ ] Copy new PNG in Finder → DT "Paste to" → Paste: no crash, config-load prompt appears, sampler and seed mode populate CORRECTLY in DT's UI
- [ ] TS gallery strip still shows full metadata for new images (configJSON path)
- [ ] Drag the new PNG back INTO TS canvas: PNGMetadataParser reads it (integer v2 path) and prompt/sampler populate
- [ ] Build clean; Completion Protocol per CLAUDE.md
