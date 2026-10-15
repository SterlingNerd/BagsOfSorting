# 07 — Open Questions

Each entry: the question, the real options, **a recommendation** (or a decision), and what it takes
to decide. Disagreeing means editing the recommendation to your alternative and why — not a comment
thread.

Resolved entries stay in the file with their evidence. That is what stops the same argument being
had twice.

---

## Q1 — Product name — **DECIDED: `Bags of Sorting` (plural)**

Plural because the product *is* several bags; "Bag of Sorting" reads like one bag.

| Field | Value |
|---|---|
| Repo / GitHub | `BagsOfSorting` — `https://github.com/SterlingNerd/BagsOfSorting.git` |
| Addon folder / `addonName` | `BagsOfSorting` (client-visible; `../addons/BagsOfSorting` symlinks to the repo) |
| SavedVariables | `BagsOfSortingDB` |
| TOC `## Title` | `Bags of Sorting` |
| Slash command | `/bos` (unchanged, short, unclaimed) |
| CurseForge | project `1745962` |
| Wago | `bGoYJY60` |

**Needed:** nothing. Check CurseForge/Wago for a *different addon* claiming the name before the first
public upload, not before the first commit.

## Q2 — Dependency set — **DECIDED: zero vendored libraries**, with the cost named

Evidence that settled it:
- BetterBags declares `AceGUI-3.0` and `AceConfig-3.0` in its TOC and uses **neither** in its own
  28k LOC. Its whole settings UI is vanilla: `WowScrollBox`, `MinimalScrollBar`, `ScrollUtil`,
  `UIPanelButtonTemplate`, `InputBoxTemplate`, `WowStyle1DropdownTemplate`,
  `UICheckButtonTemplate`, `UISliderTemplate`, `ButtonFrameTemplate`.
- `origin/forever` ships all of those, plus `UIDropDownMenu`/`EasyMenu` (so BetterBags' vendored
  `LibUIDropDownMenu` is a Classic concession), plus `StackSplitFrame` with a Camelot override, plus
  `IconDataProviderMixin` and the `IconSelectorPopupFrameTemplate` picker the macro UI uses.
- Forever exposes no options-panel widget API (`C_SettingsUtil` only), so the settings UI is ours
  regardless.
- Not vendoring Ace3 removes the `AceEvent30Frame` class of `ADDON_ACTION_FORBIDDEN` that bit this
  workspace (`../TODO.md`).

What we give up, honestly — this is the part the "avoid dependencies" rule used to hide:

| Lost habit | Real consequence | Replacement |
|---|---|---|
| LibDataBroker + LibDBIcon minimap icon | Baggins/Bagnon users look for a draggable minimap icon; broker-display addons (Titan-class) cannot host us | `## AddonCompartmentFunc` + `## IconTexture` in v1 (verified present on camelot); a ~60-line own minimap button if users ask (`FR-123`) |
| AceConfig option tables | we do not appear inside someone else's aggregated options suite | nothing on Forever — no such suite is installed here and there is no options-panel API |
| LibQTip dewdrops | Baggins' rule-editing hover panels | `UIDropDownMenu`/`EasyMenu` + `TooltipBackdropTemplate` popovers |
| LibPeriodicTable curated lists | 329 rules in the measured config depend on named item sets (`docs/01`) | our own preset data as `itemID in {…}` categories (`FR-31`) — same content, ours to maintain |
| LibBagUtils / LibWindow / LibSharedMedia / LibItemUpgradeInfo | bag slot counting, saved positions, media, upgrade arrows | `C_Container.GetBagSlotFlag`, own positions, no custom fonts, Pawn integration (`FR-122`) |
| Masque / Pawn / ConsolePort / QuickFind | skinning, upgrade arrows, gamepad, cross-addon search | Masque + Pawn as guarded optional hooks (`FR-121`, `FR-122`); the rest skipped unless asked |

**Reopen triggers:** `core/db.lua` profiles becoming a recurring bug source (AceDB alone would be
defensible), or a minimap button request recurring in feedback.

## Q3 — Can a section hold multiple categories? — **DECIDED: B, a section binds a list of categories**

The measured configs settle it (`docs/01`): 6–8 sections per profile bind more than one category,
including `Elements{5}`, `Enchanting{5}`, `Metals and Ores{2}`. "One block, several kinds of thing"
is not an advanced feature, it is how the config is actually written.

Consequences, all of which must move together:
- `docs/04`: `section.categories = { … }`.
- Precedence is **unchanged**: ownership is still decided globally by category priority. Several
  categories in one section is a *display* grouping, never a precedence rule (`docs/04` §Precedence 7).
  This is the sentence that keeps the model from becoming Baggins' ordering puzzle.
