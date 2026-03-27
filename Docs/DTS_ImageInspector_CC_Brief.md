# DrawThingsStudio — Image Inspector Redesign
## Claude Code Implementation Brief

---

## Overview

This brief covers a redesign of the **Image Inspector** view in DrawThingsStudio. The goal is to transform it from a fixed three-panel layout into a flexible, image-first workbench that serves both browsing and research. The inspector handles native Draw Things images as well as externally imported images (CivitAI, DeviantArt, arbitrary sources), and connects to local LLM services for vision analysis and prompt assistance.

All implementation targets **macOS 14** minimum deployment. Use `#available` checks for any APIs newer than macOS 14. SwiftUI throughout.

---

## Design Philosophy

- **The image dominates.** The selected image is always the primary element. Everything else is context.
- **Warmth over sterility.** Slightly warm neutral surfaces, generous spacing, native macOS materials where appropriate.
- **Depth on demand.** The UI is clean at rest; richness is available when the user leans in.
- **Contextual intelligence.** Panels and suggestions adapt based on what metadata is available for the selected image.

---

## Layout: Three-State System

The inspector has three layout states. The user cycles through them by **clicking the image** (the primary interaction) or using the mode pills in the toolbar. State persists per session.

### State 1: Balanced (default)
```
┌─────────────┬──────────────────────┬──────────────┐
│  Collection │                      │  Right panel │
│  sidebar    │    Image stage       │  (300pt)     │
│  (200pt)    │                      │              │
│             │                      │              │
├─────────────┴──────────────────────┴──────────────┤
│  Filmstrip (104pt tall, full width)                │
└────────────────────────────────────────────────────┘
```

### State 2: Focus
```
┌──────┬──────────────────────────────────┬──────┐
│ Rail │                                  │ Rail │
│(48pt)│        Image stage               │(44pt)│
│      │                                  │      │
├──────┴──────────────────────────────────┴──────┤
│  Filmstrip                                      │
└─────────────────────────────────────────────────┘
```
- Left rail: small thumbnails (32×32pt) with source indicator dots, plus import button
- Right rail: icon buttons for Metadata / Assist / Actions tabs

### State 3: Immersive
```
┌──────────────────────────────────────────────────┐
│                  Image stage                     │
│                  (full width)                    │
├──────────────────────────────────────────────────┤
│  Filmstrip                                       │
└──────────────────────────────────────────────────┘
```
- Both sidebars hidden entirely
- Filmstrip remains visible (navigation is essential even in immersive mode)

### Transition Animation
Use `withAnimation(.spring(response: 0.35, dampingFraction: 0.82))` when switching states. Animate the column widths via a geometry-driven approach — `GeometryReader` or `HStack` with explicit frame widths driven by the state enum. Do not use sheet/overlay transitions for this; it should feel like the layout breathes, not navigates.

### State Indicator
Show a subtle overlay label on the image stage (bottom-left, inside the stage, on a dark scrim) indicating the current state and the click affordance:
- Balanced: "Balanced · click to expand"
- Focus: "Focus · click for immersive"  
- Immersive: "Immersive · click to restore"

Fade this out after 2 seconds of inactivity. Show it again on hover.

---

## Collection Sidebar (Balanced state)

### Header
- Title: "Collection" (10pt, uppercase, tertiary color)
- Import button (top-right): opens a file picker or URL import sheet (see Import section)

### Source Filter Tabs
Three tabs: **All · DT · Imported**
- Filters the grid by image source
- "DT" = images from Draw Things SQLite databases
- "Imported" = manually added images from external sources

### Thumbnail Grid
- 3-column grid in balanced state
- Each thumbnail is square, aspect-ratio-filled (`aspectRatio(1, contentMode: .fill)`)
- 4pt gap between thumbnails
- Selected thumbnail: 2pt blue outline (`Color.accentColor`)
- Source indicator: 6×6pt filled circle, bottom-left of each thumbnail
  - Green (`#28C840`): Draw Things source
  - Amber (`#FFBD2E`): CivitAI
  - Gray (`#888780`): other external source
- Hover: subtle scale(1.03) with spring animation

### Rail (Focus state)
- 32×32pt thumbnails, same source dots
- Import button at top as a `+` icon button (28×28pt, bordered)
- Scroll vertically

---

## Image Stage

### Appearance
- Background: `Color(NSColor.black)` — the stage is always dark regardless of app theme
- Image displayed with `resizable().scaledToFit()`, centered
- The image should fill as much of the stage as possible while maintaining aspect ratio

### Stage Toolbar (top-right overlay)
Small floating buttons on a semi-transparent dark background:
- **Compare** — placeholder for future side-by-side comparison
- **↗ Full** — opens the image in a full-screen `NSPanel` or QuickLook

### Stage Footer (bottom overlay)
Semi-transparent dark scrim across the full width:
- Source badge (green/gray pill): "Draw Things" or "Imported"
- Filename (truncated with ellipsis)
- Dimensions (e.g., "960 × 1728")

