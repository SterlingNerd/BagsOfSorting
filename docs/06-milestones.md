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

Deliverables
- `BagOfSorting.toc`, `.pkgmeta`, `.luacheckrc` (WoW globals declared), `LICENSE`
- **no `libs/` directory** — zero vendored libraries (`docs/07` Q2 resolved)
- `core/boot.lua`, `core/client.lua` (capability flags), `core/constants.lua`, `core/log.lua`,
  `core/events.lua` (own frame + dispatch table), `core/locale.lua`
- `/bos` slash command printing the resolved capability table — this doubles as the Forever fact
  verification tool required by `agents.md`
- `tests/fixtures.lua` + `/bos selftest` stub (asserts nothing yet, but the harness works)
- CI: GitHub Actions running `luacheck` on push (copy the shape of `../addons/Baggins/.github/workflows/check.yml`)
- per-directory `README.md` stubs (`NFR-3`)

Exit criteria
- **AC-1** loads with zero errors on login and 3× `/reload`; `/events` clean.
- `/bos` prints `isForever=true`, `hasWarbank=false`, `itemButtonType=ItemButton`, and **fills in
  the unverified `agents.md` facts** (keyring presence, reagent bag slot, `NUM_TOTAL_EQUIPPED_BAG_SLOTS`
  value, container index ranges). Update `agents.md` with the answers — this milestone is what
  turns the "unverified" column into facts.
- `luacheck` clean in CI.

Risks: none material. If `/bos` cannot print the capability table, the client detection assumption
is wrong and everything downstream is re-planned here, cheaply.

---

## M1 — Pipeline: real items, one window (1.5–2.5 wk)

**Goal:** prove harvest → enrich → classify → sort → render on Forever with real inventory.

Deliverables
- `data/harvest.lua`, `data/enrich.lua`, `data/classify.lua`, `data/rules.lua`, `data/sort.lua`
- `filters/registry.lua` + 8 fields: `type`, `subtype`, `quality`, `ilvl`, `name`, `expansion`,
  `equipSlot`, `isQuestItem`
- `frames/window.lua`, `frames/item.lua` (pooled, `ItemButton` type), `frames/section.lua`
- one hardcoded window ("Backpack") with 3 hardcoded categories (Junk / Armor / Everything-else)
  written **in the data model**, not in code — so the schema is exercised from day one
- `core/async.lua` chunking + `core/events.lua` bucketing
- `/bos perf` printing ms per pipeline phase

Exit criteria
- **AC-14, AC-16** real inventory appears, nothing duplicated, unmatched items in the catch-all.
- **AC-42** button pool stays flat across 10 open/close cycles (`/bos perf` reports pool stats).
- **AC-100/101** timings recorded in `docs/06` as actual numbers, not targets.
- **AC-103** loot an item never seen by the client; it lands in catch-all, then re-sorts when info
  arrives.
- `/bos selftest` passes: fixture items × rule trees → expected category, including `any/all/none`
  nesting and the precedence tie-breaks from `docs/04`.

Risks
- Tooltip-based and expansion-based fields may need data we cannot read cheaply on Forever. If
  `expansion` is unavailable, drop it from the v1 field set and record it in `docs/02` (FR-21) as a
  removal, not a silent gap.
- Secret-value handling for `C_Item` on Forever: verify `ItemLocation:CreateFromBagAndSlot` paths
  work for bank tabs.

---

## M2 — Windows, sections, flow layout (1.5–2 wk)

**Goal:** the Baggins shape. Multiple user-visible windows, sections packed inside them.

Deliverables
- `data/windows.lua`, `data/sections.lua`, `layout/flow.lua`, `layout/sizing.lua`, `layout/anchors.lua`
- per-window `columns`, saved position/scale, `compact` windows, collapsed/hidden sections
- `frames/header.lua` with the configure-mode handle placeholders
- `frames/movemode.lua` — saved clamped positions + **EditMode spike** (`docs/07` Q13): join
  Blizzard move mode ThreatMeter-style (`EventRegistry` `EditMode.Enter/Exit`,
  `EditModeSystemSelectionTemplate`, `EditModeSystemMixin` adoption), and test whether
  `EditModeManagerFrame:RegisterSystemFrame` tolerates a dynamic number of our windows
