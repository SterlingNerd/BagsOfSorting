# BagsOfSorting — Agent Context

A WoW: **Forever** (Blizzard codename *Camelot*) bag addon. Baggins' multi-window virtual-bag
shape, with a configuration model and UI that a human can actually use.

**Current phase: prototype (M0 + M1).** The pipeline, the rule grammar and one rendered Backpack
window exist. The configuration UI does not. `docs/` is still the source of truth for what to build;
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
| Keyring | **confirmed present in-game** (user, 2026-10-08, and visible in the Warcraft Tavern screenshot). Earlier doubt about it was a misread UI element, not a missing keyring | in-game observation + `Blizzard_MainMenuBarBagButtons/Camelot/MainMenuBarBagButtons.lua` (`KEYRING_CONTAINER`, `GetKeyRingSize`, `PutKeyInKeyRing`) |
| Reagent bag slot | **confirmed: it is the 5th equipped bag slot on Forever**, the same special bag as modern WoW — spell reagents and crafting materials kept out of the main slots | warcrafttavern.com/forever/news/changes-to-bags-banks-in-world-of-warcraft-forever (2026-09-16); `CharacterReagentBagMixin` in the Camelot bag-buttons file |
| Reagent bag slot | present | `CharacterReagentBagMixin` in the same Camelot file; `ForeverPlus/Modules/BagSlots.lua` counts it |
| `C_Bank` | present, but **it reads no items** — its whole surface is tabs, money and locks (`FetchPurchasedBankTabIDs`, `FetchNumPurchasedBankTabs`, `FetchMaxNumBankTabs`, `FetchDepositedMoney`, `AutoDepositItemsIntoBank`, `IsItemAllowedInBankType`, `CanUseBank`, `CloseBankFrame`, `UpdateBankTabSettings`). **Bank contents arrive only through the container API** | `origin/forever` `BankDocumentation.lua`, full function list |
| `Enum.BagIndex` on Forever | 27 values, -3..23: `Accountbanktab -3`, `Characterbanktab -2`, `Keyring -1`, `Backpack 0`, `Bag_1..4 = 1..4`, `ReagentBag 5`, `CharacterBankTab_1..9 = 6..14`, `AccountBankTab_1..9 = 15..23`. **There are no `BankBag_*` values** | `BagIndexConstantsDocumentation.lua` |
| **Storage shape (confirmed in-game, 2026-10-08)** | **Character:** backpack + **4 bag slots** + a **reagent bag** (the 5th slot) + a **keyring**. **Bank:** **8 bank bag slots** + a base grid whose size is **disputed between 48 and 96 slots** — issue #9 measures it | user confirmation + the news sources above |
| The arithmetic that follows | `NUM_BAG_SLOTS = 4`, `NUM_REAGENTBAG_SLOTS = 1` → `NUM_TOTAL_EQUIPPED_BAG_SLOTS = 5` → `ITEM_INVENTORY_BANK_BAG_OFFSET = 5`. Eight bank bags therefore land on **indices 6..13** — exactly where `Enum.BagIndex.CharacterBankTab_1..8` also sits. Either those enum values are legacy on this client, or the base grid's tabs are what lives there and bank bags are elsewhere. **Issue #9's probe decides which**, and it is the single most important number in the harvest design | `Constants.lua:168-174`, `BagIndexConstantsDocumentation.lua`, `Camelot/BankFrame.lua:26` |
| **Bank size: the sources disagree** | wowhead measured the beta at **48 default slots** (six rows of eight, eight locked bag slots beneath). Blizzard's senior game designer Josh Greenfield said in the Blizzcon interview *"I believe it's either twice or four times as large… I think it's 96 slots or something like that."* **48 and 96 are a factor of two apart, and the harvest design depends on the real number** — measure it, do not assume either | wowhead 382995 (2026-09-21), wowforever.be, warcrafttavern (2026-09-16) quoting mmorpg.com |
| Inventory pressure is being reduced elsewhere | a **mounts window** removes mounts from bags, and **transmog** stores appearances without keeping the item. Both shrink what the bags actually have to hold, so capacity assumptions should not be built on Classic-era bag math | warcrafttavern, same article |
| Camelot bank paging threshold | `BankPanel` on Camelot sets `maximumTotalSlotsPerPage = 88` (Mainline default is 96). A 48-slot bank fits on **one page**, so the client may present the bank as one continuous grid even if tabs exist underneath. `GetNumPagesForBankType` returns 1 page when `ShouldUsePlayerBagsInBank()` is false | `Blizzard_UIPanels_Game/Camelot/BankFrame.xml:88`, `Camelot/BankFrame.lua:86-101` |
| `C_CurrencyInfo` | present and large: `PlayerMoney`, `AccountMoney`, `GetCoinText`, `GetCoinTextureString`, `GetBackpackCurrencyInfo`, `GetCurrencyListInfo`, `GetCurrencyListSize`, `GetCurrencyLink`, `GetCurrencyIDFromLink`, `SetCurrencyBackpack`, `PickupCurrency`, `IsAccountWideCurrency`, `FetchCurrencyDataFromAccountCharacters`, `CurrencyDisplayUpdate`. Forever has a currency tab on the character panel — **money and currency display is the client's API, not ours to rebuild** (`FR-48`) | `CurrencyInfoDocumentation.lua`, `CurrencyConstantsDocumentation.lua` on `origin/forever` |
| `C_Bank.ShouldUsePlayerBagsInBank()` | exists, no args. Camelot's `BankFrameMixin:GetNumPagesForBankType` returns **1 page when it is false** and pages by `totalSlots / 88` when it is true (`BankFrame.xml:88` sets `maximumTotalSlotsPerPage = 88`). Whether the bank uses the player's own bags is the unknown that decides whether bank bags exist here at all | `Blizzard_UIPanels_Game/Camelot/BankFrame.lua:86-101` |
| `BankTabData` | `{ ID, bankType, name, icon (fileID), depositFlags (BagSlotFlags), tabCleanupConfirmation, tabNameEditBoxHeader }` — the *API* gives bank tabs a name, an icon and per-tab auto-deposit flags, and `C_Bank.UpdateBankTabSettings(bankType, tabID, tabName, tabIcon, depositFlags)` writes them. **Whether the character bank on this client actually has tabs is unverified** — Forever's 48-slot bank looks like one grid, and named/iconned tabs with deposit rules are much more a guild-bank shape. Issue #9 settles it; do not design bank windows around tab identity until it does | `BankDocumentation.lua` + the 48-slot fact above |
| `Enum.BankType` | `{ Character = 0, Guild = 1, Account = 2 }`. The guild bank is reachable as a *type*, but **the guild bank is out of scope for this addon** — its stacking rules and per-tab restrictions are a separate problem and only an offline-search product would care (`docs/07` Q15) | `ItemConstantsDocumentation.lua` |
| `C_Bank.PurchaseBankTab` | marked **`HasRestrictions = true`**. Forever has no secure handler snippets, so **we cannot buy bank tabs** and must not imply we can | `BankDocumentation.lua` |
| Bank events | `BANKFRAME_OPENED/CLOSED`, `PLAYERBANKSLOTS_CHANGED(slot)`, `BANK_TABS_CHANGED(bankType)`, `BANK_BAG_SLOT_FLAGS_UPDATED(slot)`, `BANK_TAB_SETTINGS_UPDATED(bankType)`, `PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED(slot)` — all `SynchronousEvent`. Bank refresh is driven by these, not a timer | `BankDocumentation.lua` |
| Consequence for harvesting | **never enumerate `Enum.BagIndex` to find containers.** Derive from the constants, `pcall` each index, de-duplicate. Reading one index under two names counts the same items twice — the classic wrong-totals bug. Issues #9, #10, #11 | derived from the rows above |
| `C_Bank.IsItemAllowedInBankType(bankType, itemLocation)` | the only bank-restriction predicate on this client (there is no `C_Item.CanItemFitInContainer`). Check it **before** a deposit, not after a failure | `BankDocumentation.lua` |
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
| Altoholic ships a **Forever-specific build** (1.60.x; maintained via a fork, not the original author); **BagSync** is actively updated (20.x, 2026) with per-character item/bank/guild-bank tracking and an LDB feed meant for other bag addons | **not integrated** — cross-character search is out of the product (`docs/07` Q15); if an alt-database addon wants our classification, `FR-113` is the door |
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
lua5.1 tests/run.lua            # headless pipeline + classifier checks (phases 1-7 touch no frames)
lua5.1 -e "loadfile('X.lua')"  # syntax-only smoke
# install for in-game test: copy/symlink into ../addons/BagsOfSorting/
# runnable in-game checks: the `spike` issues #1–#11  (/script works on Forever, gated)
```

The harness in `tests/` is the smallest one M0 calls for: `luacheck` plus `/bos selftest`, which
runs the same assertions `tests/run.lua` runs off the client. It proves the classifier and the
pipeline wiring — not the Forever API calls (hard rule 1).

---

## What not to do

- Do not fork Baggins or BetterBags. Read them for behavior; write our own.
- Do not add a filter/rule type without also adding its chip rendering + preview support in the
  config UI. A rule type that the UI cannot explain is a Baggins-style footgun.
- Do not add options that have no UI story. Every setting must answer: where does the user see
  it, and how do they learn it exists?
- Do not touch `../addons/Baggins` or `../addons/BetterBags` from this repo. They are read-only
  references (both are git clones of upstream).