### Click Behavior
Tapping the image cycles: Balanced → Focus → Immersive → Balanced.
The click target is the entire stage area, not just the image rect.

---

## Filmstrip

Persistent across all three states. Positioned at the bottom, 104pt tall.

### Structure
```
[Siblings label] [thumb] [thumb] [thumb] [divider] [History label] [thumb] [thumb] ...
```

- **Siblings**: other images generated with the same prompt (different seeds). Group them first.
- **History**: recent images from the collection, most recent first.
- Section labels: 10pt, uppercase, tertiary color, not scrollable (pinned left of their group)
- Divider: 0.5pt vertical line, 56pt tall, secondary border color
- Each thumbnail: 76×76pt, 7pt corner radius, 0.5pt border
- Selected/active thumbnail: 2pt blue border
- Caption overlay (bottom of thumb): filename truncated, 9pt, white 65% opacity on dark scrim
- Horizontal scroll, no snap

---

## Right Panel (Balanced state)

Three tabs: **Metadata · Assist · Actions**

In Focus state, these collapse to the right rail icon buttons. Tapping a rail icon expands back to Balanced state with that tab active.

---

### Tab 1: Metadata

Displays all available metadata for the selected image. Sections:

**Prompt** (if present)
- Label: "Prompt" (10pt uppercase tertiary)
- Value: scrollable text in a secondary background rounded rect, 11.5pt, 1.6 line height

**Negative Prompt** (if present)
- Same pattern as Prompt

**Configuration** (if present)
- 2-column grid of config cells
- Each cell: secondary background, 6pt radius, 8pt padding
- Cell label: 10pt tertiary
- Cell value: 12pt, weight 500
- Fields: Size, Steps, CFG, Sampler, Seed, Strength, Shift (show only fields that have values)

**Model** (if present)
- Same label/value pattern, 11pt mono or regular for the model name

If no metadata is present, show an empty state:
- Icon: a small document with a question mark (SF Symbol: `doc.questionmark` or similar)
- Text: "No metadata available" + "Use the Assist tab to analyze this image with vision AI"

---

### Tab 2: Assist

This is the core differentiating feature. See the full Assist Tab spec below.

---

### Tab 3: Actions

Vertical stack of action buttons. Show only actions relevant to the current image:

**Always available:**
- Copy image to clipboard
- Reveal in Finder
- Delete (destructive, with confirmation — existing pattern)
- Export / Save As

**When metadata is present:**
- Copy prompt to clipboard
- Copy full config as JSON

**Always available (DT connection):**
- **Send to Draw Things** — primary action button (blue, full width). Sends prompt + config values to the connected Draw Things instance via gRPC. If no DT connection is active, show a disabled state with "Connect to Draw Things in Preferences".

**Import source info** (read-only, for imported images):
- Source URL if available
- Import date

---

## Assist Tab — Full Spec

The Assist tab provides LLM-powered analysis and prompt assistance for any image, regardless of metadata availability. It uses vision-capable local LLM models (Ollama, LM Studio, MstyStudio).

### Context Badge
Top-right of the panel header, a small pill badge indicating available context:
- **"Prompt + vision"** (blue): image has a prompt in metadata → both enhance chips and vision chips available
- **"Vision only"** (gray): no prompt metadata → vision chips only

### Image Context Row
Below the header, a compact row showing:
- Thumbnail (44×44pt) of the current image
- Filename
- Source + dimensions + key config values (if available, e.g., "Draw Things · 960×1728 · DPM++ 2M · 8 steps")

### Suggestion Chips

Horizontally scrollable row of suggestion chips. Chips are contextual — show only relevant ones.

**Vision chips** (blue tint — always shown):
- "Describe this image"
- "How would I recreate this?"
- "Suggest a prompt for this style"
- "What model might have made this?"

**Enhance chips** (teal tint — only shown when prompt metadata is present):
- "Enhance this prompt"
- "Create a variation"
- "Change the style"

Tapping a chip populates the text input and immediately sends the request (no extra tap needed).

Chip styling:
- Vision chips: `#E6F1FB` background, `#185FA5` text, `#85B7EB` border (dark mode: `#042C53` / `#B5D4F4` / `#185FA5`)
- Enhance chips: `#E1F5EE` background, `#0F6E56` text, `#5DCAA5` border (dark mode: `#04342C` / `#9FE1CB` / `#0F6E56`)
- 16pt corner radius (pill shape), 4pt vertical / 10pt horizontal padding

### Conversation Area
A scrollable conversation history. Each turn:
- **User message**: right-aligned bubble, info background color (`Color(NSColor.systemBlue).opacity(0.12)`)
- **Assistant message**: left-aligned, secondary background, with a "role" label above in 10pt uppercase tertiary

Assistant responses that contain a generated/enhanced prompt render a special **Prompt Result Card** below the text:
```
┌─────────────────────────────────────┐
│ SUGGESTED PROMPT          (10pt)    │
│                                     │
│ [prompt text, 11.5pt, 1.6 lh]      │
│                                     │
│ [Use in Draw Things] [Copy] [Refine]│
└─────────────────────────────────────┘
```

