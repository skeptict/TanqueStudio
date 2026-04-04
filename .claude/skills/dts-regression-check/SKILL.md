---
name: dts-regression-check
description: Runs the DrawThingsStudio regression verification protocol before any task is declared complete. Use when completing any DTS implementation task, before declaring done, before committing, after fixing a bug, or when asked to verify the app is stable. Applies to "verify this is done", "check for regressions", "is this safe to commit", "run the completion checklist", "confirm this builds". Returns a structured pass/fail report with explicit verification of all critical paths.
---

## Purpose

This skill enforces a non-negotiable verification gate before any DrawThingsStudio task is declared complete. "Probably works" is not a passing result. Each item below must be explicitly checked and reported.

## Reasoning

DTS has a history of regressions introduced by changes that passed a build check but broke adjacent behavior — panel snap-back, layout collapse, metadata not parsing, LoRA dropdowns off-screen. These failures have a common cause: declaring done after confirming the build passes without verifying actual runtime behavior. This skill closes that gap.

## Output Format

Return a report with this exact structure:

```
## DTS Regression Check

### Pre-commit scope audit
- Files modified: [list]
- Files in original pre-task contract: [list]
- Scope violations (files touched but not in contract): [list or NONE]

### Build status
- Build result: SUCCEEDED / FAILED
- New errors introduced: [list or NONE]
- New warnings introduced: [list or NONE]

### Critical path verification
- [ ] Sidebar loads, all items present and navigable
- [ ] Generate Image view renders without layout errors
- [ ] Image Inspector Balanced state: sidebar + stage + right panel all visible
- [ ] Image Inspector Focus state: icon rails only, stage fills correctly
- [ ] Image Inspector Immersive state: stage fills window, filmstrip visible
- [ ] No panel snap-back on drag resize
- [ ] LoRA dropdown opens above content, not clipped off-screen

### Task-specific verification
[State what behavior was changed and how it was verified — not "should work" but what was actually observed]

### Result
PASS — safe to commit
FAIL — [specific item that failed, what needs fixing]
```

## Edge Cases

- If a build fails, stop here. Do not attempt to verify runtime behavior on a broken build.
- If scope violations are found (files touched outside the pre-task contract), flag them explicitly in the report. Do not silently omit them.
- If a critical path item cannot be verified (e.g., a view requires a running Draw Things instance), state that explicitly rather than marking it passed.
- Intermittent failures in the 10 known flaky UI tests do not count as regressions.

## Example — Passing Report

```
## DTS Regression Check

### Pre-commit scope audit
- Files modified: GenerateWorkbenchView.swift, ImageGenerationViewModel.swift
- Files in original pre-task contract: GenerateWorkbenchView.swift, ImageGenerationViewModel.swift
- Scope violations: NONE

### Build status
- Build result: SUCCEEDED
- New errors: NONE
- New warnings: NONE

### Critical path verification
- [x] Sidebar loads, all items present
- [x] Generate Image renders without layout errors
- [x] Inspector Balanced state correct
- [x] Inspector Focus state correct
- [x] Inspector Immersive state correct
- [x] Panel drag stable, no snap-back
- [x] LoRA dropdown positions correctly

### Task-specific verification
Added SSS field to left panel config. Verified: SSS slider appears in left panel, value persists after app restart, value is included in gRPC config payload (confirmed via Xcode console log showing fbb field written).

### Result
PASS — safe to commit
```
