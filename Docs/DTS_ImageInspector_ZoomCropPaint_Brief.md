# DrawThingsStudio — Image Inspector: Zoom, Crop & Inpainting Mask
## Claude Code Implementation Brief

---

## Overview

This brief adds three interactive image manipulation features to the Image Inspector's stage area:

1. **Zoom and pan** — examine any part of the image closely
2. **Crop** — select a region and save/export/send it
3. **Inpainting mask painter** — paint a mask over the image and send it to Draw Things for inpainting

These are additive features on top of the existing three-state layout. The stage view gains a mode system: **View** (default), **Crop**, and **Paint**. Only one mode is active at a time.

All three features are macOS 14+ compatible. Use `#available` checks for any newer APIs.

---

## Stage Mode System

Add a `StageMode` enum at module scope in `ImageInspectorViewModel.swift`:

```swift
enum StageMode {
    case view      // default — zoom/pan only
    case crop      // drag to select a crop region
    case paint     // inpainting mask brush
}
```

Store `@Published var stageMode: StageMode = .view` in `ImageInspectorViewModel`.

When the selected image changes, reset to `.view` mode and clear any crop selection or paint mask.

### Stage Toolbar (updated)

The existing stage toolbar (top-right overlay) gains two toggle buttons alongside the existing Compare and Full buttons:

- **Crop** — scissors SF Symbol (`crop`), toggles `.crop` mode. Active state: blue tint background.
- **Paint** — paintbrush SF Symbol (`paintbrush`), toggles `.paint` mode. Active state: blue tint background.

Switching modes resets any in-progress crop selection or paint stroke (with a confirmation alert if work would be lost — "Discard crop selection?" / "Discard mask?").

---

## Feature 1: Zoom and Pan

### Behavior
- **Scroll wheel / trackpad scroll**: zoom in/out, centered on cursor position
- **Pinch gesture** (`MagnificationGesture`): zoom in/out
- **Drag** (when zoomed in): pan the image
- **Double-click**: reset to fit (zoom = 1.0, offset = .zero)
- Minimum zoom: 1.0 (fit). Maximum zoom: 8.0.
- Zoom and pan state is ephemeral — resets when a new image is selected.

### Implementation
Add to the stage view:

```swift
@State private var zoomScale: CGFloat = 1.0
@State private var panOffset: CGSize = .zero
@State private var lastPanOffset: CGSize = .zero
```

Apply to the image:
```swift
image
    .scaleEffect(zoomScale)
    .offset(panOffset)
    .gesture(MagnificationGesture()
        .onChanged { value in zoomScale = max(1.0, min(8.0, value)) }
    )
    .gesture(DragGesture()
        .onChanged { value in
            guard zoomScale > 1.0 else { return }
            panOffset = CGSize(
                width: lastPanOffset.width + value.translation.width,
                height: lastPanOffset.height + value.translation.height
            )
        }
        .onEnded { _ in lastPanOffset = panOffset }
    )
    .onTapGesture(count: 2) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            zoomScale = 1.0
            panOffset = .zero
            lastPanOffset = .zero
        }
    }
```

Add scroll wheel zoom via `NSScrollView` wrapping or `.onScrollWheel` modifier if available on macOS 14. On scroll: `zoomScale = max(1.0, min(8.0, zoomScale + delta * 0.05))`, centered on cursor.

When zoom resets (new image selected or double-click), animate with `.spring(response: 0.3, dampingFraction: 0.8)`.

### Zoom indicator
When `zoomScale > 1.0`, show a small overlay in the bottom-right of the stage (above the filename bar):
- Text: e.g. "2.4×" — 11pt, white 70% opacity, on dark scrim pill
- Fades out 1.5 seconds after the last zoom gesture

---

## Feature 2: Crop

### Entering crop mode
Tapping the Crop toolbar button sets `stageMode = .crop`. The cursor changes to crosshair.

### Selection interaction
In crop mode, drag over the image to draw a selection rectangle:
- Selection rect is drawn as a white/blue dashed border with a semi-transparent fill (`Color.white.opacity(0.15)`)
- Corner handles (8×8pt white squares) allow resizing after initial drag
- The selection rect is constrained to the image bounds (not the full stage area)
- Store selection in image-coordinate space (0.0–1.0 normalized), not screen points, so it's resolution-independent

```swift
@State private var cropSelection: CGRect? = nil  // normalized 0–1 in image space
```

### Crop confirmation UI
When a selection exists, show a confirmation bar at the bottom of the stage (above the filename bar), replacing it temporarily:

```
[ Save to Inspector ]  [ Export to File ]  [ Send to Generate ]  [ Cancel ]
```

Button behaviors:

**Save to Inspector:**
- Crop the full-resolution PNG to the selected region
- Create a new `PersistedInspectorEntry` with:
  - New UUID
  - Cropped PNG written to `InspectorHistory/<newUUID>.png`
  - Same metadata as parent (prompt, config, etc.)
  - `sourceURL` set to `nil`
  - Add a `cropNote` string to the JSON sidecar: `"Cropped from <parentFilename>"`
