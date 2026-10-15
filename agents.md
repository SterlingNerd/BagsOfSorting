# BagsOfSorting — Agent Context

A WoW: **Forever** (Blizzard codename *Camelot*) bag addon. Baggins' multi-window virtual-bag
shape, with a configuration model and UI that a human can actually use.

**Current phase: spec.** Code has not started. `docs/` is the source of truth for what to build;
change the spec there before changing direction in code.

---

## Read this order

| File | What it is |
|---|---|
| `readme.md` | Human-facing pitch + status |
| `docs/00-vision-and-scope.md` | Problem statement, design thesis, in/out of scope |
| `docs/01-reference-analysis.md` | Feature inventory of Baggins + BetterBags, steal/adapt/skip |
| `docs/02-requirements.md` | Numbered FR/NFR with MoSCoW priority + acceptance criteria |
| `docs/03-architecture.md` | Modules, pipeline, load order, file tree |
| `docs/04-data-model.md` | SavedVariables schema, rule grammar, migration/export |
| `docs/05-config-ui.md` | The differentiator: config UX design |
| `docs/06-milestones.md` | M0→M7 plan with exit criteria + in-game test checklists |
| `docs/07-open-questions.md` | Open decisions, each with a recommendation |

If a task contradicts `docs/02-requirements.md` or `docs/05-config-ui.md`, stop and ask.

---

## Target client: WoW: Forever (Camelot)

| Fact | Value | Source |
|---|---|---|
| `WOW_PROJECT_ID` | `18` (`WOW_PROJECT_CAMELOT`) | verified in `../addons/Baggins`, `../addons/BetterBags` |
| Interface version | `16001` (patch 1.60.1, build 70170) | `Baggins.toc`, `BetterBags_Camelot.toc` |
| `LE_EXPANSION_*` | reports `LE_EXPANSION_CLASSIC` (Vanilla ruleset) | parent `../agents.md` |
| Engine | modern: `C_Container`, `C_Item`, `C_Spell`, secret values, `ItemLocation` | verified |
| Flavor dir | `_classic_beta_`, `.flavor.info` = `wow_classic_beta` | verified |
| Bags start **combined** into one window | yes (`ContainerFrameCombinedBags`, `IsUsingCombinedBags`) | `origin/forever` + `../addons/ForeverPlus/Modules/BagWindow.lua` |
| EditMode's **Bags** system | the bag **button bar**, not the bag window | `../addons/ForeverPlus/Modules/BagWindow.lua` |
| `/script` available | yes, gated (`C_GameRules … UserScriptsDisabled`, one-time dangerous-scripts popup); `/dump`, `/eventtrace`, `/framestack`, `/api` too | `origin/forever` `Blizzard_ChatFrameBase/Shared/SlashCommands.lua` |
| Addon Compartment | present on camelot (`AddonCompartment.lua [AllowLoadGameType mainline]`, no camelot exclusion) | `origin/forever` `Blizzard_Minimap/Blizzard_Minimap.toc` |
| Keyring | present (expect it) | `Blizzard_MainMenuBarBagButtons/Camelot/MainMenuBarBagButtons.lua` uses `KEYRING_CONTAINER`, `GetKeyRingSize` |
| Reagent bag slot | present | `CharacterReagentBagMixin` in the same Camelot file; `ForeverPlus/Modules/BagSlots.lua` counts it |
| `C_Bank` | present, but **it reads no items** — its whole surface is tabs, money and locks (`FetchPurchasedBankTabIDs`, `FetchNumPurchasedBankTabs`, `FetchMaxNumBankTabs`, `FetchDepositedMoney`, `AutoDepositItemsIntoBank`, `IsItemAllowedInBankType`, `CanUseBank`, `CloseBankFrame`, `UpdateBankTabSettings`). **Bank contents arrive only through the container API** | `origin/forever` `BankDocumentation.lua`, full function list |
| `Enum.BagIndex` on Forever | 27 values, -3..23: `Accountbanktab -3`, `Characterbanktab -2`, `Keyring -1`, `Backpack 0`, `Bag_1..4 = 1..4`, `ReagentBag 5`, `CharacterBankTab_1..9 = 6..14`, `AccountBankTab_1..9 = 15..23`. **There are no `BankBag_*` values** | `BagIndexConstantsDocumentation.lua` |
| Bank bags exist anyway, computed | `ITEM_INVENTORY_BANK_BAG_OFFSET = NUM_TOTAL_EQUIPPED_BAG_SLOTS`; Camelot's `GetBagIDFromBankTypeAndSlot` returns `bagSlot + offset` (character) and `bagSlot + offset + NUM_CHARACTER_BANK_SLOTS` (account). If the offset is 5 here, **bank bags land on the bank-tab indices** — `NUM_BAG_SLOTS` / `NumCharacterBankSlots` are C-side, so only the client answers this | `Blizzard_UIPanels_Game/Camelot/BankFrame.lua:26`, `Blizzard_FrameXMLBase/Constants.lua:168-174` |
| Consequence for harvesting | **never enumerate `Enum.BagIndex` to find containers.** Derive from the constants, `pcall` each index, de-duplicate. Reading one index under two names counts the same items twice — the classic wrong-totals bug. Issue #2 | derived from the two rows above |
| `Enum.BagSlotFlags` | 10 values, 1..512 (`DisableAutoSort`, `ClassEquipment`, `ClassConsumables`, `ClassProfessionGoods`, `ClassJunk`, `ClassQuestItems`, `ExcludeJunkSell`, `ClassReagents`, `ExpansionCurrent`, `ExpansionLegacy`) | `BagConstantsDocumentation.lua` |
| `C_Item.GetItemInfo` | `MayReturnNothing = true` — the client only knows items it has seen | `ItemDocumentation.lua` |
| Async item fetch | `C_Item.RequestLoadItemDataByID(itemID)` → `ITEM_DATA_LOAD_RESULT`; Blizzard's own `AsyncCallbackSystemMixin` (`ASYNC_ITEM`) is the reference and loads on camelot | `Blizzard_ObjectAPI/Mainline/AsyncCallbackSystem.lua` |
| Icon picker | `IconDataProviderMixin` (`GetNumIcons`, `GetIconByIndex`, `GetIconForSaving`, `GetIndexOfIcon`) + `IconSelectorPopupFrameTemplate` | `Blizzard_FrameXMLBase/IconDataProvider.lua` |
| `C_Item.CanItemFitInContainer` | **absent** on Forever — bag restrictions must be inferred from `GetBagSlotFlag` + item type | grep of `Blizzard_APIDocumentationGenerated` |

