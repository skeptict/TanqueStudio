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

## Generate reopens where you left it

Generate used to start every launch from scratch: no model, 1024×1024, 8 steps. It now
remembers its whole configuration between launches — model, size, steps, sampler, guidance,
shift, LoRAs, hires fix, tiling and the rest — so the Focus Room reopens on the setup you
left it with. With **Randomize each run** on, a fresh seed is still rolled; with it off, your
seed comes back too. Prompts are not remembered.

## Labs remembers where you were

Labs used to reopen on StoryFlow every time, and the Style Browser's search and section
filter reset with it. Within a session, Labs now reopens on the tab you left, and the Style
Browser keeps its search, section and **Rendered only** filter.

## Style Browser: Cancel is the safe default

The confirmation shown before rendering more than 50 styles highlighted **Render** as the
default button, so pressing Return could start hours of rendering. **Cancel** is now the
default.

**Verified in the app:** the Generate model and canvas size came back after quitting and
relaunching; Labs reopened on Style Browser with a section filter and search intact after a
trip to the Dashboard; and the confirmation now shows Cancel as the default.

## Style Browser: Favorites and your own collections

Star a style to add it to **Favorites**, or gather styles into collections of your own —
"Portraits", "Golden Age", whatever suits. Collections are shared across every set, so
the same list works whatever subject you're rendering.

- **☆ on any card** adds it to Favorites or takes it out again.
- **Right-click a card** to add it to a collection or start a new one with it.
- In a style's detail view, **Favorite** and **Collections** do the same, and you can
  name a new collection right there.
- **The Collection menu**, beside the search field, filters the grid to one collection.
  It combines with the section, the search and **Rendered only** — so **Render visible**
  renders exactly that collection.
- The same menu creates, renames and deletes collections. Deleting asks first, and only
  removes the list; the styles and anything rendered from them stay. Favorites can't be
  renamed or deleted.

Collections are saved alongside your sets in Tanque Studio's own folder.

**Verified in the app:** stars toggle and stay put after a relaunch, without starting a
render on the card underneath; the detail view's Favorite button and the card's star
agree; the detail view's Collections button opens its list. Checked by hand by Ned: choosing a
collection from the Collection menu and rendering it, creating, renaming and deleting
collections, right-clicking a card, and naming a new collection in the detail view.

## Style Browser: New from this set

To render the same subject at a new size, or with a new model, change it in Generate and
press **New from this set**. The new-set panel opens with the current set's subject
already filled in, and lists exactly what will differ — for example *"size 1664×960 →
1344×768"* — or warns when nothing does, so you don't make a duplicate by accident.
**Keep this set's seed** is on by default, so the two sets differ only in what you changed
and can be compared style for style. Your collections work with the new set as they are.

**Verified in the app:** the panel opens prefilled, the changes line tracks Generate's
settings, and turning the seed option off adds the seed to the changes. **Not yet tried by
hand:** pressing Create set from this panel.
