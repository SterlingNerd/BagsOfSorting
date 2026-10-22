# 08 — Window behavior on the Forever client

What our windows do, and the rules that follow from it. The client facts and their measurements live in
the `wow-forever-api` skill (`../.agents/skills/wow-forever-api/references/`); this file carries only the
decisions that belong to BagsOfSorting. Read the reference for evidence, this file for the rule.

---

## Placement

| Rule | Why |
|---|---|
| The stack anchors bottom-right to `ContainerFrameCombinedBags`' bottom-right, **shifted 10 px left** | reproduces the client's own gap from the screen edge; right-aligning to its corner is what the flush look is (`containers-and-bags.md` §bag bar) |
| When that window is closed, the stack anchors to `MainMenuBarBackpackButton` instead | a player who uses our windows has usually closed Blizzard's bag window, so this is a live path, not an edge case (issue #32, #30, #18) |
| Never anchor above the bag bar | Camelot's `BagsBar` is configurable and the test account runs it **vertical**, where `BagsBar:GetTop()` measures 317 px — the stack lands flush to the right edge with no margin (`docs/reference/window-placement-flush-right-vertical-bar.png`, issue #28) |
| Placement is a **port** of Blizzard's layout loop, never a call to it | `UpdateContainerFrameAnchors()` reads `ContainerFrameSettingsManager:GetBagsShown()` and its constants are `local` to the file (hard rule 8, `containers-and-bags.md`) |
| Anything that hides Blizzard's container frames iterates `NUM_CONTAINER_FRAMES`, not `NUM_TOTAL_BAG_FRAMES` | 6 or 7 frames on this client; a hide bounded at 5 left the tradeskill bag window open at a vendor (issue #38) |

`layout/anchors.lua` owns the anchor rule; `layout/flow.lua` owns the stack.

## Suppression: a vendor or the bank opens ours and keeps Blizzard's closed

`core/interactions.lua` opens our windows and hides Blizzard's bag windows whenever an interaction
(vendor, bank) opens a Blizzard panel, and restores on close.

- The vendor events on this client are `MERCHANT_SHOW` / `MERCHANT_CLOSED` — both with no payload
  (`containers-and-bags.md`).
