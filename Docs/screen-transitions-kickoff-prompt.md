# Kickoff prompt — screen transitions + click targets in Tanque Studio (paste into a fresh Claude Code session)

> Working directory: `/Users/skeptict/Documents/GitHub/TanqueStudio`
> Branch: create `feature/screen-transitions` from `main`. You will probably start on `feature/prompt-composer` — 3 commits ahead of `main`, working tree clean apart from untracked `.claude/` folders. Leave those uncommitted.

---

Two pieces of UI polish, one session, separate commits:

1. **Animated screen transitions** between the Dashboard and its sections, with a Settings picker: **Off / Fade / Slide / Push**.
2. **Click targets.** Several plain-styled buttons respond only to clicks on their glyphs — the padding, the gap across a row, the inside of an outlined button are dead. Fix that with one shared button style.

Everything in "How it works today" was checked against the tree on 2026-10-13. Line numbers are from `main`. The three `prompt-composer` commits also edit `AppSettings.swift` (cited by symbol here for that reason) and `DashboardFocusPanels.swift` (one line number below; it's `main`'s).

**Setup:** after branching, save this prompt as `Docs/screen-transitions-kickoff-prompt.md` and commit it on its own (`docs: screen transitions kickoff prompt`), like the other kickoff prompts in `Docs/`.

## How it works today

