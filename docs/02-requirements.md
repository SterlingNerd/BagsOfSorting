# 02 — Requirements

Priority: **M** = Must (v1 ships without it or the product is wrong) · **S** = Should (v1 if
time allows; missing = acceptable) · **C** = Could (nice, explicitly deferrable) · **W** = Won't
(v1, named so it is not accidentally added).

Acceptance criteria are written as things a human verifies **in-game on the Forever client**
(`agents.md` §Hard rules 1). `AC` lines are the checklist entries reused by `docs/06`.

---

## A. Client & platform

| ID | P | Requirement |
|---|---|---|
| FR-1 | M | Runs on WoW: Forever (Camelot, `WOW_PROJECT_ID == WOW_PROJECT_CAMELOT`, interface 16001) with no load errors and no `ADDON_ACTION_FORBIDDEN` on login or `/reload`. |
| FR-2 | M | Client detection is one module (`core/client.lua`) exposing capability flags (`isForever`, `isRetailLike`, `hasWarbank`, `hasReagentBank`, `hasBlizzSort`, `hasContainerQuestInfo`, `itemButtonType`), not inline `if IsForeverWow()` at call sites. |
| FR-3 | M | Never performs a protected action. All init that touches frames is either at `ADDON_LOADED` before login, or deferred via a plain frame listening to `PLAYER_REGEN_ENABLED`. |
| FR-4 | M | Works while dead, while in combat (read-only display), and after `ReloadUI()` mid-combat without tainting item buttons silently. |
| FR-5 | S | TOC declares Forever first (`## Interface-Forever: 16001`) and does not claim support for clients we do not test. |
| FR-6 | W | Retail / Classic Era / TBC / Cata / MoP support in v1. Architecture must not *prevent* it (`docs/03` §Client capability layer). |
| FR-7 | C | Loads alongside Baggins or BetterBags with a startup warning that two bag addons are active, rather than silently double-drawing bags. |

**AC-1** fresh install, `/reload` ×3, login while in combat (death-restore case), no errors in
`/events`. **AC-2** `grep -rn "IsForever\|WOW_PROJECT" core/ frames/` shows hits only in
`core/client.lua`. **AC-4** toggle every bag window during combat: no taint, no lockdown error.

## B. Inventory model

| ID | P | Requirement |
|---|---|---|
| FR-10 | M | The user can create, rename, reorder and delete **windows** (custom bags). Each window has: name, kind (`backpack` \| `bank`), priority (ordering), `openWithAll` flag, column count, saved position and scale. |
| FR-11 | M | Each window contains ordered **sections**. A section is a labeled block bound to a category. Sections can be renamed, reordered, collapsed, hidden, and moved between windows. Whether one section may bind *several* categories is open — see `docs/07` Q3; v1 assumes one. |
| FR-12 | M | A **category** is a named classification rule set that can be referenced by zero or more sections. One category may appear in several windows/sections. |
| FR-13 | M | Backpack and bank are both handled, with bank windows scoped by `kind = bank` and never shown when the bank is closed. |
| FR-14 | M | Items in real containers (backpack slots, equipped bags, bank tabs, bank bags, keyring, reagent bag if present on Forever) are harvested exactly once and displayed in virtual windows; the addon does not fabricate inventory. |
| FR-15 | M | An item never appears in two windows/sections unless the category explicitly opts into duplication. |
| FR-16 | M | Items that match no category land in a catch-all section whose name and position the user controls. |
| FR-17 | S | Per-window column count (default 5) independent of other windows. |
| FR-18 | S | A window can be marked "compact" so it shrinks to its content and hides when empty (`hideemptybags`). |
| FR-19 | S | Specialty container awareness: reagent bag / ammo pouch / soul bag slots are visually distinguishable in the empty-slot representation. |

**AC-10** create 3 windows, rename each, drag window 2 above window 1, delete window 3, `/reload`,
state persists. **AC-11** drag a section from window A to window B; collapse it; hide it; reload;
state persists. **AC-14** every equipped bag, every bank tab and the keyring (if present) are
accounted for in the harvested totals — compare against stock bag counts. **AC-17** window A set to
8 columns and window B to 4: both pack correctly and independently. **AC-15** with duplication off, `grep` the rendered frames for a duplicated
item GUID — zero. **AC-13** open the bank: bank windows appear, all bank tabs and bank bags are harvested, no backpack window leaks bank contents; close the bank: bank windows are gone.
**AC-16** loot an item no rule matches; it appears in the catch-all named as
configured.

