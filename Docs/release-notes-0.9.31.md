# v0.9.31

A fix release on top of 0.9.30. Two of the four fixes close gaps that 0.9.30's own notes
described as known.

## Render dimensions match the image you get

**Draw Things silently floors render width and height to a multiple of 64.** Ask for
700×500 and it renders 640×448. Tanque Studio didn't know that, so it sent 700×500, got a
640×448 image back, and saved 700×500 in the metadata beside it — a stored size that didn't
describe its own PNG. Since the reason we store a config at all is to make a render
reproducible, that defeated the point.

Dimensions are now floored before the request goes out, everywhere a render starts: both
Generate paths and StoryFlow. In practice you'll see the width/height fields snap when you
press Generate — type 700×500 and they become 640×448, which is what was always going to be
rendered. The gallery record now agrees with the image.

Note it's a **floor, not a rounding**: 700 becomes 640, not 704. That matches Draw Things.
One deliberate difference — Draw Things' own arithmetic turns any dimension under 64 into
zero, and we clamp to 64 instead.

## `size` and `adaptSize` re-frame the canvas

*This closes a known gap from 0.9.30.*

Both instructions set the dimensions for the next render, and those were always correct on
the wire. But the canvas image kept its old size, so following one with an img2img render
below full strength gave you the old dimensions back — Draw Things sizes a sub-strength
img2img to its source. At the default strength of 1.0 it was already correct, which is why
it went unnoticed.

The canvas is now trimmed to the new dimensions, as a **centred crop**. It only ever trims,
never grows: enlarging a canvas in Draw Things reveals empty space, and padding an img2img
source with invented pixels is worse than leaving that axis alone.

## Settings is readable

The Settings screen painted itself in the dark palette while sitting inside the app's light
shell, so every control the system draws for itself resolved for the wrong scheme and
disappeared — Shared Secret, API Key, both Test Connection buttons, both Browse buttons were
invisible. Settings is now on the same paper palette as the rest of the app.

This affected both places Settings appears: the Dashboard page and the ⌘, window.

## Opening an output folder in Finder works

Clicking StoryFlow's output-folder button failed with *"Tanque Studio does not have
permission to open …"* whenever your image folder lived outside the app's container. Writing
to that folder always worked, which is what made it look like a Finder quirk rather than our
bug — only the open-in-Finder buttons were missing the permission claim. Fixed there and in
the Generate panel's LLM operations folder, which had the same fault.

## Known gaps

- The ⌘, Settings window paints its own background in the margins either side of the
  settings column, and those stay system white. Cosmetic; the Dashboard's Settings page is
  unaffected.
- The remaining passthrough instructions (mask, depth and pose operations, and the canvas
  operations Draw Things performs locally) are still preserved on save but not executed. A
  run says which ones it will skip, and whether skipping them changes the image.
- Clip playback decodes frames and shows them in sequence rather than assembling a movie.