- Add to the top of the Inspector collection
- Reset crop mode, show brief success feedback ("Saved to Inspector")

**Export to File:**
- `NSSavePanel` with default filename `<originalName>_crop.png`
- Write cropped PNG to chosen location
- Reset crop mode

**Send to Generate:**
- Crop the full-resolution PNG to selection
- Set the cropped image as the i2i source image in `ImageGenerationViewModel`
- Navigate to the Generate Image tab
- Reset crop mode

**Cancel:**
- Clear `cropSelection`, stay in crop mode (user can draw a new selection)
- Tapping the Crop toolbar button again exits crop mode entirely

### Image cropping utility
Add a helper in `ImageInspectorViewModel`:

```swift
func cropImage(_ image: NSImage, to normalizedRect: CGRect) -> NSImage? {
    let size = image.size
    let pixelRect = CGRect(
        x: normalizedRect.origin.x * size.width,
        y: normalizedRect.origin.y * size.height,
        width: normalizedRect.width * size.width,
        height: normalizedRect.height * size.height
    )
    // Use CGImage cropping, return as NSImage
}
```

---

## Feature 3: Inpainting Mask Painter

### Entering paint mode
Tapping the Paint toolbar button sets `stageMode = .paint`. A brush size slider appears in a small overlay at the bottom-left of the stage.

### Mask canvas
The mask is a separate full-resolution bitmap rendered as an overlay on the image:
- Mask background: fully transparent (unpainted areas)
- Painted areas: white at 70% opacity in the overlay (so the user can see both the image and what they've masked)
- The actual mask sent to Draw Things is binary: white where painted, black elsewhere

```swift
@State private var maskImage: NSImage? = nil  // full-resolution mask bitmap
```

Initialize `maskImage` as a black-filled bitmap at the same resolution as the selected image when paint mode is entered.

### Brush interaction
- **Drag**: paint white onto the mask at brush size
- **Option + drag** (or toggle eraser button): erase (paint black) to correct mistakes
- Brush is circular, soft edge (use `CGContext` with shadow/blur for soft brush feel, or keep hard-edge for simplicity — hard-edge is fine for v1)
- Brush size: 10–200pt, controlled by a slider overlay at bottom-left of stage
- Brush preview: show a circle outline following the cursor in paint mode

### Paint mode toolbar overlay
Small panel overlaid at bottom-left of stage (above the filename bar):
```
Brush: [——●——] 40pt    [ Eraser toggle ]    [ Clear mask ]
```

### Mask confirmation UI
When any painting has been done, show the confirmation bar at the bottom:

```
[ Send to Draw Things ]  [ Clear ]  [ Cancel ]
```

**Send to Draw Things:**
- Resize the mask bitmap to match the image dimensions if needed
- Invert if necessary (Draw Things expects white = inpaint region, black = preserve)
- Call the existing gRPC client's `generateImage` with:
  - `sourceImage`: the current full-resolution image
  - `mask`: the painted mask bitmap
  - All existing config values from the selected image's metadata
- Navigate to Generate Image tab to show progress
- Reset paint mode

**Clear:**
- Fill mask with black (reset to unpainted state)
- Stay in paint mode

**Cancel:**
- Discard mask with confirmation alert: "Discard mask painting?"
- Return to view mode

### Mask rendering
Render the mask as an overlay using `Canvas` or a `NSView`-backed drawing surface:

```swift
// Overlay on stage image
ZStack {
    imageView
    maskOverlayView  // white painted regions at 70% opacity, only visible in paint mode
}
```

The mask overlay should respect the current zoom and pan state — it must be aligned with the image at all zoom levels.

---

## Actions Tab: DT Layer Stub

In `DTImageInspectorActionsView.swift`, add a disabled section below the existing "Send to Draw Things" button:

```
Send to canvas layer / moodboard
──────────────────────────────────────────
[  Moodboard  ]  [  Canvas layer  ]
```

Both buttons are disabled (`.disabled(true)`) with a caption below:
- "Requires future Draw Things API support"

This surfaces the affordance for when the Draw Things gRPC API adds layer targeting, without implying it works today.

---

## File Scope

Files to modify:
- `ImageInspectorView.swift` — stage mode toolbar buttons, crop selection overlay, mask overlay, zoom/pan gestures, confirmation bars
- `ImageInspectorViewModel.swift` — `StageMode` enum, crop/mask state, `cropImage()` helper, `sendMaskToDrawThings()` method
- `DTImageInspectorActionsView.swift` — add disabled DT layer stub section

No new files required.

---

## Implementation Order

1. **Zoom and pan** — purely additive, no mode switching needed, lowest risk
2. **Stage mode system** — add `StageMode` enum and toolbar buttons, no behavior yet
3. **Crop** — selection rect, confirmation bar, three save actions
4. **Inpainting mask** — brush painting, mask overlay, send to Draw Things

Build and confirm after each step.

---

## Out of Scope

- StoryFlow / JSON export
- Canvas layer / moodboard targeting (stubbed UI only)
- Soft-edge brush (hard-edge is fine for v1)
- Multiple mask layers
- Undo/redo for brush strokes (v2)
- Crop aspect ratio lock (v2)
