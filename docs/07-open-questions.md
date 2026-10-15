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
- **Forever ships the modern addon settings API** (`Settings.RegisterAddOnCategory`,
  `RegisterVerticalLayoutCategory`/`RegisterCanvasLayoutCategory`, `CreateCheckbox`/`CreateSlider`/
  `CreateDropdown`, `RegisterProxySetting`/`RegisterAddOnSetting`, `SetKeybindingsCategory`,
  `RegisterModifiedClickSetting`), verified 2026-10-08 in `Blizzard_Settings_Shared/Blizzard_Settings.lua`
  with Blizzard's own guide in `Blizzard_ImplementationReadme.lua`. **My earlier claim that Forever has
  only `C_SettingsUtil` was wrong.** This does not change the decision — it removes the only honest
  argument for ever wanting AceConfig here (`FR-88`).
- Not vendoring Ace3 removes the `AceEvent30Frame` class of `ADDON_ACTION_FORBIDDEN` that bit this
  workspace (`../TODO.md`).

**AceConfig is refused on its own merits, not because it is unavailable.** It is the part of Baggins
that hurts most in practice: its layout engine wraps, truncates and reflows long section and category
names, which is exactly what a config with dotted hierarchy names and 20-section windows produces.
A UI whose whole idea is "edit the bag you are looking at" cannot be built in it. Stated once so
nobody re-litigates it: the cost is that we never appear inside anyone else's aggregated options
suite, and no addon installed here aggregates option trees anyway.

What we give up, honestly — this is the part the "avoid dependencies" rule used to hide:

| Lost habit | Real consequence | Replacement |
|---|---|---|
| LibDataBroker + LibDBIcon minimap icon | Baggins/Bagnon users look for a draggable minimap icon; broker-display addons (Titan-class) cannot host us | `## AddonCompartmentFunc` + `## IconTexture` and Options → AddOns. **We are not building a minimap icon at all** (`FR-123`) — no LibDBIcon, ever, unless a real request appears |
| AceConfig option tables | we do not appear inside someone else's aggregated options suite | the client's own Options → AddOns panel (`FR-88`) |
| LibQTip dewdrops | Baggins' rule-editing hover panels | `UIDropDownMenu`/`EasyMenu` + `TooltipBackdropTemplate` popovers |
| LibPeriodicTable curated lists | the most-used named-set rules in real configs depend on them (`docs/01`) | our own preset data as `itemID in {…}` categories, **user-editable**, because LibPeriodicTable has not been meaningfully updated in years and cannot describe items Forever adds (`FR-31`) |
| LibBagUtils / LibWindow / LibSharedMedia / LibItemUpgradeInfo | bag slot counting, saved positions, media, upgrade arrows | `C_Container.GetBagSlotFlag`, own positions, no custom fonts, Pawn integration (`FR-122`) |
| Masque / Pawn / ConsolePort / QuickFind | skinning, upgrade arrows, gamepad, cross-addon search | Masque and Pawn as guarded optional hooks **later, not requirements** (`FR-121`, `FR-122`, `FR-125`); the rest skipped unless asked |

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

**The mental model worth writing down, because that is where the confusion lives.** Our bags are a
*view* over real containers: harvest reads real slots, classification decides where each item is
*drawn*, and we already hold the map `item → (window, section, button)` because rendering needs it.
Search is that map run in reverse — a query in, a set of buttons out. So "the addon knows where
everything is" is true **for inventory the client currently knows**, and that is the whole of it. The
limit is not our data structure; it is that a closed bank and another character's bags have no data on
this client to map.

What Blizzard gives us for free is the *predicate*, not an index:

- `BagSearch_OnTextChanged` syncs text across `BagItemSearchBox` / `BankItemSearchBox` /
  `GuildItemSearchBox` and calls `C_Container.SetItemSearch(text)`; buttons answer
  `ItemButtonUtil.GetItemContextMatchResultForItem(ItemLocation:CreateFromBagAndSlot(bag, slot))` and
  dim themselves.
- That is a per-button filter over known inventory. No result list, no closed bank, no alts, and
  `GetItemContextMatchResultForContainer` is absent on camelot (`agents.md`).

So: **drive the client's search and reuse its matcher** (`FR-50`) so our search and the game's agree,
then add our own fields (type, quality, ilvl, expansion, category) on the enriched record. Anything
that reaches beyond the open bags is a snapshot problem (`FR-110`+, Q15) and gets its own UI, not a
filter bolted onto the bag bar.

The DSL itself stays **Should**, land in M6, capped to the FR-28 field subset. If M3's chip editor
turns out to cover what people actually try to express, cut the DSL and spend the time on dynamic
categories instead.

