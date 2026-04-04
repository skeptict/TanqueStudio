---
name: dts-grpc-config-field
description: Guides adding a new configuration field to DrawThingsStudio's gRPC generation path end-to-end. Use when adding a new Draw Things parameter, exposing a new model option, adding a new generation setting, or wiring a new config value through the gRPC pipeline. Applies to "add X parameter", "expose the Y setting", "wire up Z to gRPC", "add support for new DT config field". Returns a pre-task contract, ordered implementation steps with FlatBuffer safety checks, and a verification protocol.
---

## Purpose

Adding a gRPC config field in DTS touches at least five files across the config model, FlatBuffer serialization, PNG metadata, and UI. Missing any step produces a silent failure — the field either doesn't reach Draw Things, doesn't survive a round-trip, or isn't displayed back to the user. The FlatBuffer `def:` gotcha has produced at least one confirmed silent bug (`resolutionDependentShift`). This skill makes every step explicit and non-skippable.

## Reasoning

The DTS gRPC config pipeline has a layered structure:
1. `DrawThingsGenerationConfig` (Swift struct — the canonical representation)
2. `DrawThingsGRPCClient.convertConfig()` (FlatBuffer serialization)
3. Draw Things receives and interprets the FlatBuffer blob
4. `PNGMetadataParser` reads the value back from stored image metadata
5. `DTImageInspectorMetadataView` displays it to the user

A field that's missing from step 2 never reaches DT. A field that's wrong in step 3 (FlatBuffer `def:` mismatch) silently uses the wrong value. A field missing from step 4 is lost when images are stored and reloaded. A field missing from step 5 is invisible to the user. All five steps are required.

## FlatBuffer Safety Protocol

Before writing any `fbb.add` call:

1. Find the field definition in `config_generated.swift`
2. Record the `def:` value specified in the generated code
3. Test what Draw Things reads when the field is absent (check DT source or test empirically)
4. If `def:` value ≠ read-side default: **this field has the `resolutionDependentShift` problem** — document it in Known Footguns in CLAUDE.md and add a comment above the `fbb.add` call

Required comment format above every new `fbb.add` call:
```swift
// FlatBuffer def: [value] | DT read-side default when absent: [value] | Safe to omit: [yes/no]
fbb.add(element: value, def: X)
```

## Pre-Task Contract

Before writing any code:

1. **Field name and type:** What is the new field called in `DrawThingsGenerationConfig` and what is its Swift type?
2. **FlatBuffer field:** What is the corresponding field name in `config_generated.swift`? What is its `def:` value?
3. **Read-side default:** What does Draw Things read when this field is absent from the FlatBuffer? (Check DT source or test empirically — do not assume it matches `def:`)
4. **Files to modify:** Confirm all five pipeline files are in scope.
5. **UI location:** Where will this field be displayed — left panel config, metadata tab, or both?

## Implementation Steps (in order — do not skip)

### Step 1: `DrawThingsProvider.swift`
Add the field to `DrawThingsGenerationConfig`. Include a doc comment explaining what the field controls and its valid range/values.

### Step 2: `DrawThingsGRPCClient.swift` — `convertConfig()`
Add the `fbb.add` call in `convertConfig()`. Add the required safety comment above it (see FlatBuffer Safety Protocol). If the field has a `def:` mismatch with the read-side default, document it in CLAUDE.md Known Footguns before proceeding.

### Step 3: `PNGMetadataParser.swift`
Add parsing for the field in the `dts_metadata` iTXt chunk reader. Use `extractDouble(_:key:)` for numeric fields. Confirm the JSON key matches what `ImageStorageManager` writes.

### Step 4: `DTImageInspectorMetadataView.swift`
Add the field to the metadata display grid. Use existing grid row pattern for consistency.

### Step 5 (if applicable): `ImageGenerationView.swift` / left panel config
Add UI control if this field is user-configurable. Use `NeuTypography` tokens and `NeumorphicStyle` modifiers. Follow dts-ui-change skill for any layout additions.

## Verification Protocol

After all steps are complete:

```
## gRPC Config Field Verification: [field name]

### FlatBuffer audit
- def: value: [value]
- DT read-side default: [value]
- Mismatch documented: yes / N/A
- Safety comment added: yes

### Round-trip test
- Generated image with field set to [non-default value]
- Confirmed DT received correct value: yes / not verifiable
- Confirmed value stored in PNG metadata: yes
- Confirmed value parsed back from PNG: yes
- Confirmed value displayed in Inspector Metadata tab: yes

### Build status
- BUILD SUCCEEDED: yes
- New errors: NONE / [list]

### Result
PASS / FAIL — [details]
```

## Edge Cases

- If the FlatBuffer field doesn't exist yet in `config_generated.swift`, stop — it needs to be added to the proto definition and regenerated. Do not hand-write FlatBuffer field accessors.
- If the field is write-only (DT uses it but it's not stored in DTS-generated PNG metadata), skip Step 3 but document that decision explicitly.
- If the field requires UI but touches `GenerateWorkbenchView`, follow the dts-ui-change skill and declare the blast radius before proceeding.
