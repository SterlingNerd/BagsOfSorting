# 06 — Milestones & Plan

Ordering rule: **thin end-to-end slices first.** M1 must show real items in a real window on the
real client before any config UI exists, because the pipeline is where the Forever API risk lives.
Config UI (M3/M4) is the product's reason to exist, but it is built on a pipeline we have already
proven in-game.

Estimates are solo-dev calendar weeks for a part-time hobby project, not commitments.

```
M0 → M1 → M2 ─┬→ M3 → M4 ─┬→ M5 → M6 → M7
              └───────────┘
M3 can start once M2's layout model is stable; M4 needs M3's command layer.
```

---

## M0 — Skeleton that loads on Forever (0.5–1 wk)

**Goal:** an addon folder that loads clean on the Forever client, so every later milestone has a
place to be tested.

**Status: done 2026-10-19.** Every deliverable exists, CI runs `luacheck` and the off-client suite
green on each push, and `/bos` has printed the capability table on the live client with the answers
written into `agents.md` — which is what turns that file's unverified column into facts.


Deliverables
- `BagsOfSorting.toc`, `.pkgmeta`, `.luacheckrc` (WoW globals declared), `LICENSE` (WTFPL),
  `Media/Icon.png` (256×256, wired to `## IconTexture`)
- **no `libs/` directory** — zero vendored libraries (`docs/07` Q2 resolved)
- `core/boot.lua`, `core/client.lua` (capability flags), `core/constants.lua`, `core/log.lua`,
  `core/events.lua` (own frame + dispatch table), `core/locale.lua`
- `integrations/compartment.lua` — `AddonCompartmentFunc` entry, our icon, opens configure mode
- `/bos` slash command printing the resolved capability table — this doubles as the Forever fact
  verification tool required by `agents.md`. It must also answer: is `C_Item.RequestLoadItemDataByID`
  present, does `ITEM_DATA_LOAD_RESULT` arrive, is `IconDataProviderMixin` present, is
  `EditModeManagerFrame` present, what is `IsUsingCombinedBags`, what is
  `C_Bank.FetchNumPurchasedBankTabs(Enum.BankType.Character)`
- `tests/fixtures.lua` + the headless harness `tests/run.lua` (asserts nothing yet, but the harness works)
- CI: GitHub Actions running `luacheck` on push (copy the shape of `../addons/Baggins/.github/workflows/check.yml`)
- per-directory `README.md` stubs (`NFR-3`)

Exit criteria
- **AC-1** loads with zero errors on login and 3× `/reload`; `/events` clean. **Met**, measured across
  every `/bos` and `/bos test` run since 2026-10-17 (Forever has no `/events`, so errors surface in
  `/console`). Lua errors found later are chased as they surface rather than treated as a gate on this
  milestone — the one error seen on 2026-10-19 came from a probe's wrong API call, not from loading.
- `/bos` prints `isForever=true`, `hasWarbank=false`, `itemButtonType=ItemButton`, and **fills in the
  unverified `agents.md` facts** (keyring presence — expect yes, since
  `Blizzard_MainMenuBarBagButtons/Camelot/MainMenuBarBagButtons.lua` uses `KEYRING_CONTAINER` and
  `GetKeyRingSize`; reagent bag slot; `NUM_TOTAL_EQUIPPED_BAG_SLOTS`; container index ranges).
  Update `agents.md` with the answers — this milestone is what turns the "unverified" column into
  facts.
- The four item-data questions in **issue #1** are **deferred 2026-10-19**: cold-cache behaviour is
  measured with the onboarding work later in the plan, where a fresh character and a cold SavedVariables
  file exist anyway. Issue #1 stays open and is assigned to that milestone. What M0 needed from it —
  `C_Item.RequestLoadItemDataByID`, `ITEM_DATA_LOAD_RESULT`, `IconDataProviderMixin` and
  `EditModeManagerFrame` being present — is measured and recorded.
- `luacheck` clean in CI.

Risks: none material. If `/bos` cannot print the capability table, the client detection assumption
is wrong and everything downstream is re-planned here, cheaply.

---

## M1 — Pipeline: real items, one window (1.5–2.5 wk)

**Goal:** prove harvest → enrich → classify → sort → render on Forever with real inventory.

**Status: done 2026-10-19.** Code complete, and the off-client suite (83 checks, run in CI) covers
rules, the priority ladder, sort modes and flow boundaries. Every exit criterion is measured on the live
client:

