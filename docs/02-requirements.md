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
| FR-10 | M | The user can create, rename, reorder and delete **windows** (custom bags). Each window has: name, kind (`backpack` \| `bank`), priority (ordering), `openWithAll` flag, column count, icon, saved position and scale. |
| FR-10b | M | A window can be created **as a copy of another window** (typically a bank window copied from its backpack twin): same name pattern, same sections in the same order, same category bindings, then free to diverge. Copy is a command with an inverse. |
| FR-10c | M | **Linked windows.** A window may be *linked* to another (typically a bank window linked to its backpack twin): the two share the same section list and category bindings, so adding, renaming, reordering or re-binding a section on one updates the other. Not shared: kind, columns, scale, position, compact, icon. A link is explicit, visible on both windows, breakable in one action (unlink keeps the current shape as a copy), and never implicit — `copyFrom` (`FR-10b`) records where a window came from; `link` is the thing that keeps them in step (`docs/07` Q11). |
| FR-11 | M | Each window contains ordered **sections**. A section is a labeled block bound to **one or more categories** (`docs/07` Q3 resolved: B). Sections can be renamed, reordered, collapsed, hidden, and moved between windows. Multiple categories in one section are sub-ordered by category priority, then by the section's own sort rule. |
| FR-11b | S | A section may bind a **category group** instead of a single category: binding `Tradeskills.Enchanting` pulls in `Tradeskills.Enchanting.Dust`, `.Essence`, `.Rod` — every category under that dotted prefix (`docs/07` Q8). Group membership comes from the name, so renaming a category out of the prefix moves it out of the section, and the UI says so at rename time. |
| FR-12 | M | A **category** is a named classification rule set that can be referenced by zero or more sections. One category may appear in several windows/sections. |
| FR-13 | M | Backpack and bank are both handled, with bank windows scoped by `kind = bank` and never shown when the bank is closed. |
| FR-14 | M | Items in real containers are harvested exactly once and displayed in virtual windows; the addon does not fabricate inventory. **The shape on this client: character = backpack + 4 bag slots + reagent bag + keyring; bank = a 48-slot base grid at container index 6 plus 8 purchasable bank bags at indices 7..14** (issue #9). The container list is derived from constants and `pcall`-probed, never enumerated from `Enum.BagIndex` — Forever has no `BankBag_*` enum values while the client computes bank-bag indices arithmetically, and those land on the same numbers as `CharacterBankTab_1..9` (issue #9). Indices are de-duplicated: reading one index under two names counts the same items twice. |
| FR-15 | M | An item never appears in two windows/sections unless the category explicitly opts into duplication. |
| FR-16 | M | Items that match no category land in a catch-all section whose name and position the user controls. |
| FR-17 | S | Per-window column count (default 5) independent of other windows. |
| FR-18 | S | A window can be marked "compact" so it shrinks to its content and hides when empty (`hideemptybags`). |
| FR-19 | S | Specialty container awareness: reagent bag / ammo pouch / soul bag slots are visually distinguishable in the empty-slot representation, and their `Enum.BagSlotFlags` (`ClassReagents`, `ClassProfessionGoods`, `ClassJunk`, `ClassEquipment`, `ClassConsumables`, `ClassQuestItems`, `ExpansionCurrent`, `ExpansionLegacy` — verified on Forever) are read, not guessed. **Eight bank bag slots make this matter in the bank too**: a bank with eight containers is where bag affinity compaction (`FR-66`) has something to choose between. |

**AC-10** create 3 windows, rename each, drag window 2 above window 1, delete window 3, `/reload`,
state persists. **AC-10b** copy the "Crafting" backpack window to a bank window; the copy has the
same sections in the same order; edit the copy; the original is untouched; undo removes the copy.
**AC-10c** link a bank window to its backpack twin; add a section on the backpack side and it appears on the bank side; unlink and the bank window keeps the shape it had; `/reload` keeps the link. **AC-11** drag a section from window A to window B; bind two categories to one section; bind a group (`Tradeskills.Enchanting`) and confirm its children appear; collapse it; hide it; reload; state persists. **AC-14** every equipped bag, every bank tab and the keyring (if present) are
accounted for in the harvested totals — compare against stock bag counts. **AC-17** window A set to
8 columns and window B to 4: both pack correctly and independently. **AC-15** with duplication off, `grep` the rendered frames for a duplicated
item GUID — zero. **AC-13** open the bank: bank windows appear, all bank tabs and bank bags are harvested, no backpack window leaks bank contents; close the bank: bank windows are gone.
**AC-16** loot an item no rule matches; it appears in the catch-all named as
configured.

## C. Rules & classification

| ID | P | Requirement |
|---|---|---|
| FR-20 | M | Rules are a declarative tree: `any{...}`, `all{...}`, `none{...}`, each leaf `{field, op, value}`. The tree renders as one readable sentence and is editable without understanding evaluation order. |
| FR-21 | M | v1 field set: `type`, `subtype`, `quality`, `ilvl`, `name`, `tooltip`, `expansion`, `equipSlot`, `bindType`, `itemID`, `classID`, `subclassID`, `containerFamily`, `bagID`, `isReagent`, `isQuestItem`, `isNew`, `category` (reference another category — the composition users actually rely on: 120 uses in the measured config, and the way a curated preset list gets pulled into a user category). |
| FR-22 | M | v1 operators: `=`, `!=`, `>=`, `<=`, `contains`, `startsWith`, `in {…}`. String comparisons are case-insensitive. |
| FR-23 | M | Categories have a numeric **priority**; the first matching category by priority owns the item. Ties broken deterministically (documented in `docs/04` §Precedence) and shown in the inspector. |
| FR-24 | M | `itemID in {…}` is a **leaf inside a rule tree**, so a category can be "type = Consumable AND NOT itemID in {…}" — the single most common shape in real configs. A category may also be a **manual list only** (drag an item in, drag it out) with no other rules. |
| FR-24b | M | Item-ID entry is bulk-friendly: one paste box accepts IDs separated by newlines, commas, semicolons, spaces or tabs, mixed with item links and names, and reports "43 IDs, 2 unknown to this client" before applying. Applies as one command (one undo step). |
| FR-24c | M | "Except this item" is a one-action edit: our item menu (Ctrl+right-click, `FR-60b`) → *Exclude from category* adds `NOT itemID` to that category. Exclusions outnumber conjunctions several to one in real configs; it must not require opening a rule editor. |
| FR-25 | M | A category can be **dynamic**: one section per distinct value of a field (`type`, `subtype`, `expansion`), auto-created, auto-named, no per-value config. |
| FR-26 | M | Editing any rule re-classifies only the affected categories, not the whole inventory. |
| FR-27 | M | Every placed item can be explained: which category, which leaf matched, which higher-priority categories were tested and rejected. |
| FR-28 | S | Search expression authoring: a subset of a query language (`name`, `type`, `subtype`, `ilvl`, `quality`, `expansion`, `slot`, `tooltip`, `id`, `and/or/not`, parentheses, `= != >= <= contains`) that compiles to the same rule tree, and can be saved as a category. |
| FR-29 | S | Rule linting: an empty rule, a rule whose field has no values, a category that matches nothing, and a category referenced by no section are all reported in the UI, not silently inert. |
| FR-30 | S | `shortcut:`-documented escape hatch for a raw Lua predicate per category, with a visible "advanced, unsupported" marker. |
| FR-31 | S | Preset "smart" categories shipped as **data, not code** (consumables, reagents, tradeskill materials by profession, tools, hearth, bandages, junk), organised with dotted names so they demonstrate the grouping convention (`FR-11b`) rather than requiring it. These replace Baggins' `PeriodicTable Set` usage — but LibPeriodicTable has not been meaningfully updated in years and **cannot describe items Forever adds**, so presets must be user-editable: add IDs, remove IDs, rename, disable, and a version marker so a preset update is a visible change rather than a silent overwrite. |
| FR-32 | W | Third-party filter plugins in v1. |

**AC-20** build `any{ all{type=Armor, quality>=Rare}, none{tooltip contains "Bind on Equip"} }`
purely by clicking; the sentence preview matches intent; matching items land in the right section.
**AC-24** a category whose tree is `all{ type = Consumable, none{ itemID in {…50 ids} } }` renders
as one readable sentence and classifies correctly. **AC-24b** paste 43 IDs as one newline-separated
block and as one comma-separated block: same result, unknowns reported, one undo step. **AC-24c**
right-click a misfiled item → Exclude from category → it is gone on the next refresh and survives
`/reload`.
**AC-23** two categories both matching an epic sword; changing priority 10→5 moves it, live, no
reload. **AC-27** right-click any item → "Why here?" and confirm the named rule is the one you
wrote. **AC-26** editing one rule re-classifies only the affected categories — verified by what actually re-classifies, not by a phase delta (`/bos perf` cannot time phases on this client, issue #20).
**AC-28** save a search as a category; loot a new matching item; it lands in that category.
**AC-29** create a category with no rules → UI says it matches nothing.

## D. Layout & rendering

| ID | P | Requirement |
|---|---|---|
| FR-40 | M | Sections are packed into rows within a window up to the window's column count (Baggins-style flow), and the window resizes to its content. |
| FR-41 | M | **Windows are placed, not dragged** (`docs/07` Q24, decided 2026-10-17). The first window anchors where the client's own backpack window opens; each further window stacks **above** it up to a maximum height, then wraps to the **left**. Scale persists per window. Nothing is draggable in v1: the client's own bags are not draggable, and this addon is meant to read as the game's bags (`docs/00` design thesis — the draggable window was inherited from BetterBags and is dropped). Override placement through EditMode (`docs/07` Q13) or an explicit anchor setting, never by dragging the frame. |
| FR-42 | M | Item buttons are pooled and reused; a full backpack redraw does not create a new button per slot. |
| FR-43 | M | **Stack display is a user choice, not a behaviour.** Default: stacks of the same item are merged into one button showing the true total (3 × 20 → one button, 60) and compressed into as few real slots as the affinity rules allow. `showStacks` = `merged` (default) \| `always` (never merge) \| `session` (merged, but a *Show stacks* toggle un-merges until the bags are closed) \| `vendor` (un-merge automatically while a vendor is open). Merging never changes what is actually in which bag. |
| FR-44 | M | Empty slots are shown either as a compact count per container family or as individual slots, user-selectable. |
| FR-44b | M | **Selling does not re-flow the window.** While a vendor is open, a sold item's slot becomes an empty slot **in place**: the section keeps its shape and the remaining items do not move. Re-flow happens when the vendor closes. A re-flow mid-sale moves the button under the cursor between the click and the next drag, which is how a bulk sell sells the wrong item. Recorded, not solved — see the queue in `docs/06`. |
| FR-45 | M | **Quality/rarity presentation is a required feature, with options:** colour the button border or the icon tint or both; a per-quality on/off set; a minimum-quality threshold; an intensity for the tint; and an off state that leaves the client's own quality look alone. Defaults must look like the client's bags, not like a different addon's. |
| FR-45b | M | **Item-level presentation is a required feature, with options:** show ilvl on the button; only on gear (or on everything); minimum ilvl to display; text position and size; optional quality-coloured ilvl text; hide when the item's data is not cached yet (`FR-103`) rather than showing `ilvl 0` or `ilvl 1`. |
| FR-46 | M | Sorting: sections by name / size desc / size asc / manual order; items within a section by name→quality, quality→name, ilvl, expansion. |
| FR-47 | M | **New/recent item highlight**, with a clear policy the user controls: clear when the bags close, or keep the highlight until cleared manually. Clearable by keybind, by context menu, and by `/bos new`. Optional duration-based expiry and optional flash. This exists because Forever has no Blizzard auto-sort and no reliable new-item signal of its own. **The reference is the client's own highlight**: a bright glow around the whole slot that cycles bright → dim (`docs/reference/new-item-highlight-bright.png`, `docs/reference/new-item-highlight-dim.png`). Measured 2026-10-17: our buttons showed it inconsistently and stopped showing it after a `/reload`, because nothing in our paint path calls `ContainerFrameItemButtonMixin:UpdateNewItem(quality)` — whatever appears today is incidental. Scheduled at M2 (`docs/06`); `/bos test 11` is how it gets verified. |
| FR-48 | S | Money and currency display attached to a window, **built on the client's own currency API rather than hand-rolled**: `C_CurrencyInfo` on Forever (`PlayerMoney`, `AccountMoney`, `GetCoinText`, `GetCoinTextureString`, `GetBackpackCurrencyInfo`, `GetCurrencyListInfo`, `GetCurrencyLink`, `SetCurrencyBackpack`, `PickupCurrency`, `CurrencyDisplayUpdate`). Forever ships a currency tab on the character panel, so the data model and the icons are the client's, not ours. |
| FR-49 | M | **No theme system.** Windows and item buttons are built from Blizzard's own pieces (`ItemButton` frame type, `ContainerFrameItemButtonTemplate`, the client's bag/backdrop atlases) so a skinning addon the user already runs applies to our bags without our involvement. Masque support is an optional integration, not a feature (`docs/03` §Integrations, `docs/07` Q16). |
| FR-50 | S | In-window search bar. Our bags are a *view* over real containers, and we already hold `item → (window, section, button)`; search is that map run in reverse. We drive the client's own matcher so the two agree: our search box calls `C_Container.SetItemSearch(text)` and filters with `ItemButtonUtil.GetItemContextMatchResultForItem(ItemLocation:CreateFromBagAndSlot(bag, slot))`, the same predicate Blizzard's `BagItemSearchBox` uses. Extra fields (type, quality, ilvl, expansion, category) run on our enriched record. What this cannot do is search inventory the client does not currently know — and that is out of this addon, not a feature waiting behind a snapshot (`docs/07` Q7, Q15). |
| FR-51 | M | **Real bags stay reachable.** A toggle on the client's bag bar switches between vanilla bags and sorting bags, and a *vanilla-only* view can open one physical bag (e.g. the herb bag) without opening the rest. This is how a player upgrades cloth → linen → silk and moves bags to the bank. |
| FR-52 | C | Item upgrade arrow vs equipped gear, via Pawn when installed (`docs/03` §Integrations) rather than our own comparison. |
| FR-53 | C | Per-section column override for wide categories (e.g. a 10-wide gear section in a 5-wide window). |
| FR-54 | S | Windows participate in Blizzard's EditMode ("move mode") on Forever: selection highlight, snap preview, magnetism, entered from `/bos move` or a configure-mode handle. Plain drag must still work if EditMode is unavailable. Where EditMode exposes a per-system settings dialog (`EditModeSystemSettingsDialogButtonTemplate`), the boring numeric knobs live there: columns, scale, compact, open-with-all. |

**AC-40** 12 sections in a 5-column window: no overlap, no clipped titles, window height matches
content. **AC-41** drag + resize a window, `/reload`, position and scale are where they were; with no
config at all, a fresh install sits where the client's bag bar is. **AC-43** merge 3 stacks of 20 into
one button showing 60; split 15 out; count and real slots both correct; `showStacks = always` shows
the three original stacks instead; `session` un-merges on toggle and re-merges after the bags close.
**AC-44** both empty-slot modes render correctly with a reagent bag / ammo pouch equipped.
**AC-45** quality borders: per-quality toggles, border vs tint, threshold and intensity all visibly
change the buttons; "off" looks like stock bags. **AC-45b** ilvl shows on gear only by default, hides
for an item whose data is not cached, and respects the minimum-ilvl setting.
**AC-47** loot 5 items, close the bags, reopen: highlight present or absent exactly as the
`clearNewOnClose` setting says; `/bos new` and the keybind clear it either way.
**AC-49** with Masque installed and nothing configured by us, our item buttons take the user's
Masque skin. **AC-51** from the bag bar: switch to vanilla bags, open only the herb bag, buy a bigger
bag from a vendor, equip it, switch back — no `ADDON_ACTION_FORBIDDEN`, no lost item.
**AC-54**
`/bos move` opens the vanilla EditMode UI, our windows are selectable and draggable inside it, snap
lines appear against another bag window, positions persist after Exit EditMode and after `/reload`;
repeat with `Blizzard_EditMode` disabled — drag still works. **AC-42** profile item-button count after opening a full backpack stays constant on
re-open.

## E. Item interaction

| ID | P | Requirement |
|---|---|---|
| FR-60 | M | Normal item interaction is unchanged: click to pick up, **right-click for the standard item menu**, drag to spellbars/trade/vendor. The addon must not replace the default item menu. |
| FR-60b | M | **Our item menu lives on a modifier, not on naked right-click.** On bag item buttons the client already owns right-click (item menu), shift-click (`EXPANDITEM` / `SPLITSTACK`) and alt-click (`HandleModifiedItemClick` — inventory scan / link). Our item menu is **Ctrl+right-click** by default, rebindable, and registered through the client's own modified-click settings (`Settings.RegisterModifiedClickSetting` exists on Forever). Naked right-click stays ours everywhere there is no conflict: window titles, section headers, category chips, our bag-bar buttons. |
| FR-61 | M | Dragging an item onto a section header in configure mode assigns it to that section's category (manual membership). |
| FR-62 | M | Right-click on a section header gives: rename, move up/down, move to window, collapse, hide, disable, sort-this-section, show/hide merged stacks, clear new-item highlights, and (at a vendor) sell-this-section / (at the bank) deposit-all — the vendor/bank entries gated by a setting and by `FR-65`'s buyback rules. |
| FR-63 | M | Our item menu (Ctrl+right-click) gives "Why is this here?", "Move to category…", "Exclude from category", and clear-new. |
| FR-64 | S | Keybinds: toggle all backpack windows, toggle bank, toggle vanilla/sorting bags, open search, toggle configure mode, clear new-item highlights. Registered via the addon's own binding frame, not by hooking protected bags-bar functions, and surfaced in the client's Key Bindings panel (`Settings.SetKeybindingsCategory`). **First-run experience must handle the collision**: the default `B` already opens Blizzard's bags, so on first login we detect the conflict and point at the keybind panel instead of silently stealing or silently duplicating it (`docs/07` Q4, `FR-87`). |
| FR-65 | S | Bulk action: move a whole section's items to another window's section, or to the bank. **Selling a whole section is deliberately cautious**: vendor buyback is limited and a mistaken bulk sell is the one action in this addon that can cost a player real gold. Bulk sell therefore (a) names the exact item list and total gold before acting, (b) is limited to categories the user has marked sellable (junk/trash) unless they explicitly enable "sell anything", (c) states the buyback limit rather than implying safety, and (d) is off by default. General vendor integration (price awareness, restock, merchant-specific logic) is out of scope. |
| FR-65b | C | **Auto-sell** (v1.x, not v1): sell a designated trash category, and/or sell grey-quality items, on opening a vendor, with a confirm showing count and gold, and a global off switch. |
| FR-66 | S | **Bag affinities.** A category may declare an affinity to a specialty container family (`Enum.BagSlotFlags`), and virtual compaction prefers a matching physical bag: herbs compact into the herb pouch, ore into the quiver/mining pouch. If the specialty bag is full or absent, the category falls back to an ordinary bag rather than failing. The client's own restriction is never fought: an item the client will not allow in a bag is never targeted. |
| FR-67 | S | **Empty this bag.** A physical bag's context menu (and a button in the vanilla-bags view) moves every item in that bag into other containers, honouring affinities and free-slot counts, so a player can sell or bank an empty bag. |
| FR-68 | M | Physical moves (`FR-65`, `FR-66`, `FR-67`, vendor/deposit) use the pickup→place pattern (`C_Container.PickupContainerItem` on the source, then on the destination slot), are refused during `InCombatLockdown()`, are chunked through the event bucket, verify destination space **before** the first pickup, and never leave an item on the cursor. |

**AC-60** pick up / put down / shift-click / alt-click / right-click menu / drag to a spellbar all
behave identically to stock bags. **AC-60b** Ctrl+right-click opens our item menu; naked right-click
still opens the stock item menu; shift-click still splits stacks. **AC-61** drag a linen glyph onto
"Crafting → Reagents" header; it is there on next refresh and survives reload.
**AC-63** Ctrl+right-click an item → "Why is this here?" names the category, the matching leaf, and
the categories that competed.
**AC-65** sell a section marked sellable at a vendor: the confirm lists every item and the total gold,
and the gold received matches; a section *not* marked sellable cannot be bulk-sold without the
explicit setting, and the confirm states the buyback limit. **AC-66** with a herb pouch equipped, a
virtual stack of 6 partial linen-glyph stacks compacts into the pouch first; unequip the pouch and it
compacts into ordinary bags instead.
**AC-67** empty a 20-slot bag that is full of herbs into a bag with 18 free slots: it refuses with
"2 items, 18 slots free" rather than half-emptying; with room, the bag ends empty and every item is
accounted for. **AC-68** every physical move is attempted in combat and refused with an explanation,
not a taint.

## F. Configuration UX — the reason this project exists

| ID | P | Requirement |
|---|---|---|
| FR-70 | M | **The bags are the editor.** Every structural edit — window, section, category, rule — is reachable from the thing it configures: the window title, a section header, an item, a category chip. The client's Options → AddOns panel exists for browsing, searching and bulk work only, and a full layout must be buildable without ever opening it. |
| FR-71 | M | Blizzard's EditMode carries the boring numeric window knobs (columns, scale, compact, open-with-all, icon) in its own per-system settings dialog where available, because that is where users already go to arrange their UI. Everything else is ours, in context. |
| FR-72 | M | **Configure mode** (`/bos configure`): the bag windows themselves become the editor — titles editable in place, sections and windows draggable, category chips on section headers, context menus on window / section / item. |
| FR-73 | M | Rules are shown as **chips** (`type = Tradeskill`, `quality ≥ Rare`, `EXCEPT tooltip contains "Bind on Equip"`), each editable in a small popover, drag-reorderable, drag-removable. |
| FR-74 | M | The category editor is a small modal whose body is the **live list of your own matching items** — no separate preview pane, because the real inventory is the preview. Editing a chip re-runs the classifier and repaints the list within one frame. |
| FR-75 | M | **Commit model, stated.** Structural edits commit the moment they are made and are *undone*, not cancelled. A half-built **rule tree** is not a valid model state, so the category editor stages a draft with **Apply / Cancel**: Apply is one command (one undo step), Cancel discards the draft. Configure mode has an explicit exit (`Done`, `Esc`, idle timeout) that is **not** a commit boundary — nothing is pending when you leave. Invalid edits are refused in the modal (Apply disabled) rather than committed and then undone. |
| FR-76 | M | Undo/redo are **buttons** (configure-mode bar, category editor, toast action). `Ctrl+Z`/`Ctrl+Y` are not bound by default: they sit next to WASD and are plausibly someone's spell, macro or addon. A user may bind them in the keybind panel. |
| FR-77 | M | Creating a category from an item is one chain: pick item → "Move to category…" → new name → done, with the match list already visible. |
| FR-78 | M | The inspector explains placement for any item, including which categories competed and why they lost. |
| FR-79 | M | A first-run state that is useful with zero user action: preset windows + sections + categories, and a visible hint pointing at configure mode. |
| FR-80 | M | Every setting has a discoverable home. A setting with no UI location is not added (enforced at review). |
| FR-81 | S | Guided creation: "make a category from these N selected items" suggests the narrowest rule set that covers them and shows what else it would sweep in. |
| FR-82 | S | Category/window **presets** installable from Options → AddOns (leveling, tradeskill, collections, minimal). |
| FR-83 | S | A "what changed" toast after each structural edit, naming the effect ("3 items moved to Crafting") and carrying the Undo action. |
| FR-84 | S | A Find pane that searches by name and by item ("show me every rule that matches Linen Glyph"), with jump-to-result. |
| FR-85 | S | Window icons are configurable through the client's own icon picker (`IconDataProviderMixin` / `IconSelectorPopupFrameTemplate` — the picker the macro UI uses), stored as the bare `Interface\ICONS\` name. Our own overlay art may be drawn on top of the chosen icon. |
| FR-86 | C | A read-only layout diagram of windows/sections/categories for users who prefer an overview. |
| FR-87 | M | **An intro / help page.** "Configure it by touching it" is not a familiar shape, and a novel UI that is never explained gets uninstalled. A `?` in every modal and on the configure bar opens a page that explains the three nouns, the four gestures (right-click, drag, in-place name, Apply/Cancel on rules), where each kind of setting lives, and what Undo does. It also carries the first-run keybind-conflict prompt (`FR-64`). Ships **after the PoC and before 1.0** — not at M0, because the UI it describes must exist first, and not at M7, because by then it is documentation rather than onboarding. |
| FR-88 | M | **Settings that need a window live in the client's own Options → AddOns panel.** Forever ships the modern settings API (`Settings.RegisterAddOnCategory`, `Settings.RegisterVerticalLayoutCategory`, `Settings.RegisterCanvasLayoutCategory`, `Settings.RegisterProxySetting`, `Settings.SetKeybindingsCategory` — verified in `Blizzard_Settings_Shared/Blizzard_Settings.lua` on `origin/forever`, `AllowLoad: Both` with Camelot overrides). The utility panes (profiles, presets, import/export, find) register there; the editor stays on the bags. No AceConfig, and no second settings window of our own invention. |
| FR-89 | S | Category and section **name completion**: typing `Tradeskills.` offers existing children and suggests continuing the dotted convention, so the grouping convention (`FR-11b`) is supported without being forced. |

**AC-70** a person who has never seen the addon can, in under 3 minutes and without help, create a
window named "Sell", put Junk + Quest in it, and confirm it on screen — **the Options panel never
opened**. **AC-74** the category editor's item list changes within one frame of a chip edit, using
real inventory. **AC-75** build a draft rule tree, Cancel it → model unchanged; Apply it → one Undo
removes the whole tree. **AC-76** 10 edits, 10 undos via buttons, state returns exactly to start
(verified by SavedVariables diff); `grep` finds no default `SetBinding` of Ctrl+Z/Ctrl+Y.
**AC-80** every setting we expose has an observable effect; any setting with none is removed at review. **AC-72** build 3 windows and 8 sections using configure mode alone.
**AC-79** fresh install with no config: preset sections exist and are labeled.
**AC-85** pick a macro-picker icon for a window, `/reload`, it is still there; export/import carries
it. **AC-87** a person who has never seen the addon reads the help page once and then completes the
AC-70 task without asking. **AC-88** Options → AddOns → *Bags of Sorting* shows our utility panes
and our keybinds appear in the client's Key Bindings panel.

## G. Data, profiles, sharing

| ID | P | Requirement |
|---|---|---|
| FR-90 | M | Single SavedVariables file, schema documented in `docs/04`, versioned, with a migration entry point. |
| FR-91 | M | Config is per-profile (own profile store, no library) with a **shared Default** and **per-character overrides** that inherit from Default and store only the differences (`docs/07` Q11). Switching profile re-lays-out everything. |
| FR-92 | M | Export/import of windows + sections + categories as a copy-pasteable string. |
| FR-93 | M | No SavedVariables write on item-render hot paths. Writes are debounced (≥ 1 s) and structural only. |
| FR-94 | W | Migrate a Baggins profile. **Deferred** (`docs/07` Q5): ship two sensible default profiles instead. The migration table in `docs/04` stays in the spec as the answer to "if we ever do it", and if anything is migrated the target is Bagnon/AdiBags-shaped data, which has the users. |
| FR-95 | S | "Reset this category / window" without resetting the whole profile. |
| FR-96 | C | Share string includes item IDs for manual categories but not character-specific state. |
| FR-97 | M | A **persistent item-info cache** (`itemID → name, quality, type, subtype, ilvl, icon`), bounded and debounced. Without it, a category holding 40 pasted item IDs re-requests every one of them at every login (`FR-103`). This is the one piece of derived state we do persist, and `docs/04` says so explicitly. |

**AC-92** export from character A, import on character B, layout matches. **AC-93** open/close a
full backpack 20×, then diff the SavedVariables file: no growth from render churn. **AC-97** log out
with a 40-ID manual category, log back in, `/bos perf` shows zero `RequestLoadItemDataByID` calls
for cached IDs.

## H. Performance & robustness

| ID | P | Requirement |
|---|---|---|
| FR-100 | M | Opening all backpack windows on a full inventory (≥ 100 slots, ≥ 60 distinct items) is under 300 ms measured, and never drops a frame over 50 ms. |
| FR-101 | M | A single item change (loot one item) re-renders in under 50 ms. |
| FR-102 | M | Heavy work is chunked across frames (coroutine/bucket), so a refresh cannot lock the UI thread. |
| FR-103 | M | **Uncached item data is a normal state, not an error.** `C_Item.GetItemInfo` is documented `MayReturnNothing` on Forever: the client only knows items it has seen. `C_Item.GetItemInfoInstant` gives icon/type/classID/subclassID without a server round trip; `C_Item.RequestLoadItemDataByID(itemID)` + `ITEM_DATA_LOAD_RESULT` (and Blizzard's own `AsyncCallbackSystemMixin`, `ASYNC_ITEM`) fetch the rest asynchronously. An item with no info yet renders in the catch-all with a pending marker and re-sorts when the info arrives; a manual item-ID category renders icons immediately and names as they resolve. Nothing ever blocks a refresh waiting for item data. |
| FR-104 | M | No memory growth across repeated open/close cycles (pools return what they allocate). |
| FR-105 | S | `luacheck` clean with a committed `.luacheckrc` declaring WoW globals; CI runs it. |
| FR-106 | S | The fixture-based classifier assertions run **off the client** (`lua5.1 tests/run.lua`, run by CI). The addon loads no test code: `tests/` is not in the TOC and is excluded from the release package. |
| FR-107 | S | Log-only failure: a rule that errors is disabled and reported, not allowed to break the refresh loop. |

**AC-100/101** measured with `/bos test 13` (ms per refresh sampled across frames) plus `/bos perf` for what a refresh did; per-phase ms is unmeasurable on this client (issue #20). **AC-103**
loot a never-seen item, confirm it lands in the catch-all first and moves to the correct category
within 2 s; then `/script C_Item.RequestLoadItemDataByID(26042)` on an item never seen and confirm
the pending button resolves without a reload.

## I. Search, and what search must never become

| ID | P | Requirement |
|---|---|---|
| FR-109 | M | **Nothing derived is persisted except the item cache (`FR-97`).** No bank snapshot, no alt snapshot, no inventory store. This is a rule, not an absence: earlier drafts of this spec carried a `snapshot` table and a closed-bank search feature, and both are deleted. |
| FR-113 | M | **The model stays clean enough that an API would be possible.** Categories, rule trees, windows and sections remain plain data with stable names and a version marker — no Lua closures in the schema, no classifier logic entangled with storage, no profile-specific hacks in the rule grammar. This is an internal hygiene requirement, **not** a shipped API: `BagsOfSortingAPI`, a LibDataBroker feed, or any other transport is a later decision made by whoever needs it, and it is explicitly not our problem now. What is ours is making it *possible* without a rewrite — which we want for our own reasons (export/import, migration, tests) whether or not anyone else ever reads it. |

**Why offline search left this addon.** Three reasons, each sufficient on its own:

1. **It ends in a trip to the bank anyway.** "You have 3 Linen Glyph in the bank" has exactly one
   possible follow-up action, and it is walking to a bank. An answer that cannot be acted on is trivia.
2. **It is incomplete by construction.** The item is just as likely to be in an alt's bank. A feature
   that answers the question for one character is not answering the question.
3. **It is a different problem.** "Do I have this thing anywhere" is a *database* question. "Organise the
   stuff so I can manipulate it" is a *manipulation* question. This addon is the second one, and merging
   the first into it means persisting inventory, a results UI that is not a bag, and a privacy story —
   all to serve the weakest version of the answer.

So the split is: **we keep classification clean and self-contained; anyone who wants cross-character
storage builds it.** If such an addon ever wants our category definitions, the fact that they are plain
versioned data is what makes that a twenty-line job instead of a fork — but designing a transport for a
consumer that does not exist yet is how projects acquire surface area they then have to support forever.

Out of this addon entirely: searching the bank while it is closed, searching alts and alt banks,
searching the guild bank (`docs/07` Q15, Q22).

**AC-109** `stat` the SavedVariables file before and after a session that opens the bank, searches, and
reloads: no inventory blob.
**AC-113** `grep` the schema and the rule registry for functions stored in data (`= function`, closures
in SavedVariables, `setfenv`): zero. A category's rule tree round-trips through `Export()`/`Import()`
without our process being alive.

## J. Integrations (no vendored libraries)

| ID | P | Requirement |
|---|---|---|
| FR-120 | M | `## AddonCompartmentFunc` + `## IconTexture` so the addon has a native home on Forever (verified present: `Blizzard_Minimap/Mainline/AddonCompartment.lua`, `[AllowLoadGameType mainline]`, no camelot exclusion). |
| FR-121 | S | Masque: register our item buttons with a Masque group when Masque is loaded (`LibStub('Masque', true)`, ~40 lines, optional dep). Never required, never vendored. |
| FR-122 | C | Pawn upgrade arrow via `PawnShouldItemLinkHaveUpgradeArrowUnbudgeted` when Pawn is loaded, behind our upgrade-provider seam (BetterBags `integrations/pawn.lua` shape). |
| FR-123 | M | **No minimap button, and therefore no LibDBIcon.** The home is the Addon Compartment plus Options → AddOns (`FR-88`). A minimap icon is not a feature we are postponing; it is a feature we are not building. |
| FR-124 | C | Coexistence tested against the addons actually installed here: `ForeverPlus` (which already repositions the vanilla bag window), `Leatrix_Plus` (which can `hooksecurefunc('OpenAllBags', CloseAllBags)`), `Baggins`, `BetterBags`. |
| FR-125 | C | Optional integrations are **later additions, not requirements**: Pawn (`FR-122`), Masque (`FR-121`). Each is a guarded read of another addon's published data, never a dependency, never vendored. The reverse direction — us publishing our classification for an alt-database addon — is `FR-113`. |
| FR-126 | M | **Items looted during combat are visible in our windows immediately**, not when combat ends. Sorting them mid-combat is not required: an unsorted item may land in the catch-all or the last section and re-sort on regen. Measured 2026-10-17: the client's own bag window shows a mid-combat loot instantly; ours shows it only after regen, because painting a secure `ItemButton` is a protected call. *How* is `docs/07` Q23's decision at M4; this requirement is the outcome, not the mechanism. |

**AC-120** the addon appears in the Addon Compartment with our icon and opens configure mode.
**AC-124** run each of the four alongside us and record what breaks in the coexistence issue.

## K. Non-functional

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
   users love most in BetterBags and the hardest to render as chips.) — **open**, `docs/07` Q8.
2. Is FR-28 (search DSL) Should or Could? It is the cheapest power-user escape hatch, but it is a
   parser + index + evaluator. — **open**, `docs/07` Q7.
3. ~~Is FR-94 (Baggins migration) worth the effort?~~ **answered: no, deferred** (`docs/07` Q5).
4. Is FR-64 (own keybind frame) enough, or do we need to hook `OpenAllBags`/`CloseAllBags` like
   Baggins does to make other addons' "open bags" behave? See `docs/07` Q4. — **open**, M2 test.
5. Does FR-11 (a section may bind several categories) survive contact with the layout engine? It is
   the change with the largest blast radius in this doc: `docs/04` schema, `layout/flow`, the
   section header UI, and the precedence explanation all move together.
