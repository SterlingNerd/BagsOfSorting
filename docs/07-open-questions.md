# 07 — Open Questions

Each entry: the question, the real options, **a recommendation**, and what it takes to decide.
Disagreeing means editing the recommendation to your alternative and why — not a comment thread.

---

## Q1 — Product name

Repo dir is now `BagOfSorting` (renamed 2026-10-14, nothing pushed yet), and `../addons/BagOfSorting`
is a symlink to it — so the client-visible addon folder name already matches the addon name WoW
requires. Remaining open item is only the public name on CurseForge/Wago.

| Option | Notes |
|---|---|
| `Bag of Sorting` (`BagOfSorting`, `BagOfSortingDB`, `/bos`) | matches the repo dir and the addon symlink folder, descriptive, `/bos` is short and unclaimed |
| Keep it a working title and pick at M7 | cheap now, painful later |

**Recommendation:** lock `Bag of Sorting` / `/bos` now. Check CurseForge + Wago for a name clash
before M0's first commit; if it clashes, pick the alternative today, not at M7.

**Needed:** one search on CurseForge/Wago.

## Q2 — Dependency set

**Resolved 2026-10-13: zero vendored libraries in v1.**

Evidence that settled it:
- BetterBags declares `AceGUI-3.0` and `AceConfig-3.0` in its TOC and uses **neither** in its own
  28k LOC. Its whole settings UI is vanilla: `WowScrollBox`, `MinimalScrollBar`, `ScrollUtil`,
  `UIPanelButtonTemplate`, `InputBoxTemplate`, `WowStyle1DropdownTemplate`,
  `UICheckButtonTemplate`, `UISliderTemplate`, `ButtonFrameTemplate`.
- `origin/forever` ships all of those, plus `UIDropDownMenu`/`EasyMenu` (so BetterBags' vendored
  `LibUIDropDownMenu` is a Classic concession), plus `StackSplitFrame` with a Camelot override.
- Forever exposes no options-panel widget API (`C_SettingsUtil` only), so the settings window is
  ours regardless — which was always going to be the case.

What we now hand-roll (`docs/03` §Dependencies): module lifecycle ~40 lines, event dispatch ~60,
hooks ~30, locale ~15, saved positions ~100, **profiles ~250 lines + tests**.

**Remaining live question:** is `core/db.lua` (profiles: Default / per-character / copy-from /
reset / versioned migrate) worth vendoring `AceDB` alone to avoid? Recommendation: **no** — write
it, test it, and revisit only if it becomes a recurring bug source. AceDB is the single defensible
exception, not a reason to take the rest of Ace3.

**Needed:** none. Reopen only if the M0/M1 profile code misbehaves.

## Q3 — Can a section hold multiple categories?

Baggins: `section.cats = { "Herbs", "Ores", "Reagents" }` — a section is a *group* of categories.
BetterBags: one section per category.

| Option | Consequence |
|---|---|
| **A. One category per section** (BetterBags) | model is simple, UI is obvious ("this block shows the Herbs category"), but "Herbs + Ores in one block" requires a category whose rules are `any` of both |
| **B. Section = list of categories** (Baggins) | matches the feature users cite about Baggins ("one block, several kinds of thing"), costs a merge/sort rule for how multiple categories lay out inside one block |

**Recommendation:** **A for v1**, with `category.duplicate` and `any{}` groups covering most of B's
value, **plus** a documented path to B: a section may reference a *category group* (a named list of
categories rendered as one block, sub-sorted by category). Ship A in M2, add the group variant in
M6 only if real usage shows we need it. This keeps the config UI honest — one block, one thing to
explain.

**Needed:** decision. This is the single biggest model decision in the project; it changes
`docs/04` and the left pane of `docs/05`.

## Q4 — Do we hook Blizzard's bag functions?

Baggins raw-hooks `OpenAllBags`, `ToggleAllBags`, `ToggleBackpack`, `OpenBag`, `OpenBackpack`,
`ToggleBag` so that other addons (and Blizzard keybinds) open *our* windows. That is what makes a
bag addon feel native — and it is also the most taint-prone code in either reference repo.

| Option | Consequence |
|---|---|
| **A. Hook them** (Baggins-style) | other addons' "open bags" works, Blizzard bag button works, more combat/taint risk |
| **B. Own keybinds + hide/reparent the Blizzard bags bar** (BetterBags-style) | less hooking, but addons that call `OpenAllBags()` directly will open stock bags alongside ours |
| **C. Hook only `BackpackOpenButton`/`CharacterFrame` bag button click, not the global functions** | middle ground |

**Recommendation:** **B first, in M2**, and add **C** in M6 if real usage shows conflicts (e.g. with
`../addons/Leatrix_Plus` or `ForeverPlus`, both installed here). Never A in v1.

**Needed:** in-game check at M2 — with our windows open, press the default B keybind and confirm
nothing stock opens; then load Leatrix_Plus and re-test.

## Q5 — How do Baggins' multi-category sections migrate?

Consequence of Q3. If we land on A, a Baggins section with `cats = {"Herbs","Ores"}` has no direct
equivalent.

**Recommendation:** migrate it to **one new category** named after the section, whose rule tree is
`any{ <category Herbs tree>, <category Ores tree> }`, and list that transformation in the migration
report as a semantic change (the original categories still exist and still compete). Do not create
N sections — that silently explodes the layout.

**Needed:** Q3 decided first.

## Q6 — Export format: model dump or command log?

| Option | Notes |
|---|---|
| Model dump (`{windows, categories}` serialized) | simple, stable, human-diffable |
| Command log replay | guarantees import runs through the same validated path as UI edits |

