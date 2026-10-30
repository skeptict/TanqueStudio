# Tanque Studio 0.9.51 (draft)

## Style Browser: Show in Finder

A style's detail view has a new **Show in Finder** button, which opens Finder with that
preview's PNG selected. The previews live in folders named by ID inside Tanque Studio's own
Application Support folder, so finding one by hand was hard.

This matters most for Draw Things. Each preview carries its prompt and settings in Draw
Things' own format, but dragging an image onto Draw Things' canvas brings in the image only.
Draw Things loads embedded settings only when you open the file with **Select From Files**.
Show in Finder gets you to the file: drag it from Finder into that panel to jump straight to
it. The detail view's tooltip used to promise that dragging carried the settings; it now
says what actually happens.

**Verified in the app:** on a rendered card, Show in Finder opened the set's `images` folder
with that style's PNG selected.

## Notes

Test suite: 500 passed, 8 skipped, 0 failures.
