# Handoff: Three Layout Forks for Tanque Studio

## Overview

Tanque Studio currently ships one navigation shell: a fixed left sidebar + 4-pane split
view (config / canvas / gallery / inspector). Three alternative shells were explored as
interactive HTML prototypes and are being handed off as **three separate implementation
forks** — not a single app with a runtime toggle.

**Why forks, not a toggle:** these three concepts are different data models, not skins.
Workbench Tabs assumes multiple concurrent generation sessions; Command Deck and
Dashboard/Focus Rooms assume one active session with different chrome. Building a shared
toggle would mean permanently maintaining 3x the SwiftUI view code and reconciling that
session-model mismatch forever. Instead: build each as its own branch, let the user live
with each on the real app, pick a winner, merge it into `main`, delete the other two
branches.

## About the Design Files

The three HTML files in `prototypes/` are **high-fidelity, fully-interactive design
references** — not production code to port directly. Recreate each one natively in
SwiftUI, in its own git branch off `main`, reusing all existing business logic
(`GenerateViewModel`, `DrawThingsGRPCClient`, `LLMService`, `ImageStorageManager`, etc.)
— only the view layer and, where noted, the view-model's session shape change.

Open each HTML file directly in a browser to click through it before starting — every
control is live (sliders drag, tabs switch, Generate produces a fake progress animation
and a toast, panels open/close/drag).

## Fidelity

**High-fidelity.** Colors, spacing, type sizes, and component shapes in the prototypes
are intentional and should be matched precisely. All three keep IBM Plex Mono (labels,
controls) + Atkinson Hyperlegible (prose) as the fixed typographic thread — see each
fork's palette section for its accent color, which differs by design intent.

## Common Ground Across All Three Forks

Every fork must preserve 100% of current functionality:

- Prompt + negative prompt entry
- Model picker (checkpoint), sampler picker
- Aspect ratio selection
- Steps / CFG / Seed parameters
- LoRA list with per-LoRA weight
- img2img source drop zone
- Moodboard reference strip
- Gallery of past generations (generated vs. imported, selectable)
- Inspector: Metadata / Assist (LLM ops) / Actions tabs
- Draw Things connection status
- Navigation to DT Project Browser, StoryFlow / Story Studio / Workflow Builder (Labs), Settings
- Generate action with real progress feedback

None of these need new backend work — `GenerateViewModel` already exposes all of this
state. The forks differ in **how it's arranged and revealed**, and in one case
(Workbench Tabs), in **how many of it can exist at once**.

Each fork also directly addresses the two stated pain points with the current UI:
bland list/dropdown controls, and no visual feedback for actions taken. All three
replace plain `Picker`/`List` rows with card-style pickers (model swatches, LoRA
cards) and add live feedback: animated progress fills, completion toasts, and
(fork 3) a live progress ring embedded in each session tab.

---

## Fork 1 — Command Deck

**File:** `prototypes/1-command-deck.html`
**Branch suggestion:** `layout/command-deck`

### Concept

No permanent chrome. The canvas fills the entire window edge-to-edge. All controls
live in floating translucent (glass-material) panels that appear on demand — summoned
from a slim icon rail or from a full command palette (⌘K). This is the most radical
departure: it treats Generate as a canvas-first creative tool, not a form with a
preview pane.

### Layout Structure

```
ZStack (full window, black canvas background + subtle radial glow + dot grid)
├── Canvas content (centered, generated image or empty state)
├── Top-left: circular logo button → opens App Switcher popover
├── Top-right: connection status pill + "⌘K" hint
├── Bottom-center: floating Command Bar (docked, glass material)
│     ├── Aspect ratio chip row (above the bar)
│     ├── icon buttons: Params / LoRAs / img2img (toggle floating panels)
│     ├── auto-growing prompt textarea (placeholder: "Describe your image… (⌘K for commands)")
│     └── circular Generate button — shows a ring progress indicator while generating
├── Right-edge: slim icon rail (Gallery, Inspector toggles)
├── Floating panels (glass, draggable-feeling but fixed position in this prototype):
│     Params (model cards + steps/CFG/seed sliders), LoRAs, img2img+Moodboard,
│     Gallery (2-col grid), Inspector (Metadata/Assist/Actions tabs)
├── Toast (bottom-right) on generation complete
└── Command Palette (⌘K) — full-text search over navigation + quick actions
```