**Needed:** evidence from the M3 human tests — specifically, rules people tried to build and could not
express as chips.

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

**And borrow its position (`FR-41`).** Where the player put the bag bar *is* where they want their
bags. Our windows anchor off `BagsBar` / `MainMenuBarBackpackButton` by default, so a fresh install
lands where the game already puts them and a player who arranged their UI keeps the arrangement. If we
ever ship our own bar of sorting-bag buttons, it takes the same anchor.

## Q10 — Forever container facts we still do not know

Partly answered by reading `origin/forever` (2026-10-15):

| Fact | Status | Evidence |
|---|---|---|
| Keyring exists | **yes, expect it** | `Blizzard_MainMenuBarBagButtons/Camelot/MainMenuBarBagButtons.lua` uses `KEYRING_CONTAINER`, `GetKeyRingSize`, `PutKeyInKeyRing` |
| Reagent bag slot exists | **yes, present** | `CharacterReagentBagMixin:GetSlotAtlases()` in the Camelot bag-buttons file; `ForeverPlus/Modules/BagSlots.lua` counts it as a special bag |
| Bags start **combined** into one window | **yes** | `ContainerFrameCombinedBags`, `IsUsingCombinedBags` (ForeverPlus `BagWindow.lua`) |
| `C_Bank` exists with `FetchNumPurchasedBankTabs`, `IsItemAllowedInBankType`, `FetchDepositedMoney` | **yes** | `Blizzard_APIDocumentationGenerated/BankDocumentation.lua` on `origin/forever` |
| `NUM_TOTAL_EQUIPPED_BAG_SLOTS` value, bank-bag index range | **unknown, and now known to be a trap** | `Enum.BagIndex` on Forever has **no `BankBag_*` values** (27 values: `Keyring -1`, `Backpack 0`, `Bag_1..4`, `ReagentBag 5`, `CharacterBankTab_1..9 = 6..14`, `AccountBankTab_1..9 = 15..23`), yet `Blizzard_UIPanels_Game/Camelot/BankFrame.lua:26` computes bank bags as `bagSlot + ITEM_INVENTORY_BANK_BAG_OFFSET` where that offset is `NUM_TOTAL_EQUIPPED_BAG_SLOTS`. If that is 5 here, bank bags land on the bank-tab indices. In-game only — issue #2 |
| Whether the client still answers bank container indices after the bank closes | **unknown, and it decides `FR-110`** | if yes, closed-bank search is free; if no, it is cut. Issue #2 |
| Whether inert `Enum.BagIndex.AccountBankTab_N` errors or returns 0 in a harvest loop | **unknown** | in-game only |
| `AddonCompartment` available | **yes** | `Blizzard_Minimap/Blizzard_Minimap.toc`: `AddonCompartment.lua [AllowLoadGameType mainline]`, no camelot exclusion |
| `/script` available for testing | **yes, gated** | `Blizzard_ChatFrameBase/Shared/SlashCommands.lua`: `SCRIPT` → `RunScript`, gated by `C_GameRules.IsGameRuleActive(Enum.GameRule.UserScriptsDisabled)` and a one-time dangerous-scripts popup. `/dump`, `/eventtrace`, `/framestack`, `/api` also present |

**Recommendation:** unchanged — M0's `/bos` capability dump answers the rest in one run, and every
container loop iterates a **discovered** list built at load, never a hardcoded constant. Update
`agents.md` with the results.

## Q11 — Profile default, and can profiles inherit? — **DECIDED: shared Default + copy + explicit link**

**Default:** **shared Default + per-character override that stores only the differences.** A bag layout
is a personal habit, not a class-specific need, and per-character defaults create the "I configured it
on my mage and my warrior is a mess" complaint.

Most of a real config *should* be shared — categories especially, and the bank half of the layout. The
question is how to share without spooky action at a distance.

- What users want is *"my warrior's layout is my mage's layout plus a War section, and my bank windows
  are the same on every character"*.
- The dangerous version is runtime inheritance — edit Default, eleven characters change, nobody knows
  why, and a per-character override that "inherits" a category silently re-appears when Default
  changes.
- The safe version, in order of preference:
  1. **Copy with provenance** (`window.copyFrom`, `docs/04`) — one action, no spooky link. This alone
     answers most of it.
  2. **Explicit link** (`window.link`, `FR-10c`) — for the one case where copying alone is genuinely
     wrong: a bank window and its backpack twin. The link shares the **section list and its category
     bindings** and nothing else — not kind, columns, scale, position, compact or icon. Created by one
     deliberate action, shown on both window titles in configure mode, broken by one action that keeps
     the current shape. Editing a section on either side updates both, and the toast names the other
     window that changed.
  3. Runtime inheritance across profiles — only if 1 and 2 demonstrably fail. If ever, it is a field
     with its own semantics and its own UI indicator, never an implicit default.

