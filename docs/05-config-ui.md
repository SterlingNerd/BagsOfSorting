# 05 — Configuration UI

This is the differentiator. If this doc is not convincing, the project is not worth building.

---

## Principles

1. **The bags are the editor.** Anything you can do in a settings dialog, you can do by touching
   the thing it configures. The settings window is for browsing, searching, and bulk work — not
   for the primary act of organizing.
2. **Consequence is visible while you edit.** No commit-then-inspect loop. Every rule edit shows
   the items it will claim, live.
3. **One mental model, three nouns.** *Window* (a bag on screen) → *Section* (a labeled block in
   it) → *Category* (the rule that decides what goes in that block). Never a fourth noun, never a
   synonym. Terms appear in the UI with a one-line explanation the first time they are editable.
4. **Immediate commit, easy undo.** No Apply/Cancel, no "you must reload", no dirty-state icons.
   `Ctrl+Z` is the safety net that lets us be bold about immediate commit.
5. **Everything explainable.** Any item answers why it is where it is. Any category answers what
   it claims and what competes with it.
6. **Progressive disclosure, not hidden depth.** Advanced things (search DSL, raw predicate) are
   visibly marked advanced, never required, never silently available.

---

## Screen 1 — Settings window (`/bos`)

Three panes. No nesting deeper than tab → section.

```
┌───────────────────────────────────────────────────────────────────────────────────┐
│ Bag of Sorting                                    [Configure] [Search] [?]  ✕     │
├──────────────┬───────────────────────────────────┬────────────────────────────────┤
│ WINDOWS      │ CATEGORY: Crafting → Herbs        │ PREVIEW  42 items match        │
│ ▸ Backpack   │                                   │                                │
│   Backpack   │ Priority   [ 10 ▾]                │ ⌕ filter preview               │
│   Crafting   │ Matches ANY of:                   │ ┌──┐ Linen Glyph        ×14    │
│   Sell       │   ┌───────────────────────────┐   │ │🌿│ → Crafting / Herbs        │
│ ▸ Bank       │   │ type = Tradeskill      ✕  │   │ ┌──┐ Peace Lily       ×3      │
│   Bank       │   │ subtype starts with Herb ✕ │   │ │🌿│ → Crafting / Herbs        │
│              │   └───────────────────────────┘   │ ┌──┐ Netherstar         ×1     │
│ CATEGORIES   │   AND all of:                     │ │✨│ → Backpack / Misc ⚠       │
│ ▸ Rules (18) │   ┌───────────────────────────┐   │ │  │                            │
│   Armor      │   │ quality ≥ Uncommon     ✕  │   │ └──┐ Silvershard       ×6      │
│   Herbs      │   └───────────────────────────┘   │ │🪙│ → Sell / Junk ⚠           │
│   Junk       │                                   │                                │
│   Quest      │ [+ Add condition]  [Add group]    │ ⚠ = would be claimed by a      │
│ ▸ Manual (3) │                                   │   higher-priority category     │
│ ▸ Dynamic (2)│ [Rename] [Duplicate?] [Disable]   │                                │
│              │ [Delete category]                 │ [Create category from these]   │
├──────────────┴───────────────────────────────────┴────────────────────────────────┤
│ Undo  Redo                                  Presets ▾   Import/Export ▾  Profiles ▾│
└───────────────────────────────────────────────────────────────────────────────────┘
```

Pane roles:

- **Left — navigation.** Two trees: the physical one (windows → sections) and the logical one
  (categories, grouped by kind). Selecting either side highlights the other where they connect, so
  "which sections use the Herbs category?" is a hover, not a search.
- **Center — editor.** The rule tree rendered as English-ish sentences with chips. Chips are the
  atomic unit: one leaf = one chip, drag to reorder, `✕` to remove, click to edit in a popover.
  Groups are labeled `Matches ANY of:` / `AND all of:` / `EXCEPT:` — the user never has to know
  the words "predicate" or "boolean".
- **Right — preview.** The killer feature. Runs the real classifier over the current inventory with
  the *draft* rule tree substituted, and lists what would match, where it would land, and which
  higher-priority category would steal it (`⚠`). Updates on every keystroke in a chip popover.
  Also the entry point for `FR-79` ("create a category from these selected items").

Preview honesty rule: the preview uses the real inventory, not a sample. If the user has no
matching items, the pane says so and offers "show item IDs that would match from your bank" rather
than showing a fake example.

## Screen 2 — Configure mode (`/bos configure`)