- **AC-14/16** — real inventory, nothing counted twice, grey items in Junk, armour in Armor, the rest in
  the catch-all.
- **AC-42** — `itemButton: created=25` before and after several hotkey show/hide cycles, `idle` returning
  to 25 with the window closed: no button created per cycle. The capture does not count the cycles, so
  the number is "several", not a counted ten.
- **AC-100/101** — 2.20 ms per refresh (1000 refreshes over 10 frames, 2204 ms) on `_classic_beta_`
  1.60.1 build 70450.
- **AC-103** — a looted item the client had never seen lands in the catch-all and classifies correctly
  once its data arrives.
- **AC-97** — `/exit` then a fresh login: `item cache=113, tier3 requested=0 resolved=0 pending=0`.
- **Priority ladder** — Tools, Quest Items and Junk all classify as designed once schema version 2 ran,
  which puts 5411 Winterhoof Cleansing Totem (Armor *and* a quest item) in Quest Items, not Armor.

`expansion` is measured out of the v1 field set. Cold-cache item data (issue #1) is deferred to the
onboarding work later in the plan, and the bank-tab `ItemLocation` check moved to M5.


Deliverables
- `data/harvest.lua`, `data/enrich.lua`, `data/itemcache.lua`, `data/classify.lua`, `data/rules.lua`,
  `data/sort.lua`
- the three-tier item lookup from `docs/03` §Item data is not always there: tier-1
  `GetItemInfoInstant`, tier-2 persisted cache, tier-3 `RequestLoadItemDataByID` +
  `ITEM_DATA_LOAD_RESULT`, batched and cancellable (`AsyncCallbackSystemMixin` as the reference)
- `filters/registry.lua` + 7 fields: `type`, `subtype`, `quality`, `ilvl`, `name`, `equipSlot`,
  `isQuestItem` (`expansion` measured out of the v1 set — see Risks below)
- `frames/window.lua`, `frames/item.lua` (pooled, `ItemButton` type), `frames/section.lua`
- one hardcoded window ("Backpack") with 5 hardcoded categories — Quest Items, Tools (manual:
  Mining Pick, Hearthstone), Junk, Armor, Everything-else — written **in the data model**, not in
  code, so the schema is exercised from day one, plus a schema version 2 migration that adds them to a
  SavedVariables file already in the wild (**issue #26**)
- `core/async.lua` chunking + `core/events.lua` bucketing
- `/bos perf` reporting what a refresh did (item-data requests issued, pool stats) and `/bos test clock` for
  ms per refresh (**issue #20** closed: `GetTime` is frame-quantized, so `/bos perf` says it cannot time a
  single-frame refresh instead of printing `0.00` per phase)
- `Bindings.xml` + `config/keybinds.lua` and the Options → AddOns category from `config/settingspanel.lua`
  (`FR-64`, `FR-88`, pulled forward from M6: a prototype with no keybind entry and no options entry
  is one the player cannot find or configure). **Issue #13** closed: the binding does persist —
  `bind CTRL-B BAGSOF_SORTING_TOGGLE` in the account's `bindings-cache.wtf`, surviving `/reload` twice
  and a game restart, in `Enum.BindingSet.Account`. The 2026-10-17 report does not reproduce: in that
  session the edit never reached the file. `config/keybinds.lua` stays as insurance

Exit criteria
- **AC-14, AC-16** real inventory appears, nothing duplicated, unmatched items in the catch-all.
- **AC-42** button pool stays flat across 10 open/close cycles (`/bos perf` reports pool stats).
- **AC-100/101** timings recorded in `docs/06` as actual numbers, not targets. **Met 2026-10-19**, on
  `_classic_beta_` 1.60.1 build **70450** (`.build.info`), level-1 character, 14 harvested items, 113
  cached: `/bos test clock` → `bench: 1000 refreshes over 10 frames, 2204ms total, 2.20ms per refresh`,
  of which at least 160ms is frame time, not pipeline. `/bos perf` alongside it:
  `itemButton: created=34 idle=20`, `section: created=2 idle=0`, `item cache=113, tier3 requested=0`.
- **AC-103** loot an item never seen by the client; it lands in catch-all, then re-sorts when info
  arrives. Then `C_Item.RequestLoadItemDataByID` on a cold ID and confirm it resolves without a
  reload (issue #1).
- **AC-97** a hand-written manual category (Tools: Mining Pick 2901, Hearthstone 6948) renders icons
  on first login and issues zero tier-3 requests on the second.
- `lua5.1 tests/run.lua` green: fixture items × rule trees → expected category, including
  `any/all/none` nesting, the precedence tie-breaks from `docs/04`, every sort mode and the flow
  boundaries.

Risks
- Tooltip-based and expansion-based fields may need data we cannot read cheaply on Forever.
  **Resolved 2026-10-19** by `/bos test expansion`: `expansion` is readable, and position 15 of
  `C_Item.GetItemInfo` is confirmed as `expansionID` against `ItemDocumentation.lua` — but all 14 items
  in the real inventory report `0` (Classic), so the field cannot discriminate on a Vanilla-ruleset
  client. Removed from the v1 field set (`docs/02` FR-21) as a recorded removal, not a silent gap.
- Secret-value handling for `C_Item` on Forever: verify `ItemLocation:CreateFromBagAndSlot` paths work
  for bank tabs. **Moves to M5** (2026-10-19): nothing harvests a bank container until the bank wiring
  lands there, so there is nothing to verify at M1.

---

## M2 — Windows, sections, flow layout (1.5–2 wk)

**Status: in progress (2026-10-20).** Opened by **issue #28**: `layout/anchors.lua` delivered — the
`FR-41` placement rule, ported from Blizzard's own bag layout — and three hard-coded backpack windows
(`Backpack`, `Quests`, `Tools`) delivered as profile data, with no configuration UI. The schema goes
back to `version = 1` and the migration that carried Quest Items and Tools is removed: while one user
owns every deployed file the schema changes breakingly (`docs/04` §Migration). The rest of M2 is not
started.

Measured in-game 2026-10-20 (build 1.60.1 build 70450, `/bos test 28`, capture on the issue): a fresh
SavedVariables file writes the three windows; the column math holds exactly — `y` 0 / 204 / 346 against
heights 196 / 134 / 96, gaps of 8, one column, no overlap; 5411 lands in Quests and 2901 + 6948 in
Tools; a dragged window survives `/reload` while the other two keep their slots. Two defects came out
of the same run: the bag-bar anchor is wrong on a bar the player has rotated (**#30**, fixed on this
branch — the anchor is the client's bag window), and a window with no sections renders at a height its
chrome cannot draw (**#31**).

**Goal:** the Baggins shape. Multiple user-visible windows, sections packed inside them.

Deliverables
- `data/windows.lua`, `data/sections.lua`, `layout/flow.lua`, `layout/sizing.lua`, `layout/anchors.lua`
- per-window `columns`, scale, `compact` windows, collapsed/hidden sections
- `layout/anchors.lua` implements the `FR-41` placement rule (`docs/07` Q24, **issue #18**): the first window where
  the client's backpack window opens, further windows stacked above it to a maximum height, then
  wrapping left. Windows are **not draggable** in v1; EditMode (Q13, `AC-54`) is the override
- **new-item highlight** (`FR-47`): our own policy, drawn the way the client draws it — a bright glow
  around the slot cycling bright → dim (`docs/reference/new-item-highlight-*.png`). Today our buttons
  show it only by accident; `frames/item.lua` never calls `UpdateNewItem` (**issue #15** for what is
  actually lit, **issue #16** for the overlays our paint path omits)
- **sections bound to several categories** (`FR-11`): packing one block whose contents come from N
  categories, sub-ordered by category priority
- `window.copy` command (`FR-10b`) — a bank window built from a backpack window in one action, and
  `window.link` (`FR-10c`) — the same two windows kept in step, with the link visible on both titles
- `frames/header.lua` with the configure-mode handle placeholders
- `frames/bagbar.lua` — vanilla↔sorting toggle on the client's bag bar, plus a vanilla-only view that
  can open one physical bag on its own (`FR-51`)
- `frames/movemode.lua` — saved clamped positions + **EditMode spike** (`docs/07` Q13): join
  Blizzard move mode ThreatMeter-style (`EventRegistry` `EditMode.Enter/Exit`,
  `EditModeSystemSelectionTemplate`, `EditModeSystemMixin` adoption); test whether
  `EditModeManagerFrame:RegisterSystemFrame` tolerates a dynamic number of our windows, **and whether
  the per-system settings dialog (`EditModeSystemSettingsDialogButtonTemplate`) is reachable for a
  frame we registered** — that dialog is where columns/scale/compact live (`FR-71`)
- `frames/emptyslot.lua` (compact family counts + "show all slots" mode), reading
  `C_Container.GetBagSlotFlag` rather than guessing bag kinds
- virtual stacking (`data/stacks.lua`) + split slider, with `showStacks` modes (`FR-43`): merged by
  default, `always`, `session` (toggle un-merges until the bags close), `vendor`
- **presentation options** (`FR-45`, `FR-45b`): quality/rarity border-and-tint controls and item-level
  controls, opened from the window's *Appearance* modal, defaults matching stock bags
- money frame (`frames/money.lua`)
- window icons: `IconDataProviderMixin` picker + `overlay` layer (`FR-85`)

Exit criteria
- **AC-10, AC-10b, AC-11, AC-17** create/rename/reorder/delete windows and sections, copy a backpack
  window into a bank window, bind two categories to one section — via **temporary slash commands**
  (`/bos test newwindow Crafting`, `/bos test copywindow w1 bank`, `/bos test movesection …`): the
  model and layout are fully exercised before the UI exists. Slash-command config is throwaway and
  deleted in M3.
- **AC-40** 12 sections in a 5-column window: no overlap, no clipped titles, correct resize. Then the
  `docs/01` stress case (issue #5): ~20 sections in one window with a 30-character name.
- **AC-43** merged stacks show the true total, split pulls the right count into real slots, and each
  `showStacks` mode renders what `docs/02` says it renders.
- **AC-45, AC-45b** quality borders and item level: per-quality toggles, border vs tint, threshold,
  intensity, gear-only ilvl, minimum ilvl, and ilvl hidden for an item not yet in the cache.
- **AC-44** empty-slot modes both render correctly with a reagent bag / ammo pouch present.
- **AC-49** with Masque installed, our buttons pick up its skin with no code from us beyond the
  template choice — or the reason they do not is written down here.
- **AC-51** switch to vanilla bags from the bag bar, open only the herb pouch, buy and equip a bigger
  bag, switch back: no `ADDON_ACTION_FORBIDDEN`, nothing lost.
- **AC-41** window position and scale survive `/reload`.
- **AC-85** pick an icon from the client's picker, `/reload`, still there.
- **AC-54** `/bos move` opens vanilla EditMode with our windows draggable in it, snap lines against
  another window, positions persist after Exit + `/reload`; drag still works with EditMode absent.
  Record the Q13 A-vs-B verdict **and the settings-dialog verdict** in `docs/07`.

Risks
- River packing with long section titles is exactly where Baggins gets ugly (`title:GetStringWidth()/39`
  magic). Plan for a real measurement-based sizing function, and test with a 30-char section name.
- Bank container enumeration is **settled** (issue #9, measured 2026-10-18): index 6 is the 48-slot grid,
  7..14 are the bank bag slots. Bank windows stay in M5 by plan, not by uncertainty.

---

## M3 — Config layer + the category editor (2.5–4 wk) — **the product milestone**

**Goal:** replace the throwaway slash commands with the command layer and the modals that are the
editor.

Deliverables
- `config/commands.lua` (every action in `docs/05` §Interaction inventory, each invertible),
  `config/undo.lua` (bounded log, default 50)
- `config/form.lua` — minimal in-house form builder (section, checkbox, slider, dropdown, input,
  color, button group) built on vanilla templates only
- **`config/categoryeditor.lua`** — the modal from `docs/05` §Screen 2: chips, the `EXCEPT` row, the
  live list of real inventory, Apply/Cancel draft semantics, `⚠` competitor markers
- **`config/itemlisteditor.lua`** + `util/idlist.lua` — the paste parser (`FR-24b`), one command per
  paste
- `config/sectioneditor.lua` — combo box + sortable category list (`docs/05` §Screen 4)
- `config/settingswindow.lua` — the **utility** window (Find / Presets / Import-Export / Profiles) +
  `config/panes/{windows,sections,categories,rules,profiles}.lua`
- chip rendering (`frames/chips.lua`) + chip popover with "applies to N of your items"
- incremental reclassify on rule change (**FR-26**)
- undo/redo as **buttons** (configure bar, modal footers, toast); no default Ctrl+Z/Ctrl+Y binding
- delete the M2 throwaway slash commands

Exit criteria
- **AC-70, AC-74, AC-75, AC-80** — including the timed test: a person who has never seen the addon
  creates a "Sell" window with Junk + Quest in under 3 minutes, unaided, **without opening the
  settings window**. **Run this test with an actual human, not with yourself.** Record what they
  clicked; the failures become M4 work.
- **AC-20** a nested `any/all/none` tree built purely by clicking chips.
- **AC-23** priority change moves items live.
- **AC-24b** the same 43 IDs pasted newline-separated and comma-separated produce the same category,
  in one undo step.
- **AC-29** empty/no-match/no-reference states all visibly reported.
- **AC-26** editing one rule does not re-run the full pipeline (`/bos perf` shows the delta).
- Undo/redo across 10 mixed edits verified by SavedVariables diff before/after.
- The category editor handles a 12-rule `EXCEPT`-heavy category (the `Consumables.Misc` shape from
  `docs/01`), not just a 1-rule category.

Risks
- The category editor is the highest-value, highest-risk component: it must run the classifier over
  the current inventory with a *draft* tree substituted, without mutating the real model. Budget a
  spike (1–2 days) to prove draft substitution before building anything else on it.
- Dropdown widget choice on Forever: `WowStyle1DropdownTemplate` vs `UIDropDownMenuTemplate` —
  resolve in M0's capability output and use one of them everywhere.

---

## M4 — Configure mode + inspector (2–3 wk)

**Goal:** the bags become the editor.

Deliverables
- `config/configuremode.lua`: in-place title editing, section handles (`⌃ ⌄ ⇄ ⌫ ✎`), drop targets,
  window/section/item context menus, `Done`/`Esc`/idle exit, configure-bar Undo/Redo
- drag-and-drop assignment (`FR-61`) with `OnReceiveDrag`/`OnDragReceived` on section headers
  without breaking secure item pickup
- `frames/inspector.lua` (**FR-78**) reading the per-harvest `trace`, with *Exclude from category*
  and *Make a category for this item* wired straight from it (**FR-24c**)
- `category.createFromItem` flow (**FR-77**)
- "what changed" toast (**FR-83**) carrying the Undo action
- combat lockdown behavior for structural handles

Exit criteria
- **AC-60** stock item interaction is bit-for-bit unchanged (pickup, right-click menu, drag to
  spellbar/trade/vendor, shift-click, click-cast).
- **AC-61, AC-63, AC-24c** drag-to-section, the inspector, and one-click *Exclude from category* all
  work on real looted items.
- **AC-72** a full layout (3 windows, 8 sections) can be built **without ever opening the settings
  window**.
- **Q23 decided here**: combat usability — whether "readable but stale in combat" ships for v1, or
  our buttons stop being secure (**issue #17**). Measure BetterBags' behaviour in combat before choosing (`docs/07` Q23).
  The requirement it has to land on is **`FR-126`**: mid-combat loot visible immediately, unsorted is
  acceptable, re-sort on regen.
- **AC-4** configure handles disabled in combat with an explanation, no taint.
- Re-run the M3 timed human test in configure mode only; target ≤ 6 interactions for a custom
  window + 2 sections.

Risks
- Drop targets on secure item buttons are the classic bag-addon taint trap, and **Forever has no
  secure handler snippets** (`C_SecureHandlerRegisterSnippets` / `SecureHandlerOnSNippet` are absent
  — `agents.md`), so the modern snippet escape hatch is not available. Spike first: confirm we can
  observe a drag started on a secure button (via our own `OnReceiveDrag` on the header +
  `GetCursorInfo`) without adding attributes to the button in combat. If not possible, fall back to
  right-click → "Move to category…" as the only assignment path and record the limitation.

---

## M5 — Bank, presets, profiles, sharing (1.5–2.5 wk)

Deliverables
- bank windows (`kind = "bank"`), bank tabs + bank bags harvesting, bank control frame
- `window.copy` exposed in configure mode (*Copy a window* → bank twin) — the thing the measured
  Baggins configs do by hand 6 times (`docs/01`)
- `config/presets.lua` (leveling / tradeskill / collections / minimal) **as data**, including the
  curated item-ID lists that replace Baggins' `PeriodicTable Set` usage (`FR-31`): food, water,
  potions, bandages, explosives, hearth, tools, ore, herbs, cloth, leather, thread
- `config/importexport.lua` (`BOS1.` strings, diff-before-apply)
- profiles UI (switch / copy-from / per-character override / reset-this-category)
- `core/db.Migrate()` for our own schema versions. **No Baggins importer** (`FR-94` = Won't, deferred
  by `docs/07` Q5)
- dynamic categories (`kind = "dynamic"`, **FR-25**) if `docs/07` Q8 keeps it Must
- **no `data/snapshot.lua`** (`FR-109`): the harvest loop is the only inventory reader, and bank
  containers are read while the bank is open. Issue #9 answered: a bank window maps onto **one 48-slot
  grid at index 6**, plus one container per purchased bank bag at 7..14

Exit criteria
- **AC-13** bank windows only appear while the bank is open; bank bags and tabs are complete.
- **AC-10b** the bank twin of a 20-section window is created in one action and stays correct after
  both are edited.
- **AC-79** fresh install with preset installed: usable layout, zero config.
- **AC-92** export on one character, import on another, layout matches; collision policy exercised.
- **AC-93** 20 open/close cycles on a full backpack → SavedVariables file does not grow. Settle the
  file-name question first (**issue #14**): the TOC declares `BagsOfSortingDB`, the client writes
  `SavedVariables/BagsOfSorting.lua`
- **AC-110** closed-bank search behaves honestly before and after visiting the bank.

Risks
- The container model is measured (issue #9): index 6 = the 48-slot grid, 7..14 = bank bags,
  `BAG_UPDATE(6)` is the refresh path, and index 6 answers 0 slots while the bank is closed. Two
  consequences are hard requirements: `harvest.Invalidate()` + `Discover()` on `BANKFRAME_OPENED`
  (opening fires no container event, so nothing else ever reveals the bank container) and dropping it
  on `BANKFRAME_CLOSED` (AC-13). The only unmeasured shape is a **purchased** bank bag — **issue #25**,
  blocked on gold, with the working assumption recorded in `agents.md`.
- A persisted snapshot is the first place this design writes derived state to disk. If it grows
  unbounded or leaks item data a user did not opt into, it is cut back to session-only rather than
  tuned.

---

## M6 — Search, physical moves, integrations, performance (2–3 wk)

Deliverables
- `util/query.lua` lexer+parser and `data/search.lua` index for the FR-28 field subset;
  "save search as category"
- in-bag search bar (**FR-50**), reusing `ItemButtonUtil.GetItemContextMatchResultForItem` where it
  applies so our search and the client's agree (`docs/07` Q7)
- section bulk actions: deposit-all, move-to-window, and **sell-this-section behind its opt-in gate**
  (**FR-62, FR-65**) — confirm lists every item, the total gold and the vendor buyback limit
- **`bag.empty`** — empty a physical bag (**FR-67**), and **affinity compaction** (**FR-66**) using
  `C_Container.GetBagSlotFlag` + `Enum.BagSlotFlags`
- physical-move safety rails (**FR-68**): destination check before first pickup, bucketed moves,
  cursor never left holding, refusal in lockdown
- `integrations/masque.lua` (**FR-121**) and `integrations/pawn.lua` (**FR-122**), both guarded, both
  optional-later rather than required
- `config/settingspanel.lua` (**FR-88**): Options → AddOns category for Find / Presets / Import-Export
  / Profiles / Keys, via `Settings.RegisterAddOnCategory` + vertical or canvas layout. **No minimap
  button** (`FR-123`) — that feature is refused, not deferred
- performance pass against the `FR-100/101` numbers with a deliberately overstuffed test character

Exit criteria
- **AC-28** a saved search category tracks new matching items as they are looted.
- **AC-65** selling a section marked sellable at a vendor in one action, with a confirm naming every
  item, the total gold and the buyback limit; a section not marked sellable cannot be bulk-sold
- **AC-66, AC-67, AC-68** affinity compaction, empty-bag, and combat refusal all behave as written in
  `docs/02`.
- **AC-124** run alongside `ForeverPlus`, `Leatrix_Plus`, `Baggins`, `BetterBags`; record what breaks.
- `/bos test clock` numbers meet or beat the M1-recorded numbers after the feature load.
- **NFR-1** own-code LOC check: under ~8,000. If over, write down which module blew up and why.

---

## M7 — Ship (0.5–1 wk)

- `.pkgmeta` packaging (LICENSE and Media/ included), release TOC version bump, CHANGELOG
- remove debug scaffolding not gated behind `settings.debug` (**NFR-6**) — including the decision on
  `core/diag.lua` (**issue #21**): `/bos test <n>` and `/bos find` are in the TOC, so they ship unless
  kept, gated on `settings.debug`, or moved to a dev-only TOC
- README screenshots/GIFs replacing the placeholder, using `Media/Icon.png`
- publish: GitHub `SterlingNerd/BagsOfSorting`, CurseForge project `1745962`, Wago `bGoYJY60`
  (`docs/07` Q14), `## X-Curse-Project-ID` / `## X-Wago-ID` already in the TOC
- a written "known limitations" section pulled from every `shortcut:` comment in the codebase
- **`config/help.lua` — the intro / help page (`FR-87`, `docs/07` Q20)**. It ships here, not earlier:
  the UI it explains must exist, and by 1.0 it is onboarding rather than documentation. Three nouns,
  four gestures, where each kind of setting lives, what Undo means. Opened by `?` on the configure bar
  and in every modal footer, and by `/bos help`.
- a first-run note about the `B` keybind collision (`docs/07` Q4), and our keybinds registered through
  `Settings.SetKeybindingsCategory` so they are findable in the client's own Key Bindings panel

---

## After M7 — v1.x, in the order they earn their place

Not milestones; a queue. Each gets a milestone only when the one before it ships.

1. **Auto-sell** (`FR-65b`) — a designated trash category and/or grey-quality items on opening a
   vendor, with a confirm and a global off switch. Deliberately after bulk sell has been used in the
   wild, because this is the feature that can sell something by accident.
2. **Group bindings** (`FR-11b`) if category counts keep growing in real use — `Tradeskills.Enchanting ∗`
   binding a whole dotted family (`docs/07` Q18).
3. **No re-flow while a vendor is open** (`FR-44b`, **issue #19**) — a sold slot becomes an empty slot in place and
   the section re-flows when the vendor closes. Cheap to state, and it is what makes bulk sell safe.

Offline search and the guild bank are **not in this queue** — they are out of the product (`FR-109`,
`docs/07` Q15). A published config API is not in the queue either: we keep the model publishable
(`FR-113`) and let a future consumer decide the transport (`docs/07` Q22).

Exit criteria: installable from a release zip into `../addons/` with no dev tooling, on a character
that has never had the addon, with the first-run experience tested by someone else.

---

## Standing test discipline (every milestone)

1. `luacheck` clean in CI.
2. `lua5.1 tests/run.lua` green in CI — classifier fixtures grow with each new field.
3. `/bos test <n>` probes run for what they cover: 2 (bank arithmetic), 7 (keybind persistence),
   11 (new-item textures), 13 (clock + pipeline cost). Probes live in `core/diag.lua` because
   `/script` is one line capped near 255 characters. Pending tests are issue-numbered entries in the
   same file, deleted when their capture is ingested; the run sheet numbers every step and each step is
   **one action** — a compound step is how a manual action gets skipped (issue #27).
4. In-game checklist (`tests/CHECKLIST.md`) run on Forever and pasted into the milestone entry with
   the date and patch. A milestone is not done until its AC lines have a dated entry. The runnable
   snippets for the API questions live in the **spike issues** (#1–#11), not in a docs file
   (`docs/07` Q21).
5. `/bos perf` and `/bos test clock` numbers recorded, not asserted.
6. One manual "hostile" pass per milestone: full inventory, a dozens-of-categories config imported in
   the `docs/01` shape, ~20 sections in one window, a 30-char section name, an item Blizzard has no
   info for, combat, death, `/reload` mid-combat.
7. Coexistence pass against the installed addons (`FR-124`).

## What would make us stop and re-plan

- M1 timings blow the `FR-100` budget by > 3× on a normal backpack → the pipeline model (not the
  UI) is wrong; revisit chunking or caching before writing more UI.
- M3's timed human test fails twice with different people → "the bags are the editor" is not the
  right shape on its own; revisit `docs/05` before continuing.
- M3's category editor cannot show a 12-rule `EXCEPT`-heavy category readably → the rule grammar is
  too expressive for its own UI; cut nesting to `all{ any{…}, none{…} }` flat and revisit `docs/04`.
- M4's drag spike fails → configure mode loses drag-to-assign; re-evaluate whether configure mode is
  still the differentiator or whether the category editor carries it alone.
