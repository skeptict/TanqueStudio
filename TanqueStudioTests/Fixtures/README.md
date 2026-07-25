# StoryFlow test fixtures

Drop real StoryFlow Editor project files (`.json`, as written by **[Save Project]**)
into this folder. The target uses an Xcode file-system–synchronized group, so any
file added here is picked up automatically — no pbxproj edit needed.

`StoryFlowProjectCodecTests.testFixturesSurviveFullRoundTrip` discovers every
bundled `.json` and asserts the round-trip contract from
`DrawThingsStudio/StoryFlowProjectCodec.swift`:

```
load → toWorkflow → toProject   ← item types and values must be identical
```

With no fixtures present the test calls `XCTSkip`, so a fresh clone stays green.

Real-world projects are the valuable part here — particularly ones containing
instruction types TanqueStudio cannot execute, since those exercise the
lossless-by-preservation rule (`.passthrough` steps must re-emit verbatim rather
than degrade into notes).

Fixtures must have a `.json` extension to be discovered. A file saved without one
(e.g. `LTX-2 config yeah`) needs renaming before it will run.