`copyFrom` answers "how do I get the bank half"; `link` answers "keep them in step". Both ship in v1.
What does **not** ship is any inheritance the user cannot see on the window itself.

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

## Q15 — Offline search: bank while closed, alts, guild bank — **DECIDED: out of this addon entirely**

Earlier drafts of this spec carried a `snapshot` table, a closed-bank search feature, and a plan to read
BagSync or Altoholic. All three are deleted. Two things made that clear.

**First, `C_Bank` reads no items.** Its entire surface is tabs, money and locks —
`FetchPurchasedBankTabIDs`, `FetchNumPurchasedBankTabs`, `FetchMaxNumBankTabs`, `FetchDepositedMoney`,
`AutoDepositItemsIntoBank`, `IsItemAllowedInBankType`, `CanUseBank`, `CloseBankFrame`,
`UpdateBankTabSettings`. Bank contents arrive through the container API, exactly like backpack contents.
So there was never a second inventory system to build — only a question of whether to *cache* one.

**Second, the feature does not survive contact with why you would want it.**

1. **It ends in a trip to the bank anyway.** "You have 3 Linen Glyph in the bank" has one possible
   follow-up action: walk to a bank. An answer you cannot act on is trivia, and it is the weakest answer
   the question can have.
2. **It is incomplete by construction.** The item is just as likely to be in an alt's bank. Answering
   the question for one character is not answering it.
3. **It is a different problem.** "Do I have this thing anywhere" is a *database* question — it needs
   persistence, a results UI that is not a bag, and a privacy story. "Organise the stuff so I can
   manipulate it" is a *manipulation* question, and that is what this addon is. Merging them gives us a
   SavedVariables blob, a second UI paradigm inside the first, and a feature that still cannot find the
   item half the time.

**The split we chose instead: we own classification, an alt-database addon owns storage.** Our categories
and rule trees become plain versioned data behind `BagsOfSortingAPI` (`FR-113`, Q22). An addon that
persists what your characters have can then say "your mage has 4 items matching
`Tradeskills.Enchanting`" using *our* rules. That is smaller than a snapshot and worth more: it helps
every addon in that category instead of making us a worse version of one of them.

| Question | Answer |
|---|---|
| Search the open bags | v1, `FR-50` |
| Search the bank while the bank is open | v1, `FR-13` — it is the same harvest loop on different indices |
| Search the bank while closed | **out.** Not deferred — out |
| Search alts / alt banks | **out of this addon.** Belongs to an alt-database addon, which reads our classification via `FR-113` |
| Search the guild bank | **out.** Whether the guild bank is reachable as data at all is issue #11 — information that addon needs, not us |
| Bagnon-compatible `AllInventory` published by us | **out.** It cannot be honest without persisted per-character data, which `FR-109` forbids |

**Reopen trigger:** none inside this addon. If someone builds the alt-database addon and `FR-113` turns
out to be the wrong shape for it, that is a bug in `FR-113`, not a reason to start storing inventories here.

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

## Q18 — Do dotted category names cascade? — **DECIDED: yes, as an explicit group binding**

The idea: a section bound to `Tradeskills.Enchanting` should also pull in `Tradeskills.Enchanting.Dust`
and `Tradeskills.Enchanting.Essence`, so a family of categories is filed by one binding and adding a
child category needs no re-binding.

It is attractive because it is what the naming convention in `docs/01` already implies, and because it
scales the way a live game needs: a whole expansion's enchanting materials under one prefix, another
expansion under another, one section binding each.

**Decision:** binding a **group** is a distinct kind of binding (`Tradeskills.Enchanting ∗`,
`FR-11b`), resolved from names at classify time. Three rules keep it from becoming a trap:

1. **It is visible.** The section editor shows `∗` and how many categories it currently resolves to.
   A binding whose membership changes by itself is the exact thing people hate about bag addons.
2. **Renaming says what it does.** Moving `Tradeskills.Enchanting.Dust` to `Tradeskills.Mining.Dust`
   removes it from that section; the rename toast reports the section it left. Silent group exit is a
   support ticket.
3. **It is not inheritance for rules.** A child category does not inherit its parent's rule tree — the
   dot is a namespace, not a class hierarchy. Composition stays what it already is: a `category` leaf
   naming one category, or a group binding naming many.

This also shrinks the case for `kind = "dynamic"` (Q8): a lot of what dynamic categories were meant to
buy — "six sections appear from one setting" — is what a group binding plus a few real categories
already gives, with nothing appearing that the user did not create. **Q8 gets re-decided against this
before M5.**