Action buttons on the Prompt Result Card:
- **Use in Draw Things** (primary/blue): copies the prompt into the Generate Image prompt field. If config metadata is available, also pre-fills matching config values.
- **Copy**: copies prompt text to clipboard
- **Refine further**: appends the prompt as context in the input field with a "Refine this: …" prefix and focuses the input

### Empty State
When no conversation has started:
- Centered in the conversation area
- Icon: `wand.and.stars` SF Symbol, 28pt, tertiary color
- Text: "Ask about this image" (primary, 13pt)
- Subtext: "Vision analysis always available. Prompt enhancement available when metadata is present." (tertiary, 12pt, centered)

### Model Selector
Bottom of the panel, above the input area:
- Label: "Model" (10pt tertiary)
- Picker: shows available connected LLM services (Ollama, LM Studio, MstyStudio) and their loaded vision-capable models
- Persists selection in `UserDefaults`

### Input Area
- Multiline `TextEditor`, ~48pt tall, secondary background, 8pt radius
- Placeholder: "Ask about this image or prompt…" (vision+prompt) or "Ask about this image…" (vision only)
- Send button: blue, right of input, same height

### LLM Request Construction

When sending a request, always include the image as a vision input regardless of mode. Construct the system prompt contextually:

**Vision only mode:**
```
You are a helpful assistant for an AI image generation app. The user is showing you an image 
and wants help understanding or recreating it. Analyze the image visually. When suggesting 
prompts, format them as generation-ready text suitable for Stable Diffusion or Flux models.
```

**Prompt + vision mode:**
```
You are a helpful assistant for an AI image generation app. The user is showing you an image 
along with its original generation prompt: "[PROMPT]". You can both analyze the image visually 
and work with the existing prompt to enhance or vary it. When outputting an enhanced or new 
prompt, place it on its own line preceded by "PROMPT:" so it can be detected and displayed 
as a prompt card.
```

Detect `PROMPT:` prefix in responses to trigger the Prompt Result Card rendering.

---

## Import Flow

The Import button (sidebar header in Balanced, `+` icon in rail) opens a sheet with two options:

### Option 1: File Import
- Standard `NSOpenPanel` filtered to image types (png, jpg, jpeg, webp, tiff)
- On selection, copy the file to DTS's local image store
- Attempt to read EXIF/PNG metadata chunks for any embedded generation data
- Add to collection with source = "Imported", import date = now

### Option 2: URL Import  
- Text field for a URL
- On confirm, download the image
- Attempt metadata extraction
- Store source URL for display in Actions tab
- This is a future/placeholder feature — implement the UI shell but the actual download can be a stub that shows "URL import coming soon"

---

## Source Model

Each image in the collection has an associated source type. Define an enum:

```swift
enum DTImageSource {
    case drawThings(projectURL: URL)
    case civitai(sourceURL: URL?)
    case imported(sourceURL: URL?)
    case unknown
}
```

The source determines:
- The color of the source indicator dot
- The label in the stage footer badge
- Which chips appear in the Assist tab
- Available actions in the Actions tab

---

## Key Existing Patterns to Preserve

- **Deletion**: context menu + confirmation dialog pattern already implemented — keep as-is, surface in Actions tab
- **gRPC connection to Draw Things**: existing connection logic — the "Send to Draw Things" action should use this
- **SQLite reading via `DTProjectDatabase.swift`**: unchanged — the collection grid reads from the same source
- **LLM service connections** (Ollama, LM Studio, MstyStudio): existing — Assist tab model selector should enumerate available services from existing connection layer

---

## File Scope

Expected files affected or created:

- `DTProjectBrowserView.swift` — major refactor for three-state layout
- `DTProjectBrowserViewModel.swift` — add layout state enum, filmstrip data, import logic
- `DTImageInspectorAssistView.swift` — new file for Assist tab
- `DTImageInspectorMetadataView.swift` — extract/refactor from existing metadata panel
- `DTImageInspectorActionsView.swift` — new file for Actions tab
- `DTImageSource.swift` — new file for source enum
- `DTFilmstripView.swift` — new file for filmstrip component

---

## Implementation Order

Suggested sequence to avoid merge conflicts and build on stable foundations:

1. **Layout state system** — the three-state enum and animated column transitions in `DTProjectBrowserView`. Get the geometry right before filling in content.
2. **Collection sidebar refactor** — thumbnail grid with source indicators, filter tabs, rail variant.
3. **Filmstrip** — siblings + history, horizontal scroll, active state.
4. **Metadata tab refactor** — extract into `DTImageInspectorMetadataView`, clean up the existing layout.
5. **Actions tab** — straightforward list of buttons, wire up existing actions.
6. **Assist tab** — most complex, build last once the panel infrastructure is stable.

---

## Out of Scope for This Pass

- URL import (stub UI only)
- Compare mode (stub button only)  
- Workflow diagram panel (separate brief)
- Grid-only browse view (the filmstrip serves this role for now)
