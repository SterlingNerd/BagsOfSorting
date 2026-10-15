# 01 — Reference Analysis: Baggins & BetterBags

Scanned at `../addons/Baggins` @ main (upstream doadin/Baggins) and
`../addons/BetterBags` v0.5.14 (Camelot TOC, 2026-10-02). Both are read-only clones.

Size, for calibration:

| | Baggins | BetterBags |
|---|---|---|
| Lua LOC (own code) | 13,352 (4,416 core + 4,823 options + 538 filtering + 385 itemops + 362 search + 333 skins + ~2,000 in 30 filter files) | 28,207 own code, plus vendored Ace3/LibUIDropDownMenu/etc. |
| Biggest file | `Baggins-Options.lua` (4,823) — the config layer | `data/items.lua` (2,469) — the item pipeline |
| Config layer as share of own code | **36%** | ~7% (`config/*.lua` = 2,321) |
| Profile options (flat keys) | **57** (`dbDefaults.profile`, `Baggins-Options.lua:649`) | grouped per `kind` in `core/database.lua` accessors |
| SavedVariables | `BagginsDB` | `BetterBagsDB` |

That first row is the whole argument for this project: Baggins spends more than a third of its
own code on configuration UI, and it is the part users complain about.

---

## Baggins

### Data model (what we want to keep)

```
db.profile.bags      = array of { name, isBank, priority, openWithAll, sections = array of
                        { name, cats = array of category names, allowdupes, hidden } }
db.profile.categories = map catname -> array of rules { type, operation, <type-specific fields>, ids? }
db.profile.columns   = global max columns per bag window
db.profile.skin      = skin name (Baggins-Skins.lua supplies metrics + textures)
```

Three distinct concepts, and they are the right three:

1. **Window / custom bag** — a real on-screen frame the user created. `NewBag` appends
   `{name, openWithAll=true, sections={}}` (`Baggins.lua:3910`). Windows have `priority` (1..20)
   controlling draw/flow order, `isBank` to scope them to the bank, and `openWithAll` to opt out
   of the "open all bags" keybind.
2. **Section** — a labeled block inside a window. A section is a *container of categories*, not a
   category itself. That indirection is what makes "Crafting window → Herbs + Ores + Reagents"
   expressible.
3. **Category** — a named rule set, reusable across sections and windows.

### Rule engine

`AddOn:AddCustomRule(name, {DisplayName, Description, Matches(bag,slot,rule), Ace3Options,
DewDropOptions, CleanRule})` — 30 filter files register types:

`Anima, Bag, Category, Conduit, ContainerType, Empty, EquipLocation, EquipmentSet, EquipmentSlot,
Expansion, ItemBind, ItemID, ItemLevel, ItemName, ItemType, Keystone, Lockbox, NewItems, Other,
PeriodicTable, Profession, Quality, Scrap, ScrapAddon, Teleport, Tooltip, Toy`
(retail-only ones are TOC-gated; `PeriodicTable` pulls in 9 LibPeriodicTable modules).

Matching (`Baggins-Filtering.lua:CheckCategory`):

```lua
for ruleid, rule in ipairs(category) do
  operation = (ruleid == 1) and "OR" or (rule.operation or "OR")
  rulematch = RuleTypes[rule.type].Matches(bag, slot, rule)
  if operation == "OR"  then catmatch = catmatch or rulematch end
  if operation == "AND" then catmatch = catmatch and rulematch end
  if operation == "NOT" then catmatch = catmatch and (not rulematch) end
end
```

Plus: `Category` rule type recurses into another category (recursion guarded by a
`recursionmagic` counter), `Other` is a catch-all rule that claims whatever nothing else claimed,
per-`(bag,slot)` caches (`categorycache`, `bankcategorycache`) keyed `"bag..':'..slot"`, and
signals `CategoryMatchAdded / CategoryMatchRemoved / SlotMoved` drive incremental relayout.

**Keep:** the pluggable rule-type registry, the per-slot cache, the incremental signal model,
`Other` as an explicit catch-all, category reuse across windows.
**Refuse:** order-dependent `OR/AND/NOT` chaining (semantics change when you reorder a rule —
and reordering is a config UI action), per-type bespoke option tables, per-type bespoke dewdrop
UI, `rule.ids` side-table for manual membership.

### Layout engine

`FlowSections` ("Like a river, man") packs sections into rows inside a window up to
`profile.columns`, accounting for collapsed sections' title width; `GetSectionSize`,
`OptimizeSectionLayout`, `UpdateBagFrameSize` resize the window; windows are movable, positions
saved per window (`SaveBagPosition`), plus a global `layoutanchor` + 4 offsets for auto-layout.
Sections can be collapsed/hidden; empty sections hidden by default.

**Keep:** river packing, per-window saved position, collapsed sections, shrink-to-fit width.
**Refuse:** one global `columns` for every window (per-window is what users actually want).