## Q19 — Right-click is already taken. Where does our item menu go? — **DECIDED: Ctrl+right-click**

On bag item buttons the client owns: naked right-click (the stock item menu), `EXPANDITEM` and
`SPLITSTACK` via `OnModifiedClick` (shift by default, configurable in Interface Options), and
alt-click via `HandleModifiedItemClick` (inventory scan, link). Shift and alt are therefore both
claimed and both user-configurable, which makes them unusable as *our* modifier — we would be silently
changing a control the player set themselves.

**Decision:** our item menu is **Ctrl+right-click** (`FR-60b`), registered with
`Settings.RegisterModifiedClickSetting` so it appears in the client's own modified-click options and
the player can change it there. Naked right-click stays ours everywhere it does not collide: window
titles, section headers, category chips, our bag-bar buttons. That is why the design puts its menus on
headers and its item actions behind a modifier — the collision is real, and pretending otherwise is
how a bag addon gets uninstalled.

## Q20 — Does the "configless-config" idea need an explainer? — **DECIDED: yes, and it is a requirement (`FR-87`)**

A UI you configure by touching it is not a UI anyone has met before, and "there is no settings window"
sounds like a missing feature until it is explained. The help page (`docs/5` §Screen 8) carries the
three nouns, the four gestures, where each kind of setting lives, and what Undo means here.

**Timing:** after the PoC, before 1.0. Earlier and it describes a UI that does not exist yet; later and
it is documentation instead of onboarding. It also carries the first-run keybind-conflict note (Q4).

## Q21 — Where do spikes and plans live? — **DECIDED: GitHub issues, not a docs file**

`docs/08-test-plan.md` is deleted. Spikes (container index ranges, EditMode registration, Masque
reach, `RequestLoadItemDataByID` behaviour, coexistence runs) become GitHub issues with their
`/script` snippets in the issue body, because that is where results get recorded, closed and linked to
commits. Stabilised plans graduate into issues too. Docs keep *decisions*, issues keep *open work*.

## Q22 — Is our config a public API? — **DECIDED: yes, as data, and that is the whole extent of it**

`FR-113` exists because offline search left (`Q15`) and took the one genuinely interesting
cross-addon idea with it. An alt-database addon can store what your characters have; what it cannot
invent is what a *category* means. Ours is the thing it wants.

**What we publish** — one guarded global, `BagsOfSortingAPI`:

| Function | Purpose |
|---|---|
| `Version()` | lets another addon detect that our rule grammar changed before it misreads our data |
| `Categories()` | the category names in this profile |
| `Category(name)` | the rule tree, as plain data — the same structure the `BOS1.` export string carries |
| `Matches(itemID, categoryName)` | our classifier's answer for one item, without the caller reimplementing the grammar |
| `Export()` / `Import(string)` | the existing `BOS1.` string, exposed programmatically as well as by copy-paste |

**What we do not publish:** no plugin API (`FR-32` stays Won't), no event bus, no LibDataBroker feed, no
way for another addon to register a rule type, no hook into our rendering. Publishing *data* is a few
dozens of lines and a version number. Publishing an *extension point* is a support obligation forever.

Two consequences that must be honoured or the API is a trap:

1. **The rule grammar is now a public format.** `BOS1.` and `Category(name)` are the same shape, so a
   grammar change is a breaking change to someone else's addon. `docs/04`'s schema version and
   `Version()` are what make that survivable; a grammar change gets a version bump and a migration note,
   not a silent edit.
2. **`Matches` must agree with our own classifier.** One classifier, one entry point. If the API ever
   diverges from what the bags actually show, the API is a lie and should be deleted.

**Needed:** nothing before M6. Build it when the first real consumer exists — an API with no consumer is
just surface area. Issue #11 (is the guild bank reachable as data at all) is the nearest thing to a
consumer question we have.

---

## Decisions needed **before M0 commits**

Q1 (name), Q2 (dependencies), Q3 (section ↔ categories), Q5 (no migration), Q6 (export format),
Q11 (Default + copy + link), Q14 (distribution), Q15 (no offline search, no snapshots), Q16 (no themes),
Q17 (no DI), Q18 (group binding), Q19 (Ctrl+right-click), Q20 (help page), Q21 (issues not docs) are
decided. Q8 (dynamic categories) must be re-confirmed against Q18 before M5. Q22 (config as an API) is
decided in principle and built only when a consumer exists. Everything else is decided at the milestone
that needs it: Q4/Q9/Q13 at M2, Q7 at the M3→M4 boundary.
