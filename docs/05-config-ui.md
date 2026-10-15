# 05 — Configuration UI

This is the differentiator. If this doc is not convincing, the project is not worth building.

---

## Principles

1. **The bags are the editor.** Anything you can do in a settings dialog, you can do by touching the
   thing it configures. Doubled down: Options → AddOns is not where organizing happens. It is a
   utility — browse, search, import/export, profiles — and a layout can be built without opening it
   once (`AC-72`).
2. **Consequence is visible while you edit.** No commit-then-inspect loop, and no separate preview
   pane either: the live list of *your own items* is inside the editor. Real inventory is the
   preview.
3. **One mental model, three nouns.** *Window* (a bag on screen) → *Section* (a labeled block in it)
   → *Category* (the rule that decides what lands in that block). Never a fourth noun, never a
   synonym. Terms appear in the UI with a one-line explanation the first time they are editable.
4. **Immediate commit, undo instead of cancel — with one honest exception.** Structural edits take
   effect the instant they are made and are undone, not cancelled. A *half-built rule tree* is not a
   valid model state, so the category editor stages a draft with Apply / Cancel. §Commit below is
   normative.
5. **Everything explainable.** Any item answers why it is where it is. Any category answers what it
   claims and what competes with it.
6. **Progressive disclosure, not hidden depth.** Advanced things (search DSL, raw predicate) are
   visibly marked advanced, never required, never silently available.
7. **Use the affordance the player already has.** Window placement and the boring numeric knobs go
   into Blizzard's EditMode, the icon picker is the macro icon picker, the search box is a
   `SearchBoxTemplate`. We invent UI only where nothing exists.

---

## How far can we get without a config window?

Everything the user can configure, and where it lives:

| Thing | Where it is edited | Needs a window? |
|---|---|---|
| number of windows, their names, order, kind | configure mode: `+ window`, in-place title, drag | no |
| columns per window, scale, compact, open-with-all, icon | **Blizzard EditMode** per-system settings dialog (`/bos move`), mirrored in the window's context menu | no |
| sections: add, remove, rename, reorder, collapse, hide, move between windows | configure mode: header handles + drag + context menu | no |
| which categories a section contains | **section editor modal**: combo box + sortable list | no (it is a modal) |
| a category's rules | **category editor modal** (§Screen 2) | no (it is a modal) |
| a category's item ID list | category editor → *Item IDs* → paste box (§Screen 3) | no |
| priority, duplicate, disable, affinity | chips/rows inside those two modals | no |
| add one item to / remove one item from a category | drag onto a section header; Ctrl+right-click an item → *Exclude from category* | no |
| keybinds | the client's own Key Bindings panel (our frames are registered there) | no |
| bulk sell / deposit / move-to-window | section header context menu | no |
| empty a physical bag, vanilla↔sorting toggle | the bag bar and the vanilla-bags view | no |
| presets, import/export strings, profile switch, "every rule that matches Linen Glyph" | **Options → AddOns** | yes — 4 things, one panel page |

So: **no config window for organizing.** One page in the client's own settings panel exists for the four
things above that have no physical counterpart, and `/bos` opens *configure mode*, not that page.
`/bos settings` jumps the client's panel to our category (`Settings.OpenToCategory`).

What we are not pretending: a config with dozens of categories is hard to *see* in a bag. That is what
the Find pane is for — finding a category, not editing it.

---

## Screen 1 — Configure mode (`/bos configure`)

```
┌─ Crafting ✎ ──────────────────────────── ⚙ ⌫ ─┐   ✎ title: rename in place
│ ┌ Herbs ─────────────────── ⌃ ⌄ ⇄ ⌫ ✎ ┐       │   ⌃⌄ reorder · ⇄ move to window
│ │ 🌿 🌿 🌿 🌿 🌿                          │       │   ⌫ hide · ✎ edit this section
│ │ 🌿 🌿 🌿                              │       │
│ └──────────────────────────────────────┘       │
│ ┌ Ores · Metals ─────────── ⌃ ⌄ ⇄ ⌫ ✎ ┐       │   two categories, one block
│ │ ⛏ ⛏ ⛏ 🪙 🪙                          │       │
│ └──────────────────────────────────────┘       │
│ ┌ + section ┐  ┌ + copy a window here ┐        │
└────────────────────────────────────────────────┘
   [Undo] [Redo]                    Done            ← configure-mode bar, not a keybind
```