Detection pattern (copy this, do not invent another):

```lua
local isCamelot = WOW_PROJECT_CAMELOT ~= nil and WOW_PROJECT_ID == WOW_PROJECT_CAMELOT
addon.isForever = isCamelot
addon.isRetailLike = WOW_PROJECT_ID == WOW_PROJECT_MAINLINE or isCamelot
addon.hasWarbank = addon.isRetail and not addon.isForever   -- Forever ships no warbank
```

### Forever HAS (retail-like)
- `ItemButton` frame type for container slots
- `CharacterReagentBag0Slot`, `KeyRingButton`
- modern money frame with atlas textures (`coin-gold/silver/copper`)
- `C_Container.GetContainerItemQuestInfo`

### Forever does NOT have (classic-like, or absent entirely)
- reagent bank tab (`REAGENT_BANK_TAB`)
- Warbands / account (warbank) bank — `Enum.BagIndex.AccountBankTab_N` exists but is inert
- item crafting quality overlays, pet-battle levels in tooltips
- `ItemButtonUtil.GetItemContextMatchResultForContainer`
- Blizzard auto-sort (`BlizzSortBags`)

Anything not in those two lists is **unverified**: confirm in-game or with
`wow-ui-source` `origin/forever` before writing a code path for it. Add confirmed facts to this
table — this file is the client-fact cache.

### Forever UI toolkit (verified against `../wow-ui-source` `origin/forever`)

Present, use these instead of any widget library:

| Vanilla piece | Evidence on `origin/forever` |
|---|---|
| `WowScrollBox`, `MinimalScrollBar`, `ScrollUtil` | 135 / 135 / 141 files |
| `NineSlice`, `ButtonFrameTemplate`, `DefaultPanelFlatTemplate`, `TooltipBackdropTemplate` | 120 / 110 / 6 files |
| `UIPanelButtonTemplate` | 172 files |
| `UICheckButtonTemplate`, `CheckButtonTemplate` | 33 / 59 files |
| `InputBoxTemplate`, `SearchBoxTemplate`, `BagSearchBoxTemplate` | 26 / 85 / 4 files |
| `WowStyle1DropdownTemplate` | 79 files |
| `UIDropDownMenuTemplate` + `UIDropDownMenu`/`EasyMenu` | Blizzard-provided: `Blizzard_SharedXML/Mainline/UIDropDownMenuTemplates.xml` — **do not vendor LibUIDropDownMenu** |
| `UISliderTemplate` | 5 files |
| `ColorPickerFrame` | 16 files |
| `StackSplitFrame` (vanilla split-stack UI) | `Blizzard_FrameXML/Mainline/StackSplitFrame.lua` + a **Camelot override** `Blizzard_FrameXML/Camelot/StackSplitFrame.xml` |
| `ContainerFrameItemButtonTemplate`, `ItemButton` secure type | used by BetterBags on the Camelot build |
| `C_Container` bag API | `Blizzard_APIDocumentationGenerated/ContainerDocumentation.lua`, `BagIndexConstantsDocumentation.lua` |

Absent on Forever — do not design around these:

| Missing | Consequence |
|---|---|
| `C_SecureHandlerRegisterSnippets`, `SecureHandlerOnSNippet`, `SecureCmdOptionCheck` | no secure-snippet handling on item buttons; M4's drag spike must not assume them |
| `SetBindingSnippet` | keybinds via plain `SetBinding` on our own frame |
| Blizzard EditMode is not addon-*documented* | `Blizzard_EditMode/Camelot/*` ships only Blizzard systems (action bars, unit frames, minimap) and there is no documented addon registration — but it **is** joinable in practice, see the recipe below. |
| `HorizontalSliderTemplate`, `ColorPickerSwatch`, `InputSpinBoxTemplate`, `CheckboxInputTemplate`, `HeaderStrip`, `SharedUIPanelCursorDragEffect`, `SpawnFrameArea`, `MoveUnitFrame` | newer-retail or other-branch names; not on Forever. (`SettingsPanel*Template` **is** present, under `Blizzard_Settings_Shared/Mainline/` — see below.) |

Present on Forever and worth using — do not assume these are retail-only:

| Present | Consequence |
|---|---|
| **The modern addon Settings API** — `Blizzard_Settings_Shared/Blizzard_Settings.lua` (`AllowLoadGameType Both`): `Settings.RegisterAddOnCategory`, `RegisterVerticalLayoutCategory`, `RegisterCanvasLayoutCategory`, `RegisterVerticalLayoutSubcategory`, `RegisterProxySetting`, `RegisterAddOnSetting`, `RegisterCVarSetting`, `RegisterInitializer`, `CreateCheckbox`, `CreateSlider`, `CreateDropdown`, `CreateColorSwatch`, `SetKeybindingsCategory`, `RegisterModifiedClickSetting`, `OpenToCategory`, `SETTING_GROUP_ADDONS = "AddOns"` | **This is the Options → AddOns panel.** My earlier claim that Forever has no options-panel API was wrong. The utility panes register there with zero dependencies — no AceConfig, no minimap icon (`FR-88`, `FR-123`). `Blizzard_Settings_Shared/Blizzard_ImplementationReadme.lua` is Blizzard's own in-tree guide for an addon settings page. |
| `Settings.RegisterModifiedClickSetting` | the client already has a UI for modified-click bindings; our item-menu modifier (`FR-60b`) registers there instead of inventing its own |
| Right-click on a bag item is **already taken** | the stock item menu owns it; `OnModifiedClick` handles `EXPANDITEM`/`SPLITSTACK` and `HandleModifiedItemClick` owns alt-click (inventory scan, link). Our item menu needs a free modifier — Ctrl+right-click |
| Altoholic ships a **Forever-specific build** (1.60.x; maintained via a fork, not the original author); **BagSync** is actively updated (20.x, 2026) with per-character item/bank/guild-bank tracking and an LDB feed meant for other bag addons | cross-character search should read one of these when present rather than build our own store (`FR-111`, `docs/07` Q15) |
| LibPeriodicTable is stale | the curated sets Baggins leans on have not been meaningfully updated in years and cannot describe items Forever adds; our preset categories ship as **editable data** (`FR-31`) |

### Config scale, from a long-lived personal Baggins setup

Not a benchmark — a shape to design against: **dozens of categories, a few hundred rules, ~12
windows made of a purpose set plus a near-mirror bank set, over a hundred sections (up to ~20 in one
window), hundreds of manually listed item IDs.** Most categories have one rule; the outliers are the
exclusion-heavy ones. `OR` dominates and `NOT` beats `AND` by a wide margin. `ItemID` lists and
curated named sets are the two most-used rule types, and category→category references are a primary
tool, not an advanced one. Full write-up in `docs/01`.