### Display features worth having

`compressall / compressstackable / compressempty / CompressShards / CompressAmmo` (+ per-window
compress button), quality coloring with threshold + intensity, quest-item highlight, new-item
`*New*` / `*+++*` markers with `newitemduration=420`, `hideduplicates = global|bag|disabled`,
`alwaysresort`, item upgrade arrow, empty-slot counts with special/ammo/soul/key breakdown
(`CountNormalSlots`, `CountAmmoSlots`, `CountSoulSlots`, `CountSpecialSlots`, `CountKeySlots` via
LibBagUtils), money frame, bank control frame, in-bag search (`Baggins-Search.lua`), split-stack
slider (`BagginsItemButton_Split`), compress-to-specialty-bag (`MoveToSpecialtyBags`).

### The config layer (the thing we are replacing)

- Two option tables: `Baggins` (Blizzard options panel) and `BagginsEdit` ("Waterfall Config
  window", opened from a button in the bag menu).
- Dynamic rebuild functions that regenerate the whole option tree on every structural change:
  `RebuildOptions`, `RebuildBagOptions`, `RebuildSections`, `RebuildCategoryOptions`,
  `RebuildCategoryRules`, `RebuildBagCategoryOptions`.
- Structural editing expressed as AceConfig widgets: `baglistitem<id>` inline groups with
  `name` input + `^` / `v` / `X` execute buttons (`width = "half"`), `select` widgets whose values
  are "all other bags" for copy/import, `arg = bag` pointer-passing, `getArgName/setArgName`
  accessors, `confirm = confirmRemoveBag` dialogs.
- Rule editing: `select` of rule types → `RebuildCategoryRules` → per-rule inline group →
  `OpenRuleDewdrop` (LibQTip) for the type-specific fields.
- 57 flat profile keys, several of them mutually dependent (`compressall` disables four others;
  `qualitycolor` gates `qualitycolormin` and `qualitycolorintensity`; `highlightnew` gates
  `Reset New`).

Concrete toil, in user terms:

| Task | Baggins interaction count |
|---|---|
| Rename a window | open edit config → find window in scroll list → click → edit name → close |
| Move a section to another window | open edit config → window → sections list → remove → other window → add category → close |
| Reorder two sections | 1–3 `^`/`v` clicks, each triggering a full option-tree rebuild |
| Add "all epic items" to a section | new category → add rule → pick `Quality` → pick `>=` → pick Epic → add category to section → close → open bags |
| Understand why an item is in section X | not possible from the UI |

### Bugs/limits observed while reading

- `CleanRule` wipes a rule then sets `rule.type = type` — `type` is the *Lua function* `type`, not
  the rule type (`Baggins-Filtering.lua:64`). Rules survive only because `rule.ruletype` is read
  for the clean hook and `rule.type` is separately assigned by callers. Do not copy this.
- `OnEnable` re-registers events that were commented out just above it (`PLAYERREAGENTBANKSLOTS_CHANGED`,
  `PLAYERBANKBAGSLOTS_CHANGED`), i.e. bank-bag purchase handling is half-disabled.
- `db.profile.hideduplicates` had a boolean→string migration inside `OnEnable` rather than a
  migration step.
- `self.db.char.lastNumItemButtons` is written on every button acquire — a SavedVariables write
  path on a hot loop.
- Retail/Classic branching is repeated inline at ~30 call sites instead of behind a capability
  layer.

---

## BetterBags

### What it gets right (steal these)

**Form-based settings window.** `forms/form.lua` + `forms/layouts/stacked.lua`: a scrollable
window with `AddSection / AddCheckbox / AddDropdown / AddSlider / AddInputBox / AddTextArea /
AddColor / AddButtonGroup / AddInlineSubSection / AddSubIndex`, an optional clickable index that
scroll-to-sections, `tabbed = true`, theme integration, and per-widget `getValue/setValue(ctx)`
binding. `config/config.lua` (1,142 lines) builds the whole settings UI from it — no AceConfig
dialog anywhere (the only `AceConfigRegistry:NotifyChange` call in the addon is commented out).
This is the single most reusable idea in either repo.

**Real dialogs, not dropdowns.** `frames/question.lua` gives `YesNo`, `Alert`, `AskForInput`;
`frames/groupdialog.lua` and `frames/searchcategory.lua` are purpose-built editors.

**Category model.** `data/categories.lua`: permanent vs ephemeral membership, enabled/disabled/
hidden/pinned, rename, delete, dynamic categories (`IsDynamicCategory`, `IsGroupBySubcategory`),
search categories with `priority` and `groupBy` (none/type/subtype/expansion).

**Unified precedence resolution.** `items:GetCategory` — recent items → gear set → search category
vs manual category by numeric priority (lower wins, tie goes to search) → junk → equipment
location → type/subtype/tradeskill. Priority is a number the user can see.

**Search as a first-class language.** `util/query.lua` (lexer + parser → AST) and `data/search.lua`
(indexed fields + `EvaluateAST`): `name, type, subtype, category, slot, expansion, equipmentSet,
guid, binding, tooltip, ilvl, rarity, id, count, class, subclass, bagid, slotid, bindtype,
reagent, bound, quest, activeQuest` with `= != %= > < >= <= and or not ()`. Any search can become
a category (`Enter to Make Category`). This is the best "power user escape hatch" in either repo.

**Refresh pipeline.** `items.lua` is an explicit 11-phase pipeline (`Phase1_DetermineBags` →
`Harvest` → `ExtractPreviousState` → `ClearMovedItemGlows` → `EnrichData` → `ApplyVirtualStacks` →
`EnrichCategories` → `BuildOrderedItems` → `Sort` → `PartitionIntoTabs` → `CommitAndDispatch`),
run through `core/async.lua` coroutines (`Each`, `Batch`, `StableIterate`) so a big backpack does
not hitch the UI. `core/context.lua` passes a Go-style context through every call, which is how
cancellation and event provenance stay sane.

**Object pooling** (`core/pool.lua`), **event bucketing** (`events:BucketEvent`, 0.2 s),
**profiles** (`DB:SwitchToProfile/CreateProfile/CopyFromProfile/RenameProfile/DeleteProfile/
GetProfileCharacterCounts`), **export/import** (`util/serialization.lua` serialize + base64),
**per-module READMEs** (every directory has one — this is why the repo is navigable at 28k LOC),
**plugin API** (`config/plugin.lua` merges plugin option tables into the form), **integrations**
(Pawn, Masque, QuickFind, ConsolePort, SimpleItemLevel), **themes as modules**
(`themes/themes.lua` + `default/simpledark/gw2/elvui`).

**Forever handling is a good template.** `core/forever.lua` loads only from
`BetterBags_Camelot.toc` and sets `addon.isForever` before `constants.lua` sizes tables;
`addon.hasWarbank = addon.isRetail and not addon.isForever` gates every warbank path, and the
account-bag tables are simply not built on Forever, so table-driven sites go inert with no
per-site branching. Copy this pattern.

### What it does not give us (the gap)

- `const.BAG_VIEW = { SECTION_GRID = 2, SECTION_ALL_BAGS = 4 }` — views are per-window grids.
  There is no user-defined window, no section→category-grouping, no per-window column count or
  priority. `groups.lua` puts categories on **tabs** at the bottom of one window; that is a
  different axis from Baggins' "several windows you can place independently".
- Category assignment is a chain of hardcoded filters in `items:GetCategory`; a user cannot add a
  new *kind* of rule without writing a plugin.
- `config/config.lua` is 1,142 lines of hand-written form calls. Fine for flat settings, but
  structural editing (windows/sections) is done in separate bespoke panes (`categorypane.lua` is
  561 lines) rather than on the bags.

### Things to avoid

- Vendoring all of Ace3 + LibUIDropDownMenu + WagoAnalytics (736 KB of `libs/`) for an addon that
  uses `AceAddon/AceDB/AceHook/AceEvent/AceGUI/AceConfig` partially.
- `debug/` + `frames/debug.lua` + `core/translations.lua` (108 KB generated translations) shipped
  in the same package as the addon.
- Analytics shim loaded unconditionally.

---

## Steal / adapt / refuse — summary

| Idea | Source | Verdict |
|---|---|---|
| user-defined windows (custom bags) with priority + openWithAll | Baggins | **steal** |
| section = ordered container of categories | Baggins | **steal** |
| river packing of sections into rows | Baggins | **steal** |
| per-slot category cache + match signals | Baggins | **steal** |
| pluggable rule-type registry | Baggins | **adapt** → declarative field registry |
| order-dependent OR/AND/NOT rule chaining | Baggins | **refuse** → `any/all/none` tree |
| AceConfig waterfall + dynamic option-tree rebuilds | Baggins | **refuse** |
| 57 flat profile keys | Baggins | **refuse** → grouped, defaults-first |
| per-type bespoke option UI | Baggins | **refuse** → one chip editor |
| form system for settings window | BetterBags | **steal** (own minimal version) |
| numeric category priority + explicit precedence chain | BetterBags | **steal** |
| search DSL → save-as-category, groupBy | BetterBags | **adapt** (v1: subset of fields) |
| 11-phase async refresh pipeline | BetterBags | **steal** (shape, not code) |
| context objects through every call | BetterBags | **steal** |
| export/import base64 strings | BetterBags | **steal** |
| per-directory READMEs | BetterBags | **steal** |
| capability flags + table-inert gating for Forever | BetterBags | **steal** |
| category tabs/groups inside one window | BetterBags | **out of scope v1** (windows replace it) |
| vendored Ace3 + analytics | BetterBags | **refuse** |
