# In-game checklist (Forever)

The manual half of the test story: everything here is untestable off the client because it is a
frame, a keybind, a protected action or a live Blizzard API. Run it on Forever, then paste the
results into the milestone entry in `docs/06` with the date and patch (standing discipline #3).

`/script` is gated on Forever: expect the one-time dangerous-scripts popup the first time.

## Setup (once per branch)

1. `ln -sfn /home/josh/Projects/wow/BagsOfSorting-prototype /home/josh/Projects/wow/addons/BagsOfSorting`
2. Delete any existing `WTF/Account/<account>/<realm>/<character>/BagsOfSortingDB.lua`.
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
2. Run `/bos test 2` at the bank and paste the output into **issue #9** — the full bank run sheet is below.
3. Write the numbers you can see next to the paste: base grid rows × columns (measured 2026-10-17: **6 × 8 = 48**) and how many bank bag slots the UI shows (**8**, against `NUM_CHARACTER_BANK_SLOTS = 9`).
4. Update the `unverified` rows in `agents.md` with what the client actually said.

**Expected:** `NUM_BAG_SLOTS=4`, `NUM_REAGENTBAG_SLOTS=1`, `NUM_TOTAL_EQUIPPED_BAG_SLOTS=5`, `KEYRING_CONTAINER=-1` with 32 slots. The `total container slots` line must account for the 48-slot base grid — if it comes up short by 48, the grid is not a container index (see the next test). The `bank bag` lines say whether the client has inventory slots for 8 or 9.

### Manual test: is the bank's base grid a container? (issue #9, FR-14)

**Precondition:** at an open bank. Move your hearthstone (item ID **6948**) into the **base grid** — the 6×8 area, not a bag — where you can see it. Keep the bank open for every step.

1. Run `/bos find 6948`.
2. Move the hearthstone into an equipped backpack bag and run `/bos find 6948` again.
3. Move it back into the base grid and run `/bos test 2`, then compare the index from step 1 with the per-index list.

**Expected:** step 1 prints an index and a slot for the hearthstone while it sits in the grid — **that index is the base grid**, and `data/harvest.lua` can read it like any other bag. Measured 2026-10-17: `[6] slot 19`, and the same item moved into an equipped backpack bag reported `[1] slot 1`. Step 2 must report a backpack index (0..5) instead, which proves the search itself works. If step 1 finds nothing while the item is visibly in the grid, the grid is not a container index and the harvest loop needs a different reader — the most important possible finding, and the one issue #9 exists to settle.

### Manual test: bank container model and refresh events (issue #9)

**Precondition:** at a bank. Bank bags are not required — with none purchased the probes still
answer the grid questions, and "no bank bag owned yet" is itself part of the answer.

**Capture:** every probe writes its output to SavedVariables as well as to chat, so a long run is
never truncated by the chat window. `/reload` or log out, then read
`../account/SavedVariables/BagsOfSorting.lua` → `BagsOfSortingDB.diag.bankOpen`, `.bankClosed`,
`.bankEvents`, `.keybind`. Paste from that file into **issue #9**, one bucket per block.

**Run A — bank open: `/bos test 2`.** What each line decides:

| Line | Question it answers |
|---|---|
| `grid containers N` + the `grid` lines | is the 48-slot base grid **one container** or several? `N = 1` with 48 slots closes it |
| `[6] …` and `[7]`..`[14]` in the index list | names and slot counts. Unpurchased bank bag slots must read 0 or ERR; a real bag name at 7..14 with none purchased means those indices are something else |
| `bank bag 1..9` | which of the nine slots has an inventory slot — the 9-vs-8 question |
| `total container slots` | must equal keyring 32 + backpack + equipped bags + the grid. Short by the grid means the grid is not a container index |
| `tabs max/hasMax/purchased/canPurchase/lockedReason`, `viewable bank types` | whether there is a tab strip to honour at all (issue #10's `depositFlags` depend on this) |
Measured 2026-10-18 (level 1, two bags equipped, no bank bag purchased): `grid containers 1 total slots 48
per page 88 page 1`, `[6] Bank 48`, `[7]..[14] Bank 0`, `bank bag 1..9 → 63..71`, total **116** =
keyring 32 + backpack 20 + 6 + 6 + reagent 4 + grid 48. All four questions that run answers are closed.


**Run B — bank closed: `/bos test 2` again** (`bank window shown false` is what tells the two
pastes apart). Measured 2026-10-18: index 6 reads **0 slots closed, 48 open**, `FetchPurchasedBankTabData`
returns 0 entries closed and 1 open, `CanPurchaseBankTab` flips to false, `FetchViewableBankTypes`
empties, and the total drops 116 → 68. So the bank half of the container list is re-discovered on
`BANKFRAME_OPENED` and dropped on `BANKFRAME_CLOSED` (AC-13), and no `C_Bank` predicate is readable
while the bank is closed.

**Run C — refresh events: `/bos test 3`**, then **one action at a time**, waiting for the print after
each: withdraw one item → deposit one item → move a bank bag between bank bag slots (skip it if none
is owned) → close the bank → open the bank. Run `/bos test 3` again to stop logging. Turn `/bos debug`
off first: our own refresh lines interleave with the event lines.

Measured 2026-10-18, two runs — the second: deposit into grid slot 1, deposit into slot 48, withdraw,
close the bank, re-open.

- `BANKFRAME_OPENED` and `BANKFRAME_CLOSED` fire with **no payload**, and opening fires **no
  `BAG_UPDATE`**. Combined with index 6 reading 0 slots while closed, the bank container can only
  enter the discovered list through an explicit `BANKFRAME_OPENED` handler — waiting for a container
  event never works.
- A deposit or withdraw produces `ITEM_LOCK_CHANGED(containerID, slot)` then `BAG_UPDATE(containerID)`
  on **both** sides: `6 1` + `BAG_UPDATE 6` for the grid, `0 1` + `BAG_UPDATE 0` for the backpack,
  with `BAG_UPDATE -1` alongside. The existing bucketed `BAG_UPDATE` listener covers bank refresh;
  no bank timer.
- `ITEM_LOCK_CHANGED` slots are grid-relative inside container 6 (`6 1`, `6 48`), not a global bank
  slot number.
- **`PLAYERBANKSLOTS_CHANGED` never fired** across either run, through deposits and withdrawals. Bank
  refresh is `BAG_UPDATE(6)` plus `ITEM_LOCK_CHANGED(6, slot)`; the payload question is moot.

**Still to run** — moved to **issue #25** when issue #9 closed:

1. Once a bank bag is affordable, run A again: a purchased bag's slot count, whether 7..14 then
   report real counts, and whether paging grows past one page.
2. `BANK_TABS_CHANGED` and `BANK_BAG_SLOT_FLAGS_UPDATED` are still unobserved — run `/bos test 3`
   across a purchase and see whether either fires.

**Record:** the buckets as a dated comment on the issue, then the verdicts into `agents.md` and
`docs/07` Q10 — done for the 2026-10-18 run.

### Manual test: real inventory, nothing counted twice (AC-14, AC-16, FR-15)

**Precondition:** character has items in the backpack, at least one equipped bag, something in the keyring, one grey-quality item and one item whose tooltip type is Armor.

1. Run `/bos show`.
2. Run `/bos` and read the container lines: `[index] name slots=N filled=M kind=…`.
3. Compare each `filled` against the same container's count in the stock bag window.
4. Check no container index appears twice in the list.
5. Add up the item counts across the window's sections.
6. Scan for any item drawn in two sections.

**Expected:** every container you own appears exactly once; each `filled` matches the stock window; section totals equal the sum of `filled`; no item appears twice; the grey item is in **Junk**, the armour in **Armor**, everything else in **Everything else**.

### Manual test: window sits above the bags bar, not on it (FR-41)

**Precondition:** default config — you have never dragged a window. Bags bar visible bottom-left.

1. Run `/bos show`.
2. Look at the gap between the window's bottom edge and the top edge of the bags bar.
3. Click the backpack button.

**Expected:** the window's bottom edge is above the bags bar's top edge with a visible gap; no bag button and no micro-bar button is covered; the backpack button still opens Blizzard's bags.

### Manual test: the window drags by its body, and the position persists (FR-41, section mouse fix)

**Precondition:** window shown.

1. Drag the window by its title bar, 200 px up and right, release.
2. Drag it by an empty area of the body — between sections, not on an item button.
3. Run `/reload`.

**Expected:** both drags move the whole window (step 2 is the regression: before the fix the body swallowed the press); after reload the window is where you left it; item buttons still respond to clicks.

### Manual test: the X closes a window and it stays closed (FR-41)

**Precondition:** window shown.

1. Click the window's own X.
2. Pick up an item from the ground, or run `/bos refresh`.
3. `/reload`.
4. Log out and log back in.
5. Run `/bos show`.

**Expected:** the window does not come back at steps 2, 3 or 4; step 5 brings it back, with the item you picked up in the correct section.

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

1. Run `/bos test 7`: the client's key, the binding set, `registered index`, and `stored` (our copy).
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

### Manual test: the overlays our paint path omits (FR-45, FR-47, FR-49, FR-65)

**Precondition:** windows open; one item you have not picked up this session (loot a mob), one **quest** item, one **grey** item, and Blizzard's bag window open beside ours showing the same slots.

1. Loot the new item and look at our window before touching it.
2. Run `/bos test 11` **without hovering** — it walks our own named button pool and the client's own bag buttons and prints every child texture that is lit, which is what `/framestack` cannot do once the hover clears the state.
3. Compare the two halves of the output: same item, same texture names, same atlases?
4. Compare the two for the quest item and the grey item too. `docs/reference/new-item-highlight-bright.png` and `-dim.png` are the client's own highlight for reference.
5. Hover our button, then look at Blizzard's window for the same slot.

**Expected:** for the same item, our button and Blizzard's show the same border colour and the same overlays. Any overlay ours lacks is a `shortcut:` in `frames/item.lua` and needs the milestone that owns it. Step 5 is the coexistence half: `ContainerFrameItemButton_OnEnter` → `OnUpdate` → `C_NewItems.RemoveNewItem(bagID, slot)` runs on our buttons, so hovering ours clears the client's new-item state for the real slot — record whether Blizzard's glow disappears at the same time, and file it against issue #7 if it does.

### Manual test: button pool stays flat across open/close cycles (AC-42)

**Precondition:** window shown with a full-ish backpack.

1. Run `/bos perf` and write down the `itemButton: created=N idle=M` numbers.
2. Run `/bos hide` then `/bos show`, ten times.
3. Run `/bos perf` again.

**Expected:** `created` is unchanged from step 1 (no new button per slot, AC-42); `idle` returns to the same number each cycle.

### Manual test: timings recorded, not asserted (AC-100, AC-101)

**Precondition:** a normally full backpack (not a level-1 character), windows open.

1. Run `/bos test 13`. It first measures the clock (1e6 Lua iterations) and then runs the pipeline many times across frames.
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

**Precondition:** a 40-ID manual category written into SavedVariables by hand — there is no category editor until M3. Quit, edit `WTF/…/BagsOfSortingDB.lua`, add `profiles.Default.categories['Test40'] = { priority=5, kind="manual", enabled=true, itemIDs={ [id]=true, … } }` for 40 IDs you own, plus a section bound to `Test40`. Restart.

1. Login 1: run `/bos perf`, note `tier3=` and `item cache=`.
2. `/exit`, log in again.
3. Run `/bos perf`.

**Expected:** login 1 renders the new section's icons; login 2's first refresh shows no `tier3=` and `item cache` at least 40.

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
