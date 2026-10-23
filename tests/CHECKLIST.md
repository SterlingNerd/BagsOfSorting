# In-game checklist (Forever)

The manual half of the test story: everything here is untestable off the client because it is a
frame, a keybind, a protected action or a live Blizzard API.

**Pending tests are not listed here.** `/bos test` lists them — short QA or investigation tasks tied
to an open issue, defined in `core/diag.lua` and deleted once their capture is ingested. `/bos test
<id>` prints one run sheet. The workflow — writing a test, running it, syncing, ingesting the result,
and deleting the entry — is `.pi/skills/bos-test-capture/SKILL.md`.

What stays here is the standing acceptance checklist: milestone acceptance criteria, and what those
runs found. A client fact goes to the `wow-forever-api` reference that owns it; a decision about our own
windows goes to `docs/08-window-behavior.md`; `docs/06` moves only at a milestone boundary (standing
discipline #3). The raw capture goes to the issue as a dated comment. `agents.md` is the index, not the
destination.

`/script` is gated on Forever: expect the one-time dangerous-scripts popup the first time. A test step
reaches the same API from the addon instead, which is why the run sheets here do not hand out
`/script` lines.

## Setup (once per branch)

1. `ln -sfn /home/josh/Projects/wow/BagsOfSorting /home/josh/Projects/wow/addons/BagsOfSorting`
2. With the client **closed**, delete `WTF/Account/<account>/SavedVariables/BagsOfSorting.lua` on the
   game machine. It is account-level and named after the **addon folder**, whatever the TOC declares
   (issue #14) — not `<realm>/<character>/BagsOfSortingDB.lua`. An open client rewrites SavedVariables
   at logout and silently discards the edit.
3. Start Forever, log in, expect the addon to appear in `/addonlist`.

**Coverage note:** a level-1 character with no bags exercises the keyring and the backpack only —
`/bos` then lists `[-1] Keyring` and `[0] Backpack` and nothing else, which is correct, not a bug.
Tests 3, 10 and 17 need at least one equipped bag; tests 2 and 3 need bank access. Re-run those once the
character has a bag and can reach a bank.

---

### Manual test: loads clean (AC-1)

**Precondition:** Setup done, fresh character with no SavedVariables file.

1. Log in and watch for the red Lua error frame.
2. Run `/bos`.
3. `/reload`, twice more (three total).

**Expected:** no Lua error frame and no "Action blocked" at any step — Forever has no `/events`, so
open `/console` if an error appeared and read the script errors there; `/bos` prints
`project=18 camelot=true build=<build>` followed by the capability table.

### Manual test: capability dump fills the client-fact cache (M0 exit criterion)

**Precondition:** standing at an open bank. Bank bags help but are not required — if you cannot afford one yet, say so in the paste, because "eight slots visible, none filled" is itself an answer.

1. Run `/bos` and copy the whole output into **issue #2**.
2. Run `/bos test dump` at the bank and compare it against the storage-shape table in the
   `wow-forever-api` skill's `references/containers-and-bags.md`.
3. Write the numbers you can see next to the paste: base grid rows × columns (measured 2026-10-17: **6 × 8 = 48**) and how many bank bag slots the UI shows (**8**, against `NUM_CHARACTER_BANK_SLOTS = 9`).
4. Update the `unverified` rows in that reference with what the client actually said.

**Expected:** `NUM_BAG_SLOTS=4`, `NUM_REAGENTBAG_SLOTS=1`, `NUM_TOTAL_EQUIPPED_BAG_SLOTS=5`, `KEYRING_CONTAINER=-1` with 32 slots. The `total container slots` line must account for the 48-slot base grid — if it comes up short by 48, the grid is not a container index. The `bank bag` lines say whether the client has inventory slots for 8 or 9.

### Manual test: real inventory, nothing counted twice (AC-14, AC-16, FR-15)

**Precondition:** character has items in the backpack, at least one equipped bag, something in the keyring, one grey-quality item and one item whose tooltip type is Armor.

1. Run `/bos show`.
2. Run `/bos` and read the container lines: `[index] name slots=N filled=M kind=…`.
3. Compare each `filled` against the same container's count in the stock bag window.
4. Check no container index appears twice in the list.
5. Add up the item counts across every window's sections.
6. Scan for any item drawn in two sections **or two windows**.

**Expected:** every container you own appears exactly once; each `filled` matches the stock window; section totals equal the sum of `filled`; no item appears twice; the grey item is in **Junk**, the armour in **Armor**, everything else in **Everything else**. Measured 2026-10-19: containers once each, no duplicates, grey items in Junk, armour in Armor, the rest in Everything else.

### Manual test: the priority ladder (issue #26, across windows per issue #28)

**Precondition:** fresh SavedVariables (Setup step 2). The mining pick (2901) and, above all, **5411 Winterhoof Cleansing Totem** in a bag — it is `type = Armor` *and* a quest item, so two categories claim it.

1. Run `/bos show`.
2. Find 5411.
3. Find the mining pick.
4. Run `/bos find 5411` and `/bos find 2901` to confirm they are where the window says they are.

**Expected:** five windows — **Backpack** (Junk, Armor, Everything else), **Quests** (Quest Items), **Consumables** (Consumables), **Tradeskills** (one section per material type), **Tools** (Tools). 5411 sits in the **Quests** window, not in Backpack's Armor section (priority 5 beats 20). The mining pick sits in the **Tools** window, not Everything else, even though it is a Weapon — a curated list beats a type rule (8 beats 20). A grey item still lands in **Junk** (10 beats 20). A window adds nothing to the ladder: precedence is `category.priority` alone, and a category lands in the one window that binds it.

### Manual test: materials and consumables sort by what they are (issue #41)

**Precondition:** fresh SavedVariables (Setup step 2), our windows open (`/bos show`), and a bag holding at least one herb, one ore, a cooking ingredient, a potion, food and a bandage. Put one of them in the **reagent pouch** (container index 5) on purpose — where an item sits is the thing this test rules out.

1. Look at the stack bottom-up: **Consumables** and **Tradeskills** sit between **Quests** and **Tools**.
2. Find the herb (Silverleaf 765 is the one this account carries). It is in the Tradeskills window's **Herbs** section even if it was in the reagent pouch.
3. Find the potion (118), the water (159) and the bandage (1251): all three in **Consumables**, none in a tradeskill section.
4. Find a cloth or leather **armour**: it stays in Backpack's Armor section, not in the Cloth or Leather section.
5. Run `/bos find 765` and `/bos find 118` and confirm the window agrees with the container.
6. Optional, for the raw data behind it: `/bos test subclasses` prints the client's own class and subclass vocabulary; `/bos test owners` prints every placement with the `type / subtype` pair that decided it.

**Expected:** a tradeskill section is drawn only when it holds something, so the Tradeskills window shows headers for what you actually carry and nothing else. Consumables (priority 12) outranks every tradeskill category (15), so nothing consumable reaches a materials section. The tradeskill rules match `type = "Trade Goods"` **and** a subtype, so a subtype armour shares (`Cloth`, `Leather`) does not pull gear into the materials window. Sorting never consults the container: the reagent pouch, an equipped bag and the backpack all feed the same section.

**Measured 2026-10-20 (build 1.60.1 70450):** every shipped subtype name is one this client uses. Its Trade Goods subclasses are Parts, Cloth, Leather, Metal & Stone, Cooking, Herb, Elemental, Other and Enchanting — **no Jewelcrafting**, which is why there is no Gems section; and its Consumable class covers Potions, Elixirs, Flasks, Draughts, Scrolls, Food & Drink and Bandages in one rule. A gem in a bag plus `/bos test owners` is what would settle where gems live.

### Manual test: the stack starts at the client's bag window (FR-41, issue #28)

**Precondition:** Blizzard's bag window open. Run `/bos unplace` first if you have ever dragged a window — a saved point overrides the layout rule, and this test is about the layout rule.

1. Run `/bos show`.
2. Compare the **Backpack** window's bottom-right corner with the client backpack window's bottom-right corner.
3. Look at the gap between each pair of stacked windows.
4. Click the backpack button.

**Expected:** our windows' right edge sits just left of the client backpack window's right edge, with a visible gap between our windows and the screen edge; Quests, Consumables, Tradeskills and Tools stack above it with the same gap between each pair and no window overlapping another; no bag button and no micro-bar button is covered; the backpack button still opens Blizzard's bags. `/bos test windows` prints the anchor frame, its bottom and right, the screen size, and each frame's own right edge — the margin as a number rather than an impression. Measured 2026-10-20 against the **bag bar**: the stack started 317 px up the screen with no margin on a vertical bar — that anchor was issue **#30**, resolved.

### Manual test: a window with nothing in it draws no body (issue #28 decision 2, #43)

**Precondition:** five windows shown; Mining Pick (2901) and Hearthstone (6948) are the only items the Tools category matches, and the bank is reachable.

1. Run `/bos show`.
2. Deposit 2901 in the bank.
3. Deposit 6948 in the bank.
4. Look at the Tools window and the window directly below it: the collapsed window's title band, its medallion and arm, its corners, its top and bottom edges.
5. Withdraw 2901 back into a bag.

**Expected:** the Tools window is still on screen, still 206 wide, and **95 px tall** — `constants.WINDOW_CHROME_HEIGHT`, the height the client's own bag chrome measures end to end. No blank slot cell, no grid, no body. Its medallion, its arm and all four corners are drawn: the capture prints `ring … shown true` and `bottom corner 95x24 … shown true` for it, against 32 px of corner on the 103-tall Backpack and 100 px on the 171-tall Tradeskills. **Its arm does reach past its own bottom edge into the window below** — 79 px of arm on a 95 px window, 16 px of the next window's arm above its own top edge, 8 px of gap — and that overlap is accepted until the art itself is edited. Step 5 puts the grid back at the same width. The height and the no-body rule are asserted off-client in `tests/run.lua` and `tests/selftest.lua`; the chrome geometry behind them was captured on the live client on 2026-10-20 and 2026-10-21 (`/bos test 43`, pasted on **issue #43**, and the `portrait` helper still prints it on any later run).

### Manual test: the window drags by its body, and the position persists (FR-41, section mouse fix)

**Precondition:** window shown.

1. Drag the window by its title bar, 200 px up and right, release.
2. Drag it by an empty area of the body — between sections, not on an item button.
3. Run `/reload`.
4. Run `/bos unplace`.

**Expected:** both drags move the whole window (step 2 is the regression: before the fix the body swallowed the press); after reload the window is where you left it; item buttons still respond to clicks; step 4 drops it back into the stack with the other windows.

### Manual test: the X closes a window and it stays closed (FR-41)

**Precondition:** all five windows shown, nothing dragged.

1. Click the **Tools** window's own X — it is the topmost one.
2. Pick up an item from the ground, or run `/bos refresh`.
3. `/reload`.
4. Log out and log back in.
5. Run `/bos show`.
6. Close the **Quests** window instead and look at where Tools lands.

**Expected:** Tools does not come back at steps 2, 3 or 4; step 5 brings it back, with the item you picked up in the correct section of the correct window; closing the topmost window leaves Backpack and Quests exactly where they were. Step 6 is the placement rule and not a bug: a window that leaves the model gives up its slot in the column, so Tools drops into it (issue #28 decision 2).

### Manual test: the free-slot indicator (FR-44 compact, issue #36)

**Precondition:** our windows open (`/bos show`) and the bags have free space. Filling the backpack and the four bag slots needs a lot of items — vendor stacks of 20 are the fastest way, and a second character to hold them helps. The reagent pouch may stay open: it is not part of this number.

1. Run `/bos test freeslots`.
2. Look at the end of the **Backpack** window's last row: one slot with a number in it.
3. Add the `free=` column it printed for indices 0..4 and compare it with that number; the reagent pouch `[5]` prints apart and is not in it.
4. Buy stacks until every backpack and bag slot is filled.
5. Run `/bos test freeslots` again.
6. Look at the same spot in the window.
7. Sell one item.

**Expected:** step 3 matches exactly — the number is the `free=` sum of indices 0..4 (issue #36 measured 22 = 5+6+5+6 on 2026-10-20, with the pouch's 3 printed apart and excluded). At step 6 the slot is **gone** and the window is one cell shorter: `emptySlots=nil`, `cell=nil`, `indicator: none drawn`, even while the pouch still has free slots — **measured on the client 2026-10-20**. Step 7 brings it back reading 1 — Blizzard's own count setter hides a count of 1 unless the button lowers `minDisplayCount`, so a bare `1` is the thing to look for. The slot must read as the game's own empty bag slot: same background, same number style as a stack count — the half of this story a capture cannot record.

### Manual test: a tradeskill section counts its own bag (FR-44 compact, issue #44)

**Precondition:** our windows open (`/bos show`), one tradeskill bag equipped in a bag slot (herb bag,
mining bag, leatherworking bag…) with at least one matching item in it and at least one slot free.

1. Run `/bos test freeslots`.
2. Read the `family=` value on each container line and the `family N free=…` lines under them.
3. Look at the row below the last item in the matching **Tradeskills** section: one empty slot with a number in it.
4. Put one matching item into that bag.
5. Run `/bos test freeslots` again.
6. Take that item back out.
7. Fill every slot of that bag.
8. Run `/bos test freeslots` again.
9. Unequip the tradeskill bag.
10. Run `/bos test freeslots` once more.

**Expected:** step 3's number equals that bag's `free=` at step 2, and the section is one cell taller
than the sections either side of it. Step 5 lowers it by one. Step 8 leaves `emptySlots=nil`,
`cell=nil` and no slot drawn while the section keeps its items and its height drops back. Step 10
leaves no section with a count at all. The **Backpack** window's own number still covers the whole
bag set, this bag included — the two numbers are different questions, not a disagreement.
 Step 6 is the empty-category half: with the last item of that trade out of the bag, the section header
and its cell stay on screen — the bag's free slots are what keep the section drawn, and the cell is
where the next one goes. A category with no items *and* no bag of its own stays hidden.

### Manual test: the money bar is on the default backpack window only (FR-48, issue #42)

**Precondition:** a fresh login with the default profile and money in the purse, our windows open (`/bos show`), Blizzard's bag window closed.

1. Run `/bos test windows`.
2. Read the `money:` line under each window in the capture.
3. Look at the bottom edge of every open window.
4. Sell one stack at a vendor.
5. Close the **Backpack** window with its X, then run `/bos test windows` again.
6. Reopen everything with `/bos show`.
7. Open the bank.

**Expected:** exactly one window carries the bar. At step 2 it is **Backpack** — `money: shown true`, `h 13`, coins matching `GetMoney()` — and Quests, Consumables, Tradeskills and Tools each print `money: none`. At step 3 the coin row is visible on Backpack's bottom edge and on no other window, and those windows are 17 px shorter than they were before issue #42 (`constants.MONEY_BAR_SPACE` is reserved only by the window that draws the bar). At step 4 the coins on that one bar update with no refresh from us. At step 5 the bar has **travelled**: Quests is the only window that prints `money: shown true` (a closed window is out of the model, so it prints nothing at all) and Backpack's own frame is hidden with its bar hidden inside it. One carrier, never two. At step 6 it is back on Backpack. At step 7 the five bank windows appear and every one of them prints `money: none` — the bar is a purse, and a bank window is not one (issue #47) — while Backpack keeps the only `money: shown true`. No `Action blocked` and no taint anywhere — the bar is `ContainerMoneyFrameTemplate`, Blizzard's own.

### Manual test: keybind appears in the client's own panel (FR-64)

**Precondition:** Setup done. No default key is bound on purpose — `B` stays Blizzard's.

1. Esc → Options → Key Bindings, search `Bags of Sorting`.
2. Bind **Toggle sorting bags** to `F7`.
3. Press `F7`.
4. Press `F7` again.
5. `/reload` and press `F7`.

**Expected:** a **Bags of Sorting** category exists in the panel with one entry, currently unbound; `F7` shows the windows, `F7` again hides them.

### Manual test: the keybind survives a reload and a logout (FR-64, issue #13)

**Precondition:** a key bound to *Toggle sorting bags* in Options → Key Bindings. Measured 2026-10-19 with `CTRL-B`: the client writes it (`bind CTRL-B BAGSOF_SORTING_TOGGLE` in `bindings-cache.wtf`), holds it in its own binding table, and it survives `/reload` twice and a game restart. The 2026-10-17 failure with `F7` does not reproduce — in that session the line never reached the bindings file, so the panel edit was never committed.

1. Run `/bos test keybind`: the client's key, the binding set, `registered index`, and `stored` (our copy).
2. `/reload`, then run it again.
3. Log out, log back in, run it again.
4. `grep BAGSOF_SORTING ../account/bindings-cache.wtf`.

**Expected:** the key present at every step, `registered index` non-nil, and `stored` matching the client. Measured 2026-10-19: `BAGSOF_SORTING_TOGGLE = CTRL-B`, `registered index 287`, `stored CTRL-B`, `binding set 1` = `Enum.BindingSet.Account`, so the key is account-wide rather than per character. Step 4 finds the line; a missing line means the panel never committed the edit.

Probe 7 died after its first line until 2026-10-19 because it called `GetBinding('BAGSOF_SORTING_TOGGLE')`, and `GetBinding` takes a binding index on this client. It calls `GetBindingKey` now.

### Manual test: bags are reachable in combat, contents may lag (Q23)

**Precondition:** `F7` bound, windows open, out of combat, a trainable target, and something to loot once you are in combat.

1. Enter combat.
2. Press `F7` (close).
3. Press `F7` (open).
4. Loot an item while still in combat.
5. Open `/console` and look for "Action blocked".
6. Leave combat and wait a second.

**Expected:** steps 2 and 3 both work with no error; the reopened window shows the contents as they were before combat; step 4 adds nothing to the window until step 6, when it re-renders and the looted item appears in the correct section; no "Action blocked" anywhere. An empty window at step 3 means nothing was painted before combat — the known limit of Q23 option A, record it rather than treating it as a crash.

### Manual test: Options → AddOns entry (FR-88)

**Precondition:** addon loaded.

1. Esc → Options → AddOns → **Bags of Sorting**.
2. Tick *Debug logging*, run `/bos refresh`.
3. Untick it, run `/bos refresh`.
4. Tick it again, `/reload`, reopen the panel.
5. Run `/bos debug`.

**Expected:** the category exists under AddOns (no AceConfig window, no minimap icon); step 2 prints debug lines (`closed window …`, `refresh(…)`), step 3 stops them; the checkbox is still ticked after reload because it writes `settings.debug`; step 5 flips the same value, so the panel and the slash command agree.

### Manual test: Blizzard's own item interactions are unchanged (AC-60, FR-60)

**Precondition:** window shown, an item you can move, a vendor within reach, one stack of 5+.

1. Left-click an item, move it to another bag slot, left-click again to drop it back.
2. Right-click an item.
3. Shift-click an item.
4. Alt-click an item.
5. Drag an item from a section onto the vendor's sell area.
6. Split a stack of 5+ in half.
7. Hover an item.

**Expected:** every step behaves exactly as it does in Blizzard's own bag window: the stock item menu opens on right-click (not blocked, not empty), shift-click links the item in chat, alt-click does the client's modified-click action, the sale completes and money updates, Blizzard's own `StackSplitFrame` appears, and the tooltip is Blizzard's. No "Action blocked" anywhere.

### Manual test: the new-item highlight (FR-47, issue #35)

**Precondition:** our windows open with Blizzard's bag window open beside them showing the same slots; nothing looted or bought since the last `/reload`.

1. `/reload`, and look at our window before touching anything.
2. Loot or buy one new item, and look at our window before hovering it.
3. Compare that slot with the same slot in Blizzard's window.
4. Hover our button, move the mouse away, and look again two seconds later.
5. Move the item to another slot, and look at the slot it left and the slot it entered.
6. Run `/bos test 35` for the numbers behind steps 1-4.

**Expected:** step 1 — no slot in our window glows. Step 2 — the new slot carries a glow that cycles bright → dim, about one cycle a second, in the same atlas and colour Blizzard shows for that item's quality (`docs/reference/new-item-highlight-bright.png`, `-dim.png`), and no other slot glows. Step 4 — the glow is gone and stays gone. Step 5 — neither slot glows.

Measured 2026-10-20 (`/bos test 35`, build 70450): steps 1, 2 and 4 — 24 slots at login read 0 flagged new, acquiring one item flags one slot and our button draws `NewItemTexture bags-glow-white` at `alpha=0.46` mid-pulse, and after the hover nothing is flagged and the texture is gone. Steps 3 and 5 need Blizzard's bag window open; `/bos test newitem` reads its buttons through `ContainerFrameCombinedBags.Items`.

### Manual test: the overlays our paint path omits (FR-45, FR-49, FR-65)

**Precondition:** windows open; one item you have not picked up this session (loot a mob), one **quest** item, one **grey** item, and Blizzard's bag window open beside ours showing the same slots.

1. Loot the new item and look at our window before touching it.
2. Run `/bos test newitem` **without hovering** — it walks our own named button pool and the client's own bag buttons and prints every child texture that is lit, which is what `/framestack` cannot do once the hover clears the state.
3. Compare the two halves of the output: same item, same texture names, same atlases?
4. Compare the two for the quest item and the grey item too. `docs/reference/new-item-highlight-bright.png` and `-dim.png` are the client's own highlight for reference.
5. Hover our button, then look at Blizzard's window for the same slot.

**Expected:** for the same item, our button and Blizzard's show the same border colour and the same overlays. Any overlay ours lacks is a `shortcut:` in `frames/item.lua` and needs the milestone that owns it. Step 5 is the coexistence half: `ContainerFrameItemButton_OnEnter` → `OnUpdate` → `C_NewItems.RemoveNewItem(bagID, slot)` runs on our buttons, so hovering ours clears the client's new-item state for the real slot — record whether Blizzard's glow disappears at the same time, and file it against issue #7 if it does.

### Manual test: button pool stays flat across open/close cycles (AC-42)

**Precondition:** window shown with a full-ish backpack.

1. Run `/bos perf` — **not `/bos debug`**, which only toggles logging — and write down the line that reads `itemButton: created=N idle=M`.
2. Run `/bos hide` then `/bos show`, ten times.
3. Run `/bos perf` again.

**Expected:** `created` is unchanged from step 1 (no new button per slot, AC-42); `idle` returns to the same number each cycle. Measured 2026-10-19: `itemButton: created=25` on both readings with several hotkey show/hide cycles between them, `idle` 7 with the window open and 25 with it closed — every button released, none created per cycle.

Note when reading the output: **a hide runs no refresh** (`windows.HideAll()` releases the pool; only show and the pipeline refresh). So the `refresh(<reason>)` line is the *last refresh*, while the `created=`/`idle=` line is live. Read the pool line for AC-42.

### Manual test: timings recorded, not asserted (AC-100, AC-101)

**Precondition:** a normally full backpack (not a level-1 character), windows open.

1. Run `/bos test clock`. It first measures the clock (1e6 Lua iterations) and then runs the pipeline many times across frames.
   If the clock line reports `0`, `GetTime` is frame-quantized on this client — measured 2026-10-17 — which is why `/bos perf` prints `timings: unmeasurable in one frame` instead of per-phase numbers (issue #20). The `bench:` line is the timing that gets recorded.
2. Run `/bos perf` five times for the pool and cache numbers.
3. Paste the clock line, the `bench:` line and the five `/bos perf` lines into the M1 entry in `docs/06` with the date and patch.

**Expected:** five recorded lines in `docs/06`. No pass/fail — if any phase is over the `FR-100` budget by more than 3×, that triggers the re-plan in `docs/06` §What would make us stop.

### Manual test: an item the client has never seen (AC-103, FR-103)

**Precondition:** a mob that drops something this client session has never seen (or a vendor you have never opened).

1. Loot it.
2. Look at the window immediately.
3. Wait two seconds, look again.
4. Run `/bos perf`.

**Expected:** it appears in **Everything else** immediately, then moves to the correct section (Junk or Armor) within a couple of seconds with no `/reload`; `/bos perf` shows `tier3=1` for that refresh.

### Manual test: second login issues zero tier-3 requests (AC-97)

**Precondition:** the shipped **Tools** category (Mining Pick 2901, Hearthstone 6948). It is in `DEFAULT_PROFILE` (`core/db.lua`), so a fresh SavedVariables file carries it — no hand editing, no migration. Carry both items in a bag so the section has something to match. Two IDs are enough: the criterion is that **cached** IDs cost zero requests, not that volume works. After a SavedVariables wipe (Setup step 2) re-run this from the wipe: expect tier-3 requests on the first login and zero on the second.

1. Login 1: run `/bos perf`, note `tier3=` and `item cache=`.
2. `/exit`, log in again.
3. Run `/bos perf`.

**Expected:** login 1 shows a Tools section holding those items with icons; login 2's first refresh shows no `tier3=` and `item cache` at least 2. Measured 2026-10-19: after `/exit` and a fresh login, `item cache=113, tier3 requested=0 resolved=0 pending=0`, and Tools, Quest Items and Junk all classify correctly.

### Manual test: no test code loads in-game (FR-106)

**Precondition:** addon loaded from this branch.

1. Run `/bos help`.
2. Run `/bos selftest`.
3. Check `/addonlist` and the login error frame.

**Expected:** help lists `perf`, `refresh`, `show|hide`, `debug`, `help` and no `selftest` line; `/bos selftest` falls through to the capability dump rather than running assertions; no `SelfTest` error on login.

### Manual test: hostile pass (docs/06 standing discipline #5)

**Precondition:** full inventory, windows open.

1. `/reload` mid-combat.
2. Loot while still in combat.
3. Die, release, then open the windows.
4. `/bos refresh` after each.

**Expected:** no errors and no missing buttons at any step; the windows re-render after death; looted items land in the correct section.

### Manual test: coexistence (FR-124, issue #7)

**Precondition:** the addons actually installed on this account — BetterBags, BetterForeverChat, ErrorCrate, ForeverMouseTooltip, ForeverPlus, ForeverQuestTint, GatherMate2, GearQuestForever, Leatrix_Maps, Leatrix_Plus, Leatrix_Sounds, LoreForever, MapUtils, PlayerFrameHider, TalentsForeverBook, ThreatMeter, TidyPlates_ThreatPlates, TrackingSwitch_X, WhatsTraining, WhisperMessenger, sct. **BetterBags is the important one**: two bag addons on the same character.

1. Log in and run `/bos show`.
2. Open Blizzard's bags and ours at the same time and check no container appears twice.
3. Loot something with BetterBags loaded and check which addon's windows show it.
4. Run `/bos` and read the container lines against ForeverPlus's bag window.
5. Paste the results into **issue #7**.

**Expected:** no errors, no duplicate container entries, no addon stealing another's window. Masque and Pawn are **not installed** on this account, so the `FR-49` skinning question (does a skinning addon reach our buttons?) stays open — record it as untested rather than passed.