- `frames/emptyslot.lua` (compact family counts + "show all slots" mode)
- virtual stacking (`data/stacks.lua`) + split slider
- money frame (`frames/money.lua`)

Exit criteria
- **AC-10, AC-11, AC-17** create/rename/reorder/delete windows and sections via **temporary
  slash commands** (`/bos test newwindow Crafting`, `/bos test movesection …`) — the real UI does
  not exist yet, but the model and layout must be fully exercised. Slash-command config is throwaway
  and deleted in M3.
- **AC-40** 12 sections in a 5-column window: no overlap, no clipped titles, correct resize.
- **AC-43** merge 6 partial stacks → correct total; split 15 out → real slots correct.
- **AC-44** empty-slot modes both render correctly with a reagent bag / ammo pouch present.
- **AC-41** window position and scale survive `/reload`.
- **AC-54** `/bos move` opens vanilla EditMode with our windows draggable in it, snap lines against
  another window, positions persist after Exit + `/reload`; drag still works with EditMode absent.
  Record the Q13 A-vs-B verdict in `docs/07`.

Risks
- River packing with long section titles is exactly where Baggins gets ugly (`title:GetStringWidth()/39`
  magic). Plan for a real measurement-based sizing function, and test with a 30-char section name.
- Bank container enumeration on Forever (bank tabs + bank bags indices) is the highest-uncertainty
  area; if it slips, bank windows move to M5 and M2 stays backpack-only.

---

## M3 — Config layer + settings window (2.5–4 wk) — **the product milestone**

**Goal:** replace the throwaway slash commands with the command layer and the 3-pane window.

Deliverables
- `config/commands.lua` (every action in `docs/05` §Interaction inventory, each invertible),
  `config/undo.lua`
- `config/form.lua` — minimal in-house form builder (section, checkbox, slider, dropdown, input,
  color, button group) built on vanilla templates only
- `config/settingswindow.lua` + `config/panes/{windows,sections,categories,rules,preview}.lua`
- chip rendering (`frames/chips.lua`) + chip popover
- preview pane running the real classifier with a draft rule tree substituted
- incremental reclassify on rule change (**FR-26**)
- delete the M2 throwaway slash commands

Exit criteria
- **AC-70, AC-71, AC-74, AC-78** — including the timed test: a person who has never seen the addon
  creates a "Sell" window with Junk + Quest in under 3 minutes, unaided. **Run this test with an
  actual human, not with yourself.** Record what they clicked; the failures become M4 work.
- **AC-20** a nested `any/all/none` tree built purely by clicking chips.
- **AC-23** priority change moves items live.
- **AC-29** empty/no-match/no-reference states all visibly reported.
- **AC-26** editing one rule does not re-run the full pipeline (`/bos perf` shows the delta).
- Undo/redo across 10 mixed edits verified by SavedVariables diff before/after.

Risks
- The preview pane is the highest-value, highest-risk component: it must run the classifier against
  a *draft* model without mutating the real one. Budget a spike (1–2 days) to prove the
  draft-substitution design before building panes on top of it.
- Dropdown widget choice on Forever: `WowStyle1DropdownTemplate` vs `UIDropDownMenuTemplate` —
  resolve in M0's capability output and use one of them everywhere.

---

## M4 — Configure mode + inspector (2–3 wk)

**Goal:** the bags become the editor.

Deliverables
- `config/configuremode.lua`: in-place title editing, section handles (`⌃ ⌄ ⇄ ⌫`), drop targets
- drag-and-drop assignment (`FR-61`) with `OnReceiveDrag`/`OnDragReceived` on section headers
  without breaking secure item pickup