## C. Rules & classification

| ID | P | Requirement |
|---|---|---|
| FR-20 | M | Rules are a declarative tree: `any{...}`, `all{...}`, `none{...}`, each leaf `{field, op, value}`. The tree renders as one readable sentence and is editable without understanding evaluation order. |
| FR-21 | M | v1 field set: `type`, `subtype`, `quality`, `ilvl`, `name`, `tooltip`, `expansion`, `equipSlot`, `bindType`, `itemID`, `classID`, `subclassID`, `containerFamily`, `bagID`, `isReagent`, `isQuestItem`, `isNew`, `category` (reference another category). |
| FR-22 | M | v1 operators: `=`, `!=`, `>=`, `<=`, `contains`, `startsWith`, `in {…}`. String comparisons are case-insensitive. |
| FR-23 | M | Categories have a numeric **priority**; the first matching category by priority owns the item. Ties broken deterministically (documented in `docs/04` §Precedence) and shown in the inspector. |
| FR-24 | M | A category can also be a **manual list** of item IDs (drag an item in, drag it out) with no rules. |
| FR-25 | M | A category can be **dynamic**: one section per distinct value of a field (`type`, `subtype`, `expansion`), auto-created, auto-named, no per-value config. |
| FR-26 | M | Editing any rule re-classifies only the affected categories, not the whole inventory. |
| FR-27 | M | Every placed item can be explained: which category, which leaf matched, which higher-priority categories were tested and rejected. |
| FR-28 | S | Search expression authoring: a subset of a query language (`name`, `type`, `subtype`, `ilvl`, `quality`, `expansion`, `slot`, `tooltip`, `id`, `and/or/not`, parentheses, `= != >= <= contains`) that compiles to the same rule tree, and can be saved as a category. |
| FR-29 | S | Rule linting: an empty rule, a rule whose field has no values, a category that matches nothing, and a category referenced by no section are all reported in the UI, not silently inert. |
| FR-30 | S | `shortcut:`-documented escape hatch for a raw Lua predicate per category, with a visible "advanced, unsupported" marker. |
| FR-31 | C | Preset "smart" categories shipped as data, not code (gear sets, collections, consumables, reagents, junk). |
| FR-32 | W | Third-party filter plugins in v1. |

**AC-20** build `any{ all{type=Armor, quality>=Rare}, none{tooltip contains "Bind on Equip"} }`
purely by clicking; the sentence preview matches intent; matching items land in the right section.
**AC-23** two categories both matching an epic sword; changing priority 10→5 moves it, live, no
reload. **AC-27** right-click any item → "Why here?" and confirm the named rule is the one you
wrote. **AC-26** editing one rule re-classifies only the affected categories — `/bos perf` shows the phase delta.
**AC-28** save a search as a category; loot a new matching item; it lands in that category.
**AC-29** create a category with no rules → UI says it matches nothing.

## D. Layout & rendering

| ID | P | Requirement |
|---|---|---|
| FR-40 | M | Sections are packed into rows within a window up to the window's column count (Baggins-style flow), and the window resizes to its content. |
| FR-41 | M | Windows are movable, position- and scale-persisting, with an optional fixed anchor and grow-direction. |
| FR-42 | M | Item buttons are pooled and reused; a full backpack redraw does not create a new button per slot. |
| FR-43 | M | Stacks can be merged into one button with a total count, with a split slider to pull N out (and this is per-category, not global-only). |
| FR-44 | M | Empty slots are shown either as a compact count per container family or as individual slots, user-selectable. |
| FR-45 | M | Item button decorations: quality color (threshold + intensity), new/recent marker, quest marker, cooldown, locked icon. |
| FR-46 | M | Sorting: sections by name / size desc / size asc / manual order; items within a section by name→quality, quality→name, ilvl, expansion. |
| FR-47 | S | Recent-items handling without Blizzard auto-sort: track new items with a configurable duration, optional "mark all gains as recent", optional flash. |
| FR-48 | S | Money frame attached to a window. |
| FR-49 | S | Two built-in looks: stock-like (BackdropTemplate, Blizzard-ish) and dark/flat. Masque support if it costs < 1 day. |
| FR-50 | C | In-window search bar filtering visible sections/items live. |
| FR-51 | C | "Show real bags" view for swapping equipped bags / buying bank slots. |
| FR-52 | C | Item upgrade arrow vs equipped gear. |
| FR-53 | C | Per-section column override for wide categories (e.g. a 10-wide gear section in a 5-wide window). |
| FR-54 | S | Windows participate in Blizzard's EditMode ("move mode") on Forever: selection highlight, snap preview, magnetism, entered from `/bos move` or a configure-mode handle. Plain drag must still work if EditMode is unavailable. |

