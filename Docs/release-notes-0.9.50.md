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