### Key SwiftUI Notes

- Use `.background(.ultraThinMaterial)` / `.regularMaterial` for all floating surfaces —
  this is the one fork that leans hardest into native macOS vibrancy.
- App Switcher (replaces sidebar entirely): a popover anchored to the logo button,
  listing all 6 nav items with the same Labs badge treatment as today.
- Command palette: a borderless `NSPanel` or `.sheet` with a text field + filtered list;
  bind to `⌘K` via a global keyboard shortcut (`.keyboardShortcut("k", modifiers: .command)`).
- Floating panels are plain `VStack`s in `.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))`
  positioned with `.offset` or `.position` — they do not need to be real draggable
  windows for v1, but should feel that way (drag handle cursor, subtle header divider).
- Generate button: circular, 38×38pt, shows an `AngularGradient`-free `Circle().trim(from:to:)`
  progress ring in brass while generating (matches the SVG ring in the prototype).

### Colors (this fork's palette — near-black, warmer)

- Canvas/background: `#08090a` / `#0a0b0d`
- Glass panels: `rgba(22,23,25,0.68)` over `.ultraThinMaterial`
- Brass accent: `#c9a058` (same brass as current DS)
- Text: `#e8e4dc`, muted `#726c62`, muted2 `#a89f8f`

### Interactions

| Action | Behavior |
|---|---|
| Click logo | Opens App Switcher popover, listing all nav destinations |
| ⌘K | Opens Command Palette; typing filters; Enter runs top result; Esc closes |
| Click icon in bottom bar | Toggles that floating panel open/closed |
| Click right rail icon | Toggles Gallery / Inspector panel |
| Generate | Ring fills around the circular button; on completion, toast appears bottom-right for ~3s |
| Aspect chip | Immediate selection, brass border + tint |

---

## Fork 3 — Workbench Tabs

**File:** `prototypes/3-workbench-tabs.html`
**Branch suggestion:** `layout/workbench-tabs`

### Concept

Multiple concurrent generation sessions, each a browser-style tab across the top of the
window. Each tab shows a live animated progress ring around its thumbnail while that
session is generating — so several in-flight generations are glanceable at once without
switching tabs. Controls for the active session live in a bottom "shelf" that expands
upward on click and collapses back down to a slim 44px bar.

**This is the one fork with a real data-model change:** today `GenerateViewModel` holds
one session's state. This fork needs an array of sessions, each with its own prompt,
model, params, progress, and gallery selection — i.e. `[GenerateSession]` instead of a
single `GenerateViewModel`. Plan for this as a model-layer change, not just a view change.

### Layout Structure

```
VStack(spacing: 0)
├── Tab bar (44pt) — one tab per session (thumbnail + name + model), "+" to add a session,
│   right-aligned: connection dot + grid icon → Launcher popover (same nav list as other forks)
│   Launcher popover, when in a non-generate mode, replaces the tab row with a "← Workspaces" back button
├── Body (flex)
│   ├── Canvas (teal-tinted dot-grid background, active session's image/empty state)
│   └── Shelf (collapsed: 44pt bar with inline prompt preview + Generate button + chevron;
│              expanded: 360pt, tabbed — Prompt / Model / Params / LoRA / img2img / Gallery)
```

### Key SwiftUI Notes

- New model: `class GenerateSession: Identifiable, ObservableObject` holding today's
  `GenerateViewModel` fields (prompt, negPrompt, model, sampler, aspect, steps, cfg, seed,
  loras, isGenerating, progress, gallerySelection). `AppState` holds `[GenerateSession]` +
  `activeSessionID`.
- Tab thumbnail progress ring: `Circle().trim(from: 0, to: session.progress)` stroked in
  the fork's teal accent, animated with `.animation(.linear(duration: 0.1), value: session.progress)`.
