# Tanque Studio 0.9.50 (draft)

## Render Queue keeps control of a run when you leave Labs

Fixes the known issue listed in 0.9.49. Leaving Labs while a Render Queue run was going
used to orphan it: the run kept rendering, but when you came back the queue showed it
stopped, **Pause** and **Stop** no longer reached it, **Run** started a second run alongside
the first, and the job in flight was reset to pending while it was still rendering. The
queue's controller now lives as long as the app does, as the Style Browser's always has,
so a run stays visible and controllable however you navigate.

**Verified in the app** (by Ned): a run started, left for the Dashboard and resumed in Labs
still showed as running, and Pause/Stop worked.

## Generate reopens where you left it

Generate used to start every launch from scratch: no model, 1024×1024, 8 steps. It now
remembers its whole configuration between launches — model, size, steps, sampler, guidance,
shift, LoRAs, hires fix, tiling and the rest — so the Focus Room reopens on the setup you
left it with. With **Randomize each run** on, a fresh seed is still rolled; with it off, your
seed comes back too. Prompts are not remembered.

## Labs remembers where you were

Labs used to reopen on StoryFlow every time, and the Style Browser's search and section
filter reset with it. Within a session, Labs now reopens on the tab you left, and the Style
Browser keeps its search, section and **Rendered only** filter.

## Style Browser: Cancel is the safe default

The confirmation shown before rendering more than 50 styles highlighted **Render** as the
default button, so pressing Return could start hours of rendering. **Cancel** is now the
default.

**Verified in the app:** the Generate model and canvas size came back after quitting and
relaunching; Labs reopened on Style Browser with a section filter and search intact after a
trip to the Dashboard; and the confirmation now shows Cancel as the default.