That config names categories with a **dotted hierarchy** (`Consumable.Potions`,
`Tradeskills.Enchanting.Wrath`). It is one person's convention, not a requirement — but it is worth
supporting, because a dotted name is a category group in disguise and it scales to a whole expansion
per family (`FR-11b`, `docs/07` Q8).

### EditMode ("move mode") is joinable — ThreatMeter proves it on Camelot

`../addons/ThreatMeter/editmode.lua` participates in Forever's EditMode; its
`ThreatMeter_Camelot.toc` declares `## OptionalDeps: Blizzard_EditMode`. Verified on
`origin/forever`: `EditModeSystemSelectionTemplate` (1), `EditModeSystemSelectionMixin` (2),
`EditModeSystemMixin` (15), `EditModeSystemSettingsDialogButtonTemplate`,
`EditModeSystemSettingsDialogExtraButtonTemplate`, `EventRegistry` `EditMode.Enter`/`EditMode.Exit`,
`EditModeManagerFrameMixin:RegisterSystemFrame`, `EditModeMagnetismManager:ApplyMagnetism`,
`C_EditMode.*` (13 methods incl. `GetLayouts`, `SetActiveLayout`, `ConvertLayoutInfoToString`).

Recipe (from ThreatMeter, all guarded so it degrades to plain drag if a piece is missing):

1. `## OptionalDeps: Blizzard_EditMode` in the TOC.
2. `frame.Selection = CreateFrame("Frame", nil, frame, "EditModeSystemSelectionTemplate")`;
   `SetAllPoints()`; raise frame level; `Selection:SetSystem(frame)`; hidden by default.
3. Implement on the movable frame: `GetSystemName`, `HighlightSystem`, `SelectSystem`,
   `ClearHighlight`.
4. Copy the snap/magnetism math off `EditModeSystemMixin` onto our frame for the ~21 method names
   EditMode expects (`GetFrameMagneticEligibility`, `HasValidSelectionRect`,
   `IsVerticallyAlignedWithFrame`, `GetScaledSelectionCenter`, `GetSnapOffsets`, `SnapToFrame`, …),
   only where we do not already define them.
5. `OnDragStart`/`OnDragStop`: `StartMoving`/`StopMovingOrSizing`,
   `EditModeManagerFrame:SetSnapPreviewFrame(self)` / `ClearSnapPreviewFrame`,
   `IsSnapEnabled()`, `EditModeMagnetismManager:ApplyMagnetism(self)`.
6. `EventRegistry:RegisterCallback("EditMode.Enter"/"EditMode.Exit", ...)` to show/hide handles.
7. Open it: guard `InCombatLockdown()`, close `SettingsPanel` first, then
   `ShowUIPanel(EditModeManagerFrame)`.
8. Optional per-window options dialog via `EditModeSystemSettingsDialog*Template`.

`EditModeManagerFrameMixin:RegisterSystemFrame(frame)` exists (a plain `table.insert` into
`registeredSystemFrames`, which EditMode then calls `OnEditModeEnter/OnEditModeExit` on) but is
**undocumented and not in `C_EditMode`** — treat it as best-effort, and never as the only way to
move our windows. ThreatMeter deliberately does not call it.

### Reference source
- `../wow-ui-source` — cloned `Gethe/wow-ui-source`. Forever UI lives on `origin/forever`:
  `git show origin/forever:Interface/AddOns/Blizzard_MainMenuBarBagButtons/Camelot/...`
- `../addons/Baggins` — the shape we want (see `docs/01`)
- `../addons/BetterBags` — the ergonomics we want (see `docs/01`)
- `../account` — symlink to live `WTF/Account/1071383#1/` for SavedVariables inspection

---

## Hard rules

1. **Syntax checks prove nothing.** `luacheck`/`lua -p` passing is necessary, not sufficient.
   Every behavior change must be confirmed in-game on the Forever client. This repo's parent
   `../agents.md` states this because the API surface differs per client.
2. **Never perform protected actions.** No `RegisterEvent` on Blizzard/protected frames, no
   showing/hiding Blizzard container frames outside a lockdown-safe path, no secure-button
   attribute writes while `InCombatLockdown()`. Deferred init uses a plain
   `CreateFrame("Frame")` + `PLAYER_REGEN_ENABLED`, never an AceEvent-mediated deferral
   (that pattern already bit this workspace — see parent `../agents.md` §Debugging).