- **Right-click is the main menu**, on the window title, on a section header, and on an item. One
  menu each, ~6 entries, no submenus deeper than one.
- Handles appear only in configure mode; normal use stays clean.
- A section header shows its category chips on hover: `Tradeskill · subtype Herb · quality ≥ Uncommon`.
- Configure mode never blocks normal item interaction: pickup, right-click item menu, drag to a
  spellbar, shift-click, all unchanged. Drop-on-header is an *additional* target.
- Exiting: `Done`, `Esc`, or 60 s idle. Exiting is **not** a commit boundary — nothing is pending.
- During `InCombatLockdown()` the structural handles are disabled with a tooltip saying why.

## Screen 2 — The category editor (the hard one)

Opened from a section header's `✎`, from a chip, or from an item's *Move to category…*. It is a
modal, roughly the size of one small bag window, and its body is **your real inventory filtered by
the draft rule** — that is the whole design trick, and it is why there is no preview pane.

```
┌ Category: Herbs ─────────────────────────────────────── [?] ─┐
│ shown in: Crafting/Herbs, Bank Trade Goods/Herbs   [manage]  │
│ priority [10 ▾]   ☐ allow duplicates   ☐ enabled             │
│ affinity  [Herb pouch ▾]                                     │
│                                                              │
│ MATCHES  ▸ any of                                            │
│   ┌ type = Tradeskill ┐ ┌ subtype starts with "Herb" ┐      │
│   └ ✎ ✕              ┘ └ ✎ ✕                       ┘      │
│   [ + condition ]  [ + group ]                              │
│                                                              │
│ EXCEPT   ▸ none of                                           │
│   ┌ itemID in {Silvershard +2} ┐  ┌ category = Junk ┐       │
│                                                              │
│ 42 items · 14 stacks            ⌕ filter                     │
│ ┌──┐ Linen Glyph        ×14   ┌──┐ Peace Lily       ×3      │
│ │🌿│ → Crafting / Herbs       │🌿│ → Crafting / Herbs       │
│ ┌──┐ Netherstar         ×1    ┌──┐ Silvershard      ×6      │
│ │✨│ → Backpack / Misc  ⚠     │🪙│ → Sell / Junk   ⚠        │
│                                                              │
│ [ Item IDs… ]  [ Make a category from the ticked ones ]      │
│                                    [ Cancel ]  [ Apply ]     │
└──────────────────────────────────────────────────────────────┘
```

Rules that make it work:

- **Chips are leaves.** One chip = one leaf. `✎` opens a popover anchored to the chip (field picker →
  value picker, with "applies to N of your items" under the value list). Drag to reorder, drag off to
  remove. A group is a labeled row: `MATCHES any of`, `AND all of`, `EXCEPT none of` — the words
  "predicate" and "boolean" never appear.
- **`EXCEPT` is a row you can add to without thinking**, because exclusions outnumber conjunctions
  several to one in real configs (`docs/01`) and it must not require opening a rule editor
  `NOT` and only 44 are `AND` (`docs/01`). The fastest path to it is not this modal at all: right-click
  the offending item in the bag → *Exclude from category*.
- **The item list is bidirectional.** Drag an item from the bags onto this list → it joins the ID
  list. Tick a row and press *Exclude* → it joins `EXCEPT itemID in {…}`. Drag-and-tick is the editor;
  chips are the refinement.
- `⚠` marks an item the draft would claim but a higher-priority category owns, and names the winner on
  hover. This is the preview's only genuinely new information.
- Items whose data the client has not cached render with their tier-1 icon and a `…` name until
  `ITEM_DATA_LOAD_RESULT` resolves them (`FR-103`). Never a blank row.
- **Apply / Cancel, and only here.** The draft is not written to the model until Apply; Apply is one
  command, so one Undo removes an entire rebuilt rule tree. Cancel discards the draft and the model
  never knew it existed. Apply is disabled (with a reason) when the tree is invalid: empty group,
  unknown field, a value with no options.
- The modal is resizable and its list is a `WowScrollBox` + `MinimalScrollBar`. It is not a
  `ButtonFrameTemplate` dialog with a waterfall inside it.

## Screen 3 — Item IDs (`FR-24b`)

`[ Item IDs… ]` opens a small modal: a multiline edit box, a live count, and one Apply.

