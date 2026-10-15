# 03 — Architecture

Shape borrowed from BetterBags (module-per-concern, explicit pipeline, context objects, per-dir
READMEs) with Baggins' window/section/category vocabulary and a config layer that is a command
log rather than an option tree.

---

## Module map

```
core/      boot, client, constants, context, events, db, async, pool, log
data/      harvest, enrich, classify, rules, stacks, sort, layout-model, windows, sections, categories
layout/    flow (river packing), sizing, anchors
frames/    window, section, item, header, chips, menu, inspector, money, empty-slot
config/    commands, undo, settings-window, panes/{windows,sections,categories,rules,preview},
           configure-mode, presets, importexport
filters/   field registry (one file per field: type, quality, ilvl, name, tooltip, ...)
themes/    themes, stock, dark
util/      serialize, color, text, query (if FR-28 lands), test
```

Load order = `core → data → layout → frames → config → themes → filters → util → core/init`.
`core/init.lua` last, like BetterBags, so every module exists before anything is enabled.

---

## The pipeline

One refresh, explicit phases (BetterBags' `Phase1..11` reduced to what we actually need):

```
1 harvest   which containers belong to which kind (backpack/bank); read slots
2 enrich    item info (async, cache-aware), expansion, equip slot, bind, quest, sets
3 classify  for each item: evaluate categories by priority → owner category
4 assign    category → section(s) → window(s); apply duplicate policy
5 stack     merge virtual stacks per category policy
6 sort      sections order + items within section
7 flow      pack sections into rows within each window's column budget
8 render    acquire pooled item buttons, paint, resize window, commit
```

Rules:
- Phases 1–7 are pure functions over a `Snapshot` table. **No phase touches a frame.** Only
  `render` does. This is what makes the classifier testable (`/bos selftest`) and what makes the
  config preview pane cheap: the preview runs 1–7 against a filtered snapshot and renders a list.
- Each phase runs inside a `Context` (BetterBags pattern) carrying the triggering event, so a
  burst of `BAG_UPDATE` events can be cancelled/coalesced.
- `events:BucketEvent('BAG_UPDATE', 0.2)` coalesces; `async.Batch` chunks 2–7 across frames when
  the item count exceeds a threshold (start: 60).
- Incremental path: a single slot change re-runs 2–4 for that slot, then re-flows only the
  affected sections. `FR-26` depends on this.

### Classification

```lua
-- data/classify.lua
owner = nil
for _, cat in ipairs(categoriesByPriority) do
  if cat:matches(item) then owner = cat; break end
end
trace = { tested = {...}, matched = owner, rejected = {...} }   -- feeds FR-27 inspector
```

`trace` is kept per item for the current snapshot only (not persisted). It is the single most
important debuggability feature in the design.

### Rule representation

```lua
category = {
  name     = "Crafting → Herbs",
  priority = 10,
  kind     = "rules" | "manual" | "dynamic",
  rules    = { op = "all", children = {
               { op = "any", children = {
                   { field = "type",    cmp = "=",      value = "Tradeskill" },
                   { field = "subtype", cmp = "startsWith", value = "Herb" },
               }},
               { field = "quality", cmp = ">=", value = 2 },
             }},
  dynamicField = nil,          -- "type" | "subtype" | "expansion" for kind = "dynamic"
  itemIDs  = nil,              -- for kind = "manual"
  duplicate = false,           -- FR-15
  enabled  = true,
}
```

Fields come from a **field registry** (`filters/`), one file per field:

```lua
fields.register({
  key = "quality",
  label = "Quality",
  valueKind = "enum",                 -- enum | number | string | bool | idlist
  values = function() return qualityEnum() end,   -- { {v=2,label="Uncommon",color=...}, ... }
  cmps = { "=", "!=", ">=", "<=" },
  read = function(item) return item.quality end,
  sentence = function(rule) return ('quality ≥ %s'):format(qualityName(rule.value)) end,
})
```

`sentence` is what the chip renders and what the preview header prints. A field without `sentence`
is not allowed in the registry — that is how `FR-20`'s "readable sentence" is enforced in code.

---

## Config layer: commands, not options

```
UI widget → config:execute(Command) → model mutation → model emits change → data re-classify
                                       ↘ undo log entry
```

Commands are small named records: `{ type = "section.move", args = {...}, invert = fn }`.
Everything the settings window and configure mode can do is a command; nothing else mutates the
model. Consequences:

- `FR-74` undo/redo is a log walk, not a snapshot diff.
- Configure mode and the settings window are two views over the same command set — no duplicated
  logic, no risk of them disagreeing.
- `FR-81` "what changed" toast comes free: the command knows which categories it touched, and the
  re-classify pass reports moved-item counts.
- Import/export is a serialized command list or a model dump (choose in `docs/07` Q6).

**No AceConfig.** The settings window is built on a small in-house form builder (checkbox,
slider, dropdown, input, color, button group, section header, index) — the BetterBags `forms/`
idea, sized to what we use (~400 lines, not 1,100).

---

## Client capability layer

`core/client.lua` is the only file that knows what the client can do. Everything else asks:

```lua
if client.has('reagentBank') then ... end
local btnType = client.get('itemButtonType')     -- 'ItemButton' on Forever
```

Forever facts (from `agents.md`) are resolved once at load:

| capability | Forever |
|---|---|
| `itemButtonType` | `ItemButton` |
| `reagentBank` | false |
| `warbank` | false |
| `blizzSort` | false |
| `containerQuestInfo` | true (`C_Container.GetContainerItemQuestInfo`) |
| `modernMoney` | true (atlas coin textures) |
| `keyring` | verify in-game (Baggins treats Forever as classic-like here) |

Pattern to copy from BetterBags: when a capability is false, **do not build the table that drives
the feature**, so table-driven loops go inert instead of every call site gaining a branch.

---

## Taint & combat strategy

- Item buttons: created from `ContainerFrameItemButtonTemplate` + `SecureActionButtonTemplate`
  (Forever uses the `ItemButton` frame type). Pool them (`core/pool.lua`). Pre-warm the pool at
  `ADDON_LOADED` sized from a persisted high-water mark, but **write that mark debounced**, not on
  every acquire (Baggins' `lastNumItemButtons` bug).
- If a button must be created during `InCombatLockdown()`, mark it `tainted`, show it, and replace
  it on `PLAYER_REGEN_ENABLED`. Log once, not per button.
- No hooking of `OpenAllBags`/`CloseAllBags`/`ToggleBackpack` in v1 unless `docs/07` Q4 decides
  otherwise; instead our own keybinds + our own close-all-on-`PLAYER_INTERACTION_MANAGER_FRAME_SHOW`.
- Deferred init: plain `CreateFrame("Frame")` + `PLAYER_REGEN_ENABLED` if `InCombatLockdown()` at
  enable time. Never an AceEvent-mediated deferral (parent `../agents.md` §Debugging).

---

## Dependencies: none vendored (v1)

Evidence, not taste. BetterBags lists `AceGUI-3.0` and `AceConfig-3.0` in its TOC and uses **zero**
of either in its own 28k LOC — its entire settings UI is `WowScrollBox` + `MinimalScrollBar` +
`ScrollUtil` + `UIPanelButtonTemplate` + `InputBoxTemplate` + `WowStyle1DropdownTemplate` +
`UICheckButtonTemplate` + `UISliderTemplate` + `ButtonFrameTemplate`. The only Ace3 it actually
consumes is `AceAddon` (70 `NewModule` calls), `AceDB`, `AceEvent`, `AceHook`, `AceConsole`.

Forever already ships every widget we need (`agents.md` §Forever UI toolkit), including
`UIDropDownMenu`/`EasyMenu` via `Blizzard_SharedXML/Mainline/UIDropDownMenuTemplates.xml` — so
BetterBags vendoring `LibUIDropDownMenu` is a Classic concession we do not need.

| What a library would give us | Replace with | Cost |
|---|---|---|
| AceAddon module lifecycle | module table + explicit init order in `core/init.lua` | ~40 lines |
| **AceDB profiles** | `core/db.lua`: Default + per-character profiles, copy-from, reset, versioned migrate | **~250 lines + tests — the only non-trivial item** |
| AceEvent | one owned frame + dispatch table + `util/bucket.lua` | ~60 lines |
| AceHook | `hooksecurefunc` + manual swap | ~30 lines |
| AceLocale | `L` table with `__index` fallback-to-key | ~15 lines |
| AceGUI widgets | vanilla templates (see `agents.md`) | 0 |
| AceConfig / AceDBOptions | banned by design (`docs/05`) | 0 |
| LibWindow-1.1 saved positions | `frames/movemode.lua` | ~100 lines |
| LibUIDropDownMenu | Blizzard-provided on Forever | 0 |
| LibDataBroker + LibDBIcon (minimap) | `AddonCompartmentFunc` (already in the TOC) | 0 |
| LibSharedMedia | skip unless we ship custom fonts | 0 |
| LibPeriodicTable (preset definitions) | ship our own preset data (`config/presets.lua`) | 0 |

**Zero vendored libraries in v1.** Also removes the entire `AceEvent30Frame` protected-frame class
of bugs that bit this workspace (parent `../agents.md` §Debugging) — we never touch a Blizzard or
library-owned frame to register events.

Optional *dependencies* (Blizzard-provided, not vendored): `Blizzard_EditMode` for move mode
(`docs/05` §Move mode), `Masque` if skin integration proves cheap.

Revisit only if `core/db.lua` profiles turn out to be a recurring source of bugs — that is the one
place where vendoring would be defensible, and it would be `AceDB` alone.

---

## File tree (target, M5)

```
BagOfSorting/
├── BagOfSorting.toc
├── .pkgmeta
├── .luacheckrc
├── core/{boot,client,constants,context,events,db,async,pool,log}.lua + README.md
├── data/{harvest,enrich,classify,rules,stacks,sort,layoutmodel,windows,sections,categories}.lua + README.md
├── layout/{flow,sizing,anchors}.lua
├── frames/{window,section,item,header,chips,menu,inspector,money,emptyslot,movemode}.lua + README.md
├── config/{commands,undo,form,settingswindow,configuremode,importexport,presets}.lua
│   └── panes/{windows,sections,categories,rules,preview,profiles}.lua + README.md
├── filters/{registry,type,subtype,quality,ilvl,name,tooltip,expansion,equipslot,bind,itemid,
│            classid,subclassid,containerfamily,bagid,isreagent,isquest,isnew,category}.lua
├── themes/{themes,stock,dark}.lua
├── util/{serialize,color,text,test}.lua
├── locales/BagOfSorting-enUS.lua
└── tests/{fixtures.lua,selftest.lua}
```

## TOC draft

```toc
## Interface-Forever: 16001
## Title: Bag of Sorting
## Version: @project-version@
## Notes: Multi-window inventory organization with live, in-place configuration.
## Author: josh
## SavedVariables: BagOfSortingDB
## X-Category: Inventory
## OptionalDeps: Blizzard_EditMode, Masque
## AddonCompartmentFunc: BagOfSorting_OnAddonCompartmentClick
## IconTexture: Interface\Icons\INV_Misc_Bag_10
```

No `_retail_`/`_classic_` conditional TOC blocks in v1 — we ship one client.

## Packaging

Repo root **is** the addon root (`BagOfSorting.toc` at `./`), so a release zip is the repo minus the
spec. `.pkgmeta` carries the exclusions — this is what keeps the published package clean:

```yaml
package-as: BagOfSorting

ignore:
  - docs
  - agents.md
  - readme.md
  - tests
  - .github
  - .luacheckrc
  - .gitignore
  - .agents
```

No `externals:` section — v1 vendors nothing (`docs/07` Q2). `tests/` is excluded from the release
but `/bos selftest` stays loadable in dev checkouts (`docs/06` M0).