The settings window is optional. With configure mode on, the bag windows themselves gain handles:

```
┌─ Crafting ─────────────────────────── ✎ ─┐   ✎ = window title is editable in place
│ ┌ Herbs ──────────────────── ⌃ ⌄ ⇄ ⌫ ┐   │   ⌃⌄ reorder · ⇄ move to window · ⌫ hide
│ │ 🌿 🌿 🌿 🌿 🌿                        │   │
│ │ 🌿 🌿 🌿                             │   │
│ └──────────────────────────────────────┘   │
│ ┌ Ores ──────────────────── ⌃ ⌄ ⇄ ⌫ ┐     │
│ │ ⛏ ⛏ ⛏                                │   │
│ └──────────────────────────────────────┘   │
│ ┌ + add section ┐                          │
└────────────────────────────────────────────┘
```

- Item buttons get a drop target: **drag an item onto a section header** → manual membership
  (`FR-61`). Drag onto `+ add section` → prompts for a name and creates a category seeded with
  that item (`FR-75`).
- Section header handles appear only in configure mode, so normal use stays clean.
- A section header shows its category's chip summary on hover: `type = Tradeskill AND subtype
  starts with Herb AND quality ≥ Uncommon`.
- Configure mode never blocks normal item interaction: pickup, right-click menu, and drag to a
  spellbar still work. Drop-on-header is an *additional* drop target, not a replacement.
- Exiting configure mode is automatic after 60 s of no interaction, with a persistent badge
  reminder in the window title bar so it cannot be silently left on.

## Move mode: use Blizzard's, don't invent one

Forever ships a real move mode (EditMode) and users already know it — the same affordance they use
for action bars and unit frames. ThreatMeter already joins it on Camelot
(`../addons/ThreatMeter/editmode.lua`, `## OptionalDeps: Blizzard_EditMode`), so the path is proven
on this client, not theoretical. Recipe in `agents.md` §EditMode.

Design consequence:

- **`/bos move`** (or the Configure-mode handle) opens the vanilla EditMode UI with our windows
  participating: selection highlight, snap preview lines, magnetism, and the user's existing layout
  habits. Our windows get the same "click a frame, drag it, snap it to a neighbour" experience.
- **Fallback drag always works.** If EditMode is unavailable, disabled by the user, or a mixin method
  is missing, windows are still `SetMovable` frames with saved clamped positions. EditMode is a
  nicety layered on top, never a requirement — ThreatMeter's defensive `if EditModeSystemSelectionMixin`
  guard is the pattern to copy.
- We do **not** build a grid, a snap-settings panel, or a layout-preset system. That is Blizzard's
  feature and it is already good. `shortcut: no own layout-preset system; add one only if EditMode
  layout save/restore proves unusable for multi-window bag layouts.`