```
┌ Item IDs: Herbs ────────────────────────────┐
│ ┌─────────────────────────────────────────┐ │
│ │ 26042, 26044                            │ │
│ │ [Linen Glyph]                           │ │
│ │ 4378 4379 4380                          │ │
│ └─────────────────────────────────────────┘ │
│ 43 IDs · 2 unknown to this client: abc, 99999999
│ ☑ replace current list   ☐ add to current list
│                        [ Cancel ] [ Apply ] │
└─────────────────────────────────────────────┘
```

IDs may be separated by newlines, commas, semicolons, spaces or tabs, mixed with item links, in one
paste. Unknown-but-valid IDs are kept (they will resolve when the client sees them); tokens that are
not IDs are dropped with a reason. The whole paste is one command → one Undo.

## Screen 4 — Section editor

`⇄`/`✎` on a header opens a modal with exactly two controls, because that is all a section is:

```
┌ Section: Ores · Metals ─────────────────────┐
│ name  [ Ores · Metals                    ]  │
│ categories, in order:                       │
│   ⠿ Ores        [✕]                         │
│   ⠿ Metals      [✕]                         │
│   ⠿ Tradeskills.Enchanting ∗  [✕]          │
│   [ add category ▾ ]  [ + new category ]    │
│ ☐ collapse by default    ☐ hidden           │
│                        [ Cancel ] [ Apply ] │
└─────────────────────────────────────────────┘
```

Combo box for adding, drag to reorder, `✕` to unbind (the category itself survives, and the toast says
so). Reordering *sections* is a drag on the bags, never in a list here — one place to do each thing.

- **`∗` binds a whole group** (`FR-11b`): `Tradeskills.Enchanting ∗` pulls in every category under that
  dotted prefix — `.Dust`, `.Essence`, `.Rod` — so adding a child category needs no re-binding. The
  modal shows how many categories the group currently resolves to, and renaming a category out of the
  prefix says so at rename time rather than silently dropping items out of the section.
- **Name completion** (`FR-89`): typing `Tradeskills.` offers existing children, so the dotted
  convention is supported without being mandatory. Nothing in the model requires a dot.

## Screen 5 — Inspector (Ctrl+right-click an item → "Why is this here?")

Naked right-click stays the stock item menu, and shift/alt-click stay the client's (`EXPANDITEM`,
`SPLITSTACK`, inventory scan). Our item menu is on a modifier — Ctrl+right-click by default,
rebindable, registered through `Settings.RegisterModifiedClickSetting` so it appears in the client's
own modified-click options (`FR-60b`).

```
Linen Glyph
  Placed in: Crafting / Herbs   (category priority 10)
  Matched:   type = Tradeskill  ✓
             subtype starts with "Herb"  ✓
             quality ≥ Uncommon  ✓
  Competed:  Backpack / Misc  (priority 40) — lost, higher priority won
             Junk (priority 900) — not tested
  Membership: rule match (not an ID list)
  [Move to category…]  [Exclude from this category]  [Disable this rule]
```

This panel replaces the entire "why is my addon doing this" support conversation, and it is why the
classifier keeps a `trace` (`docs/03`).

## Screen 6 — Move mode: use Blizzard's, don't invent one

Forever ships a real move mode and users already know it. ThreatMeter joins it on Camelot
(`../addons/ThreatMeter/editmode.lua`, `## OptionalDeps: Blizzard_EditMode`), so the path is proven
here, not theoretical. Recipe in `agents.md` §EditMode.

- **`/bos move`** opens vanilla EditMode with our windows participating: selection highlight, snap
  preview, magnetism, the user's existing layout habits.
- **The boring numbers live there too.** Where EditMode exposes a per-system settings dialog
  (`EditModeSystemSettingsDialogButtonTemplate`), that is where columns, scale, compact and
  open-with-all go — the same place a player already sets their action-bar and unit-frame options.
  Every one of them is also reachable from the window's context menu, because EditMode is not always
  available (and is closed in combat).
- **Fallback drag always works.** If EditMode is unavailable or a mixin method is missing, windows are
  `SetMovable` frames with saved clamped positions. ThreatMeter's defensive guard is the pattern.
- We do **not** build a grid, snap-settings panel, or layout-preset system.
  `shortcut: no own layout-preset system; add one only if EditMode layout save/restore proves
  unusable for multi-window bag layouts.`
- Caveat measured from Blizzard's own code: on this client EditMode's *Bags* system is the **bag
  button bar**, not the bag window (`../addons/ForeverPlus/Modules/BagWindow.lua`). Our windows are
  their own systems; do not assume EditMode's "Bags" entry means us. Open question: `docs/07` Q13.