**Recommendation:** **model dump**, but import feeds the dump through the command layer as one
batch command (`import.apply`) so it is validated, atomic and undoable. Best of both, no complexity.

**Needed:** decision only.

## Q7 — Is the search DSL in v1?

FR-28 is Should today. A lexer+parser+index is roughly 1,000 lines (BetterBags: `util/query.lua`
194 + `data/search.lua` 738). It is the only way a user can express "everything from Outland that
is not a quest item and has 'herb' in the tooltip" without us shipping a field for every idea.

**Recommendation:** keep it **Should**, land it in M6, and cap the v1 field set to the FR-28 list.
If M3's chip editor turns out to cover everything in practice, cut the DSL and spend the time on
dynamic categories instead. Decide at the M3→M4 boundary using what people actually tried to build.

**Needed:** evidence from the M3 human tests.

## Q8 — Is `kind = "dynamic"` (group-by-type/subtype/expansion) Must?

It is the most-liked BetterBags feature and the hardest to render as chips: a dynamic category
produces N sections the user did not create, which conflicts with "sections are things you made".

**Recommendation:** **Must, but scoped**: dynamic categories expand into sections inside exactly one
window, are named `<parent> — <value>`, cannot be individually reconfigured (only disabled or
moved), and are visually marked as generated. Anything more is a v2 feature.

**Needed:** decision. If it is not Must, `docs/04`'s classify-time expansion step disappears and
M5 gets smaller.

## Q9 — Do we hide the Blizzard bags bar?

BetterBags reparents `BagsBar` to a sneaky frame to hide the stock bags. On Forever the bags bar is
`MainMenuBarBagButtons/Camelot`, and reparenting a protected-ish frame is exactly the kind of thing
that produced the `ADDON_ACTION_FORBIDDEN` mess documented in the parent `../agents.md`.

**Recommendation:** hide by `SetAlpha(0)`/`SetShown(false)` on the *button* only if M2 testing shows
no lockdown errors; otherwise leave the stock button visible and let it open our windows (Q4 option
C). A visible stock button is a cosmetic loss, not a functional one.

**Needed:** M2 in-game test.

## Q10 — Forever container facts we still do not know

`agents.md` lists what Forever has/does not have, but these are unresolved and M2 depends on them:

- keyring present or not (Baggins treats Forever as classic-like here; BetterBags has a `KeyRingButton` note)
- reagent bag slot present (`CharacterReagentBag0Slot` is listed as present — is it *equippable*?)
- `NUM_TOTAL_EQUIPPED_BAG_SLOTS` value and the bank-bag index range
- whether `Enum.BagIndex.AccountBankTab_N` being inert causes harvest loops to error or just return 0

**Recommendation:** M0's `/bos` capability dump answers all four in one run. Until then, every
container loop iterates a **discovered** list built at load, never a hardcoded constant.

**Needed:** one in-game run at M0. Update `agents.md` with the results.

## Q11 — Profile default: per-character or shared?

Ace3's `AceDB` defaults to per-character; BetterBags defaults everyone to a shared "Default"
profile. Since we are writing our own profile store (`docs/03` §Dependencies) this is a free choice.

**Recommendation:** **shared Default**, per-character opt-in, with the profile popover showing which
characters share a profile. Reason: a bag layout is mostly a personal habit, not a class-specific
need, and per-character defaults create the "I configured it on my mage and my warrior is a mess"
complaint.

**Needed:** decision only.

## Q12 — Do we ship a plugin API?

`FR-32` says Won't for v1. Internal boundaries (`data` never touches frames, field registry is data)
make it possible later.

**Recommendation:** keep the boundaries, ship nothing, and write one `docs/` page only when someone
actually wants to build a plugin.

**Needed:** none yet.

## Q13 — How deep do we go with Blizzard EditMode?

Forever's move mode is joinable (ThreatMeter does it on Camelot). Two integration depths:

| Option | What you get | Cost / risk |
|---|---|---|
| **A. EventRegistry only** (ThreatMeter-style) | Enter/Exit callbacks, selection template, manual magnetism + snap preview calls. No registration with `registeredSystemFrames`. | proven pattern; no EditMode layout save/restore for our windows |
| **B. Also call `EditModeManagerFrame:RegisterSystemFrame(frame)`** | EditMode treats our window as a system: `OnEditModeEnter/Exit` calls, anchor tracking, and possibly EditMode **layout save/restore** including our windows | undocumented, absent from `C_EditMode`, and EditMode's layout system assumes one frame per named *system* — our windows are user-created and variable in count. Could break layout import/export |

**Recommendation:** **A**, plus a spike in M2 to test B for one window and see whether EditMode's
layout persistence tolerates a dynamic number of systems. If B works cleanly it is a real win (users
move our bags in the same UI, with the same layouts, as their action bars). If it fights us, stay
on A permanently and never mention EditMode layouts in our UI.

**Needed:** M2 spike, in-game. Do not build any UI that assumes B.

## Q14 — Distribution

CurseForge, Wago, or GitHub-only. Both references are on CurseForge (Baggins `X-Curse-Project-ID:
13471`, BetterBags `942432`) and BetterBags also uses Wago.

**Recommendation:** GitHub releases first (M7), CurseForge once the name is settled. Skip Wago
until there is a reason.

**Needed:** name (Q1) + a CurseForge account.

---

## Decisions needed **before M0 commits**

Q1 (name), Q3 (section↔category cardinality). Q2 is resolved (no vendored libraries). Everything
else can be decided at the milestone that needs it.