**AC-40** 12 sections in a 5-column window: no overlap, no clipped titles, window height matches
content. **AC-41** drag + resize a window, `/reload`, position and scale are where they were.
**AC-44** both empty-slot modes render correctly with a reagent bag / ammo pouch equipped. **AC-54**
`/bos move` opens the vanilla EditMode UI, our windows are selectable and draggable inside it, snap
lines appear against another bag window, positions persist after Exit EditMode and after `/reload`;
repeat with `Blizzard_EditMode` disabled — drag still works. **AC-42** profile item-button count after opening a full backpack stays constant on
re-open. **AC-43** merge 6 partial stacks of 20 linen glyph into one button showing the true total;
split 15 out; count and real slots both correct.

## E. Item interaction

| ID | P | Requirement |
|---|---|---|
| FR-60 | M | Normal item interaction is unchanged: click to pick up, right-click for the standard item menu, drag to spellbars/trade/vendor. The addon must not replace the default item menu. |
| FR-61 | M | Dragging an item onto a section header in configure mode assigns it to that section's category (manual membership). |
| FR-62 | M | Right-click on a section header gives: rename, move up/down, move to window, collapse, hide, disable, sort-this-section, and (at a vendor) sell-all / (at the bank) deposit-all, gated by a setting. |
| FR-63 | M | Right-click on an item gives "Why is this here?" and "Move to category…". |
| FR-64 | S | Keybinds: toggle all backpack windows, toggle bank, open settings, toggle configure mode, open search. Registered via the addon's own binding frame, not by hooking protected bags-bar functions. |
| FR-65 | S | Bulk action: move a whole section's items to another window's section, to the bank, or to the vendor. |
| FR-66 | C | Compress-to-specialty-bag (Baggins' `MoveToSpecialtyBags`) as an explicit button, not automatic. |

**AC-60** pick up / put down / shift-click / right-click menu / drag to a spellbar all behave
identically to stock bags. **AC-61** drag a linen glyph onto "Crafting → Reagents" header; it is
there on next refresh and survives reload.
**AC-63** right-click an item → "Why is this here?" names the category, the matching leaf, and the categories that competed.
**AC-65** sell a whole section at a vendor in one action; the confirm names the item count; gold received matches.

## F. Configuration UX — the reason this project exists

| ID | P | Requirement |
|---|---|---|
| FR-70 | M | One settings window, three panes: navigation (left), editor (center), **live preview** (right). No nested sub-dialogs for structural editing. |
| FR-71 | M | Editing a rule updates the preview pane within one frame: list of matching items (icon + name + count + which window/section they'd land in). |
| FR-72 | M | **Configure mode** (`/bos configure`): the bag windows themselves become the editor — section titles become editable in place, sections and windows are draggable, category chips appear on section headers. |
| FR-73 | M | Rules are shown as **chips** on the category editor (`type = Armor`, `quality ≥ Rare`, `NOT tooltip contains "Bind on Equip"`), each editable in a small popover, drag-reorderable, drag-removable. |
| FR-74 | M | No Apply/Cancel. Every edit commits immediately and is undoable (`Ctrl+Z` in the settings window, plus an Undo button). Redo supported. |
| FR-75 | M | Creating a category from an item is one chain: pick item → "Move to category…" → new name → done, with the match preview already visible. |
| FR-76 | M | The inspector explains placement for any item, including which categories competed and why they lost. |
| FR-77 | M | A first-run state that is useful with zero user action: preset windows + sections + categories, and a visible hint pointing at configure mode. |
| FR-78 | M | Every setting has a discoverable home. A setting with no UI location is not added (enforced at review). |
| FR-79 | S | Guided creation: "make a category from these N selected items" suggests the narrowest rule set that covers them and shows what else it would sweep in. |
| FR-80 | S | Category/window **presets** installable from the settings window (leveling, tradeskill, collections, minimal). |
| FR-81 | S | A "what changed" toast after each structural edit, naming the effect ("3 items moved to Crafting"). |
| FR-82 | S | Search box in the settings window that finds settings by name and by item ("show me every rule that matches Linen Glyph"). |
| FR-83 | C | A read-only layout diagram of windows/sections/categories for users who prefer an overview. |

**AC-70** a person who has never seen the addon can, in under 3 minutes and without help, create a
window named "Sell", put Junk + Quest in it, and confirm it on screen. **AC-71** typing a value in
a rule popover changes the preview list before the popover closes. **AC-74** 10 edits, 10 undos,
state returns exactly to start (verified by SavedVariables diff). **AC-78** every checkbox in the
settings window has an observable effect; any setting with none is removed at review. **AC-72** build 3 windows and 8 sections using configure mode alone, settings window never opened.
**AC-77** fresh install with no config: preset sections exist and are labeled.

## G. Data, profiles, sharing

| ID | P | Requirement |
|---|---|---|
| FR-90 | M | Single SavedVariables file, schema documented in `docs/04`, versioned, with a migration entry point. |
| FR-91 | M | Config is per-profile (own profile store, no library) with Default + per-character profiles; switching profile re-lays-out everything. |
| FR-92 | M | Export/import of windows + sections + categories as a copy-pasteable string. |
| FR-93 | M | No SavedVariables write on item-render hot paths. Writes are debounced (≥ 1 s) and structural only. |
| FR-94 | S | Migrate a Baggins profile (windows → windows, sections → sections, categories/rules → best-effort rule tree) with a report of anything unmappable. |
| FR-95 | S | "Reset this category / window" without resetting the whole profile. |
| FR-96 | C | Share string includes item IDs for manual categories but not character-specific state. |

**AC-92** export from character A, import on character B, layout matches. **AC-93** open/close a
full backpack 20×, then diff the SavedVariables file: no growth from render churn.

## H. Performance & robustness

| ID | P | Requirement |
|---|---|---|
| FR-100 | M | Opening all backpack windows on a full inventory (≥ 100 slots, ≥ 60 distinct items) is under 300 ms measured, and never drops a frame over 50 ms. |
| FR-101 | M | A single item change (loot one item) re-renders in under 50 ms. |
| FR-102 | M | Heavy work is chunked across frames (coroutine/bucket), so a refresh cannot lock the UI thread. |
| FR-103 | M | Unknown/uncached item data (loot an item Blizzard has not sent info for yet) does not misclassify permanently: the item is reclassified when info arrives. |
| FR-104 | M | No memory growth across repeated open/close cycles (pools return what they allocate). |
| FR-105 | S | `luacheck` clean with a committed `.luacheckrc` declaring WoW globals; CI runs it. |
| FR-106 | S | `/bos selftest` runs fixture-based classifier assertions in-game and prints pass/fail. |
| FR-107 | S | Log-only failure: a rule that errors is disabled and reported, not allowed to break the refresh loop. |

**AC-100/101** measured with a profiling command (`/bos perf`) printing ms per phase. **AC-103**
loot a never-seen item, confirm it lands in the catch-all first and moves to the correct category
within 2 s.

## I. Non-functional

| ID | P | Requirement |
|---|---|---|
| NFR-1 | M | Own code stays under ~8,000 LOC through M5; if it exceeds it, the excess is a design smell to review, not a milestone to accept. |
| NFR-2 | M | No vendored library that we do not use at least 30% of. Dependency set decided in `docs/07` Q2. |
| NFR-3 | M | Every directory has a `README.md` explaining its modules (BetterBags pattern). |
| NFR-4 | M | Public module boundaries: `data` never touches frames; `frames` never writes config. |
| NFR-5 | S | enUS only, but all user-facing strings go through one `L` table so localization is a later drop-in. |
| NFR-6 | S | No `print` left in shipped code; diagnostics go through a debug module gated by a flag. |

---

## Review questions this doc should answer

1. Is FR-25 (dynamic categories) Must, or does it hide a complexity explosion? (It is the feature
   users love most in BetterBags and the hardest to render as chips.)
2. Is FR-28 (search DSL) Should or Could? It is the cheapest power-user escape hatch, but it is a
   parser + index + evaluator.
3. Is FR-94 (Baggins migration) worth the effort, given we are migrating our own config?
4. Is FR-64 (own keybind frame) enough, or do we need to hook `OpenAllBags`/`CloseAllBags` like
   Baggins does to make other addons' "open bags" behave? See `docs/07` Q4.
