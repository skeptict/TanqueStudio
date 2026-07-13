
# Handoff: Dashboard + Focus Rooms — Tanque Studio

## Overview

This is the finalized navigation/layout redesign for **Tanque Studio** (macOS SwiftUI
app): **Dashboard + Focus Rooms**. It was one of five layout concepts explored
(`design_handoff_layout_forks/`, `design_handoff_palette_stage/`) and is the one
selected to ship. This package supersedes those exploratory handoffs — build from
this one.

Replaces "always land on the same 4-pane Generate view" with a real home screen: a
Continue card for the last in-progress session, a system status card, a Quick Start
preset grid, a recent-generations strip, and mini summaries of Projects and Labs.
Clicking into Generate opens a full-bleed **Focus Room** — one big canvas + filmstrip
below it + a single accordion drawer on the right (not four stacked panels at once).

This is also the only concept in a light **"paper" theme** — see `colors_and_type.css`,
`[data-theme="paper"]`.

## About the Design Files

**`Tanque Studio.html`** is a **high-fidelity, fully-interactive design reference** —
not production code to port directly. Recreate it natively in SwiftUI, reusing all
existing business logic (`GenerateViewModel`, `DrawThingsGRPCClient`, `LLMService`,
`ImageStorageManager`, etc.) — only the view layer changes. Open it in a browser to
click through before starting: dashboard cards, breadcrumb + top nav, Quick Start
presets, Focus Room accordion drawer, and Generate's fake progress + toast all work.

**`colors_and_type.css`** is the canonical Tanque DS token reference (paper theme
block included). **`shared-data.js`** is a mock-data shape reference (models, LoRAs,
gallery items, DT projects, Labs steps) — reference the field shapes, don't port the
file itself.

## Fidelity

**High-fidelity.** Colors, spacing, type, and component shapes are intentional and
should be matched precisely. Typography is IBM Plex Mono (labels/controls) +
Atkinson Hyperlegible (prose).

## What Changed Since the Fork Exploration

- **Top nav fix:** the original fork prototype only exposed Projects via a card on
  the Dashboard, with no way back to it from Focus Room / Labs / Settings without
  returning home first (a teammate flagged this: "How do we access the project
  browser?"). Fixed by adding a persistent **Project Browser · Labs · Settings**
  nav group in the top bar, visible in every mode, alongside the breadcrumb. The
  wordmark also now jumps to Dashboard from anywhere. See `TopBar` in the HTML.

## Layout Structure

```
VStack(spacing: 0)
├── TopBar (56pt): wordmark (→ Dashboard), breadcrumb, persistent nav
│   (Project Browser / Labs / Settings), search field, connection dot
└── Content (mode-switched)
    ├── Dashboard
    │   ├── Continue card (thumbnail + last prompt + "Resume in Focus Room")
    │   ├── System card (DT connection, LLM assist, storage used, "Open Settings")
    │   ├── Quick Start grid (4 preset cards: Portrait / Landscape / Product Shot / Concept Art)
    │   ├── Recent Generations strip (horizontal scroll, click → Focus Room)
    │   └── two-column: Projects mini-list · Labs mini-list
    ├── Focus Room
    │   ├── Canvas (paper-toned dot grid, generated image or empty state)
    │   ├── Filmstrip (100pt, below canvas)
    │   └── Drawer (320pt, right side): Accordion sections — Prompt, Model, Parameters,
    │       LoRAs, img2img & Moodboard, Actions — plus pinned Generate button at bottom
    ├── Projects page (grid of DT Project cards)
    ├── Labs page (pill-tabs: StoryFlow / Story Studio / Workflow Builder)
    └── Settings page (grouped sections, same content as today)
```

## Key SwiftUI Notes

- **Top nav:** simple `HStack` of buttons next to the breadcrumb — `Project Browser`,
  `Labs` (with the same orange "Labs" badge used elsewhere), `Settings` — each always
  tappable regardless of current mode, with the active one tinted brass/accent. Don't
  gate this behind the breadcrumb, which only shows the current drill-down path.
- Breadcrumb: simple `HStack` of tappable segments for the *current* path (e.g.
  `Dashboard / Focus Room`); last segment is non-interactive.
- Dashboard is a new top-level view — build as `DashboardView`, composed of a reusable
  `Card` container (rounded 14pt, 1px border, subtle shadow) used for all four
  dashboard sections.
- Quick Start presets: static list of `(name, description, promptPreset, swatch)` —
  selecting one pre-fills prompt/model in a fresh session and jumps straight to Focus
  Room. Copy for these 4 presets is placeholder — confirm final wording with product
  before shipping.
- Accordion: use `DisclosureGroup` (SwiftUI's native accordion primitive) for each
  drawer section — maps ~1:1 to the prototype's custom accordion; prefer the system
  component over a custom re-implementation.
- Light theme: add a `paper` case to `TanqueDS` alongside existing dark tokens,
  reusing the `[data-theme="paper"]` values already in `colors_and_type.css` rather
  than re-deriving new ones.

### Colors (paper theme)

- Background: `#f0ebe0` / `#e8e0cc` / `#ddd2ba`
- Brass accent (darker, for contrast on light bg): `#8b4a25`
- Text: `#1a140c`, muted `#8a7458`, muted2 `#5c4a38`

## Interactions

| Action | Behavior |
|---|---|
| Click top-nav item (Project Browser / Labs / Settings) | Swaps whole content area to that page from anywhere |
| Click wordmark | Returns to Dashboard from anywhere |
| Click Continue card button | Jumps directly into Focus Room with that session's state restored |
| Click Quick Start card | Pre-fills prompt/model, jumps to Focus Room |
| Click recent-generation thumbnail | Opens Focus Room with that image loaded |
| Click Projects/Labs mini-list row | Navigates to the corresponding full page |
| Accordion section header | Expands/collapses; only the drawer scrolls, not the whole page |
| "Paste Config from DT" (Actions section) | Shows a small inline "✓ Applied" flash for ~1.4s |
| Generate | Pinned button at drawer bottom fills with progress; toast on completion; new image pulses into filmstrip |

## Files in This Package

| File | Purpose |
|------|---------|
| `Tanque Studio.html` | Full hi-fi interactive prototype — open in a browser to reference/click through |
| `colors_and_type.css` | Tanque DS token definitions incl. paper theme (source of truth) |
| `shared-data.js` | Mock data shape reference (models, LoRAs, gallery, projects, Labs steps) |
| `assets/icon_128x128.png` | App icon used in top bar |
| `screenshots/1-dashboard.png` | Dashboard home |
| `screenshots/2-project-browser.png` | Project Browser page |
| `screenshots/3-labs.png` | Labs page |
| `screenshots/4-focus-room.png` | Focus Room (empty state) |

## What Not to Change

- gRPC, LLM, and Draw Things backend logic
- `GenerateViewModel` state and data flow (session-shape unchanged from today — unlike
  the Workbench Tabs fork, this concept keeps one active session)
- `ImmersiveOverlay` full-screen image viewer behavior
- Metadata parsing / PNG embedding
- `StoryFlow*` engine and storage — only the entry point/chrome around it changes