- Shelf: an expand/collapse `VStack` — animate height with `.frame(height: expanded ? 360 : 44)`
  and `withAnimation(.spring)`. Tabs inside the shelf mirror the current left-panel sections
  (Prompt, Model, Params, LoRA, img2img) plus a new Gallery tab (since there's no permanent
  gallery strip in this layout — it's one of the shelf tabs, shown as a wrapped grid).
- "Add session" (`+` in tab bar) creates a new `GenerateSession` with defaults and makes it active.
- Non-generate views (DT Projects, Labs, Settings) replace the whole body; tab bar switches
  to a single "← Workspaces" back affordance instead of showing session tabs.

### Colors (this fork's palette — cool teal, dark)

- Background: `#0b1116` / `#0f171d` / `#162028`
- Accent (replaces brass in this fork only): `#5aafaa` — this is intentionally a
  distinct accent to reinforce "multi-session workbench" as a different mode; if brass
  consistency across the whole app is preferred instead, swap `--accent` back to `#c9a058`
  before implementation — no other change needed since it's a single CSS-custom-property-equivalent
  swap in SwiftUI too (one `TanqueDS.accent` constant).

### Interactions

| Action | Behavior |
|---|---|
| Click "+" | New session tab created and made active, defaults applied |
| Click a tab | Switches active session; shelf content updates to that session's state |
| Click shelf handle / prompt preview | Expands shelf to 360pt, opens last-used shelf tab |
| Generate (per session) | Progress ring animates in that session's tab; other tabs' generations continue unaffected in the background |
| On completion | Toast: `"{session name}" finished`, session tab ring disappears |
| Grid icon → Launcher | Popover listing all 6 nav destinations; selecting a non-generate one swaps the whole body view |

---

## Fork 4 — Dashboard + Focus Rooms

**File:** `prototypes/4-dashboard-focus.html`
**Branch suggestion:** `layout/dashboard-focus`

### Concept

Replaces "always land on the same 4-pane Generate view" with a real home screen:
a "Continue" card for the last in-progress session, a system status card, a
Quick Start grid (prompt/style presets), a recent-generations strip, and mini summaries
of Projects and Labs. Clicking into Generate opens a full-bleed **Focus Room** — one
big canvas + filmstrip below it + a single accordion drawer on the right (not four
stacked panels at once). This is also the only fork proposed in a **light "paper"
theme** — a deliberate contrast to validate whether the brass-on-dark identity should
be the only mode, or whether the DS should support a light variant.

### Layout Structure

```
VStack(spacing: 0)
├── TopBar (56pt): wordmark, breadcrumb (Dashboard / Focus Room / Projects / Labs / Settings),
│   search field, connection dot
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

### Key SwiftUI Notes

- Breadcrumb: simple `HStack` of tappable segments; last segment is non-interactive
  (current page). Update on every navigation.
- Dashboard is a new top-level view with no equivalent today — build as `DashboardView`,
  composed of reusable `Card` container (rounded 14pt, 1px border, subtle shadow) used
  for all four dashboard sections.
- Quick Start presets: static list of `(name, description, promptPreset, swatch)` — selecting
  one pre-fills prompt/model in a fresh session and jumps straight to Focus Room.
  Content for these 4 presets doesn't exist yet — either write copy for them or ask
  before shipping (do not invent prompt presets silently; confirm wording with product).
- Accordion: use `DisclosureGroup` (SwiftUI's native accordion primitive) for each drawer
  section — this maps almost 1:1 to the prototype's custom accordion, so prefer the
  system component over a custom re-implementation.
- Light theme: this is the only fork using light colors. If shipped, add a `paper` case
  to `TanqueDS` alongside the existing dark tokens (mirroring how `colors_and_type.css`
  already defines a `[data-theme="paper"]` variant for Patterns Studio) rather than
  inventing a second unrelated palette.

### Colors (this fork's palette — light "paper" theme)

- Background: `#f0ebe0` / `#e8e0cc` / `#ddd2ba`
- Brass accent (darker, for contrast on light bg): `#8b4a25`
- Text: `#1a140c`, muted `#8a7458`, muted2 `#5c4a38`
- This maps directly to the existing `[data-theme="paper"]` block already defined in
  `colors_and_type.css` — reuse those exact values rather than re-deriving new ones.

### Interactions

| Action | Behavior |
|---|---|
| Click Continue card button | Jumps directly into Focus Room with that session's state restored |
| Click Quick Start card | Pre-fills prompt/model, jumps to Focus Room |
| Click recent-generation thumbnail | Opens Focus Room with that image loaded |
| Click Projects/Labs mini-list row | Navigates to the corresponding full page |
| Accordion section header | Expands/collapses; only the drawer scrolls, not the whole page |
| "Paste Config from DT" (Actions section) | Shows a small inline "✓ Applied" flash for ~1.4s |
| Generate | Pinned button at drawer bottom fills with progress; toast on completion; new image pulses into filmstrip |

---

## Design Tokens (shared foundation, all forks)

Create `TanqueDS.swift` if it doesn't already exist (see prior handoff for DS alignment),
then add per-fork accent overrides as needed:

```swift
enum TanqueDS {
    // Shared across all forks
    static let mono = Font.custom("IBMPlexMono-Regular", size: 12)
    static let sans = Font.custom("AtkinsonHyperlegible-Regular", size: 13)

    // Fork 1 — Command Deck (near-black, brass)
    enum CommandDeck {
        static let bg = Color(hex: "#08090a")
        static let stage = Color(hex: "#0a0b0d")
        static let accent = Color(hex: "#c9a058")
    }

    // Fork 3 — Workbench Tabs (teal, dark)
    enum WorkbenchTabs {
        static let bg = Color(hex: "#0b1116")
        static let surf1 = Color(hex: "#0f171d")
        static let accent = Color(hex: "#5aafaa")   // swap to brass (#c9a058) if a single
                                                     // accent color across all forks is preferred
    }

    // Fork 4 — Dashboard + Focus Rooms (light "paper")
    enum DashboardFocus {
        static let bg = Color(hex: "#f0ebe0")
        static let surf1 = Color(hex: "#e8e0cc")
        static let accent = Color(hex: "#8b4a25")   // matches existing [data-theme="paper"] in colors_and_type.css
    }
}
```

Use the `Color(hex:)` helper from the earlier DS-alignment handoff (`design_handoff_ds_alignment/README.md`)
if not already added to the project.

## Assets

| Asset | Source |
|---|---|
| App icon | Already in `Assets.xcassets` |
| IBM Plex Mono, Atkinson Hyperlegible | Already required per the DS-alignment handoff — no new fonts needed |
| Shared mock data reference | `prototypes/shared-data.js` — model list, LoRA list, gallery items, DT projects, StoryFlow steps, action list. Use as the reference for what fields each data type needs; do not port the JS file itself. |

## Files in This Package

| File | Purpose |
|---|---|
| `prototypes/1-command-deck.html` | Fork 1 prototype — open in browser to click through |
| `prototypes/3-workbench-tabs.html` | Fork 3 prototype |
| `prototypes/4-dashboard-focus.html` | Fork 4 prototype |
| `prototypes/shared-data.js` | Mock data shape reference for all three (models, LoRAs, gallery, projects, StoryFlow steps) |
| `prototypes/index.html` | Launcher page describing all 5 original concepts (2 and 5 not forked — included for context only) |

## Suggested Sequencing

1. Branch `main` three ways: `layout/command-deck`, `layout/workbench-tabs`, `layout/dashboard-focus`.
2. Build each independently — no need to coordinate between them; they don't share view code.
3. Workbench Tabs is the largest lift (new `GenerateSession` model + array); budget more time there.
4. Once all three are running on real devices/data, evaluate with actual generation workflows
   (not just the prototype's fake progress animation) before picking a winner.
5. Merge the winner into `main`. Delete the other two branches — don't keep them around as
   permanently-maintained dead code.

## What Not to Change (all three forks)

- gRPC, LLM, and Draw Things backend logic
- `ImmersiveOverlay` full-screen image viewer behavior
- Metadata parsing / PNG embedding
- `StoryFlow*` engine and storage — only the entry point/chrome around it changes
