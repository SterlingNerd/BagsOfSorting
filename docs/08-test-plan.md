# 08 — In-game Test Plan (`/script`)

Runnable checks for the Forever client. `docs/06` says a milestone is not done until its AC lines
have a dated entry; this doc is where the entries come from.

**`/script` works on Forever** (`Blizzard_ChatFrameBase/Shared/SlashCommands.lua` → `SCRIPT` →
`RunScript`), gated by `C_GameRules.IsGameRuleActive(Enum.GameRule.UserScriptsDisabled)` and a
one-time "dangerous scripts" confirmation. Also available on `origin/forever`: `/dump`,
`/eventtrace`, `/framestack`, `/api`, `/1`…`/9` macro-text entry.

Rules for this file:
- Every snippet is pasteable as one line. Multi-line ones are marked.
- Anything that writes to SavedVariables or moves items is marked ⚠️ and says how to undo it.
- A result that contradicts `agents.md` means **update `agents.md` in the same sitting**.
- Record results as `YYYY-MM-DD @ build <GetBuildInfo()>` under each section.

---

## A. Item data is not always there (`FR-103`, `FR-97`, M0/M1)

The whole enrich design rests on these four answers. Do them before writing `data/enrich.lua`.

```
/script local id=26042 print("instant:", select(5, C_Item.GetItemInfoInstant(id)), C_Item.GetItemInfoInstant(id))
```
Expect an icon fileID even for an item never seen this session. Record **no** if the whole call
returns nil — that changes the design of the category editor's item list.

```
/script local id=26042 local a,b,c,d,e,f,g,h,i=C_Item.GetItemInfo(id) print("full:", a, b, e, f)
```
Compare with the line above on a cold ID. `GetItemInfo` is documented `MayReturnNothing`; confirm it
actually returns nothing rather than a partial row.

```
/script C_Item.RequestLoadItemDataByID(26042)
```
Then loot/see nothing and watch for the event:

```
/script local f=CreateFrame("Frame") f:RegisterEvent("ITEM_DATA_LOAD_RESULT") f:SetScript("OnEvent",function(self,e,...) print("ITEM_DATA_LOAD_RESULT", ...); local n=C_Item.GetItemNameByID(26042) print("name now:", n) end)
```
Expected: the event arrives within a second or two and the name resolves **without a reload**. If it
never arrives, `docs/03` §Item data is not always there loses tier 3 and the item cache becomes
load-bearing in a different way.

```
/script print(C_Item.GetItemQualityByID(26042), C_Item.GetItemNameByID(26042))
```
Do this immediately after login, before anything has touched those items, to learn whether these read
the same server-backed cache as `GetItemInfo` or a local table.

Fixture for the classifier: pick 5 IDs the client has definitely never seen (deep-classic items you
do not own) and 5 it definitely has. `/bos selftest` should pass on the second group and report
"pending" on the first.

---

## B. Client capability dump (M0, `Q10`)

One paste, prints the table `agents.md` is missing. Keep it as the body of `/bos` capability output.

```
/script print("project", WOW_PROJECT_ID, WOW_PROJECT_CAMELOT, GetBuildInfo())
```

```
/script print("itemButtonType", C_Container and "C_Container ok", issecure())
```

```
/script print("keyring", KEYRING_CONTAINER, C_Container.GetContainerNumSlots(KEYRING_CONTAINER), GetKeyRingSize and GetKeyRingSize())
```

```
/script print("bags", NUM_TOTAL_EQUIPPED_BAG_SLOTS, NUM_BACKPACK_SLOTS, NUM_CONTAINER_FRAMES)
```
(`NUM_BACKPACK_SLOTS` / `NUM_CONTAINER_FRAMES` may be absent on this client — a nil here is itself a
result worth recording.)

```
/script local n=C_Bank.FetchNumPurchasedBankTabs(Enum.BankType.Character) print("bankTabs", n, "account?", C_Bank.FetchViewableBankTypes and C_Bank.FetchViewableBankTypes())
```