- `docs/05` §Screen 4: the section editor is a combo box + sortable list, exactly as asked for.
- `layout/flow` must size a block whose contents come from N categories.
- Baggins' `section.cats` maps 1:1 if we ever do migration (moot — Q5).

## Q4 — Do we hook Blizzard's bag functions? — **open, decide at M2 with the installed addons running**

Baggins raw-hooks `OpenAllBags`, `ToggleAllBags`, `ToggleBackpack`, `OpenBag`, `OpenBackpack`,
`ToggleBag` so other addons' "open bags" opens *our* windows. It is what makes a bag addon feel
native, and it is the most taint-prone code in either reference repo.

| Option | Consequence |
|---|---|
| A. Hook them (Baggins-style) | other addons' `OpenAllBags()` works; highest taint/combat risk |
| B. Own keybinds + our own vanilla↔sorting toggle (`FR-51`) | no hooking; addons that call `OpenAllBags()` directly open stock bags alongside ours — which is *survivable* because we can show the vanilla bags on purpose |
| C. Hook only the bag-bar button click / `BackpackOpenButton` | middle ground |

**Recommendation:** **B**, plus `FR-51`. The vanilla↔sorting toggle changes the shape of this
question: we no longer need Blizzard's open functions to route to us, because we can give the player
the real bags whenever they want them. Add **C** at M6 only if real conflicts appear. Never A in v1.

**Taint note:** `ForeverPlus/Modules/BagWindow.lua` documents what happens when an addon calls
`ContainerFrameSettingsManager:GetBagsShown()` on this client — Blizzard's bag code ran tainted until
`UseContainerItem` was refused. Reading is not free.

**First-run matters (`FR-64`):** addons do not get to assume `B` is theirs. On first login, detect
that our toggle collides with the default bag keybind and point at the Key Bindings panel. Getting
this wrong is the #1 way a bag addon gets uninstalled.

**Needed:** M2 in-game test with `ForeverPlus`, `Leatrix_Plus` (which can
`hooksecurefunc('OpenAllBags', CloseAllBags)`), `Baggins` and `BetterBags` each loaded.

## Q5 — Baggins migration — **DECIDED: deferred, no importer in v1**

Bagnon/AdiBags/AdiBags-class addons are where the users are; Baggins' userbase is smaller and its
config shape is the thing we are deliberately not preserving. Ship **two sensible default profiles**
(a "classic-ish" one modelled on the shapes in `docs/01`, and a minimal one) and skip migration.

`docs/04`'s migration table stays as the answer to "if we ever do it", so the thinking is not lost.

## Q6 — Export format — **DECIDED: model dump**

`BOS1.<base64(serialize({windows, sections, categories}))>`, imported as **one** `import.apply`
command so it is validated, atomic and undone by one Undo. Diff shown before Apply.

## Q7 — Is the search DSL in v1, and can we reuse Blizzard's search instead?

**Blizzard's search is not reusable as our index.** On this client the bag search is
`ItemButtonUtil.GetItemContextMatchResultForItem(itemLocation)` — a per-item predicate used to
dim/hide buttons over inventory the client already knows. It has no result list, cannot see a closed
bank, cannot see an alt, and `GetItemContextMatchResultForContainer` is absent on camelot
(`agents.md`). So: our own index is required for anything beyond "filter what is on screen".

What we *do* reuse is the matcher, where it applies, so our search and the client's agree about what
"matches" means (`FR-50`).

The DSL itself stays **Should**, land in M6, capped to the FR-28 field subset. If M3's chip editor
turns out to cover what people actually try to express, cut the DSL and spend the time on dynamic
categories instead.

**Needed:** evidence from the M3 human tests — specifically, rules people tried to build and could
not express as chips.

## Q8 — Is `kind = "dynamic"` (group-by-type/subtype/expansion) Must?

Concrete example of what it is, since it is hard to picture from the words. In BetterBags, a
category `Tradeskill` with `groupBy = subtype` produces, by itself, sections named *Herbs*, *Ores*,
*Cloth*, *Leather*, *Gems*, *Elemental* — one per distinct subtype among your items — each holding
the matching items, each individually pinnable/hideable, none of them configured. Change one setting
on one category and six sections appear.

Why it is attractive here: the measured Baggins config hand-builds exactly this with 20 categories
(`Tradeskills.Enchanting`, `.TBC`, `.Wrath`, `.Cata`, `.Mop`, `Tradeskills.Elements.*`) and 22
sections in one window. A dynamic category is that, in one setting.

Why it is dangerous here: it makes sections the user *did not create* appear inside a window whose
whole point is "this is the window you made".

**Recommendation:** **Must, but scoped**: a dynamic category expands into sections inside exactly one
window, named `<parent> — <value>`, individually only *disabled* or *moved* (never reconfigured), and
visually marked as generated. Anything more is v2.

**Needed:** decision confirmed before M5, because if it drops, `docs/04`'s classify-time expansion
step disappears and M5 shrinks.