- Open questions this raises (`docs/07` Q13): do we register with `registeredSystemFrames` (undocumented,
  but gets EditMode's layout save/restore and `OnEditModeEnter/Exit` callbacks) or stay ThreatMeter-style
  and drive Enter/Exit through `EventRegistry` only?

## Screen 3 — Inspector (`FR-27`, right-click item → "Why is this here?")

```
Linen Glyph
  Placed in: Crafting / Herbs   (category priority 10)
  Matched:   type = Tradeskill  ✓
             subtype starts with "Herb"  ✓
             quality ≥ Uncommon  ✓
  Competed:  Backpack / Misc  (priority 40) — lost, higher priority won
             Junk (priority 900) — not tested
  Membership: rule match (not manual)
  [Move to category…]  [Make a category for this item]  [Disable this rule]
```

This single panel replaces the entire "why is my addon doing this" support conversation, and it is
the reason the classifier keeps a `trace` (`docs/03`).

## Screen 4 — Rule editing popover

Clicking a chip opens a popover anchored to the chip, never a new window:

```
┌ field ▾ ──────────────┐   ┌ value picker (kind depends on field) ─────┐
│ type                  │   │ ☐ Herb  ☐ Ore  ☐ Reagent  ☐ Cloth         │
│ subtype  ▾            │   │ ☐ Metal & Stone  ☐ Elemental              │
│ quality               │   ─────────────────────────────────────────── │
│ ilvl                  │   cmp: [=] [!=] [≥] [≤] [contains] [starts]   │
│ name / tooltip        │                                             │
│ expansion / slot      │   [applies to 42 of your items]  [Done]      │
│ itemID / bind / …     │                                             │
└───────────────────────┘                                             ┘
```

The "applies to N of your items" line under the value picker is the micro-preview: it counts
against your actual inventory before you even commit the chip.

## Screen 5 — Presets, import/export, profiles

Bottom bar of the settings window, each a small popover, not a tab:

- **Presets** — install a starter set of windows+categories (leveling / tradeskill / collections /
  minimal). Installing merges, never wipes, and is undoable.
- **Import/Export** — a multiline edit box with a copy button and a paste field; import shows a
  diff ("+3 windows, +11 categories, 2 name collisions") before applying.
- **Profiles** — current profile, switch, copy-from, reset-this-category. Character counts shown
  so a shared profile is visible as shared.

---

## Interaction inventory (what the user can actually do)

| Action | Where | Command |
|---|---|---|
| create window | `+ add window` in left pane, or `+ add section` chain in configure mode | `window.create` |
| rename window | click title in configure mode, or left-pane field | `window.rename` |
| reorder windows | drag in left pane, or Blizzard EditMode move mode (`FR-54`) | `window.reorder` |
| delete window | left-pane `✕` with confirm | `window.delete` |
| create section | `+ add section` in configure mode | `section.create` |
| rename section | click header in configure mode | `section.rename` |
| reorder section | drag header in configure mode | `section.move` |
| move section to another window | `⇄` handle → window list | `section.moveTo` |
| collapse / hide section | `⌃` / `⌫` handle | `section.collapse`, `section.hide` |
| assign item to category | drag item onto section header | `category.addManual` |
| remove item from manual category | right-click item → "Remove from category" | `category.removeManual` |
| create category from item | right-click item → "Make a category for this item" | `category.createFromItem` |
| add/edit/remove rule leaf | chips in center pane | `rule.add`, `rule.set`, `rule.remove` |
| change priority | `Priority` dropdown; preview re-sorts live | `category.setPriority` |
| duplicate-enable a category | `Duplicate?` checkbox | `category.setDuplicate` |
| disable a category | `Disable` (keeps config, stops matching) | `category.setEnabled` |
| delete a category | center pane `✕` with confirm + "used by 3 sections" warning | `category.delete` |
| bulk sell/deposit a section | right-click header at vendor/bank | `section.bulkMove` |
| undo / redo | `Ctrl+Z` / `Ctrl+Y`, or bottom bar | `undo.step` |

Every row is a command in `config/commands.lua` with an inverse. If an action cannot be expressed
as an invertible command, it does not ship.

---

## States we design for explicitly

| State | Design |
|---|---|
| **First run** | Preset windows/sections exist. A one-time banner on the backpack window: "This is a section. Click it in configure mode to rename it." Dismissable forever, not nagging. |
| **Category matches nothing** | Chip pane header: "Matches 0 of your items" in amber, and the left pane marks the category with a dot. Not silent. |
| **Category used by no section** | Left pane: "not shown anywhere" tag + "Add to a window" button. (Baggins' most confusing failure.) |
| **Rule would claim items a higher priority category already owns** | Preview shows them with `⚠` and names the winner. |
| **Deleting something in use** | Confirm names the dependents: "3 sections use this category." |
| **Unknown item data** | Item renders in the catch-all with a subtle pending marker, then re-sorts when info arrives (`FR-103`). |
| **Combat** | Configure mode disables structural handles during lockdown with a tooltip explaining why. |
| **Import mismatch** | Hard refusal with the version prefix named, not a partial import. |

---

## What we deliberately do NOT build

- No option tree, no breadcrumbs, no "Bag/Category Config" second window.
- No Apply/Commit/Cancel buttons.
- No settings that only exist as a checkbox with no visible effect to observe.
- No dropdown-of-30-rule-types as the entry point to classification. The entry point is an item or
  a section; the rule type is chosen *after* you know what you're classifying.
- No modal dialogs deeper than one popover.
- No confirmation for anything undoable. Confirm only for irreversible deletes (and undo covers
  those too, so the confirm is informational).
- No "advanced mode" toggle that changes what the UI looks like. Advanced things are extra
  affordances, not a different UI.
- No drag-to-reorder in the settings window for things that are draggable on the bags — one place
  to do it, on the bags.

## Measurable UX targets

| Target | How measured |
|---|---|
| Create a working custom window + 2 sections with categories in ≤ 6 interactions | counted click/drag sequence, fresh install, no help |
| Fix a miscategorized item in ≤ 3 interactions | right-click → move to category → done |
| Zero interactions to understand why an item is where it is | inspector is one right-click away |
| Preview updates within 1 frame of a rule edit | `/bos perf` logs preview latency |
