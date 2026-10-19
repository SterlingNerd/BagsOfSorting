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
| Interface version | `16001`; the installed client is **1.60.1 build 70450** (`wow_classic_beta`) | `Baggins.toc`, `BetterBags_Camelot.toc`, `.build.info` on the game machine 2026-10-19 |
| `C_Item.GetItemInfo` return order | 18 outputs, and the live client matches `ItemDocumentation.lua` position for position: 1 name, 2 link, 3 quality, 4 itemLevel, 5 minLevel, 6 type, 7 subtype, 8 stackCount, 9 equipLoc, 10 texture, 11 sellPrice, 12 classID, 13 subclassID, 14 bindType, **15 expansionID**, 16 setID (nilable), 17 isCraftingReagent, 18 description. `data/enrich.lua` reads 1/3/4/6/7/10/15 and is correct. **`expansion` is 0 (Classic) for every item this Vanilla-ruleset client knows**, so it is out of the v1 filter field set (`docs/02` FR-21) | `/bos test 14` 2026-10-19 (Linen Bandage 1251 dumped by position; 14 harvested items, all `0`), `ItemDocumentation.lua:626-656` |
| `LE_EXPANSION_*` | reports `LE_EXPANSION_CLASSIC` (Vanilla ruleset) | parent `../agents.md` |
| Engine | modern: `C_Container`, `C_Item`, `C_Spell`, secret values, `ItemLocation` | verified |
| Flavor dir | `_classic_beta_`, `.flavor.info` = `wow_classic_beta` | verified |
| Bags start **combined** into one window | `ContainerFrameCombinedBags` exists and the accessor is the **method** `ContainerFrameSettingsManager:IsUsingCombinedBags()` — there is **no global `IsUsingCombinedBags`** (measured nil on the live client). Reading combined-vs-individual means calling that manager, which hard rule 8 forbids (`GetBagsShown()` on the same manager tainted Blizzard's bag code). Derive it from the container indices we already harvest instead | `origin/forever` `Blizzard_UIPanels_Game/Mainline/ContainerFrame.lua:194+`, `/bos` dump 2026-10-17 |
| EditMode's **Bags** system | the bag **button bar**, not the bag window | `../addons/ForeverPlus/Modules/BagWindow.lua` |
| `/script` available | yes, gated (`C_GameRules … UserScriptsDisabled`, one-time dangerous-scripts popup); `/dump`, `/eventtrace`, `/framestack`, `/api` too | `origin/forever` `Blizzard_ChatFrameBase/Shared/SlashCommands.lua` |
| Addon Compartment | present on camelot (`AddonCompartment.lua [AllowLoadGameType mainline]`, no camelot exclusion) | `origin/forever` `Blizzard_Minimap/Blizzard_Minimap.toc` |
| Keyring | **confirmed present in-game** (user, 2026-10-08, and visible in the Warcraft Tavern screenshot). Earlier doubt about it was a misread UI element, not a missing keyring | in-game observation + `Blizzard_MainMenuBarBagButtons/Camelot/MainMenuBarBagButtons.lua` (`KEYRING_CONTAINER`, `GetKeyRingSize`, `PutKeyInKeyRing`) |
| Reagent bag slot | **confirmed: it is the 5th equipped bag slot on Forever**, the same special bag as modern WoW — spell reagents and crafting materials kept out of the main slots | warcrafttavern.com/forever/news/changes-to-bags-banks-in-world-of-warcraft-forever (2026-09-16); `CharacterReagentBagMixin` in the Camelot bag-buttons file |
| Reagent bag slot | present | `CharacterReagentBagMixin` in the same Camelot file; `ForeverPlus/Modules/BagSlots.lua` counts it |
| `C_Bank` | present, but **it reads no items** — its whole surface is tabs, money and locks (`FetchPurchasedBankTabIDs`, `FetchNumPurchasedBankTabs`, `FetchMaxNumBankTabs`, `FetchDepositedMoney`, `AutoDepositItemsIntoBank`, `IsItemAllowedInBankType`, `CanUseBank`, `CloseBankFrame`, `UpdateBankTabSettings`). **Bank contents arrive only through the container API** | `origin/forever` `BankDocumentation.lua`, full function list |
| `Enum.BagIndex` on Forever | 27 values, -3..23: `Accountbanktab -3`, `Characterbanktab -2`, `Keyring -1`, `Backpack 0`, `Bag_1..4 = 1..4`, `ReagentBag 5`, `CharacterBankTab_1..9 = 6..14`, `AccountBankTab_1..9 = 15..23`. **There are no `BankBag_*` values** | `BagIndexConstantsDocumentation.lua` |
| **Storage shape** (measured 2026-10-18, `/bos test 2`, bank open) | **Character:** backpack **20 slots**, 4 bag slots (two equipped: 6 + 6), reagent bag at index 5 (a 4-slot pouch), keyring **32 slots**. **Bank:** one container at **index 6, named `Bank`, 48 slots** — the free base grid — plus **8 purchasable bank bags at 7..14**, all named `Bank` and 0 slots while unpurchased. `C_Bank.BankBagTypeAndIDToInvSlot(Character, 1..9)` returns inventory slots **63..71**: nine real paper-doll slots, the first one being the grid | `/bos test 2` 2026-10-18, issue #9 |
| **Measured on the live client (`/bos`, 2026-10-17, level 1, no bags equipped)** | `NUM_BAG_SLOTS=4` · `NUM_REAGENTBAG_SLOTS=1` → `NUM_TOTAL_EQUIPPED_BAG_SLOTS=5` → `ITEM_INVENTORY_BANK_BAG_OFFSET=5` · `REAGENTBAG_INDEX=5` · `KEYRING_CONTAINER=-1` with **32 slots** · **`NUM_CHARACTER_BANK_SLOTS=9`** · `C_Bank.ShouldUsePlayerBagsInBank()=true` · `FetchNumPurchasedBankTabs(Character)=0` · global `IsUsingCombinedBags` **absent** (the accessor is `ContainerFrameSettingsManager:IsUsingCombinedBags()`, which we must not call) · `ItemButtonUtil.GetItemContextMatchResultForItem` and `...ForContainer` **both present** · `Settings.RegisterAddOnCategory`, `EditModeManagerFrame`, `IconDataProviderMixin`, `C_Item.RequestLoadItemDataByID`, `C_Container.GetContainerItemQuestInfo` present · `C_Warbank`, `Enum.BagIndex.ReagentBag`, `BlizzSortBags` absent · `Enum.GameRule.UserScriptsDisabled` inactive (`/script` allowed) | `/bos` capability dump, `core/client.lua` |
| The arithmetic that follows | `NUM_BAG_SLOTS = 4`, `NUM_REAGENTBAG_SLOTS = 1` → `NUM_TOTAL_EQUIPPED_BAG_SLOTS = 5` → `ITEM_INVENTORY_BANK_BAG_OFFSET = 5`. Camelot maps bank slots itself: `GetBagIDFromBankTypeAndSlot(Character, bagSlot) = bagSlot + ITEM_INVENTORY_BANK_BAG_OFFSET` (`Camelot/BankFrame.lua:26`) and `GetExactBankTabSlot() = Enum.BagIndex.CharacterBankTab_1 + bagSlotID - 1` (`:313`). **Bank slots 1..9 are container indices 6..14**: slot 1 / index 6 is the free base grid, 7..14 are the eight purchasable bank bags. `ShouldUsePlayerBagsInBank() = true` measured in-game. `/bos test 2` confirms it on the live client | `Constants.lua:168-174`, `BagIndexConstantsDocumentation.lua`, `Camelot/BankFrame.lua:26` and `:313`, the `/bos` dump above |
| **The base grid is ONE container: index 6, 48 slots** | `[6] Bank 48`, `grid containers 1 total slots 48 per page 88 page 1`, and `FetchPurchasedBankTabData(Character)` returns **one** entry: `ID 6, name "Tab 1", icon 134400, depositFlags 0, 48 slots`. The sum over every index is **116 = 32 + 20 + 6 + 6 + 4 + 48**, so nothing is missing and nothing is double-counted. Earlier `/bos find 6948` → `[6] slot 19` agrees | `/bos test 2` 2026-10-18 (issue #9), `/bos find` 2026-10-17 |
| **`C_Bank` and the container API change answers when the bank closes** | Bank closed: `FetchPurchasedBankTabData` 1 entry → **0**, `CanPurchaseBankTab` true → **false**, `FetchViewableBankTypes` `{0}` → **empty**, and **index 6 reports 0 slots instead of 48** (total 116 → 68). `ShouldUsePlayerBagsInBank()` stays true and `BankBagTypeAndIDToInvSlot` still returns 63..71. `FetchNumPurchasedBankTabs` is **not reliable while closed** — the same closed state read 0 on 2026-10-18 and 1 on 2026-10-19. Consequence: the bank half of the container list is re-discovered on `BANKFRAME_OPENED` and dropped on `BANKFRAME_CLOSED` (AC-13); a list built at login legitimately holds no bank container, and the bank panel's own `purchasedBankTabData` must not be read while closed (it is cleared: `grid containers 0` on 2026-10-19, one stale entry on 2026-10-18) | `/bos test 2` run 2026-10-18 and 2026-10-19 (issue #9) |
| Account bank indices | 15..23 exist, named **`Account Bank`**, all 0 slots for this character, and `FetchViewableBankTypes` returns only `{0}` (`Enum.BankType.Character`) while the bank is open — the account bank is not viewable here, so it stays out of the harvest loop until that changes | `/bos test 2` 2026-10-18 |
| Why the UI shows **8** bag slots while `NUM_CHARACTER_BANK_SLOTS` is **9** | `BankFrameMixin:RefreshBagButtons` loops `for bagNum = 2, maxBankBags` under the comment "We skip the first bag as we start with the first bag purchased" (`Camelot/BankFrame.lua:136-154`): slot 1 is the free base grid, so 9 slots draw 8 bag buttons. Not a contradiction — a free first slot | `origin/forever` `Camelot/BankFrame.lua:136-154` |
| No tab strip when `ShouldUsePlayerBagsInBank()` is true | `BankPanelMixin:OnLoad` creates the `BankPanelTabTemplate` pool **only when it is false** (`BankFrameTemplates.lua:687-688`). In the true path `GenerateItemSlotsForSelectedTab` concatenates `purchasedBankTabData` containers into one 8-column grid paged at 88 slots and sizes the window as `460 + (rows − 6) × 47` (`:1076-1116`): 48 slots gives exactly the 6 rows counted in-game | `origin/forever` `Mainline/BankFrameTemplates.lua`, `Camelot/BankFrame.xml:88` |
| `BAG_UPDATE` carries a container ID and the bank panel consumes it | Source: `BankPanelMixin:OnEvent` marks the panel dirty on `BAG_UPDATE(containerID)` whenever `ShouldUsePlayerBagsInBank()` is true (`BankFrameTemplates.lua:791-794`). Measured: **`BAG_UPDATE 6` fires for the bank grid** (six times in one short session) alongside `BAG_UPDATE 0` and `BAG_UPDATE -1` — the existing bucketed `BAG_UPDATE` listener already covers bank refresh, so no bank timer is needed. Confirmed again 2026-10-19; a withdraw into an equipped bag also fires `ITEM_LOCK_CHANGED 1 1` then `BAG_UPDATE 1`, i.e. the receiving bag's own index, not only 0 | `origin/forever` source + `/bos test 3` 2026-10-18 and 2026-10-19 |
| Bank window chrome | **Page 1 only, no tab strip.** While the bank is open: `FetchNumPurchasedBankTabs = 1` (the free grid counts as the one purchased tab), `FetchMaxNumBankTabs = 9`, `HasMaxBankTabs = false`, `CanPurchaseBankTab = true`, `FetchBankLockedReason = nil` — the eight bag slots are buyable; the character simply could not afford one ("You can't afford that."). Camelot pages at 88 slots per page (`BankFrame.xml:88`) and 48 fits on one page, so whether paging grows past one page once bags exist is still unmeasured | `/bos test 2` + `/bos test 3` 2026-10-18, `Camelot/BankFrame.xml:88` |
| **Bank size: settled at 48** | Counted in-game 2026-10-17: the base grid is **six rows of eight**. wowhead's 48 matches; Josh Greenfield's "I think it's 96 slots or something like that" does not. The harvest design budgets **48** | in-game 2026-10-17, wowhead 382995 (2026-09-21) |
| Inventory pressure is being reduced elsewhere | a **mounts window** removes mounts from bags, and **transmog** stores appearances without keeping the item. Both shrink what the bags actually have to hold, so capacity assumptions should not be built on Classic-era bag math | warcrafttavern, same article |
| Camelot bank paging threshold | `BankPanel` on Camelot sets `maximumTotalSlotsPerPage = 88` (Mainline default is 96). A 48-slot bank fits on **one page**, so the client may present the bank as one continuous grid even if tabs exist underneath. `GetNumPagesForBankType` returns 1 page when `ShouldUsePlayerBagsInBank()` is false | `Blizzard_UIPanels_Game/Camelot/BankFrame.xml:88`, `Camelot/BankFrame.lua:86-101` |
| `C_CurrencyInfo` | present and large: `PlayerMoney`, `AccountMoney`, `GetCoinText`, `GetCoinTextureString`, `GetBackpackCurrencyInfo`, `GetCurrencyListInfo`, `GetCurrencyListSize`, `GetCurrencyLink`, `GetCurrencyIDFromLink`, `SetCurrencyBackpack`, `PickupCurrency`, `IsAccountWideCurrency`, `FetchCurrencyDataFromAccountCharacters`, `CurrencyDisplayUpdate`. Forever has a currency tab on the character panel — **money and currency display is the client's API, not ours to rebuild** (`FR-48`) | `CurrencyInfoDocumentation.lua`, `CurrencyConstantsDocumentation.lua` on `origin/forever` |
| `C_Bank.ShouldUsePlayerBagsInBank()` | exists, no args. Camelot's `BankFrameMixin:GetNumPagesForBankType` returns **1 page when it is false** and pages by `totalSlots / 88` when it is true (`BankFrame.xml:88` sets `maximumTotalSlotsPerPage = 88`). Whether the bank uses the player's own bags is the unknown that decides whether bank bags exist here at all | `Blizzard_UIPanels_Game/Camelot/BankFrame.lua:86-101` |
| `BankTabData` | `{ ID, bankType, name, icon (fileID), depositFlags (BagSlotFlags), tabCleanupConfirmation, tabNameEditBoxHeader }`, written by `C_Bank.UpdateBankTabSettings(bankType, tabID, tabName, tabIcon, depositFlags)`. Measured: the character bank **does** carry one real `BankTabData` entry — `ID 6, "Tab 1", icon 134400, depositFlags 0` — even though no tab strip is drawn. Tab identity exists in the API for the grid, so issue #10's auto-deposit routing has exactly one target today | `BankDocumentation.lua` + `/bos test 2` 2026-10-18 |
| `Enum.BankType` | `{ Character = 0, Guild = 1, Account = 2 }`. The guild bank is reachable as a *type*, but **the guild bank is out of scope for this addon** — its stacking rules and per-tab restrictions are a separate problem and only an offline-search product would care (`docs/07` Q15) | `ItemConstantsDocumentation.lua` |
| `C_Bank.PurchaseBankTab` | marked **`HasRestrictions = true`**. Forever has no secure handler snippets, so **we cannot buy bank tabs** and must not imply we can | `BankDocumentation.lua` |
| Bank events, measured | `BANKFRAME_OPENED` and `BANKFRAME_CLOSED` fire with **no payload**. A deposit or withdraw produces `ITEM_LOCK_CHANGED(containerID, slot)` then `BAG_UPDATE(containerID)` on **both** sides — `6 1` + `BAG_UPDATE 6` for the grid, `0 1` + `BAG_UPDATE 0` for the backpack, `BAG_UPDATE -1` alongside. `ITEM_LOCK_CHANGED` slots are grid-relative inside container 6 (`6 1`, `6 48`), not a global bank slot number. **`PLAYERBANKSLOTS_CHANGED` never fires** for character-bank moves (two runs, deposits and withdrawals): refresh is `BAG_UPDATE(6)` + `ITEM_LOCK_CHANGED(6, slot)`, so its payload question is moot. `BANK_TABS_CHANGED` / `BANK_BAG_SLOT_FLAGS_UPDATED` still unobserved — no UI on this client changes a tab name or flag yet | `/bos test 3` 2026-10-18, two runs (issue #9) |
| Opening the bank fires no container event | `BANKFRAME_CLOSED` immediately followed by `BANKFRAME_OPENED` with nothing after it. With index 6 reading 0 slots while closed, the bank container enters the discovered list only through an explicit `BANKFRAME_OPENED` handler — mandatory at M5, not an optimisation | `/bos test 3` 2026-10-18 |
| **A purchased bank bag is part of the grid, not a bag with a window** (2026-10-19) | The first bank bag slot was bought and a 6-slot bag placed in it: the bank window gained **6 slots** (48 → 54 visible). The bag **cannot be opened on its own** — it has no window of its own, it is part of the bank grid view — and its contents **travel with it** when it moves between the bank and the character, still displaying in the bank. So the bank is **one paged view over grid + bags**, and the harvest reads it as containers 6..14 rather than a grid plus separate bags. Not yet read off the client: which of 7..14 answers 6 and what `GetBagName` calls it, `FetchPurchasedBankTabIDs`, the next tab's cost, and whether `BANK_TABS_CHANGED` / `BANK_BAG_SLOT_FLAGS_UPDATED` fire at purchase — `/bos test 2` and `/bos test 3` print all of it now (**issue #25**) | observed in-game 2026-10-19 (issue #25); probe output pending |
| Consequence for harvesting | **never enumerate `Enum.BagIndex` to find containers.** Derive from the constants, `pcall` each index, de-duplicate. Reading one index under two names counts the same items twice — the classic wrong-totals bug. Issues #9, #10, #11 | derived from the rows above |
| `C_Bank.IsItemAllowedInBankType(bankType, itemLocation)` | the only bank-restriction predicate on this client (there is no `C_Item.CanItemFitInContainer`). Check it **before** a deposit, not after a failure | `BankDocumentation.lua` |
| `Enum.BagSlotFlags` | 10 values, 1..512 (`DisableAutoSort`, `ClassEquipment`, `ClassConsumables`, `ClassProfessionGoods`, `ClassJunk`, `ClassQuestItems`, `ExcludeJunkSell`, `ClassReagents`, `ExpansionCurrent`, `ExpansionLegacy`) | `BagConstantsDocumentation.lua` |
| New-item glow | `ContainerFrameItemButtonTemplate` wires `OnEnter = ContainerFrameItemButton_OnEnter`, which calls `OnUpdate` → `C_NewItems.RemoveNewItem(bagID, slot)` and hides `NewItemTexture`. Our pooled buttons inherit it, so hovering our buttons clears the client's new-item state for the mirrored slots. The glow itself is set by `ContainerFrameItemButtonMixin:UpdateNewItem(quality)` from Blizzard's own container update path — our paint path does not call it, and the highlight on our buttons is inconsistent because of that (`FR-47`, `/bos test 11`). The client's own highlight is a bright glow around the slot cycling bright → dim: `docs/reference/new-item-highlight-*.png` | `origin/forever` `ContainerFrame.lua:1687-1731`, `:1871-1900`, in-game 2026-10-17 |
| `GetTime()` resolution | **frame-quantized on this client**: 1e6 Lua iterations measured **0 ms** in-game (2026-10-17). A phase timed inside one refresh is therefore unmeasurable — `/bos perf` phase numbers read `0.00` no matter how slow the pipeline is. Measure across frames instead: `/bos test 13` runs the pipeline 100×10 times spread over frames and reports ms per refresh. Neither `GetRealTime` nor `C_Profiler` is referenced anywhere in `origin/forever` FrameXML | `/script` probe 2026-10-17, `git grep origin/forever -- Interface` |
| `/script` limits | one line, capped near **255 characters**: the chat edit box sends a single line and `RunScript` compiles one chunk. A longer snippet is truncated and Lua reports `'end' expected near '<eof>'`, which reads like a code bug and is not one. In-game probes live in `core/diag.lua` (`/bos test <n>`) for this reason | in-game 2026-10-17, `wow-forever-api` skill |
| **What this client persists** (WTF tree, 2026-10-18/19) | `SavedVariables/BagsOfSorting.lua` is written and survives a session — item cache, profile and the `/bos` probe capture all present — so the Forever "addon settings don't save" reports do not apply to us. `bindings-cache.wtf` carries other addons' `Bindings.xml` actions (`bind NUMLOCK LOREFOREVER_TOGGLE`) **and ours**: `bind CTRL-B BAGSOF_SORTING_TOGGLE`, surviving `/reload` twice and a game restart, with `C_KeyBindings.GetBindingIndex('BAGSOF_SORTING_TOGGLE') = 287` and `GetCurrentBindingSet() = 1` = `Enum.BindingSet.Account` (`KeyBindingsDocumentation.lua:212-215`) — one key for the whole account, the same scope as `db.sv.global`. The 2026-10-17 "lost on `/reload`" report does not reproduce: in that session the line never reached the file. `config/keybinds.lua` stays as insurance — it stores what the client has at login and re-applies it only when the client has nothing (issue #13) | `WTF/Account/<account>/bindings-cache.wtf` + `.old`, `SavedVariables/BagsOfSorting.lua`, `/bos test 7` 2026-10-19 |
| **SavedVariables file names ignore the TOC declaration** (issue #14) | Forever writes **one file per addon, named after the addon folder**, whatever `## SavedVariables:` declares, and puts every declared global inside it: `BagsOfSorting.lua` holding `BagsOfSortingDB`, `LoreForever.lua` holding `LoreForeverDB`, `Leatrix_Plus.lua` holding `LeaPlusDB`, `BetterBags.lua` holding `BetterBagsDB` — that TOC declares two names and still gets one file. Our TOC is written the way retail expects, so the mismatch is a Forever quirk rather than a mistake, and the file name only changes if the folder does. Issue #8 baselines `SavedVariables/BagsOfSorting.lua` | `WTF/Account/<account>/SavedVariables/*.lua` against each addon's `.toc`, 2026-10-19 |
| `GetBinding` is index-based; `GetBindingKey` is action-based | `GetBinding(i)` takes a **binding index** (`Blizzard_PTRFeedback.lua:146`) and **errors on a string** — `GetBinding('SOME_ACTION')` is a Lua error, not a nil. "What key is bound to this action?" is `GetBindingKey(action)` (up to two keys) or `C_KeyBindings.GetBindingByKey(action)` | in-game 2026-10-19 (`/bos test 7` died on its second line), `origin/forever` `Blizzard_PTRFeedback.lua:146`, `ActionButton.lua:498` |
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
- `ItemButtonUtil.GetItemContextMatchResultForItem` and `ItemButtonUtil.GetItemContextMatchResultForContainer` — measured present on the live client 2026-10-17, so the context matcher for search/filtering is the client's own

### Forever does NOT have (classic-like, or absent entirely)
- reagent bank tab (`REAGENT_BANK_TAB`)
- Warbands / account (warbank) bank — `Enum.BagIndex.AccountBankTab_N` exists but is inert
- item crafting quality overlays, pet-battle levels in tooltips
- `ItemButtonUtil` context matchers are **present** (see the HAS list above) — earlier doubt about them came from a source read, not from the client
- Blizzard auto-sort (`BlizzSortBags`) — absent, measured on the live client

Anything not in those two lists is **unverified**: confirm in-game or with
`wow-ui-source` `origin/forever` before writing a code path for it. Add confirmed facts to this
table — this file is the client-fact cache.

### Forever UI toolkit (verified against `../wow-ui-source` `origin/forever`)

Present, use these instead of any widget library:

Frame **templates** (`ContainerFrameItemButtonTemplate`, `WowStyle1DropdownTemplate`,
`PortraitFrameFlatTemplate`, …) are not globals — they resolve through the frame-tree registry, so
`X ~= nil` reads false even when the client ships them. `/bos` does not probe templates; the test is
building a frame with one.

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
  **To investigate:** the client writes the file as `SavedVariables/BagsOfSorting.lua` while the TOC
  declares `BagsOfSortingDB` and the file's own contents assign `BagsOfSortingDB = { … }`. Data
  persists correctly today; the file name simply does not match the declared name. Settle it before
  the SavedVariables growth harness (issue #8) baselines a file path.
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
# in-game probes: /bos test <n>  (core/diag.lua) — 2 bank, 7 keybind, 11 new-item, 13 clock+cost
# the manual half: tests/CHECKLIST.md; API questions: the `spike` issues #1–#11
```

The harness in `tests/` is the smallest one M0 calls for: `luacheck` plus `lua5.1 tests/run.lua`,
which loads the real modules against a stubbed container API. `tests/` is **not in the TOC**, so the
addon loads no test code in a dev checkout or in a release zip. It proves the classifier and the
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