```
/script for i=0,(NUM_TOTAL_EQUIPPED_BAG_SLOTS or 4)+(C_Bank.FetchNumPurchasedBankTabs(Enum.BankType.Character) or 0) do local ok,name=pcall(C_Container.GetBagName,i) local slots=select(1,pcall(C_Container.GetContainerNumSlots,i)) print(i, ok and name or "ERR", slots) end
```
This is the loop `data/harvest.lua` will run. Record which indices error, which return 0, and whether
the inert `Enum.BagIndex.AccountBankTab_N` range errors or returns 0 (`agents.md` open fact).

```
/script print("combinedBags", IsUsingCombinedBags and IsUsingCombinedBags(), "reagentBag", C_Container.GetContainerNumSlots(Enum.BagIndex.CharacterReagentBag or 4))
```

```
/script print("flags", C_Container.GetBagSlotFlag(0, Enum.BagSlotFlags.ClassReagents), Enum.BagSlotFlags.ExpansionLegacy, Enum.BagSlotFlags.ClassProfessionGoods)
```
Run this with a herb pouch / quiver equipped and record which flag each specialty bag reports — that
mapping is what `FR-66` affinities are built on, and it is the part no documentation states.

```
/script print("editmode", EditModeManagerFrame ~= nil, C_EditMode ~= nil, EditModeSystemSelectionTemplate ~= nil, EditModeSystemSettingsDialogButtonTemplate ~= nil)
```
Answers `Q13`'s second question before the M2 spike starts.

```
/script print("iconpicker", IconDataProviderMixin ~= nil, IconSelectorPopupFrameTemplate ~= nil, IconDataProvider_GetAllIconTypes and #IconDataProvider_GetAllIconTypes())
```
`FR-85` depends on these being present.

```
/script print("matcher", ItemButtonUtil and ItemButtonUtil.GetItemContextMatchResultForItem ~= nil, ItemButtonUtil and ItemButtonUtil.GetItemContextMatchResultForContainer ~= nil)
```
Confirms `agents.md`'s "absent on Forever" claim for the container variant (`Q7`).

```
/script print("scriptsAllowed", C_GameRules.IsGameRuleActive(Enum.GameRule.UserScriptsDisabled), C_AddOns.GetScriptsDisallowedForBeta())
```

---

## C. Taint & combat (`FR-3`, `FR-4`, `AC-4`, `AC-68`)

```
/script print("secure before", issecure())
```
Run before and after every suspicious action; a `false` means we tainted the environment and
`/events` will show who.

```
/script print("lockdown", InCombatLockdown())
```

Manual, in combat, each time: toggle every window, open/close configure mode, try a bulk sell, try
*Empty this bag*, try a drag onto a section header. Then `/events` and look for
`ADDON_ACTION_FORBIDDEN`. Record the function named.

The known trap to re-test whenever we touch container frames (`ForeverPlus` already ate this):

```
/script ContainerFrameSettingsManager:GetBagsShown() print("secure after GetBagsShown", issecure())
```
If this prints `false`, our rule "never call a Blizzard container manager just to read it" is a hard
rule, not advice.

Death / resurrect / `/reload` mid-combat: `/reload` while in combat, then `/events`, then confirm item
buttons still pick up items and that no button is silently tainted (`AC-4`).

---

## D. SavedVariables hygiene (`FR-90`, `FR-93`, `AC-93`)

```
/script local s=select(4,GetAddOnInfo("BagsOfSorting")) print("sv size", s)
```
Or off the client: `stat -c %s WTF/Account/…/BagsOfSortingDB.lua` before and after a test run.