## Screen 7 — The utility window: Options → AddOns

Demoted, small, four panes, no nesting deeper than pane → row. It is **not our own window**: it
registers into the client's own settings panel with `Settings.RegisterAddOnCategory` +
`RegisterVerticalLayoutCategory`/`RegisterCanvasLayoutCategory` + `CreateCheckbox`/`CreateSlider`/
`CreateDropdown` — all verified present on Forever (`agents.md` §Present on Forever), and Blizzard's
own guide for it ships in `Blizzard_ImplementationReadme.lua`. `/bos settings` is a shortcut that
calls `Settings.OpenToCategory`.

| Pane | Contents |
|---|---|
| **Find** | search categories/windows/rules; "every rule that matches Linen Glyph"; jump-to (selecting a result opens the right modal on the bag) |
| **Presets** | install a starter set (leveling / tradeskill / collections / minimal). Merges, never wipes, undoable. Presets are **data the user can edit afterwards** (`FR-31`) — add IDs, remove IDs, rename, disable |
| **Import / Export** | multiline box + copy + paste; shows a diff ("+3 windows, +11 categories, 2 name collisions") before Apply |
| **Profiles** | current profile, switch, copy-from, per-character override, reset-this-category; shows which characters share a profile |
| **Keys** | our keybinds via `Settings.SetKeybindingsCategory`, so they appear in the client's Key Bindings panel like any other binding |

No structural editing here. If a pane starts offering a rule editor, it is the wrong pane. **Appearance
(quality/rarity and item level, `FR-45`/`FR-45b`) is not here** — it is a modal opened from the window
context menu, because you change it by looking at the bags you are changing.

---

## Screen 8 — The help page (`?`, `/bos help`)

A UI you configure by touching is not a UI anyone has seen before, and "no settings window" sounds
like a missing feature until it is explained. This page is what makes the design legible, and it is a
requirement (`FR-87`), not documentation polish.

It is short and it answers four things, each in the order a new user hits them:

1. **Three nouns.** Window = a bag you made. Section = a labelled block inside it. Category = the rule
   that decides what lands in a block.
2. **Four gestures.** Right-click a title or header for its menu. Ctrl+right-click an item for ours —
   naked right-click is still the game's item menu. Click a name to rename it where it stands. Drag an
   item onto a header to file it.
3. **Where each kind of setting lives.** Numbers (columns, scale, compact) in move mode; looks
   (quality, item level) in the Appearance modal; everything about *organising* on the bags; profiles,
   presets, import/export and keybinds in Options → AddOns.
4. **What Undo means here.** Structural edits apply at once and are undone, not cancelled. Apply and
   Cancel exist only for a half-built rule.

Plus the first-run keybind-conflict note (`docs/07` Q4) and a link to the public repo. Opened from the
configure bar, from every modal footer, and from `/bos help`. Ships after the PoC and before 1.0.

---

## Commit, cancel, exit, undo

The question this answers: *no Apply button — then how do we exit edit mode, and how do we abandon a
failed change?*

| Situation | Answer |
|---|---|
| How do I exit configure mode? | `Done` on the configure-mode bar, `Esc`, or 60 s idle. Leaving is not a commit boundary: everything you did already applied and is still undoable after you leave. |
| How do I abandon a rename / reorder / added section / deleted window? | **Undo.** It applied immediately and there is nothing to cancel. Undo is a button on the configure bar, in every modal footer, and in the "what changed" toast. |
| Why does the category editor have Apply/Cancel then? | A half-built rule tree is not a valid model state (`docs/04`: an empty group is invalid). Staging a draft is the only place where "cancel" means something. Apply = one command = one undo step. |
| What if I make a mess of several edits? | Undo repeatedly (bounded log, default 50 steps, `docs/04`), or *Reset this category/window* (`FR-95`) from Options → AddOns. |
| What if an edit is invalid? | Refused in the modal with a reason, Apply disabled. We do not commit garbage and then ask you to undo it. |
| What if an edit is destructive (delete a category used by 3 sections)? | Confirm that names the dependents, and Undo still works afterwards. Confirm is informational, not a gate. |
| Bulk operations (import, preset install, empty-bag)? | One command each, with an inverse. Import shows a diff before applying. |
| Why not `Ctrl+Z`? | `Ctrl+Z`/`Ctrl+Y` sit next to WASD and are plausibly someone's spell, macro or other addon. They are **not bound by default**; a user may bind them in the Key Bindings panel. Buttons are the primary affordance. |

