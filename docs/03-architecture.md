# 03 — Architecture

Shape borrowed from BetterBags (module-per-concern, explicit pipeline, context objects, per-dir
READMEs) with Baggins' window/section/category vocabulary and a config layer that is a command
log rather than an option tree.

---

## Module map

```
core/      boot, client, constants, context, events, db, async, pool, log
data/      harvest, enrich, itemcache, classify, rules, stacks, sort, layoutmodel, windows,
          sections, categories
layout/    flow (river packing), sizing, anchors
frames/    window, section, item, header, chips, menu, inspector, money, emptyslot, movemode,
          bagbar, modals
config/    commands, undo, configure mode, category editor, item-list editor, import/export,
           presets (data), keybinds, help page, Options→AddOns registration, import/export
          configuremode, category-editor, presets, importexport, keybinds
filters/   field registry (one file per field: type, quality, ilvl, name, tooltip, …)
integrations/  compartment, masque, pawn
util/      serialize, color, text, query (if FR-28 lands), idlist, test
```

No `themes/` module (`docs/07` Q16): the windows are built from Blizzard's own bag pieces so the
user's skinning addon does the work. There is **no `data/snapshot.lua`**: `C_Bank` exposes no
item-reading API, so bank and guild-bank contents arrive through the same container API as backpack
contents and the harvest loop is the only inventory reader in the addon (`FR-109`); `frames/bagbar.lua`
is the vanilla↔sorting toggle on the client's bag bar.

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
  category editor's live item list cheap: the editor runs 1–7 against the real harvest with a draft
  rule tree substituted and renders a list.
- Each phase runs inside a `Context` (BetterBags pattern) carrying the triggering event, so a
  burst of `BAG_UPDATE` events can be cancelled/coalesced.
- `events:BucketEvent('BAG_UPDATE', 0.2)` coalesces; `async.Batch` chunks 2–7 across frames when
  the item count exceeds a threshold (start: 60).
- Incremental path: a single slot change re-runs 2–4 for that slot, then re-flows only the
  affected sections. `FR-26` depends on this.

### Item data is not always there (enrich)

`C_Item.GetItemInfo` is documented `MayReturnNothing = true` on Forever
(`wow-ui-source` `origin/forever` → `Blizzard_APIDocumentationGenerated/ItemDocumentation.lua`).
The client only has full data for items it has already seen this session. So `enrich` is a
three-tier lookup, never a single call:

| Tier | API | Gives | Cost |
|---|---|---|---|
| 1 | `C_Item.GetItemInfoInstant(itemID)` | icon, itemType, itemSubType, itemEquipLoc, classID, subClassID | local, safe in a loop |
| 2 | `data/itemcache.lua` (persisted, bounded) | name, quality, ilvl, bind, expansion for IDs we have resolved before | free, and it is what makes a 40-ID manual category usable |
| 3 | `C_Item.RequestLoadItemDataByID(itemID)` → `ITEM_DATA_LOAD_RESULT` | the rest, asynchronously | one request per unknown ID, batched; Blizzard's own `AsyncCallbackSystemMixin` (`ASYNC_ITEM`) is the reference implementation and is available on camelot |

Consequences: the classifier may run on tier-1 data and produce a *provisional* placement; a
resolved tier-3 result re-runs phases 2–4 for that item only (`FR-26` path). The preview/category
editor renders tier-1 icons immediately, names when known, and a placeholder otherwise — never a
blank row, never a blocked refresh. `expensive = true` in the field registry covers tooltip text and
anything that needs tier 3.

### Classification

```lua
-- data/classify.lua
owner = nil
for _, cat in ipairs(categoriesByPriority) do
  if cat:matches(item) then owner = cat; break end
end
trace = { tested = {...}, matched = owner, rejected = {...} }   -- feeds FR-27 inspector
```

`trace` is kept per item for the current harvest only (not persisted). It is the single most
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
Everything configure mode and the Options → AddOns panes can do is a command; nothing else mutates the
model. Consequences:

- `FR-74` undo/redo is a log walk, not a full-state diff.
- Configure mode and the utility panes are two views over the same command set — no duplicated
  logic, no risk of them disagreeing.