Cycle test: open/close all backpack windows 20× (`/bos test cycle 20`), then diff the file. Expected:
no growth. Any growth means a write on a render path — look for the pool high-water mark first
(Baggins' `lastNumItemButtons` is the precedent).

```
/script print("addon memory", GetAddOnMemoryUsage and GetAddOnMemoryUsage("BagsOfSorting"))
```
Take it before, after 20 cycles, after 20 more. `FR-104` is a flat line, not a shrinking one.

---

## E. Layout stress (`AC-40`, `docs/01` scale)

Throwaway slash commands from M2 are the harness; these are the cases:

| Case | How |
|---|---|
| 12 sections, 5 columns | `/bos test fill 12 5` |
| 22 sections, 6 columns (the real `Bank Trade Goods` shape) | `/bos test fill 22 6` |
| 30-character section name | `/bos test fill 1 5 "A very long section name indeed"` — check the title is not clipped and the packing math does not use a magic divisor |
| 74 categories / 117 sections | import the `docs/01` shape via `BOS1.` string, measure `/bos perf` |
| collapsed section in a packed row | collapse the middle section of a 3-section row, confirm no gap and no overlap |
| empty section | confirm hidden-by-default and that the window shrinks |

---

## F. Physical moves (`FR-68`, `AC-66`, `AC-67`)

⚠️ These move real items. Do them on a character whose inventory you do not mind shuffling, with the
bank open.

```
/script for b=0,NUM_TOTAL_EQUIPPED_BAG_SLOTS-1 do local f=C_Container.GetContainerFreeSlots(b) print(b, C_Container.GetBagName(b), f and #f or "?") end
```
Read the free-slot numbers *before* an empty-bag test so the expected outcome is known.

Empty-bag refusal case: fill a 20-slot bag, free only 18 slots elsewhere, run *Empty this bag*.
Expected: refuses with a named count, **nothing on the cursor**, no partial move:

```
/script print("cursor", GetCursorInfo())
```
Run immediately after any failed bulk move. `nil` is the only acceptable answer.

Affinity case: equip a herb pouch, `/bos test affinity herbs`, confirm the virtual stack targets the
pouch first; unequip and confirm the fallback. Record which `BagSlotFlags` value the pouch reported
(from §B) next to the result.

---

## G. Coexistence (`FR-124`, `AC-124`)

```
/script for i=1,GetNumAddOns() do local n,_,_,_,_,loaded,_,_,_,_,_,_,reason=GetAddOnInfo(i) if loaded then print(n) end end
```
Paste the list into the milestone entry — the set changes between sessions and "it worked" without a
list is not evidence.

Then, one at a time, with our windows open and our keybinds at default:

| Addon installed | What to check |
|---|---|
| `ForeverPlus` | its Movable Bag Windows module + our windows: does anything fight over position; does `UseContainerItem` still work on a bag item |
| `Leatrix_Plus` | its "close bags when opening" option (it can `hooksecurefunc('OpenAllBags', CloseAllBags)`) vs our toggle |
| `Baggins` | both drawing bags; our startup warning (`FR-7`) appears; no double item pickup |
| `BetterBags` | same, plus its `OptionalDeps` Ace3 load order vs our zero-dependency load |
| `Masque` (if installed) | `AC-49`: our buttons take its skin with no code from us |
| `Pawn` (if installed) | `FR-122`: upgrade arrow appears via our provider seam |

---

## H. Performance (`FR-100`, `FR-101`, `AC-26`)

Real numbers come from `/bos perf`, which must print per-phase ms, item-data requests issued, button
pool size, and (for `AC-26`) which phases ran for a single-slot change. Record the numbers in the
milestone entry — `docs/06` says recorded, not asserted.

Single-item case: loot one item, `/bos perf last`, expect phases 2–4 only.

---

## I. Config UI human tests (`AC-70`, `AC-72`)

Not `/script` — a person, a fresh install, and a stopwatch.

1. "Make a window called Sell containing Junk and Quest." ≤ 3 minutes, **settings window must stay
   closed**. Write down every click. Two different people, twice, or `docs/05` is wrong (M3 risk).
2. "This item is in the wrong place. Fix it." ≤ 3 interactions.
3. "Here are 40 item IDs, put them in Herbs." Paste once, Apply. ≤ 3 interactions.
4. Build 3 windows + 8 sections in configure mode only (`AC-72`).
5. Make 10 edits, undo 10 times, diff SavedVariables (`AC-76`).

---

## J. Hostile pass (every milestone)

Full inventory + 74-category config + 22 sections in one window + a 30-char section name + an item
Blizzard has no info for + combat + death + `/reload` mid-combat + bank open + a specialty bag
equipped. Then `/events`. Then `print(issecure())`.

If a milestone's checklist cannot be run in one sitting, it is too big — split the milestone, not the
checklist.
