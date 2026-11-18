# Tanque Studio 0.9.52

**Lay out comic pages.** Story Studio chapters now have **Pages**: pick a book format and page
templates, place your renders into panels, reframe them, and export pages, spreads, a vertical
scroll or a 16:9 web slideshow. Also: the Dashboard takes dropped images and has feature tiles,
and Labs has an experimental **Writing Desk** on macOS 15 and later.

> **Back up before you update.** This version updates Tanque Studio's storage (schema 4). The
> update only adds things and kept every project in testing, but **opening the same data with
> 0.9.51 or older afterwards may wipe it**. Quit Tanque Studio and copy its data folder
> (`~/Library/Containers/tanque.org.TanqueStudio/Data/Library/Application Support`) somewhere
> safe first. The app also tries to copy the store to a `StoreBackups` folder before migrating,
> but in testing that copy wasn't made, so don't rely on it.

## Story Studio: Pages

Each chapter in the outline has a **Pages** row above its scenes.

- **Book format** lives in **Project Info**: US comic portrait, 6×9 trade, Landscape album,
  Custom, or Vertical scroll (screen only), with bleed, safe margin, gutter and panel borders.
- **Add Page** offers the templates that suit the format: Splash, Three tiers, Two tiers,
  Grid 2×3, Inset, Tall strip, and a Panorama spread, plus landscape partners such as Wide
  splash. Templates are JSON files; **Reveal Templates Folder** shows where to add your own.
- **Placing images:** drag a scene from the outline onto a panel, drag a PNG or JPEG from
  Finder, or click or drag an image from the gallery tray. An image from outside the app is
  copied into your gallery and becomes a scene, with its embedded prompt as the scene's prompt.
  **Add Images as Scenes…** on a chapter does the same for a batch, in filename order, so files
  named `1.1`, `1.2`… become scenes 1.1, 1.2….
- **Framing:** each panel shows its scene's chosen take, cropped to the panel's shape. Double-click
  a panel (or **Reframe…** in the inspector) to zoom and pan. The inspector shows the take and
  crop sizes, what the panel exports at, its print resolution, and whether the image is sharp
  enough at screen size.
- **Re-render flag:** when a panel's shape differs from its image's by more than 15%, the panel
  is flagged so you know a render at the right shape would look better. Rendering into panels
  comes in a later version.
- **Switching format** offers to swap each page's template for one made for the new shape
  (Splash ↔ Wide splash and so on), shown before and after. Crops are recentred either way.

## Export and Showcase

**Export…** in the page editor writes PNG files or one PDF for the page, its spread, the
chapter or the whole book:

- **Pages:** 2400 px on the long side (US comic 1551 × 2400).
- **Facing spreads:** left and right pages side by side (3102 × 2400), as one image or split
  at the fold.
- **Vertical scroll:** one 1080 px column, cut into images no taller than 16,384 px, always
  between panels.
- **Panel by panel:** each panel on its own.
- **PDF:** one page per comic page at trim size; images keep their full pixels.

**Showcase** (the Pages | Showcase switch) turns a chapter into a 16:9 slideshow, one slide per
scene with an image, captioned with the scene's narrator and dialogue text. Reframe a slide like
a panel. **Export Showcase…** writes `index.html` and an `images` folder: open it in a browser
and use the arrow keys, Page Up/Down, Space, Home/End, a click or a swipe. Slides are never
enlarged, and the inspector warns about takes under 1280 px wide.

**Verified in the app:** a three-page chapter of real renders (Splash; Three tiers; a full-bleed
page with an inset), placed by Add Images as Scenes, scene drags and a Finder drop, with one
panel reframed; switching to Landscape album and back; page, spread, panel-by-panel and PDF
exports opened and measured; a Showcase export stepped through in a browser with the keyboard;
and everything still there after quitting and relaunching. **Not yet tried in the app:**
vertical-scroll export (covered by tests), the 6×9 trade and Custom formats, and Book scope
with more than one chapter.

## Dashboard: drop an image, feature tiles

Drop a PNG or JPEG on the Dashboard to open it in Generate with its embedded settings, the same
as a drop on Generate's canvas. A new **Features** row has tiles for the Project Browser, the
Style Browser and (on macOS 15+) the Writing Desk.

**Verified in the app:** the layout, the tiles, and dropping a PNG with A1111 metadata. **Not
yet tried:** a JPEG, a file with Draw Things metadata, and a drag straight from Finder.

## Labs: Writing Desk (experimental, macOS 15+)

A 3D writing den: type, and the words appear on the screen of a steampunk machine. Switch the
light between chiaroscuro, dusk and daylight, show a painted room, zoom in to focus, look
around, and save to text files. The city and shelves are images you can replace from its
Backdrops folder. The tab is hidden on macOS 14.

It's a spike, shared for fun and feedback. **Verified in the app:** typing, Save, New sheet,
the Finder buttons, Reload backdrops, Look around and the Sound toggle, at 100–115 fps on a
120 Hz display. Some later visual changes (the CRT on pistons, the painted room with real
paintings) were seen only in off-screen renders.

## Notes

Test suite: 588 passed, 8 skipped, 0 failures. New tests cover book formats and template geometry, crop maths,
export sizes for every layout (including where a long scroll is cut), PDF page sizes, drawing
of borders, gutters and bleed, and the Showcase page's escaping.