- `FR-81` "what changed" toast comes free: the command knows which categories it touched, and the
  re-classify pass reports moved-item counts.
- Import/export is a serialized command list or a model dump (choose in `docs/07` Q6).

**No AceConfig, and no in-house form builder either.** Forever ships the settings system: the utility
panes register with `Settings.RegisterAddOnCategory` + `RegisterVerticalLayoutCategory` (or
`RegisterCanvasLayoutCategory` for a frame we design ourselves) and get checkboxes, sliders, dropdowns
and colour swatches from `Settings.Create*` (`FR-88`). BetterBags hand-rolls 1,100 lines of form code
because it targets Classic; on this client that code is not ours to write.

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

### Is dependency injection worth it here? No.

The question was asked because `client` looks like a service every module consumes. It is not a
service, it is **a resolved table of ~10 answers, computed once at load**. What actually removes
the `if` statements is already in the design:

1. flags resolved once (`isForever`, `hasWarbank`, …) — no re-derivation at call sites;
2. **table-inert gating** — a missing capability means the table that would drive it is never
   built, so the loop costs nothing and no branch exists;
3. value getters for things that differ in kind, not just presence (`itemButtonType`).

Injecting a `clientAdapter` into each module would add a second name for the same table, a wiring
step in `core/init.lua`, and a new class of bug (which adapter, whose copy, is this module holding
the pre-login one?). In Lua 5.1 without a framework, "DI" degenerates to manual wiring in the load
order we already have. The honest upgrade path, if a second client is ever added, is **one data
table per client plus a handful of function overrides where behaviour genuinely differs** (money
frame layout, bag-bar button names) — still data, still one file, still no injected objects.
`shortcut: single-client capability table; revisit only when a second client is actually being
built, and then as per-client data tables, not injected adapters.`

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
- **Do not call Blizzard's container managers just to read them.** `ForeverPlus/Modules/BagWindow.lua`
  documents the exact trap on this client: `ContainerFrameSettingsManager:GetBagsShown()` looks like
  a question and is not one — it *builds and stores* the list, so calling it from our code ran
  Blizzard's bag code tainted until `UseContainerItem` was refused with `ADDON_ACTION_FORBIDDEN`.
  Rule: a Blizzard function is called from our code only where its source was read and found to
  write nothing (`IsUsingCombinedBags` is the named exception in ForeverPlus, and the pattern to
  copy). Counting open container frames by name is safer than asking the game.
- **Physical moves are cursor-based and locked.** `FR-65`/`FR-66`/`FR-67` use the
  `PickupContainerItem(src)` → `PickupContainerItem(dstSlot)` pattern (the same one Baggins'
  `Baggins-ItemOps.lua` uses). Verify destination space first, one move per bucket tick, abort with
  the cursor cleared, refuse in lockdown.
- Forever starts with the bags **combined into one window** (`ContainerFrameCombinedBags`,
  `IsUsingCombinedBags`); our windows are separate frames and do not participate in
  `UpdateContainerFrameAnchors`, which re-pins Blizzard's windows every time a bag opens or closes.
  We never call it.

---

## Integrations (optional addons, zero vendoring)

The dependency decision (`docs/07` Q2) was made on widget evidence, and it holds. What it does cost
is the ecosystem habits a bag addon is expected to have. Named honestly, with the price of each:

| Integration | What users get | How we do it | Verdict |
|---|---|---|---|
| **Addon Compartment** | the native puzzle-icon menu entry + our icon, on Forever | `## AddonCompartmentFunc` + `## IconTexture` (verified: `Blizzard_Minimap/Mainline/AddonCompartment.lua`, loads on camelot) | **v1**, zero cost |
| **Options → AddOns panel** | a native home for the settings that genuinely need a window: profiles, presets, import/export, find, keybinds | Forever ships the modern settings API: `Settings.RegisterAddOnCategory` + `RegisterVerticalLayoutCategory`/`RegisterCanvasLayoutCategory` + `CreateCheckbox`/`CreateSlider`/`CreateDropdown` + `RegisterProxySetting`/`RegisterAddOnSetting` + `SetKeybindingsCategory`, all in `Blizzard_Settings_Shared/Blizzard_Settings.lua` (`AllowLoadGameType Both`), with Blizzard's own how-to in `Blizzard_ImplementationReadme.lua`. Verified 2026-10-08; **my earlier claim that Forever has no options-panel API was wrong** | **v1** (`FR-88`), zero cost. The editor stays on the bags; only the utility panes go here |
| **Minimap button** | the draggable icon Baggins users expect | nothing | **not planned** (`FR-123`). Not deferred — refused. Compartment + Options → AddOns is the home, so LibDBIcon never enters the tree. What we give up: broker-display addons (Titan/DataFeedText-class) cannot show us, and nobody has asked yet |
| **Masque** | the user's bag skin applies to our buttons with no config | `LibStub('Masque', true)` + `Masque:Group('Bags of Sorting', …)` + add/remove button, guarded — BetterBags `integrations/masque.lua` is ~60 lines | **optional later** (`FR-121`, `FR-125`); this is the strongest argument for "use Blizzard's bag visuals" (`docs/07` Q16) |
| **Pawn** | the upgrade arrow everyone already trusts | check for `PawnShouldItemLinkHaveUpgradeArrowUnbudgeted`, register as an upgrade provider behind our own seam | **optional later** (`FR-122`), not a requirement |
| **Publishing our classification** | an alt-database addon could classify the inventory it already stores using our categories and rule trees | **not shipped.** What we do is keep the model plain-data, named and versioned so it *could* be published without a rewrite (`FR-113`). Transport — a guarded global, a LibDataBroker feed, something else — is decided when a consumer exists (`docs/07` Q22) | **later, not ours.** LibDataBroker is a plausible transport, not a rejected one: we refused LibDBIcon (the display half), not the data feed |
| **BagSync / Altoholic** | what they do: per-character inventory storage and cross-character search | not integrated. That product is a different problem from this one (`docs/07` Q15), and reading their data would drag their storage model into our UI | **out.** If an alt-database addon wants our classification, `FR-113` is the door |
| **Bagnon/BagBrother-compatible API** (`AllInventory`, `BagnonTooltipItemSearch`) | other addons can answer "does any character of mine have X" from *our* data; a large installed surface depends on Bagnon | cannot be done honestly here: `AllInventory` is persisted per-character inventory, which `FR-109` forbids | **out** (`docs/07` Q15). Neither reference addon in `../addons` provides it today, so this is a feature we decline, not a compatibility we lack |
| **Blizzard's own search matcher** | our search and the client's search agree about what "matches" means | our search box calls `C_Container.SetItemSearch(text)` and filters with `ItemButtonUtil.GetItemContextMatchResultForItem(ItemLocation:CreateFromBagAndSlot(bag, slot))` — the same predicate `BagSearch_OnTextChanged` drives. Our bags already hold `item → (window, section, button)`; search is that map run in reverse (`docs/07` Q7) | use it for anything the client currently knows. It is **not** an index and cannot search a closed bank |
| **AceConfig option tables** | appearing inside someone else's unified options suite | nothing — and this is a **deliberate refusal, not a platform gap**. AceConfig is out because its layout engine is what makes Baggins' config UI unusable at real scale: it wraps, truncates and reorders long section and category names, and its widget set fights a UI whose whole point is in-place editing. Forever's own settings API removes the only real reason addons reached for it | loss: none measured. No installed addon here aggregates option trees |
| **LibSharedMedia / LibQTip / LibBagUtils / LibWindow / LibPeriodicTable** | fonts, dewdrop tooltips, bag-slot counting, saved positions, curated item lists | vanilla templates, `UIDropDownMenu`+`EasyMenu`, `C_Container.GetBagSlotFlag`, our own positions, our own preset data (`FR-31`) | replaced, no loss |
| **Ace3 itself** | nothing we cannot write | ~470 lines total across lifecycle/events/hooks/locale/profiles | **gain**: no `AceEvent30Frame` class of `ADDON_ACTION_FORBIDDEN` (parent `../agents.md` §Debugging, `../TODO.md`) |