- `frames/inspector.lua` (**FR-27**) reading the per-snapshot `trace`
- `category.createFromItem` flow (**FR-75**)
- "what changed" toast (**FR-81**)
- combat lockdown behavior for structural handles

Exit criteria
- **AC-60** stock item interaction is bit-for-bit unchanged (pickup, right-click menu, drag to
  spellbar/trade/vendor, shift-click, click-cast).
- **AC-61, AC-63** drag-to-section and the inspector work on real looted items.
- **AC-72** a full layout (3 windows, 8 sections) can be built **without ever opening the settings
  window**.
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
- `config/presets.lua` (leveling / tradeskill / collections / minimal) as data
- `config/importexport.lua` (`BOS1.` strings, diff-before-apply)
- profiles UI (switch / copy-from / reset-this-category)
- `core/db.Migrate()` + Baggins importer with the `docs/04` migration report (**FR-94**)
- dynamic categories (`kind = "dynamic"`, **FR-25**)

Exit criteria
- **AC-13** bank windows only appear while the bank is open; bank bags and tabs are complete.
- **AC-77** fresh install with preset installed: usable layout, zero config.
- **AC-92** export on one character, import on another, layout matches; collision policy exercised.
- **AC-93** 20 open/close cycles on a full backpack → SavedVariables file does not grow.
- Baggins import run against a real `BagginsDB` from `../account/` and the report reviewed by hand.

Risks
- Baggins `NOT`-rule semantics do not map cleanly (`docs/04` table). If the report is ugly, ship
  the importer as a preview/"best effort" feature or defer it to M7.

---

## M6 — Search, bulk actions, looks, performance (2–3 wk)

Deliverables
- `util/query.lua` lexer+parser and `data/search.lua` index for the FR-28 field subset;
  "save search as category"
- in-bag search bar (**FR-50**)
- section bulk actions: sell-all, deposit-all, move-to-window (**FR-62, FR-65**)
- `themes/{stock,dark}.lua`; Masque integration if cheap (**FR-49**)
- item upgrade arrow (**FR-52**), "show real bags" view (**FR-51**) if either proves cheap
- performance pass against the `FR-100/101` numbers with a deliberately overstuffed test character

Exit criteria
- **AC-28** a saved search category tracks new matching items as they are looted.
- **AC-65** selling a whole section at a vendor in one action, with a confirm naming the count.
- `/bos perf` numbers meet or beat the M1-recorded numbers after the feature load.
- **NFR-1** own-code LOC check: under ~8,000. If over, write down which module blew up and why.

---

## M7 — Ship (0.5–1 wk)

- `.pkgmeta` packaging, release TOC version bump, CHANGELOG
- remove debug scaffolding not gated behind `settings.debug` (**NFR-6**)
- README screenshots/GIFs replacing the placeholder
- CurseForge + Wago upload mechanics, `## X-Curse-Project-ID` reserved
- a written "known limitations" section pulled from every `shortcut:` comment in the codebase

Exit criteria: installable from a release zip into `../addons/` with no dev tooling, on a character
that has never had the addon, with the first-run experience tested by someone else.

---

## Standing test discipline (every milestone)

1. `luacheck` clean in CI.
2. `/bos selftest` green — classifier fixtures grow with each new field.
3. In-game checklist run on Forever and pasted into the milestone entry with the date and patch.
   A milestone is not done until its AC lines have a dated entry.
4. `/bos perf` numbers recorded, not asserted.
5. One manual "hostile" pass per milestone: full inventory, 30+ categories, a 30-char section name,
   an item Blizzard has no info for, combat, death, `/reload` mid-combat.

## What would make us stop and re-plan

- M1 timings blow the `FR-100` budget by > 3× on a normal backpack → the pipeline model (not the
  UI) is wrong; revisit chunking or caching before writing more UI.
- M3's timed human test fails twice with different people → the 3-pane model is not the right
  shape; revisit `docs/05` before continuing.
- M4's drag spike fails → configure mode loses drag-to-assign; re-evaluate whether configure mode
  is still the differentiator or whether the settings window with preview carries it alone.