## Q9 — Do we hide the Blizzard bags bar? — **reframed: we don't need to**

`FR-51` (vanilla↔sorting toggle) removes most of the reason to hide anything: the stock bar stays,
it becomes the switch. BetterBags reparents `BagsBar` to a sneaky frame; on this client the bar is
`Blizzard_MainMenuBarBagButtons/Camelot` and `ForeverPlus` already writes numbers on
`MainMenuBarBackpackButton`, so the bar is both reachable and contested.

**Recommendation:** keep the bar visible, add our toggle to it (or beside it), and hide only
Blizzard's *bag windows* while our windows are shown — hiding windows is a `SetShown` on a frame we
are not using, which is a different risk class from reparenting a protected bar. Test at M2; if
`SetShown` on container frames causes lockdown complaints, leave them visible and accept the cosmetic
loss. A visible stock button is a cosmetic loss; a blocked `UseContainerItem` is a functional one.

## Q10 — Forever container facts we still do not know

Partly answered by reading `origin/forever` (2026-10-15):

| Fact | Status | Evidence |
|---|---|---|
| Keyring exists | **yes, expect it** | `Blizzard_MainMenuBarBagButtons/Camelot/MainMenuBarBagButtons.lua` uses `KEYRING_CONTAINER`, `GetKeyRingSize`, `PutKeyInKeyRing` |
| Reagent bag slot exists | **yes, present** | `CharacterReagentBagMixin:GetSlotAtlases()` in the Camelot bag-buttons file; `ForeverPlus/Modules/BagSlots.lua` counts it as a special bag |
| Bags start **combined** into one window | **yes** | `ContainerFrameCombinedBags`, `IsUsingCombinedBags` (ForeverPlus `BagWindow.lua`) |
| `C_Bank` exists with `FetchNumPurchasedBankTabs`, `IsItemAllowedInBankType`, `FetchDepositedMoney` | **yes** | `Blizzard_APIDocumentationGenerated/BankDocumentation.lua` on `origin/forever` |
| `NUM_TOTAL_EQUIPPED_BAG_SLOTS` value, bank-bag index range | **unknown** | in-game only |
| Whether inert `Enum.BagIndex.AccountBankTab_N` errors or returns 0 in a harvest loop | **unknown** | in-game only |
| `AddonCompartment` available | **yes** | `Blizzard_Minimap/Blizzard_Minimap.toc`: `AddonCompartment.lua [AllowLoadGameType mainline]`, no camelot exclusion |
| `/script` available for testing | **yes, gated** | `Blizzard_ChatFrameBase/Shared/SlashCommands.lua`: `SCRIPT` → `RunScript`, gated by `C_GameRules.IsGameRuleActive(Enum.GameRule.UserScriptsDisabled)` and a one-time dangerous-scripts popup. `/dump`, `/eventtrace`, `/framestack`, `/api` also present |

**Recommendation:** unchanged — M0's `/bos` capability dump answers the rest in one run, and every
container loop iterates a **discovered** list built at load, never a hardcoded constant. Update
`agents.md` with the results.

## Q11 — Profile default, and can profiles inherit?

**Recommendation:** **shared Default + per-character override that stores only the differences.**
Reason: a bag layout is a personal habit, not a class-specific need, and per-character defaults
create the "I configured it on my mage and my warrior is a mess" complaint.

The inheritance question the shared model raises is real and worth designing deliberately:

- What users want is *"my warrior's layout is my mage's layout plus a War section, and my bank
  windows are the same on every character"*.
- The dangerous version is runtime inheritance — edit Default, eleven characters change, nobody knows
  why, and a per-character override that "inherits" a category silently re-appears when Default
  changes.
- The safe version, in order of preference:
  1. **Copy with provenance** (`window.copyFrom`, already in `docs/04`) — one action, no spooky link.
  2. **Explicit re-copy** — "pull the Herbs category from Default into this character's profile",
     shown as a command with an inverse.
  3. Runtime inheritance — only if 1 and 2 demonstrably fail. If we ever do it, it is a field with
     its own semantics and its own UI indicator, never an implicit default.

"Send to X" sections (a section whose purpose is *deposit here* rather than *display here*) belong to
the bulk-action work in M6, not to profiles: they are a command target, not an inheritance mechanism.

## Q12 — Do we ship a plugin API?

`FR-32` says Won't for v1. Internal boundaries (`data` never touches frames, field registry is data,
presets are data) make it possible later. Nothing official for v1; once stable, category plugins are
worth supporting. Write the docs page only when someone actually wants to build one.

## Q13 — How deep do we go with Blizzard EditMode?