Coexistence is a requirement, not a nicety (`FR-124`): `ForeverPlus` already repositions the vanilla
bag window, `Leatrix_Plus` can `hooksecurefunc('OpenAllBags', CloseAllBags)`, and both `Baggins` and
`BetterBags` raw-hook the bag open/close globals. Every milestone ends with a run against the
installed set, recorded in the coexistence issue.

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
| LibDataBroker + LibDBIcon (minimap) | `AddonCompartmentFunc` + Options → AddOns | 0 |
| LibSharedMedia | skip unless we ship custom fonts | 0 |
| LibPeriodicTable (preset definitions) | ship our own preset data (`config/presets.lua`) — **and make it user-editable**, because LibPeriodicTable has not been meaningfully updated in years and cannot describe items Forever adds (`FR-31`) | 0 |

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
BagsOfSorting/
├── BagsOfSorting.toc
├── .pkgmeta
├── .luacheckrc
├── LICENSE                     # WTFPL
├── Media/Icon.png              # 256×256: ## IconTexture + CurseForge project icon
├── core/{boot,client,constants,context,events,db,async,pool,log}.lua + README.md
├── data/{harvest,enrich,itemcache,classify,rules,stacks,sort,layoutmodel,windows,sections,categories}.lua + README.md
├── layout/{flow,sizing,anchors}.lua
├── frames/{window,section,item,header,chips,menu,inspector,money,emptyslot,movemode,bagbar,modals}.lua + README.md
├── config/{commands,undo,configuremode,categoryeditor,itemlisteditor,importexport,presets,keybinds,help,settingspanel}.lua
│   └── panes/{windows,sections,categories,rules,profiles}.lua + README.md
├── filters/{registry,type,subtype,quality,ilvl,name,tooltip,expansion,equipslot,bind,itemid,
│            classid,subclassid,containerfamily,bagid,isreagent,isquest,isnew,category}.lua
├── integrations/{compartment,masque,pawn}.lua + README.md
├── util/{serialize,color,text,idlist,test}.lua
├── locales/BagsOfSorting-enUS.lua
└── tests/{fixtures.lua,selftest.lua}
```

No `themes/` directory (`docs/07` Q16).

## TOC draft

```toc
## Interface-Forever: 16001
## Title: Bags of Sorting
## Version: @project-version@
## Notes: Multi-window inventory organization with live, in-place configuration.
## Author: josh
## SavedVariables: BagsOfSortingDB
## X-Category: Inventory
## X-License: WTFPL
## X-Curse-Project-ID: 1745962
## X-Wago-ID: bGoYJY60
## OptionalDeps: Blizzard_EditMode, Masque, Pawn
## AddonCompartmentFunc: BagsOfSorting_OnAddonCompartmentClick
## IconTexture: Interface\AddOns\BagsOfSorting\Media\Icon
```

No `_retail_`/`_classic_` conditional TOC blocks in v1 — we ship one client.

## Packaging

Repo root **is** the addon root (`BagsOfSorting.toc` at `./`), so a release zip is the repo minus the
spec. `.pkgmeta` carries the exclusions — this is what keeps the published package clean:

```yaml
package-as: BagsOfSorting

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

`LICENSE` and `Media/` are **not** ignored: the license ships inside the package, and the icon is
referenced by `## IconTexture`.

## License & publishing

**WTFPL** — `LICENSE` at the repo root, `## X-License: WTFPL` in the TOC. Shortest license that keeps
the addon forkable, accepted by CurseForge and Wago, and it needs no THIRD-PARTY-NOTICES file because
we vendor nothing. Two things to keep true:

- Our **art** (the project icon) is not code. WTFPL covers it as written; if the icon ever comes from
  somewhere with terms, it gets its own `Media/LICENSE.md`.
- A fork that vendors a GPL/MIT library carries *that* library's terms for the fork, not ours. Worth
  one line in the readme once anyone forks us.

Public locations (once something marginally usable exists — `docs/07` Q14):
GitHub `https://github.com/SterlingNerd/BagsOfSorting.git`, CurseForge project `1745962`,
Wago `bGoYJY60`.
