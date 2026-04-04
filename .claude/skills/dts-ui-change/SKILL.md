---
name: dts-ui-change
description: Guides safe UI modifications in DrawThingsStudio SwiftUI views. Use when adding UI elements, modifying layouts, fixing visual bugs, adjusting panels, or changing any SwiftUI view in DTS. Applies to "add a button to", "fix the layout of", "change how X looks", "add a row to the config panel", "fix the dropdown", "adjust the panel width", "modify the sidebar". Returns a pre-task contract, implementation approach, and verification checklist tailored to the specific change.
---

## Purpose

UI changes in DTS have historically introduced regressions through three mechanisms: modifying layout containers instead of adding isolated subviews, using GeometryReader where a simpler approach exists, and implementing drag gestures incorrectly. This skill encodes the safe path for each class of UI change.

## Reasoning

Before touching any DTS view, read the full file. DTS views are interconnected — `GenerateWorkbenchView` manages panel sizing, drag state, and popover anchoring in ways that aren't obvious from a partial read. Changes made from partial context reliably break something adjacent.

The design system is `NeumorphicStyle.swift`. All colors, modifiers, and typography tokens live there. Hardcoding values is always wrong and always creates inconsistency.

## Pre-Task Contract (always complete this first)

Before writing any code:

1. **Target file(s):** What view file(s) will be modified?
2. **Read status:** Confirm you have read the full target file, not just the relevant section.
3. **Change type:** Which category below applies?
4. **Adjacent views:** What other views render inside or alongside the target? List them.
5. **Layout container:** What is the immediate parent container of the new/changed element?
6. **High-risk files in scope:** Is this change touching `GenerateWorkbenchView`, `ImageInspectorView`, `ContentView`, or `NeumorphicStyle`? If yes, state blast radius.

## Change Categories and Safe Patterns

### Adding a new element to an existing view
- Add inside the nearest appropriate existing container — not around it, not as a new top-level sibling
- Use `NeuTypography` tokens for text (`NeumorphicStyle.swift`)
- Use `NeumorphicStyle` view modifiers for styling
- Do not introduce `GeometryReader` unless there is no other option — if you think you need it, stop and reconsider
- If adding to a `ScrollView`, verify the element doesn't overflow or clip at minimum and maximum content sizes

### Fixing a layout bug
- Read the full view before attempting a fix
- Identify the root cause before changing anything — layout bugs are usually a wrong constraint, not a missing one
- Prefer removing incorrect constraints over adding compensating ones
- Negative padding to fix alignment is a smell — find the actual cause
- If the bug involves a `GeometryReader`, the `GeometryReader` is probably the bug

### Adding or fixing a dropdown/popover
- Always use `.popover` on the trigger element — it auto-positions away from screen edges
- Never use inline `ScrollView` expansion for dropdowns — they don't reposition and will clip at screen edges
- The LoRA add dropdown (v0.9.2) is the reference implementation for this pattern

### Panel resize / drag gesture
- Capture `dragStart` once per gesture using an `isDragging` flag
- Do not check `translation.width == 0` to detect gesture start — this causes snap-back
- Persist panel width to `UserDefaults` with a key scoped to the panel name
- Clamp width to `[minWidth, maxWidth]` on every drag update
- The v0.9.2 panel drag fix is the reference implementation

### Modifying `NeumorphicStyle.swift`
- This is a Hard Stop — confirm with user before proceeding
- Changes here affect every view in the app
- When adding a new token, check all existing uses of nearby tokens to ensure visual consistency

## Output Format

### On receiving a UI change request, output:

```
## DTS UI Change Plan

### Pre-task contract
- Target file(s): [files]
- Full file read: confirmed / [why not]
- Change type: [category from above]
- Adjacent views: [list]
- Layout container for change: [container]
- High-risk files: [list or NONE]
- Blast radius: [description or N/A]
- Files I will NOT touch: [list]

### Approach
[2-4 sentences describing the implementation approach and why it's safe]

### Verification steps after implementation
- [ ] Build succeeds with no new errors
- [ ] [Specific visual behavior to verify for this change]
- [ ] Existing adjacent layout unchanged
- [ ] [Any layout states that need checking — e.g., all three Inspector states]
```

### After implementation, output the dts-regression-check report.

## Edge Cases

- If the request is ambiguous about where in a view the change should go, ask before opening any file.
- If implementing the change requires touching a Hard Stop file, stop and ask the user.
- If you find a pre-existing bug while reading the target file, note it but do not fix it without explicit instruction — scope creep is how regressions get introduced.