| Option | What you get | Cost / risk |
|---|---|---|
| A. EventRegistry only (ThreatMeter-style) | Enter/Exit callbacks, selection template, manual magnetism + snap preview | proven on this client; no EditMode layout save/restore for our windows |
| B. Also `EditModeManagerFrame:RegisterSystemFrame(frame)` | EditMode treats our window as a system: enter/exit calls, anchor tracking, possibly layout save/restore | undocumented, absent from `C_EditMode`, and EditMode's layout system assumes one frame per named *system* — our windows are user-created and variable in count |

**Recommendation:** **A**, plus an M2 spike on B for one window. Two extra things the spike must
answer, because `docs/05` now depends on them:

1. Is `EditModeSystemSettingsDialogButtonTemplate` reachable for a frame we registered, and can it
   carry our columns/scale/compact controls? If not, those controls live only in the window's context
   menu and `FR-71` is downgraded to Should.
2. EditMode's own **Bags** system on this client is the bag *button bar*, not the bag window
   (`ForeverPlus/Modules/BagWindow.lua`). Do not let our UI imply that EditMode's "Bags" entry is us.

If B works cleanly it is a real win. If it fights us, stay on A permanently and never mention
EditMode layouts in our UI. **Do not build UI that assumes B.**

## Q14 — Distribution — **DECIDED**

GitHub first (`https://github.com/SterlingNerd/BagsOfSorting.git`), CurseForge project `1745962`,
Wago `bGoYJY60`. Publish once something marginally usable exists (M7), with `## X-Curse-Project-ID`
and `## X-Wago-ID` already in the TOC. License: WTFPL (`LICENSE` at repo root, `## X-License: WTFPL`).

---

## Q15 — How much inventory do we persist? (bank / alts / guild bank)

The extended search features all hit the same wall: **there is no API to read an inventory the client
does not currently know.** Bank contents arrive when the bank is opened; another character's bags are
not on this client at all; the guild bank needs the guild bank UI and permissions.

| Feature | Possible without persistence? | With persistence |
|---|---|---|
| Search bank while closed (`FR-110`) | **yes**, after the bank has been opened once this session — the client keeps the container data | session-only is enough for v1.x |
| Search alts / alt banks (`FR-111`) | **no** | requires a per-character snapshot written by each character that ran the addon (the Bagnon/BagSync model) |
| Guild bank (`FR-112`) | after `GUILDBANKFRAME_OPENED` | same question |
| Providing a Bagnon-compatible `AllInventory` to other addons | no | same snapshot, published under Bagnon's global names |

Options: (a) session-only, honest "bank not known yet" messaging; (b) persisted per-character snapshot
of itemIDs + counts only (no names — we can resolve names from the item cache); (c) full persisted
snapshot including location.

**Recommendation:** (a) for v1.x, (b) as the v2 design, and never (c). A snapshot of itemIDs and
counts is ~1–3 KB per character and is the only part that answers "do I have this anywhere"; location
data is where the SavedVariables bloat and the privacy discomfort come from. Ship the honest
"not known yet" message rather than a fake-complete result — that is a feature, not a gap.

**Needed:** decision before any cross-character feature is scheduled.

## Q16 — Themes — **DECIDED: no theme system, use the client's own bag visuals**

Build windows and item buttons from `ItemButton` / `ContainerFrameItemButtonTemplate` / the client's
bag atlases, and let whatever skinning addon the user runs (Masque or its successor) do its job on our
bags the way it does on Blizzard's. Delete `themes/` from the file tree, delete `settings.theme`,
delete FR-49's "two built-in looks".

What this buys: zero theme code, zero theme maintenance, and the skinning ecosystem works for free.
What it costs: no "dark flat" look for users who run no skinning addon. Accepted.

**Needed:** M2 check (`AC-49`) that Masque actually reaches our buttons; if it does not, the reason
gets written down rather than a theme system being invented to compensate.

## Q17 — Is dependency injection worth it for the client module? — **DECIDED: no**

`core/client.lua` is a resolved table of ~10 answers computed once at load, not a service. The
if-statements are already removed by (1) flags resolved once, (2) table-inert gating — a missing
capability means the table that would drive the feature is never built, (3) value getters where
things differ in kind (`itemButtonType`). Injecting an adapter per module adds a second name for the
same table, a wiring step, and a new bug class, in a language where "DI" would be manual wiring in
the load order we already have. Full reasoning: `docs/03` §Is dependency injection worth it here?

If a second client is ever real, the upgrade is **one data table per client plus a few function
overrides where behaviour genuinely differs** — still data, still one file.

---

## Decisions needed **before M0 commits**

Q1 (name) and Q3 (section ↔ categories) are decided. Q2, Q5, Q6, Q14, Q16, Q17 are decided.
Q8 (dynamic categories) must be confirmed before M5. Everything else is decided at the milestone that
needs it: Q4/Q9/Q13 at M2, Q7 at the M3→M4 boundary, Q15 before any cross-character feature.