---

## The bag bar, real bags, and icons

- **Vanilla ↔ sorting toggle** (`FR-51`) on the client's bag bar: one click shows Blizzard's own bag
  windows and hides ours, and the vanilla view can open a *single* physical bag (the herb pouch, the
  quiver) without opening the rest. This is how a player upgrades cloth → linen → silk, moves a bag
  to the bank, or sells at a vendor without fighting us.
- **Empty this bag** (`FR-67`): a physical bag's context menu item that moves everything out of it,
  honouring affinities and free slots, refusing when there is not room.
- **Window icons** (`FR-85`): the window context menu → *Icon* opens the client's own icon picker
  (`IconDataProviderMixin` / `IconSelectorPopupFrameTemplate` — the picker the macro UI uses), stored
  via `GetIconForSaving` as a bare `Interface\ICONS\` name. Our own overlay art (transparent PNG)
  draws on top of the chosen icon at a fixed offset; `overlay` in `docs/04` stores which overlay, if
  any. Overlaying is two layered textures on one button — no trick, and it keeps the user's freedom
  to pick any of ~600 client icons. The same icon+overlay pair renders on the button that represents
  the window, whether that button is on Blizzard's bar or on our own bar of sorting bags
  (`docs/07` Q9).
- **Our own bar, later.** The stated wish is to replace the client's bag bar with a bar of our own
  bag buttons. That is a Q9 decision with an icon consequence: whichever bar exists, a window's
  `icon` + `overlay` is what its button draws, so the icon work is not wasted on either answer.
  Meanwhile our windows **anchor off the client's bag bar** (`FR-41`), so a fresh install lands where
  the game already puts the player's bags.
- **Linked windows** (`FR-10c`): the window context menu offers *Link to…* and *Unlink*. A bank window
  linked to its backpack twin shares the section list and its category bindings, so a section added on
  one side appears on the other. The link is shown on both window titles in configure mode — a hidden
  inheritance is the kind of thing that makes people distrust a config.
- **Appearance** (`FR-45`, `FR-45b`): window context menu → *Appearance* opens a small modal for
  quality/rarity (border, tint, both, or off; per-quality toggles; threshold; intensity) and item level
  (show, gear-only, minimum, position, quality-coloured). It is a modal on the bag, not a pane in
  Options, because you decide these by looking at the bags you are looking at. Defaults look like stock
  bags.
- **Show stacks** (`FR-43`): a toggle in the section and window context menus. Merged is the default;
  toggling un-merges for the session, until the bags close; `vendor` un-merges automatically while a
  vendor is open; `always` never merges. Nothing here changes which real slot holds what.
- **New-item highlight** (`FR-47`): cleared by keybind, by the section/window context menu, by
  `/bos new`, or automatically on close, depending on `clearNewOnClose`.
- **Selling a section** (`FR-65`): deliberately the most cautious action in the UI. Vendor buyback is
  limited, so bulk sell is off by default, limited to categories the user marked sellable, and its
  confirm lists every item, the total gold, and the buyback limit — not "this is safe".

---

## Interaction inventory

| Action | Where | Command |
|---|---|---|
| create window | `+ window` in configure mode, or *Copy a window* | `window.create`, `window.copy` |
| rename window | click title in configure mode | `window.rename` |
| move / reorder windows | Blizzard EditMode (`FR-54`), or drag in configure mode | `window.reorder` |
| columns / scale / compact / open-with-all / icon | EditMode system dialog, or window context menu | `window.set` |
| link / unlink a window to its twin | window context menu → *Link to…* / *Unlink* | `window.link`, `window.unlink` |
| quality / item-level appearance | window context menu → *Appearance* modal | `display.set` |
| show or hide merged stacks | section or window context menu | `stacking.setShowStacks` |
| clear new-item highlights | keybind, section/window context menu, `/bos new` | `items.clearNew` |
| delete window | window context menu `✕` with confirm | `window.delete` |
| create section | `+ section` in configure mode | `section.create` |
| rename section | click header in configure mode | `section.rename` |
| reorder section | drag header in configure mode | `section.move` |
| move section to another window | `⇄` handle → window list | `section.moveTo` |
| collapse / hide section | `⌃` / `⌫` handle | `section.collapse`, `section.hide` |
| bind / unbind / reorder categories in a section | section editor modal | `section.bindCategory`, `section.unbindCategory`, `section.reorderCategories` |
| add / edit / remove a rule leaf | category editor chips | `rule.add`, `rule.set`, `rule.remove` |
| add / replace an item ID list | category editor → Item IDs | `category.setItemIDs` |
| exclude one item from a category | Ctrl+right-click item → *Exclude from category* | `category.excludeItemID` |
| assign an item to a category | drag item onto a section header | `category.addManual` |
| create category from an item | Ctrl+right-click item → *Make a category for this item* | `category.createFromItem` |
| priority / duplicate / enabled / affinity | category editor rows | `category.set` |
| disable a category | category editor row | `category.setEnabled` |
| delete a category | category editor with "used by 3 sections" confirm | `category.delete` |
| bulk sell / deposit / move-to-window | section header context menu | `section.bulkMove` |
| empty a physical bag | bag context menu | `bag.empty` |
| vanilla ↔ sorting bags | bag bar toggle | `bags.setMode` |
| undo / redo | configure bar, modal footers, toast | `undo.step`, `redo.step` |
| help / intro page | `?` on the configure bar and in every modal footer, `/bos help` | — |
| keybinds | client Key Bindings panel (`Settings.SetKeybindingsCategory`) | — |

Every row is a command in `config/commands.lua` with an inverse. If an action cannot be expressed as
an invertible command, it does not ship.

---

## States we design for explicitly

| State | Design |
|---|---|
| **First run** | Preset windows/sections exist. A one-time banner on the backpack window: "This is a section. Click it in configure mode to rename it." Dismissable forever, not nagging. Plus a one-time note if our keybind collides with the default `B` (`docs/07` Q4). |
| **Category matches nothing** | Category editor header: "Matches 0 of your items" in amber; the section header shows a dot. Not silent. |
| **Category used by no section** | Options → AddOns → Find: "not shown anywhere" tag + *Add to a window*. (Baggins' most confusing failure.) |
| **Draft rule would claim items a higher priority category owns** | `⚠` in the category editor's list, winner named on hover. |
| **Deleting something in use** | Confirm names the dependents: "3 sections use this category." |
| **Item data not cached** | Tier-1 icon + `…` name + pending marker; resolves without a reload (`FR-103`). |
| **Bank closed** | Bank windows simply do not exist on screen. There is no "search the bank from anywhere" state to design for — that feature is out of the product (`FR-109`, `docs/07` Q15) |
| **Combat** | Configure handles disabled with an explanation; bulk moves refused with "not while in combat". No taint (`AC-4`, `AC-68`). |
| **Import mismatch** | Hard refusal with the version prefix named, not a partial import. |

---

## What we deliberately do NOT build

- No option tree, no breadcrumbs, no "Bag/Category Config" second window.
- No settings window for organizing. If a change needs a settings window, it needs a modal.
- No separate preview pane. The live item list is inside the editor.
- No Apply/Cancel for structural edits — Undo instead. Apply/Cancel only for the rule draft.
- No dirty-state icons, no "you must reload", no "unsaved changes" dialog.
- No default `Ctrl+Z`/`Ctrl+Y` bindings.
- No settings that only exist as a checkbox with no observable effect.
- No dropdown-of-30-rule-types as the entry point to classification. The entry point is an item or a
  section; the rule type is chosen *after* you know what you are classifying.
- No modal dialogs deeper than one popover, and no popover inside a modal's modal.
- No confirmation for anything undoable.
- No "advanced mode" toggle that changes what the UI looks like.
- No drag-to-reorder in the utility window for things that are draggable on the bags — one place to
  do it, on the bags.
- No theme/skin UI (`docs/07` Q16).

---

## Measurable UX targets

| Target | How measured |
|---|---|
| Create a working custom window + 2 sections with categories in ≤ 6 interactions | counted click/drag sequence, fresh install, no help, **settings window never opened** |
| Fix a miscategorized item in ≤ 3 interactions | right-click → Exclude from category → done |
| Add 40 known item IDs to a category in ≤ 3 interactions | paste → Apply → done |
| Zero interactions to understand why an item is where it is | inspector is one right-click away |
| Category editor list updates within 1 frame of a chip edit | `/bos perf` logs editor latency |
| A config with dozens of categories and a hundred-plus sections is navigable | the `docs/01` shape rebuilt in ≤ 30 minutes, utility panes used only for Find |