3. **Item buttons are secure.** Pool them, reuse them, and never re-create a button in combat.
   If a button must be created during lockdown, mark it `tainted` and replace it on regen.
4. **No AceConfig waterfall.** The config UI is hand-built per `docs/05-config-ui.md`. Adding
   `AceConfigDialog` back to solve a config problem is a spec change — argue it in
   `docs/07-open-questions.md` first.
5. **Config edits are model edits.** UI widgets never touch frames directly; they send commands
   to the model, the model emits change events, the view re-renders. Undo is a model concern.
6. **Every non-trivial branch gets a self-check.** A small assert-based test or `/bos test`
   path. Trivial changes need none.
7. `shortcut: <limit>, <when to upgrade>` comment on any deliberate limitation.
8. **Do not call a Blizzard container manager just to read it.** `ContainerFrameSettingsManager:GetBagsShown()`
   *builds and stores* the list; calling it from addon code tainted Blizzard's bag code on this client
   until `UseContainerItem` was refused (`../addons/ForeverPlus/Modules/BagWindow.lua`). Call a
   Blizzard function only after reading its source and finding that it writes nothing.
9. **No default `Ctrl+Z`/`Ctrl+Y` bindings** (`FR-76`). Undo is a button; those keys sit next to WASD.
10. **No theme/skin system, no `settings.theme`** (`docs/07` Q16). Build from `ItemButton` /
    `ContainerFrameItemButtonTemplate` / the client's bag atlases.

---

## Conventions

- **Language:** Lua 5.1 (WoW). No `goto`, no `#` on tables with nil holes.
- **Style:** 2-space indent, `local x = 1`, module tables as `local mod = addon:NewModule('Mod')`.
  Follow BetterBags' annotation style (`---@class`, `---@field`) — it is the readable half of
  the two references.
- **Naming:** addon folder / `addonName` / repo = **`BagsOfSorting`**, TOC title **`Bags of Sorting`**
  (plural decided, `docs/07` Q1), SavedVariables `BagsOfSortingDB`, slash command `/bos`.
- **File layout:** one concern per file, `core/`, `data/`, `layout/`, `frames/`, `config/`,
  `filters/`, `integrations/`, `util/`. **No `themes/`** (`docs/07` Q16: use the client's own bag
  visuals so the user's skinning addon works). Each directory gets a `README.md` (BetterBags does
  this; it is why BetterBags is navigable).
- **Locales:** single `L` table from `core/locale.lua` (key-falls-back-to-itself); enUS is the key
  source. Do not hand-write other locales at spec/prototype phase.
- **No new dependencies** without a `docs/07` entry. v1 target dependency set is **zero vendored
  libraries** (`docs/03` §Dependencies, `docs/07` Q2).

## Repo boundary

This repo ships **one addon and nothing else**. Wow-wide assets (the `wow-forever-api` skill,
`wow-ui-source`, installed addons, the account symlink) live outside it and are reached by relative
paths from the parent workspace — never vendored here.

```bash
ls -a .   # LICENSE  Media/  agents.md  readme.md  docs/  .gitignore  .agents -> ../.agents (ignored)
```

`.agents` is a symlink to `../.agents` and is gitignored. Do not add shared scripts, shared docs, or
another addon under this tree. `LICENSE` (WTFPL) and `Media/Icon.png` are shipped content — they are
not in the `.pkgmeta` ignore list.

## Commands

```bash
luacheck .                      # lint (see .luacheckrc; WoW globals declared)
lua5.1 -e "loadfile('X.lua')"  # syntax-only smoke
# install for in-game test: copy/symlink into ../addons/BagsOfSorting/
# runnable in-game checks: the `spike` issues #1–#8  (/script works on Forever, gated)
```

There is no unit-test harness yet. M0 in `docs/06-milestones.md` creates the smallest one
(luacheck + a `/bos selftest` slash command that asserts the classifier against fixture items).

---

## What not to do

- Do not fork Baggins or BetterBags. Read them for behavior; write our own.
- Do not add a filter/rule type without also adding its chip rendering + preview support in the
  config UI. A rule type that the UI cannot explain is a Baggins-style footgun.
- Do not add options that have no UI story. Every setting must answer: where does the user see
  it, and how do they learn it exists?
- Do not touch `../addons/Baggins` or `../addons/BetterBags` from this repo. They are read-only
  references (both are git clones of upstream).
