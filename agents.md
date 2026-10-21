# BagsOfSorting — Agent Context

A WoW: **Forever** (Blizzard codename *Camelot*) bag addon. Baggins' multi-window virtual-bag
shape, with a configuration model and UI that a human can actually use.

**Current phase: prototype (M0 + M1 done, M2 in progress).** The pipeline, the rule grammar, five
rendered windows (`Backpack`, `Quests`, `Consumables`, `Tradeskills`, `Tools`) and the `FR-41`
placement rule exist. The configuration UI does not. `docs/` is still the source of truth for what to
build; change the spec there before changing direction in code.

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
| `C_Item.GetItemInfo` return order | 18 outputs, and the live client matches `ItemDocumentation.lua` position for position: 1 name, 2 link, 3 quality, 4 itemLevel, 5 minLevel, 6 type, 7 subtype, 8 stackCount, 9 equipLoc, 10 texture, 11 sellPrice, 12 classID, 13 subclassID, 14 bindType, **15 expansionID**, 16 setID (nilable), 17 isCraftingReagent, 18 description. `data/enrich.lua` reads 1/3/4/6/7/10/15 and is correct. **`expansion` is 0 (Classic) for every item this Vanilla-ruleset client knows**, so it is out of the v1 filter field set (`docs/02` FR-21) | `/bos test expansion` 2026-10-19 (Linen Bandage 1251 dumped by position; 14 harvested items, all `0`), `ItemDocumentation.lua:626-656` |
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
| **Storage shape** (measured 2026-10-18, `/bos test dump`, bank open) | **Character:** backpack **20 slots**, 4 bag slots (two equipped: 6 + 6), reagent bag at index 5 (a 4-slot pouch), keyring **32 slots**. **Bank:** one container at **index 6, named `Bank`, 48 slots** — the free base grid — plus **8 purchasable bank bags at 7..14**, all named `Bank` and 0 slots while unpurchased. `C_Bank.BankBagTypeAndIDToInvSlot(Character, 1..9)` returns inventory slots **63..71**: nine real paper-doll slots, the first one being the grid | `/bos test dump` 2026-10-18, issue #9 |
| **Measured on the live client (`/bos`, 2026-10-17, level 1, no bags equipped)** | `NUM_BAG_SLOTS=4` · `NUM_REAGENTBAG_SLOTS=1` → `NUM_TOTAL_EQUIPPED_BAG_SLOTS=5` → `ITEM_INVENTORY_BANK_BAG_OFFSET=5` · `REAGENTBAG_INDEX=5` · `KEYRING_CONTAINER=-1` with **32 slots** · **`NUM_CHARACTER_BANK_SLOTS=9`** · `C_Bank.ShouldUsePlayerBagsInBank()=true` · `FetchNumPurchasedBankTabs(Character)=0` · global `IsUsingCombinedBags` **absent** (the accessor is `ContainerFrameSettingsManager:IsUsingCombinedBags()`, which we must not call) · `ItemButtonUtil.GetItemContextMatchResultForItem` and `...ForContainer` **both present** · `Settings.RegisterAddOnCategory`, `EditModeManagerFrame`, `IconDataProviderMixin`, `C_Item.RequestLoadItemDataByID`, `C_Container.GetContainerItemQuestInfo` present · `C_Warbank`, `Enum.BagIndex.ReagentBag`, `BlizzSortBags` absent · `Enum.GameRule.UserScriptsDisabled` inactive (`/script` allowed) | `/bos` capability dump, `core/client.lua` |
| The arithmetic that follows | `NUM_BAG_SLOTS = 4`, `NUM_REAGENTBAG_SLOTS = 1` → `NUM_TOTAL_EQUIPPED_BAG_SLOTS = 5` → `ITEM_INVENTORY_BANK_BAG_OFFSET = 5`. Camelot maps bank slots itself: `GetBagIDFromBankTypeAndSlot(Character, bagSlot) = bagSlot + ITEM_INVENTORY_BANK_BAG_OFFSET` (`Camelot/BankFrame.lua:26`) and `GetExactBankTabSlot() = Enum.BagIndex.CharacterBankTab_1 + bagSlotID - 1` (`:313`). **Bank slots 1..9 are container indices 6..14**: slot 1 / index 6 is the free base grid, 7..14 are the eight purchasable bank bags. `ShouldUsePlayerBagsInBank() = true` measured in-game. `/bos test dump` confirms it on the live client | `Constants.lua:168-174`, `BagIndexConstantsDocumentation.lua`, `Camelot/BankFrame.lua:26` and `:313`, the `/bos` dump above |
| **The base grid is ONE container: index 6, 48 slots** | `[6] Bank 48`, `grid containers 1 total slots 48 per page 88 page 1`, and `FetchPurchasedBankTabData(Character)` returns **one** entry: `ID 6, name "Tab 1", icon 134400, depositFlags 0, 48 slots`. The sum over every index is **116 = 32 + 20 + 6 + 6 + 4 + 48** with no bank bag owned, and **124** with an 8-slot bag in bank slot 2 (116 + 8) — nothing missing, nothing double-counted either way. Earlier `/bos find 6948` → `[6] slot 19` agrees | `/bos test dump` 2026-10-18 (issue #9), `/bos find` 2026-10-17 |
| **`C_Bank` and the container API change answers when the bank closes** | Bank closed: `FetchPurchasedBankTabData` 1 entry → **0**, `CanPurchaseBankTab` true → **false**, `FetchViewableBankTypes` `{0}` → **empty**, and **index 6 reports 0 slots instead of 48** (total 116 → 68). `ShouldUsePlayerBagsInBank()` stays true and `BankBagTypeAndIDToInvSlot` still returns 63..71. `FetchNumPurchasedBankTabs` is **not reliable while closed** — the same closed state read 0 on 2026-10-18 and 1 on 2026-10-19. Consequence: the bank half of the container list is re-discovered on `BANKFRAME_OPENED` and dropped on `BANKFRAME_CLOSED` (AC-13); a list built at login legitimately holds no bank container, and the bank panel's own `purchasedBankTabData` must not be read while closed (it is cleared: `grid containers 0` on 2026-10-19, one stale entry on 2026-10-18) | `/bos test dump` run 2026-10-18 and 2026-10-19 (issue #9) |
| Account bank indices | 15..23 exist, named **`Account Bank`**, all 0 slots for this character, and `FetchViewableBankTypes` returns only `{0}` (`Enum.BankType.Character`) while the bank is open — the account bank is not viewable here, so it stays out of the harvest loop until that changes | `/bos test dump` 2026-10-18 |
| Why the UI shows **8** bag slots while `NUM_CHARACTER_BANK_SLOTS` is **9** | `BankFrameMixin:RefreshBagButtons` loops `for bagNum = 2, maxBankBags` under the comment "We skip the first bag as we start with the first bag purchased" (`Camelot/BankFrame.lua:136-154`): slot 1 is the free base grid, so 9 slots draw 8 bag buttons. Not a contradiction — a free first slot | `origin/forever` `Camelot/BankFrame.lua:136-154` |
| No tab strip when `ShouldUsePlayerBagsInBank()` is true | `BankPanelMixin:OnLoad` creates the `BankPanelTabTemplate` pool **only when it is false** (`BankFrameTemplates.lua:687-688`). In the true path `GenerateItemSlotsForSelectedTab` concatenates `purchasedBankTabData` containers into one 8-column grid paged at 88 slots and sizes the window as `460 + (rows − 6) × 47` (`:1076-1116`): 48 slots gives exactly the 6 rows counted in-game | `origin/forever` `Mainline/BankFrameTemplates.lua`, `Camelot/BankFrame.xml:88` |
| `BAG_UPDATE` carries a container ID and the bank panel consumes it | Source: `BankPanelMixin:OnEvent` marks the panel dirty on `BAG_UPDATE(containerID)` whenever `ShouldUsePlayerBagsInBank()` is true (`BankFrameTemplates.lua:791-794`). Measured: **`BAG_UPDATE 6` fires for the bank grid** (six times in one short session) alongside `BAG_UPDATE 0` and `BAG_UPDATE -1` — the existing bucketed `BAG_UPDATE` listener already covers bank refresh, so no bank timer is needed. Confirmed again 2026-10-19; a withdraw into an equipped bag also fires `ITEM_LOCK_CHANGED 1 1` then `BAG_UPDATE 1`, i.e. the receiving bag's own index, not only 0 | `origin/forever` source + `/bos test log` 2026-10-18 and 2026-10-19 |
| Bank window chrome | **Page 1 only, no tab strip.** While the bank is open: `FetchNumPurchasedBankTabs = 1` with no bag slot bought and **2** with one bought (the free grid plus the bag slot), `FetchMaxNumBankTabs = 9`, `HasMaxBankTabs = false`, `CanPurchaseBankTab = true`, `FetchBankLockedReason = nil` — the eight bag slots are buyable. `FetchNextPurchasableBankTabData` gives the price: **`tabCost 10000` (1 gold), `canAfford false`** for this character, and the price rises per slot. Camelot pages at 88 slots per page (`BankFrame.xml:88`); 48 + 8 = 56 still reads `page 1`, so paging past one page needs grid + bags > 88 and is still unmeasured | `/bos test dump` + `/bos test log` 2026-10-18, `Camelot/BankFrame.xml:88` |
| **Bank size: settled at 48** | Counted in-game 2026-10-17: the base grid is **six rows of eight**. wowhead's 48 matches; Josh Greenfield's "I think it's 96 slots or something like that" does not. The harvest design budgets **48** | in-game 2026-10-17, wowhead 382995 (2026-09-21) |
| Inventory pressure is being reduced elsewhere | a **mounts window** removes mounts from bags, and **transmog** stores appearances without keeping the item. Both shrink what the bags actually have to hold, so capacity assumptions should not be built on Classic-era bag math | warcrafttavern, same article |
| Camelot bank paging threshold | `BankPanel` on Camelot sets `maximumTotalSlotsPerPage = 88` (Mainline default is 96). A 48-slot bank fits on **one page**, so the client may present the bank as one continuous grid even if tabs exist underneath. `GetNumPagesForBankType` returns 1 page when `ShouldUsePlayerBagsInBank()` is false | `Blizzard_UIPanels_Game/Camelot/BankFrame.xml:88`, `Camelot/BankFrame.lua:86-101` |
| `C_CurrencyInfo` | present and large: `PlayerMoney`, `AccountMoney`, `GetCoinText`, `GetCoinTextureString`, `GetBackpackCurrencyInfo`, `GetCurrencyListInfo`, `GetCurrencyListSize`, `GetCurrencyLink`, `GetCurrencyIDFromLink`, `SetCurrencyBackpack`, `PickupCurrency`, `IsAccountWideCurrency`, `FetchCurrencyDataFromAccountCharacters`, `CurrencyDisplayUpdate`. Forever has a currency tab on the character panel — **money and currency display is the client's API, not ours to rebuild** (`FR-48`) | `CurrencyInfoDocumentation.lua`, `CurrencyConstantsDocumentation.lua` on `origin/forever` |
| `C_Bank.ShouldUsePlayerBagsInBank()` | exists, no args. Camelot's `BankFrameMixin:GetNumPagesForBankType` returns **1 page when it is false** and pages by `totalSlots / 88` when it is true (`BankFrame.xml:88` sets `maximumTotalSlotsPerPage = 88`). Whether the bank uses the player's own bags is the unknown that decides whether bank bags exist here at all | `Blizzard_UIPanels_Game/Camelot/BankFrame.lua:86-101` |
| `BankTabData` | `{ ID, bankType, name, icon (fileID), depositFlags (BagSlotFlags), tabCleanupConfirmation, tabNameEditBoxHeader }`, written by `C_Bank.UpdateBankTabSettings(bankType, tabID, tabName, tabIcon, depositFlags)`. Measured: the character bank **does** carry real `BankTabData` entries even though no tab strip is drawn — `ID 6, "Tab 1", icon 134400, depositFlags 0` for the grid, and a second one, `ID 7, "Tab 2", icon 134400, depositFlags 0`, once a bank bag slot is bought (2026-10-19). The tab name is the client's own (`Tab 2`), never the bag item's name. Issue #10's auto-deposit routing has one target today and two once a bag slot exists | `BankDocumentation.lua` + `/bos test dump` 2026-10-18 |
| `Enum.BankType` | `{ Character = 0, Guild = 1, Account = 2 }`. The guild bank is reachable as a *type*, but **the guild bank is out of scope for this addon** — its stacking rules and per-tab restrictions are a separate problem and only an offline-search product would care (`docs/07` Q15) | `ItemConstantsDocumentation.lua` |
| `C_Bank.PurchaseBankTab` | marked **`HasRestrictions = true`**. Forever has no secure handler snippets, so **we cannot buy bank tabs** and must not imply we can | `BankDocumentation.lua` |
| Bank events, measured | `BANKFRAME_OPENED` and `BANKFRAME_CLOSED` fire with **no payload**. A deposit or withdraw produces `ITEM_LOCK_CHANGED(containerID, slot)` then `BAG_UPDATE(containerID)` on **both** sides — `6 1` + `BAG_UPDATE 6` for the grid, `0 1` + `BAG_UPDATE 0` for the backpack, `BAG_UPDATE -1` alongside. `ITEM_LOCK_CHANGED` slots are grid-relative inside container 6 (`6 1`, `6 48`), not a global bank slot number. **`PLAYERBANKSLOTS_CHANGED` fires only when the bag in a bank slot changes** (2026-10-19: payload `2` twice, once per swap), and the payload is the **bank bag slot number 1..9, not a container index** — Camelot's own conversion is `ITEM_INVENTORY_BANK_BAG_OFFSET + bagSlot`, so `2` means container 7. It never fires for deposits or withdrawals, where refresh stays `BAG_UPDATE(6)` + `ITEM_LOCK_CHANGED(6, slot)`. **Ordering, measured 2026-10-19 (`/bos test 27`): the source container unlocks before the destination locks, and both sides get their own `BAG_UPDATE` — deposit `ITEM_LOCK_CHANGED 0 6` → `6 1` → `BAG_UPDATE 6` → `BAG_UPDATE 0`; withdraw `6 1` → `BAG_UPDATE 6` → `0 6` → `BAG_UPDATE 0`. The pairs are not strictly lock-then-update per side, so a refresh keys on `BAG_UPDATE(containerID)` and treats `ITEM_LOCK_CHANGED` as detail, not as the trigger.** Moving a bag between the bank and the character fires `ITEM_LOCK_CHANGED <inventorySlot>` (32, 33 — one argument, an inventory slot) plus `BAG_UPDATE <bagIndex>` for the receiving character bag slot. `BANK_TABS_CHANGED` / `BANK_BAG_SLOT_FLAGS_UPDATED` still unobserved — they need a purchase, and no UI on this client changes a tab name or flag yet | `/bos test log` 2026-10-18, two runs (issue #9) |
| Opening the bank fires no container event | `BANKFRAME_CLOSED` immediately followed by `BANKFRAME_OPENED` with nothing after it. With index 6 reading 0 slots while closed, the bank container enters the discovered list only through an explicit `BANKFRAME_OPENED` handler — mandatory at M5, not an optimisation | `/bos test log` 2026-10-18 |
| **A purchased bank bag is a second container in the same paged grid** (measured 2026-10-19, `/bos test dump` + `/bos test log`) | One bag slot owned, an 8-slot bag in it: `bank slot [7] Bank 8`, `grid containers 2 total slots 56 per page 88 page 1` (`grid 6 48`, `grid 7 8`), `purchased tab ids 6,7`, total container slots **124**. `GetBagName(7)` is **`Bank`** — the same name as the grid and every unpurchased slot; **the container API never reports the bag item's name**, so a bank window cannot be labelled after the bag it holds. Swapping the bag moved index 7 from 6 → 0 → 8: **the container's slot count follows the bag item placed in the slot**. Its contents are read at the bag's own index with bag-relative slots (`ITEM_LOCK_CHANGED 7 5` then `BAG_UPDATE 7` for a deposit, `7 3` for a withdraw). The bag has no window of its own, so the bank is one paged view over 6..14 — what `data/harvest.lua` already assumes | `/bos test dump` + `/bos test log` 2026-10-19 (issue #25) |
| **Bag slot indices are positions, not identities** (measured 2026-10-19) | The same session read equipped bags as `[1] Small Red Pouch 6, [2] Scorched Leather Pouch 6, [3] nil` and, after a bag moved between the bank and the character, as `[1] Small Red Pouch 6, [2] nil, [3] Scorched Leather Pouch 6`. The client re-slots equipped bags, so nothing per-bag may be keyed on a bag slot index — only on the item itself. Measured again 2026-10-20 with three bags equipped: `[1] Small Red Pouch 6, [3] Scorched Leather Pouch 6, [4] Red Linen Bag 8` and **index 2 empty** — an empty middle bag slot, which harvest correctly reports as no container rather than a 0-slot one | `/bos test dump` 2026-10-19 (issues #2, #25), `/bos test 36` 2026-10-20 (issue #36) |
| Consequence for harvesting | **never enumerate `Enum.BagIndex` to find containers.** Derive from the constants, `pcall` each index, de-duplicate. Reading one index under two names counts the same items twice — the classic wrong-totals bug. Issues #9, #10, #11 | derived from the rows above |
| `C_Bank.IsItemAllowedInBankType(bankType, itemLocation)` | the only bank-restriction predicate on this client (there is no `C_Item.CanItemFitInContainer`). Check it **before** a deposit, not after a failure | `BankDocumentation.lua` |
| `Enum.BagSlotFlags` | 10 values, 1..512 (`DisableAutoSort`, `ClassEquipment`, `ClassConsumables`, `ClassProfessionGoods`, `ClassJunk`, `ClassQuestItems`, `ExcludeJunkSell`, `ClassReagents`, `ExpansionCurrent`, `ExpansionLegacy`). Measured 2026-10-19 (`/script` over `0..NUM_TOTAL_EQUIPPED_BAG_SLOTS` and `6..14`): **no flag set on any container** — the equipped Small Red Pouch, Scorched Leather Pouch and the reagent bag (`Apprentice's Herb Pouch`, index 5) all read empty, as do bank containers 6..14. Specialty identity on this client is positional (index 5 is the reagent bag), not flag-driven | `BagConstantsDocumentation.lua` + `/script` 2026-10-19 (issue #2) |
| New-item glow | The client's own new-item list is the state, and the client's own method draws it. `ContainerFrameItemButtonMixin:UpdateNewItem(quality)` reads `C_NewItems.IsNewItem(bagID, slot)`, sets `NewItemTexture`'s atlas from `NEW_ITEM_ATLAS_BY_QUALITY[quality]` (fallback `bags-glow-white`), and plays `newitemglowAnim` — alpha 1 → 0.2 → 1, 0.5 s each way, looping (`ContainerFrame.xml:86-89`): the pulsating highlight in `docs/reference/new-item-highlight-*.png`. `frames/item.lua` calls it on every paint, item slots and the free-slot cell alike, so the glow is re-derived from the client on each refresh instead of inherited by a pooled button. Hovering clears it: `OnEnter` → `OnUpdate` → `C_NewItems.RemoveNewItem(bagID, slot)` hides the texture and stops the anims, and the next paint reads false. `C_NewItems` is `IsNewItem` · `RemoveNewItem` · `ClearAll`, `Environment = "All"`; `ContainerItemInfo` carries **no** `isNewItem` field, which is why BetterBags computes it from `C_NewItems.IsNewItem` (`data/items.lua:2315`). **Measured 2026-10-20 (`/bos test 35`, build 70450): the client's list is sane on Forever** — at login 24 item slots read **0 flagged new**; acquiring one item flags exactly one slot (`[1] slot 3 item 4813`) and our button for it draws `NewItemTexture bags-glow-white` at `alpha=0.46`, mid-pulse; hovering returns it to 0 flagged and the texture is gone. No `C_NewItems.ClearAll()` at login is needed. The glow is re-derived only on our own refresh, so a client-side expiry with no `BAG_UPDATE` leaves it until the next one — `BAG_NEW_ITEMS_UPDATED`, which Blizzard's container frames register (`ContainerFrame.lua:706`), is the event to key on if that ever matters. Blizzard's own item buttons are unnamed `CreateFramePool` frames reachable as `ContainerFrameCombinedBags.Items` — **`.Items`, not `.items`** — which is what `/bos test newitem` reads; the same run showed the template's `IconQuestTexture` sitting **shown at alpha 1 with no texture** on all 25 of our buttons, i.e. invisible, the FR-45 half of issue #16 | `origin/forever` `ContainerFrame.lua:509-524`, `:685`, `:706`, `:1688-1720`, `ContainerFrame.xml:86-89` and `:116`, `NewItemsDocumentation.lua`, `ContainerDocumentation.lua:766-782`, `/bos test 35` capture 2026-10-20, issue #35 |
| **Blizzard's bag layout is not reusable by addons** | `UpdateContainerFrameAnchors()` is global (`Mainline/ContainerFrame.lua:1378`, Camelot does not override it) but its body iterates `ContainerFrameSettingsManager:GetBagsShown()` — Blizzard's own frame list, and that manager is what hard rule 8 forbids. Its helpers and constants are `local` to the file: `GetContainerScale` (`:1326`), `GetInitialContainerFrameOffsetX` (`:1318`), `CONTAINER_SPACING = 8`, `CONTAINER_SCALE = 0.75`, `CONTAINER_WIDTH = 178`; only `CONTAINER_OFFSET_Y = 85` and `CONTAINER_OFFSET_X = -4` are globals (`:21-22`). Blizzard's answer to a column that overflows is to shrink container scale in 0.01 steps down to 0.75 and restart, and it stops wrapping left at `BankFrame:GetRight() - 25` while the bank is open. Camelot's `BagsBar` is `Size y=45`, anchored `TOPRIGHT` to `MicroButtonAndBagsBar`, horizontal, `direction = Enum.BagsDirection.Left` (`Blizzard_MainMenuBarBagButtons/Camelot/MainMenuBarBagButtons.xml:44`). Consequence: our placement in `layout/anchors.lua` is a **port** of that loop, never a call to it | `origin/forever` `Blizzard_UIPanels_Game/Mainline/ContainerFrame.lua:21-28`, `:1318-1408`, `Blizzard_MainMenuBarBagButtons/Camelot/MainMenuBarBagButtons.xml:44`, issue #28 |
| **The bag bar is configurable; the bag window is not** (measured 2026-10-20) | The test account runs Camelot's bag bar in **vertical** mode, where `BagsBar:GetTop()` measures **317**. Anchoring the stack above the bar put the three windows 317 px up the screen, flush to the right edge with no margin (`docs/reference/window-placement-flush-right-vertical-bar.png`). `ContainerFrameCombinedBags` is a global **frame**, readable with `:GetBottom()`/`:GetRight()` — the forbidden thing is the `ContainerFrameSettingsManager` **manager** (hard rule 8). Our windows anchor bottom-right to the client's bag window bottom-right, **shifted 10 px left of it** — the client's own gap from the screen edge is only its `GetInitialContainerFrameOffsetX()` floor, so right-aligning to its corner reproduces the flush look | `/bos test windows` capture on issue #28, 2026-10-20; #30 |
| **The window money bar is the client's own template** (measured 2026-10-20, `/bos test 32`) | `ContainerMoneyFrameTemplate` — the frame `ContainerFrameTemplate` carries as `.MoneyFrame` (`ContainerFrame.xml:202-227`, `:289`) — loads on Camelot (`[Family]\ContainerFrame.xml` carries no game-type filter, and `Blizzard_UIPanels_Game.toc` declares `## Dep: Blizzard_MoneyFrame [AllowLoadGameType mainline]`) and an addon creates it directly with no setup beyond its anchors. Measured on all three windows: `shown true`, height **13** — `SmallMoneyFrameTemplate`'s own size, which Blizzard raises to 16 only for the combined-bag window — anchored `BOTTOMLEFT +8,+8` / `BOTTOMRIGHT -8,-8` like `ContainerFrameTokenWatcherMixin:UpdateCurrencyFrames`. Its own `OnLoad` + `OnShow` keep it current: `0 10 11` at `GetMoney() 1011` → sell one stack → `0 10 39` at `1039` → buy back → `0 10 11`, with no refresh from us and no blocked call. Clicking a coin on this template reaches `showCurrencyTracking` → `CharacterFrame:ToggleTokenFrame()`: the character frame's currency tab, not a pickup popup. Money only — nothing here reads `GetBackpackCurrencyInfo`, so `FR-48`'s currency half stays open. **One window carries the bar** (issue #42): `Pipeline.Assign` gives it to the first backpack window in screen order — the same single-owner rule as the free-slot count, and it travels when that window is closed — and `flow.Layout` reserves `MONEY_BAR_SPACE` only for the window that draws it, so the other windows are 17 px shorter and print `money: none` in probe 16 | `/bos test 32` capture on issue #32, 2026-10-20; `origin/forever` `ContainerFrame.xml`, `Blizzard_MoneyFrame/Mainline/MoneyFrame.lua:40-52`, `MoneyInputFrame.lua:219-224` |
| **The stack falls back to the backpack button when the client's bag window is closed** (measured 2026-10-20) | `/bos test windows` reads `anchor MainMenuBarBackpackButton`, `anchor bottom 0`: `ContainerFrameCombinedBags` is present but not `IsShown()` in a session where the player has closed Blizzard's bag window — the state a player who uses our windows is usually in. The placement rule therefore has a live second path, and #18 needs it as a deliberate rule rather than the fallback branch of #30 | `/bos test 32` capture (issue #32), 2026-10-20; #30, #18 |
| **The client's empty container slot is an atlas on the button template** | `ContainerFrameItemButtonTemplate` carries `emptyBackgroundAtlas = "bags-item-slot64"` (`Mainline/ContainerFrame.xml:84`). `SetItemButtonTexture(button, nil)` reaches it: `ItemButtonMixin:GetItemButtonBackgroundTexture` (`Blizzard_ItemButton/Mainline/ItemButtonTemplate.lua:417`) → `GetItemButtonBackgroundTexture_Base` (`:58`) → the icon texture is shown with that atlas (`:76-99`). The other empty-slot piece, `ItemSlotBackgroundCombinedBagsTemplate`, is only created when `GetParent():IsCombinedBagContainer()` is true (`Mainline/ContainerFrame.lua:1846`), and our wrapper answers false, so the atlas is the empty-slot look an addon gets. **Measured on our own window 2026-10-20:** the pooled button draws it, with the number in Blizzard's own `Count` fontstring — `indicator shown true bag 0 slot 2 count shown true text 26` | `origin/forever` source + `/bos test 36` capture (issue #36), 2026-10-20 |
| **Blizzard's free-slot number is `C_Container.CalculateTotalNumberOfFreeBagSlots()`** | no arguments, returns `totalFreeSlots` (`ContainerDocumentation.lua:11`). Blizzard draws it in exactly two places: the backpack **button** — `MainMenuBarBackpackMixin:UpdateFreeSlots`, text `"(%s)"`, visibility gated by the `displayFreeBagSlots` CVar (`Shared/MainMenuBarBagButtons.lua:339-356`) — and the combined-bags window's `CountContainer.Count`, which `ContainerFrameCombinedBagsMixin:Update` fills **only when `InputUtil.IsGamepadUIEnabled()`** (`Mainline/ContainerFrame.lua:2819-2833`). A keyboard player's bag window therefore shows no free-slot count at all: the number our indicator draws is ours, checked against the client's. **Measured 2026-10-20 on two `/bos test 36` runs: it is the free-slot sum of containers 0..4 — the backpack plus the four bag slots — and it leaves out the reagent bag (index 5) and the keyring.** It reads 22, 21, 22 across a vendor buy and sell while our count then read 25, 24, 25: the 3-slot `Apprentice's Herb Pouch` was the whole difference, and **our count now covers the same 0..4 set** — the pouch is harvested and drawn, its free slots are counted apart and shown nowhere until FR-44's per-family design decides how an empty reagent pouch reads (issue #36). **Inferred, not measured: while the bank is open the bank grid joins the total.** In a run that moved items between the bags and the grid, the total held at 70 three times while the bag half moved 23 → 22 → 23, so something moved 47 → 48 → 47 the other way, and the 48-slot grid is the only container that moves inversely during a deposit. Two reads either side of opening the bank would settle it. Our indicator never sees the bank either way: harvest drops the bank containers on `BANKFRAME_CLOSED` | `origin/forever` source + `/bos test 36` captures (issue #36), 2026-10-20 |
| **`SetItemButtonCount` hides a count of 1** | `minDisplayCount` defaults to 1 and the test is `count > minDisplayCount` (`ItemButtonTemplate.lua:20-21`), so a free-slot count of 1 draws nothing until the button lowers that floor — ours sets `minDisplayCount = 0` and the pool clears it on release, so item buttons keep Blizzard's own behaviour (a stack of 1 shows no number). BetterBags sets `-1` for the same reason (`frames/item.lua:911`) | `origin/forever` source, issue #36 |
| `GetTime()` resolution | **frame-quantized on this client**: 1e6 Lua iterations measured **0 ms** in-game (2026-10-17). A phase timed inside one refresh is therefore unmeasurable — `/bos perf` phase numbers read `0.00` no matter how slow the pipeline is. Measure across frames instead: `/bos test clock` runs the pipeline 100×10 times spread over frames and reports ms per refresh. Neither `GetRealTime` nor `C_Profiler` is referenced anywhere in `origin/forever` FrameXML | `/script` probe 2026-10-17, `git grep origin/forever -- Interface` |
| `/script` limits | one line, capped near **255 characters**: the chat edit box sends a single line and `RunScript` compiles one chunk. A longer snippet is truncated and Lua reports `'end' expected near '<eof>'`, which reads like a code bug and is not one. In-game captures live in `core/diag.lua` (`/bos test`) for this reason | in-game 2026-10-17, `wow-forever-api` skill |
| **What this client persists** (WTF tree, 2026-10-18/19) | `SavedVariables/BagsOfSorting.lua` is written and survives a session — item cache, profile and the `/bos` probe capture all present — so the Forever "addon settings don't save" reports do not apply to us. `bindings-cache.wtf` carries other addons' `Bindings.xml` actions (`bind NUMLOCK LOREFOREVER_TOGGLE`) **and ours**: `bind CTRL-B BAGSOF_SORTING_TOGGLE`, surviving `/reload` twice and a game restart, with `C_KeyBindings.GetBindingIndex('BAGSOF_SORTING_TOGGLE') = 287` and `GetCurrentBindingSet() = 1` = `Enum.BindingSet.Account` (`KeyBindingsDocumentation.lua:212-215`) — one key for the whole account, the same scope as `db.sv.global`. The 2026-10-17 "lost on `/reload`" report does not reproduce: in that session the line never reached the file. `config/keybinds.lua` stays as insurance — it stores what the client has at login and re-applies it only when the client has nothing (issue #13) | `WTF/Account/<account>/bindings-cache.wtf` + `.old`, `SavedVariables/BagsOfSorting.lua`, `/bos test keybind` 2026-10-19 |
| **SavedVariables file names ignore the TOC declaration** (issue #14) | Forever writes **one file per addon, named after the addon folder**, whatever `## SavedVariables:` declares, and puts every declared global inside it: `BagsOfSorting.lua` holding `BagsOfSortingDB`, `LoreForever.lua` holding `LoreForeverDB`, `Leatrix_Plus.lua` holding `LeaPlusDB`, `BetterBags.lua` holding `BetterBagsDB` — that TOC declares two names and still gets one file. Our TOC is written the way retail expects, so the mismatch is a Forever quirk rather than a mistake, and the file name only changes if the folder does. Issue #8 baselines `SavedVariables/BagsOfSorting.lua` | `WTF/Account/<account>/SavedVariables/*.lua` against each addon's `.toc`, 2026-10-19 |
| `GetBinding` is index-based; `GetBindingKey` is action-based | `GetBinding(i)` takes a **binding index** (`Blizzard_PTRFeedback.lua:146`) and **errors on a string** — `GetBinding('SOME_ACTION')` is a Lua error, not a nil. "What key is bound to this action?" is `GetBindingKey(action)` (up to two keys) or `C_KeyBindings.GetBindingByKey(action)` | in-game 2026-10-19 (`/bos test keybind` died on its second line), `origin/forever` `Blizzard_PTRFeedback.lua:146`, `ActionButton.lua:498` |
| `C_Item.GetItemInfo` | `MayReturnNothing = true` — the client only knows items it has seen | `ItemDocumentation.lua` |
| Async item fetch | `C_Item.RequestLoadItemDataByID(itemID)` → `ITEM_DATA_LOAD_RESULT`; Blizzard's own `AsyncCallbackSystemMixin` (`ASYNC_ITEM`) is the reference and loads on camelot | `Blizzard_ObjectAPI/Mainline/AsyncCallbackSystem.lua` |
| Icon picker | `IconDataProviderMixin` (`GetNumIcons`, `GetIconByIndex`, `GetIconForSaving`, `GetIndexOfIcon`) + `IconSelectorPopupFrameTemplate` | `Blizzard_FrameXMLBase/IconDataProvider.lua` |
| `C_Item.CanItemFitInContainer` | **absent** on Forever — bag restrictions must be inferred from `GetBagSlotFlag` + item type | grep of `Blizzard_APIDocumentationGenerated` |
| **Everything parented to `UIParent` shares one MEDIUM strata band, so only frame levels separate it** (measured 2026-10-20, `/bos test 34`) | `UIParent` itself reads `strata MEDIUM level 0 fixed false`, and so does every frame our windows can overlap: `MainActionBar` **50** (its EndCaps 100), `BagsBar` **52**, `MainMenuBarBackpackButton` **53**, `MicroButtonAndBagsBar` 1, `ContainerFrameCombinedBags` 1. `HasFixedFrameStrata()` is **false** on all of them — they follow UIParent rather than declaring a band — so there is no strata trick available, only levels. Our shells therefore sit on an explicit base (`frames/window.lua` `CONTENT_BASE = 300`): above every bar and above Blizzard's bag buttons (`ContainerFrameItemButtonTemplate` `frameLevel 10`), below the chrome the portrait template carries (portrait 400, border 500, title/close 510). Where our windows overlap Blizzard's own bag window **Blizzard's draws on top** — its chrome carries the same 400/500/510 numbers and its window is `toplevel` — and that is accepted, because the client's bags stay reachable (FR-51) | `/bos test 34` capture 2026-10-20, build 1.60.1 (70450); `MainActionBar.xml:29`, `Camelot/MainMenuBarBagButtons.xml:44`, `ContainerFrame.xml:308`; issue #34 |
| **Region bounds: `GetRect` is the one this client has** | `GetRect()` returns `left, bottom, width, height` and works on frames, textures and fontstrings. **`GetAbsBounds` is absent** — the first run of the `portrait` probe died on it with `attempt to call a nil value`. `GetBounds` is likewise undocumented on `origin/forever` | `/bos test 34` 2026-10-20, `SimpleScriptRegionAPIDocumentation.lua` |
| **A window shorter than its own border art has to clip that art, and the client has a call for it** | In `HeldBagLayout` the `TopLeftCorner` — `ui-frame-portraitmetal-cornertopleftsmall`, the portrait ring — anchors `TOPLEFT` at **(-13, +16)**, i.e. 16 px **above** the frame's top edge, and the bottom corners at **(-13, -3)** / **(4, -3)**, 3 px below its bottom edge. `LeftEdge` is anchored from `TopLeftCorner`'s `BOTTOMLEFT` to `BottomLeftCorner`'s `TOPLEFT` (`SetupEdge`), so once the two corners meet that edge has **negative height** and the bottom corner art reaches up over the medallion — the "left border above the bag icon" report. `NineSliceUtil.UpdateCornerCropping(container, height)` clips the bottom corners by exactly the overlap (`topCornerHeight + bottomCornerHeight − height − 16 − 3`) and is what `ContainerFrameMixin:UpdateFrameSize` calls straight after `SetSize`; `NineSlicePanelTemplate` carries no `layoutType` of its own, so it reads the frame's, and ours is `HeldBagLayout`. Reversible: the crop is recomputed from `C_Texture.GetAtlasInfo` on every call, so a taller window gets its full corners back. Offsets, the formula and the call are the client's own; the numbers on our windows are the pending `/bos test 43` capture | `origin/forever` `NineSliceLayouts.lua:361-373`, `NineSlice.lua:96` and `:101`, `:238-297`, `ContainerFrame.lua:992`; issues #43, #31 |

| **Item class and subclass names are the client's own, and they are not retail's** (measured 2026-10-20, `/bos test subclasses`, build 1.60.1 70450) | The whole table, read off `C_Item.GetItemClassInfo` / `C_Item.GetItemSubClassInfo`: **0 Consumable** (Explosives, Potions, Elixirs, Flasks, Scrolls, Food & Drink, Permanent, Bandages, Other, Draughts, Devices, Temporary) · **1 Container** (Bag, Soul Bag, Herb Bag, Enchanting Bag, Engineering Bag, Mining Bag, Leatherworking Bag, Tackle Box, Cooking Bag, **Reagent Bag**, **Trinket Bag**) · **2 Weapon** · **3 Jewelry(OBSOLETE)** · **4 Armor** (Miscellaneous, Cloth, Leather, Mail, Plate, Cosmetic, Shields, Librams, Idols, Totems) · **5 Reagent** · **6 Projectile** · **7 Trade Goods** (Trade Goods (OBSOLETE), Parts, Explosives (OBSOLETE), Devices (OBSOLETE), Cloth, Leather, Metal & Stone, Cooking, Herb, Elemental, Other, Enchanting) — **no 4/Jewelcrafting and no Inscription subclass at all** · **8 Generic(OBSOLETE)** · **9 Recipe** (Book, Leatherworking, Tailoring, Engineering, Blacksmithing, Cooking, Alchemy, First Aid, Enchanting, Fishing) · **10 Money(OBSOLETE)** · **11 Quiver** · **12 Quest** · **13 Key** · **14 Permanent(OBSOLETE)** · **15 Miscellaneous** (Junk, Reagent, Pet, Holiday, Other, Mount) · **18 WoW Token**; nothing answers for 16 or 17. Consequences for rules: the class is **`Trade Goods`**, not retail's `Tradeskill`; one `type = "Consumable"` rule covers potions, flasks, elixirs, draughts, scrolls, food, drink and bandages; `Cloth` and `Leather` are Armor subtypes too, so a tradeskill rule must pin `type`; **`Alchemy` exists only as a Recipe subtype — the book, not the reagents**; and there is no Jewelcrafting subclass, so a gems category has nothing to match until `/bos test owners` sees a gem in a bag | `/bos test subclasses` + `/bos test owners` capture on issue #41 (2026-10-20); `origin/forever` `ItemDocumentation.lua:404` and `:1020` |

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
- `Region:GetAbsBounds()` / `GetBounds()` — absent, measured: a probe call reached `attempt to call a nil value`. Use `GetRect()`

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
- **Milestone docs are planning documents.** `docs/06` changes when a milestone changes, not when a story
  inside one closes. A deliverable stays written as the plan wrote it; the verdict from its run goes to
  `agents.md` and the issue. Only a milestone's own `Status:` line moves, and only at a milestone boundary.

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
# in-game manual tests: /bos test  (core/diag.lua) — the pending list; /bos test <id> prints its numbered run sheet, one action per step
# capture workflow: .pi/skills/bos-test-capture/SKILL.md; the standing acceptance list: tests/CHECKLIST.md
# API questions: the `spike` issues
```

The harness in `tests/` is the smallest one M0 calls for: `luacheck` plus `lua5.1 tests/run.lua`,
which loads the real modules against a stubbed container API. `tests/` is **not in the TOC**, so the
addon loads no test code in a dev checkout or in a release zip. It proves the classifier and the
pipeline wiring — not the Forever API calls (hard rule 1).

The in-game half is the `/bos test` capture path, **verified end-to-end on the live client (issue #27,
2026-10-19)**: one bucket per test keyed by the issue number, a header per captured step carrying
interface version, build number, player and realm, a helper called from a test step keeps that test's
bucket and names its state inline (`dump while bankOpen`), and the last captured step writes the ingest
reminder. A run sheet step is **one action**: a compound step ("deposit it, then withdraw it") loses
its second half, because the runner's eye lands on the command printed after it.

---

## What not to do

- Do not fork Baggins or BetterBags. Read them for behavior; write our own.
- Do not add a filter/rule type without also adding its chip rendering + preview support in the
  config UI. A rule type that the UI cannot explain is a Baggins-style footgun.
- Do not add options that have no UI story. Every setting must answer: where does the user see
  it, and how do they learn it exists?
- Do not touch `../addons/Baggins` or `../addons/BetterBags` from this repo. They are read-only
  references (both are git clones of upstream).