| | |
|---|---|
| Navigation state | `DashboardRootView.swift:63` — `@State private var mode: DashboardMode = .dashboard`. `content` (`:140–165`) switches on it inside the `ZStack` at `:71–74`. Nothing animates; every change is an instant swap. |
| Every navigation | is a bare `mode = …` in `DashboardRootView`: `:70` (top bar), `:108` (Welcome sheet → Settings), `:147`, `:150`, `:152` (Dashboard home), `:157` (Projects → Generate), `:161` (Labs → Generate). Child views only call closures. (`DTClipPlayback`'s `mode =` is unrelated.) |
| Direction model | already in the design: `breadcrumb` (`:167`) treats Dashboard as the hub and every other mode as one level down. |
| Colour scheme | the root pins `.light` (`:92`). `SettingsView` **no longer** pins `.dark` — see its comment at `SettingsView.swift:519` — so there is no light/dark flip mid-transition. The root's comment at `:87–89` still says SettingsView pins dark; it's stale — correct it while you're in the file. `HelpWindow` / `WelcomeSheet` pin dark but aren't in the switch. |
| Appear-time work | `FocusRoomView` has no `.onAppear` / `.task`. `DashboardFocusPanels.swift:572` runs `adoptSlidersFromConfig` (cheap). `DashboardHomeView.swift:85` re-runs `computeStorageUsed()` every time the Dashboard appears — already true today. |
| Settings storage | `AppSettings`: `@Observable` singleton, `private init`, every property a `didSet` writing `UserDefaults.standard` under `tanqueStudio.*`. Enum precedent: `llmProvider` (stores `rawValue`; `init` decodes with a fallback). The codebase does not use `@AppStorage` — don't introduce it. |
| Settings UI | `SettingsView.swift:496` `// MARK: Appearance` holds a placeholder, "More options coming" (`:500`). Picker-row precedent: Provider, `:204–219`. `SettingsView` is hosted twice — as the `.settings` mode and as the ⌘, `Settings` scene. |
| Hit-target precedent | `accordionHitTarget` (`DashboardDS.swift`, `// MARK: - Disclosure hit target`, `:161`) already fixed this class of bug for section headers. Its doc comment is the rationale; build next to it. |
| Ghost buttons | `DashboardGhostButtonStyle` (`DashboardDS.swift:91`) paints `.background(Color.clear)` — clear isn't hit-testable — plus a 1 pt stroked border. "View all projects", "Open Labs" and "Open Settings" are full-width but likely respond only on the text and the border. |
| Platform | deployment target macOS 14.0. |

## Decisions (made in planning — follow them; if one proves wrong at runtime, stop and report rather than improvising)

1. **Name: `ScreenTransitionStyle`**, not `NavigationTransition` — SwiftUI already ships a `NavigationTransition` protocol on macOS 15. Cases `off, fade, slide, push`; display names "Off", "Fade", "Slide", "Push". `String` raw values, `CaseIterable`.
2. **One helper file:** `DrawThingsStudio/Dashboard/ScreenTransition.swift` holds the enum plus pure functions — `static func direction(from: DashboardMode, to: DashboardMode) -> ScreenTransitionDirection` (`.forward`, `.back`, `.lateral`; depth 0 for `.dashboard`, 1 for everything else), `func transition(for: ScreenTransitionDirection) -> AnyTransition`, and `var animation: Animation?` (`nil` for `.off`). No screen builds its own transition.
3. **Behaviour:**
   - **Off** — exactly today: no `withAnimation`, `.identity` transition.
   - **Fade** — opacity crossfade, `easeInOut` 0.25 s.
   - **Slide** — forward: new screen in from trailing, old out to leading. Back: mirrored. Lateral: fade.
   - **Push** — forward: new screen in from trailing with opacity while the old one *recedes* (scale 0.97 + opacity). Back: mirrored — the section leaves to trailing, the Dashboard scales back up from 0.97. Lateral: fade. `easeInOut` 0.3 s.
   - **Reduce Motion** (`@Environment(\.accessibilityReduceMotion)`): Slide and Push degrade to Fade. Fade and Off unchanged.
4. **Default `.push`**, for new and existing users. Key `tanqueStudio.screenTransition`, decoded `ScreenTransitionStyle(rawValue: …) ?? .push` — same shape as `llmProvider` — in its own `// MARK: - Appearance` block in `AppSettings` (`feature/prompt-composer` also edits that file; a separate block keeps the merge mechanical).
5. **One choke point:** `private func navigate(to target: DashboardMode)` in `DashboardRootView` — a no-op when `target == mode`, otherwise applies the style's animation. Replace all seven `mode = …` sites with it. `onSelectImage` keeps calling `selectGalleryImage` *before* navigating. The `switch` stays — no `NavigationStack`, no router object.
6. **Settings row:** replace "More options coming" with a **Screen transitions** row — a `Picker` bound to `$settings.screenTransition`, laid out like the Provider row — plus one muted caption: *"How screens animate between the Dashboard and its sections. Slide and Push become a fade when Reduce Motion is on."*
7. **Button style:** `DashboardPlainButtonStyle` in `DashboardDS.swift` beside `accordionHitTarget`, exposed as `.dashboardPlain` the way `StoryFlowDS.swift:188` exposes `.storyFlowHeaderIcon`.
   - `.contentShape(Rectangle())` on the label; pressed opacity 0.6 (matches Ghost).
   - Hover: a faint rounded highlight (`DashboardDS.text.opacity(0.05)`, radius 6) drawn in a `.background` so it cannot change layout. Hover needs `@State`, so `makeBody` returns a small private view.
   - Fix `DashboardGhostButtonStyle` by adding `.contentShape(RoundedRectangle(cornerRadius: 8))`.
   - **Migrate in this pass only:** `DashboardTopBar.swift:38` (wordmark), `:81` (breadcrumb links), `:110` (`navButton` — also give it enough vertical padding for a ~24 pt target, compensating so nothing in the bar visibly moves); `DashboardHomeView.swift:284` (project rows) and `:326` (Labs rows). `:208` and `:245` already have filled backgrounds — confirm, don't change.
8. **Out of scope:** the thumbnail-grows-into-the-canvas effect (`matchedGeometryEffect` — a later session), pointer-cursor changes (`pointerStyle` is macOS 15+), Labs' internal sub-navigation, and every `.buttonStyle(.plain)` outside the five sites above.

## Phase 0 — read-only, then STOP

1. Confirm the table above still matches the tree; list any drift.
2. **Audit** every `.buttonStyle(.plain)` under `DrawThingsStudio/Dashboard/` (`FocusRoomView` 14, `DashboardFocusPanels` 14, `DashboardHomeView` 4, `DashboardTopBar` 3, `DashboardLabsPage` 1, `DashboardDS` 1) and give a count for the rest of the app. Classify each: **filled** (label has a non-clear background — fine), **dead space** (text or a row with padding / `Spacer` and no fill — a candidate for `.dashboardPlain`), or **other** (image-only, etc.). One table: `file:line | label | class`.
3. **Runtime baseline, no code changes:** run the app and record what does and doesn't respond — the empty middle of a Dashboard project row, the space between the text and the border of "View all projects", and 3–4 pt below a top-bar nav label. Screenshot the Dashboard and the top bar for the before/after comparison.
4. **Stop.** Post the drift list, the audit table and the baseline results. Wait for Ned's go before writing code.

## Phase 1 — transitions + setting

Commit 1: `ScreenTransition.swift`, the `AppSettings` property, `navigate(to:)` and the seven call sites, the stale-comment fix, and the tests. Commit 2: the Settings row.

## Phase 2 — click targets

One commit: `DashboardPlainButtonStyle`, the Ghost fix, the five migrations.

## Rules you must not break

- **Off is exactly today's behaviour.** No animation, no transition, no extra state.
- **The removal-transition trap.** SwiftUI animates a removed view with the transition it carried in its *last* render. If the direction is updated in the same transaction as `mode`, the outgoing screen can animate with the *previous* navigation's direction — Back looks like Forward. Test Back explicitly. If it's wrong, record the direction one main-actor turn before changing `mode` inside `withAnimation`. Report which version you needed.
- Leave the toast's own `.animation(… value: toast?.id)` (`DashboardRootView.swift:100`) alone, and check that a toast arriving mid-transition doesn't drag the screen animation with it.
- Click-target changes must not move anything. Compare against the Phase 0 screenshots.
- Tests must not leak into Ned's real defaults. `AppSettings` has a `private init` and reads the hosting app's `UserDefaults.standard`. Test the decode through a pure helper (e.g. `ScreenTransitionStyle(storedRawValue: String?)`); if you do touch `UserDefaults.standard`, save and restore exactly as `GenerateTimeoutTests.swift:293–301` does.

## Verify

- `xcodebuild test -project TanqueStudio.xcodeproj -scheme TanqueStudio -only-testing:TanqueStudioTests -derivedDataPath .build -parallel-testing-enabled NO` — read the `Executed …` line. It stalls in teardown about half the time; the results are already written when it does.
- New `TanqueStudioTests/ScreenTransitionTests.swift`: `direction(from:to:)` for Dashboard→Focus (forward), Focus→Dashboard (back), Focus→Labs and Settings→Projects (lateral); `.off.animation == nil`; every case round-trips through its raw value; an unknown or missing stored value decodes to `.push`.
- **Runtime matrix — each style × each path:** top bar Dashboard→Generate; breadcrumb Generate→Dashboard; top bar Generate→Labs; Recent Generations thumbnail→Focus Room; Project Browser→Generate; Help → Welcome to Tanque Studio → the sheet's Settings button. Back must read as back. Note any hitch entering the Focus Room.
- Reduce Motion on (System Settings › Accessibility › Display): Slide and Push fade.
- The picker works and persists across relaunch **in both hosts** — the Settings mode and the ⌘, window.
- Re-run the Phase 0 clicks: everything now responds, the hover highlight shows, and the screenshots match the baseline layout.
- **This is a UI feature: a green build and passing tests verify nothing visual.** If you can't run the app and look, say so plainly rather than letting a green build imply it works.
- Report the matrix as a table (style × path, ✅/❌) plus anything you had to change from the Decisions above.