- Hiding Blizzard's bag windows costs a vendor or the bank **nothing**: buy, sell out of our window,
  deposit into the bank grid and withdraw all completed with the ordinary `ITEM_LOCK_CHANGED` +
  `BAG_UPDATE` pair on both sides (issue #38, measured 2026-10-22).
- `ToggleAllBags` is **not hooked**, so a deliberate `CTRL-B` — even while the vendor is open — brings
  the client's frames back and they stay. The player always keeps the real bags (`FR-51`).
- Known shortcut: an interaction opens **our** windows whenever none are open, so `/bos hide`
  immediately before a vendor ends with ours open. Upgrade it when the open/close pair is symmetric.

## Stacking

`frames/window.lua` sets a base level of `CONTENT_BASE = 300`: above every bar and Blizzard's bag
buttons, below the chrome the portrait template carries (400 / 500 / 510). There is no strata trick
available — everything on `UIParent` shares one MEDIUM band and none of it is fixed
(`ui-templates.md` §frame levels). Where our windows overlap Blizzard's own bag window **Blizzard draws
on top**, and that is accepted: the client's bags stay reachable (`FR-51`).

## Chrome and the height floor

`constants.WINDOW_CHROME_HEIGHT = 95` is the floor `layout/flow.lua` measures a window's height against —
it is the bag chrome art's own extent, not a chosen number (`ui-templates.md` §bag window chrome art).
The portrait ring and its medallion arm are one texture, so a window shorter than 95 px puts the arm past
its own bottom edge and into the window below: **accepted for now, open for an art edit** (issue #43,
#31). Hiding the corner pieces on a short window is the rejected fix — the medallion is the window's
identity.

## Money bar

One window carries `ContainerMoneyFrameTemplate` (issue #42): `Pipeline.Assign` gives it to the first
backpack window in screen order — the same single-owner rule as the free-slot count — and it travels when
that window is closed. `flow.Layout` reserves `MONEY_BAR_SPACE` only for the window that draws it, so the
others are 17 px shorter. The template keeps itself current; we add no refresh. Currency info
(`GetBackpackCurrencyInfo`) is still open work (`FR-48`).

## Free-slot indicator

Our count covers containers **0..4** — the backpack plus the four bag slots — the same set the client's
own `C_Container.CalculateTotalNumberOfFreeBagSlots()` sums (`containers-and-bags.md`). The reagent pouch
is harvested and drawn, but its free slots are counted apart from that number (issue #36). They reach a
window only through a specialty family the client reports for the pouch itself, in which case they
belong to the section that pairs with it (issue #44 — `/bos test 44` records what this client answers
for index 5). The indicator hides when the bag
set is full, and it never sees the bank: harvest drops the bank containers on `BANKFRAME_CLOSED`.

Our indicator's count button sets `minDisplayCount = 0` so a count of 1 draws; the pool clears it on
release so item buttons keep Blizzard's behaviour (a stack of 1 shows no number).
Our indicator's count button sets `minDisplayCount = 0` so a count of 1 draws; the pool clears it on
release so item buttons keep Blizzard's behaviour (a stack of 1 shows no number).

A **tradeskill section** carries a count of its own (`FR-44` compact, issue #44): the empty slots of
the specialty bag its category pairs with, not the whole bag set. The pairing is data —
`category.bagFamily`, a preset value on the tradeskill categories (Herbs ↔ herb bag 32, Ore ↔ mining
bag 1024, Leather ↔ leatherworking bag 8, Elements ↔ enchanting bag 64, Engineering ↔ engineering
bag 128) — and the bag is whichever container the client reports that family bit for. No bag of that
family equipped, or one with nothing open in it, leaves the section with no count and no cell; a
section with no items is not drawn at all, so it has no cell either.

The cell is one more row at the bottom of that section's block and draws through the same
`PaintEmpty` path as the window-level indicator: the client's own empty slot with the client's own
count text, pointing at a real free slot in that bag, so dropping an item on it puts the item in that
bag. Two numbers on screen at once is intended — the window's is the bag set (0..4, specialty bags
included, the client's own total) and the section's is one bag. `FR-44`'s user-selectable half,
compact count versus individual slots, arrives with the settings pane (docs/05).

## Item state we borrow rather than own

| State | Ours |
|---|---|
| New-item glow | `frames/item.lua` calls the template's `UpdateNewItem` on every paint — item slots and the free-slot cell alike — so the glow is re-derived from `C_NewItems` on each refresh instead of inherited by a pooled button (issue #35). A client-side expiry with no `BAG_UPDATE` leaves it until the next refresh; `BAG_NEW_ITEMS_UPDATED` is the event to key on if that ever matters |
| Empty slot look | the template's own `bags-item-slot64` atlas, reached by `SetItemButtonTexture(button, nil)`; our wrapper answers `IsCombinedBagContainer() == false`, so the combined-bags background template never applies (issue #36) |
| Count text | Blizzard's own `Count` fontstring on the button |
| Money | `ContainerMoneyFrameTemplate` |

## Harvest consequences that show up in the UI

- **Nothing per-bag is keyed on a bag slot index.** The client re-slots equipped bags, and an empty middle
  bag slot is no container rather than a 0-slot one (`containers-and-bags.md`). Per-bag identity is the
  item (`data/harvest.lua`, issues #2, #25, #36).
- **The bank half of the container list exists only while the bank is open.** `harvest.Discover()` on
  `BANKFRAME_OPENED` — opening fires no container event — and `harvest.Invalidate()` on
  `BANKFRAME_CLOSED` (AC-13). A list built at login legitimately holds no bank container.
- **A bank window cannot be labelled after the bag it holds**: `GetBagName` returns `Bank` for the grid and
  for every purchased bag. The bank is one paged view over indices 6..14 (issue #25).
- Refresh keys on `BAG_UPDATE(containerID)`; `ITEM_LOCK_CHANGED` is detail, not the trigger (issue #27).
