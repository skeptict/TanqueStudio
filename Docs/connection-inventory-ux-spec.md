# Connection & Inventory UX — Implementation Spec

**Status:** ready to implement · **Drafted:** 2026-06-11 (Cowork session)
**Origin:** real failures hit while testing 0.9.18-era builds: a protected DT server and a stale model list produced three confusing dead-ends in one afternoon.

## 1. Shared secret entry (SettingsView + AppSettings)

DT displays its shared secret grouped with spaces ("8EA9 N6UM WYFM") but expects it WITHOUT spaces. Users will paste/type it verbatim with spaces and silently fail auth.

- Strip ALL whitespace in `AppSettings.dtSharedSecretOrNil` (the transport normalization point) so grouped secrets work no matter how they were entered. Keep the stored string as typed.
- Add a reveal toggle (eye icon) next to the Shared Secret SecureField: pressed = plain TextField showing the value, released = SecureField. Standard show/hide pattern, no third-party code.
- Optional polish: small caption under the field — "Spaces are ignored."

## 2. Model list lifecycle (GenerateViewModel + GenerateLeftPanel)

`loadAssets()` runs once per Generate-view appearance; on failure `vm.models` stays empty with no retry path and the picker chevron is silently `.disabled`.

- Add a refresh affordance: small `arrow.clockwise` button next to the model field, visible at least when `vm.models.isEmpty`; calls `loadAssets()`.
- When `vm.models.isEmpty`, the chevron area should communicate state instead of being silently disabled — e.g. tooltip/help text "No models — check Draw Things connection, then refresh."
- Re-fetch automatically after a successful Settings → Test Connection (that already proves DT is reachable).

## 3. "Returned no image" banner wording (GenerateViewModel)

The 0-image case has at least three real causes observed in practice: model not downloaded in DT, sampler/schedule unsupported for the model (SD3 + AYS), and shared-secret auth rejection. Update the error string to name all three:
"Draw Things returned no image. Possible causes: the model isn't downloaded in Draw Things, the sampler isn't supported by this model, or the server's shared secret doesn't match (Settings → Draw Things)."

## 4. Imported-config model check (DTConfigImporter call sites / GenerateViewModel)

Applying an imported config can set `config.model` to a model DT doesn't have (the config import path bypasses the picker). When `vm.models` is non-empty and the applied model is not in it, show a non-blocking warning toast: "Model '<name>' isn't in Draw Things' model list."

## 5. Known limitation — document, do NOT code around

With a shared secret enabled on the DT server, model/LoRA listing may fail even with the correct secret configured in TS: the upstream library's `echo()` (which carries the inventory) takes no sharedSecret parameter — only `generateImage` does. Empirically observed 2026-06-11: secret ON → echo returns no usable files/override → empty picker, while authenticated generation succeeds.

- Add a "Known limitations" note to README and a line in CLAUDE.md's connectivity section.
- Separate task (not this branch): upstream issue/PR on euphoriacyberware-ai/DT-gRPC-Swift-Client to support sharedSecret on echo, if DT's proto allows it.

## 6. Finder/Spotlight param summary (ImageStorageManager) — rider item

DT appends a human-readable parameter summary to its image Description ("Steps: 8, Sampler: UniPC Trailing, Guidance Scale: 1.0, Seed: …, Size: …, Model: …, Strength: …, Seed Mode: …, Shift: …"); TS writes only the prompt to IPTC Caption-Abstract, so Finder's Get Info shows no params. Append the same summary format after the prompt in `writePNGData`'s IPTC block. Same field order as DT's example. (Logged 2026-06-11 from Ned's Finder comparison.)

## Constraints

- No ported files need modification; everything lives in SettingsView, AppSettings, GenerateViewModel, GenerateLeftPanel. If anything seems to require a ported-file change, stop and ask.
- Branch: feature/connection-inventory-ux, after feature/dt-metadata-parity merges.

## Acceptance checklist

- [ ] Secret pasted WITH spaces authenticates successfully (normalization proven against live DT with secret enabled)
- [ ] Eye toggle reveals/hides the secret
- [ ] With DT stopped at TS launch: picker shows guidance, refresh button appears; start DT → refresh → list populates without relaunch
- [ ] Successful Test Connection repopulates an empty model list
- [ ] Applying an imported config with an unknown model shows the warning toast
- [ ] New banner text appears on a 0-image generation
- [ ] README + CLAUDE.md note the echo/secret inventory limitation
- [ ] Build clean; Completion Protocol per CLAUDE.md
