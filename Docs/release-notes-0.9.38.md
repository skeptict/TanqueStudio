# Tanque Studio 0.9.38

Gallery maintenance, render diagnostics, and a hard-won correction to what the
app tells you when Draw Things returns nothing.

## Gallery maintenance

The filmstrip's new **⋯** button (top-right of the strip) opens a Gallery
Maintenance dialog with two actions:

- **Remove N Missing Entries** — drops gallery rows whose image file is no
  longer on disk. Nothing on disk is touched.
- **Delete All N Images** — clears the gallery and deletes the files.

This closes a real gap: the filmstrip is backed by database rows that cache
their own thumbnails, so deleting image files outside the app left the strip
looking completely intact, with no way to reconcile it from the UI.

### Three sandbox fixes found while building it

The app is sandboxed and the gallery folder normally sits **outside** its
container (`~/Desktop/…`), where `FileManager` quietly misreports:

- **Existence checks lied.** An unscoped `fileExists` returns `false` for files
  that are present, so a naive scan would have offered to delete rows for
  perfectly good images. A row is now counted missing only on a *verifiable*
  negative — checked under a live security-scoped grant, or inside the container
  where none is needed. Anything that cannot be verified is left alone.
- **Deletes silently did nothing.** An unscoped `removeItem` outside the
  container is a no-op under `try?`, so the row vanished while the file stayed.
  This also fixes the pre-existing per-image **Delete**, which had the same bug.
- **Clearing the gallery was one mis-click from Cancel.** It now sits behind a
  second confirmation and is no longer the styled-destructive default.

## Render stage tracing

`request_log.txt` now records the stage sequence Draw Things reports for each
render, with timings:

```
stages: textEncoding@388ms×37 → imageEncoding@6223ms×27 → sampling@10452ms×43
        → imageDecoding@17246ms×6  [total 18405ms]
```

The progress poller always saw every stage but discarded the ones it could not
turn into a percentage — text encoding, upscale, face restore — which are
exactly the ones that tell you where a render that produced no image actually
stopped. Draw Things registers nothing with the unified log, so the client is
the only readable vantage point on a failed render.

The gRPC client library's own logger is enabled too. Note it logs to os_log
under subsystem `com.drawthings.client` — **not** `com.drawthings.kit` as its
README states — and its messages are redacted for outside readers, so the
request log is the route to rely on.

## "Draw Things returned no image" now names the real cause

The old message listed three causes: missing model, unsupported sampler,
shared-secret mismatch. During a long investigation on 2026-08-04 **all three
were wrong**, and chasing them cost a full day.

The actual cause was a **stale Draw Things+ session**. With the server's Bridge
Mode on — its default — Draw Things routes renders through the DT+ account, and
a bad session there fails in exactly this shape: the call succeeds, zero images
come back, and no local render is attempted. Signing out of Draw Things+ and
back in cleared it.

That now leads the message, with the previous causes kept as secondary, and it
points at Draw Things' own window, which reports what it actually did.

> **Not visually confirmed.** This is a copy-only change with no logic touched,
> but the failure no longer reproduces on demand, so the new banner has not been
> seen rendering. If you hit it, the wording is what you should judge.

## Fixed

- A metadata-applier test had asserted *merge* semantics that 0.9.37 replaced
  with *refresh* semantics, and had been failing since. Rewritten to assert the
  real contract: fields the incoming metadata omits return to their defaults,
  while canvas size and the model survive. Unit suite: **250 executed, 6
  skipped, 0 failures.**

## Known issue, not fixed in this release

- **The window can occasionally become vertically unresizable in Generate.**
  Seen once, with the window's minimum height pinned far above the screen's, so
  there was no edge left to drag; a relaunch clears it. It has not reproduced
  since — not with every accordion section expanded, not with a large image
  loaded, not on a fresh launch — so there is no verified fix to ship. Ruled
  out: the Focus Room drawer, whose content is already inside a scroll view.
  If you hit it, note what was on screen at the time.

## Also worth knowing

Draw Things does emit useful diagnostics, but only to **stdout**, which is
discarded when the app is launched from Finder. Launching the binary from a
terminal captures its full generation log — including the line that names a
failed configuration. It registers nothing with the unified log, so `log show`
and Console are dead ends.
