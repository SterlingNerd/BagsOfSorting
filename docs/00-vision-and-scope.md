# 00 — Vision & Scope

## Problem statement

Bag addons split into two camps, and each one gives up something the other has.

**Camp A — Baggins (`../addons/baggins`).** Virtual bags: you define N windows, each window
contains sections, each section displays one or more categories, categories are defined by rules.
You get a physical-feeling, per-window organization and you can build a window that means
something to *you* ("Outland", "Sell", "Crafting"). Cost: configuration is a 4,800-line AceConfig
option tree with no feedback loop.

**Camp B — BetterBags (`../addons/BetterBags`).** One category grid per window (backpack / bank),
excellent config panes, drag-to-pin, search DSL, search-derived categories, import/export,
profiles. Cost: your inventory is a flat list of categories. You cannot say "this window is my
crafting window and it is 10 wide and only ever shows crafting + reagents".

We want Camp A's shape and Camp B's ergonomics. Neither addon is a base to fork: Baggins' config
layer is the problem we are solving, and BetterBags' data model is a single-window grid from the
floor up.

## Design thesis

1. **The layout is the config.** If a user can rename a section by clicking its title in the bag,
   reorder it by dragging it, and add an item to a category by dragging the item onto it, then
   most configuration needs no settings window at all.
2. **Every rule must show its consequence.** Editing a rule shows the live list of your items it
   matches, before you commit. No more "change rule → close dialog → open bags → squint".
3. **Every placement must be explainable.** Any item can answer "which category, which rule,
   which window, and what else was competing for it". This turns debugging into reading.
4. **Explicit precedence beats order-dependent chaining.** Baggins' rules are a flat list whose
   meaning depends on each rule's `OR`/`AND`/`NOT` slot and its position. We use an explicit
   `any / all / none` tree that can be rendered as one readable sentence.
5. **Small surface, no hidden knobs.** A setting that has no place in the UI does not get added.

## What "improve on the configuration toil" means concretely

Measured against Baggins as it exists today:

| Baggins today | Target |
|---|---|
| 2 separate option tables (`Baggins`, `BagginsEdit`), waterfall dialogs | the client's own **Options → AddOns** panel, a handful of flat panes, no nesting deeper than pane → row |
| reorder via `^` / `v` / `X` execute buttons in a scrollable group | drag the section header in the bag |
| add a rule: dropdown of 30 rule types → per-type sub-dialog → LibQTip dewdrop | one chip row: `+ rule` → field picker → value picker, with live match list |
| no preview of what a rule matches | right pane lists matching items + count, updates as you type |
| "why is this item in this section?" is unanswerable | item inspector names the category, rule chain and competitors |
| changing a rule requires a full re-sort of everything | incremental reclassify of the affected category only |
| 30 rule types each with bespoke `Ace3Options` + `DewDropOptions` | one rule grammar, one renderer, one editor |

## Scope tiers

| Tier | Meaning |
|---|---|
| **v1** | ships or the product is wrong |
| **v1.x** | extended features that need the v1 model to be right but no new model |
| **v2** | needs a model decision we are deliberately not making now |

## In scope (v1)

- Backpack and bank, Forever client first
- user-defined **windows** (custom bags): name, kind (backpack/bank), priority, columns,
  open-with-all, icon
- a bank window can be **created as a copy of a backpack window** and then diverge (`FR-10b`)
- **sections** inside a window: named, ordered, collapsible, hidden, movable between windows, each
  bound to **one or more categories** (`FR-11`, decided in `docs/07` Q3)
- **sections** inside a window: named, ordered, collapsible, hidden, movable between windows
- **categories**: rule-driven, manual item lists (bulk-pasteable), and dynamic
  ("group by type/subtype/expansion")
- rule grammar with `any/all/none` nesting and a fixed field set, where **item-ID lists and
  exclusions are first-class** — they are the most-used rule types and exclusions outnumber
  conjunctions several to one in real configs (`docs/01`)
- precedence + duplicate policy
- **configure mode: the bags are the editor.** Context menus, in-place text, drag, small modals.
  Options → AddOns is a browser/search tool for the settings that genuinely need a window, never the
  primary editor (`docs/05`)
- item inspector ("why is this here"), on Ctrl+right-click — naked right-click stays the game's item
  menu (`FR-60b`)
- stacking/compression of stacks **with the display choice left to the user**, empty-slot representation
- **quality/rarity and item-level presentation, with options** (`FR-45`, `FR-45b`) — required, not
  decoration; defaults look like stock bags
- new/recent item handling without Blizzard auto-sort (Forever has none), including a user-controlled
  policy for when the highlight clears (`FR-47`)
- **physical bag interaction**: a bag-bar toggle between vanilla bags and sorting bags, an *empty
  this bag* action, and category→specialty-bag **affinities** (`FR-51`, `FR-66`, `FR-67`)
- profiles (shared default + per-character override), export/import strings for categories+windows,
  and **linked windows** so a bank window keeps step with its backpack twin (`FR-10c`)
- undo of config edits
- an intro / help page, because "configure it by touching it" is not a UI anyone has met before
  (`FR-87`)
- a starter preset so a fresh install is useful in under a minute
- optional integrations that cost no vendored library: AddonCompartment, Masque, Pawn (`docs/03` §Integrations)

## Extended (v1.x)

- **search the bank while it is closed**, from a snapshot taken the first time the bank is opened
  this session (`FR-110`, `docs/07` Q15)
- **search alts, alt banks and the guild bank** — needs a persisted per-character item snapshot and
  a size/privacy decision. `docs/07` Q15 owns it; nothing in v1 may block it

## Out of scope (v1) — named so nobody quietly adds them

- **Retail/Classic Era/TBC/Cata/MoP support.** Forever first. The architecture keeps a client
  capability layer (`docs/03` §Client capability layer) so a second client is a layer, not a
  rewrite — but we do not build or test it now.
- **Our own theme system.** We build our windows on Blizzard's own bag visuals
  (`ContainerFrameItemButtonTemplate`, the `ItemButton` frame type, the client's bag atlases) so
  whatever skinning addon a user runs — Masque or its successor — skins our bags the way it skins
  theirs. No `themes/` module, no built-in "looks", no theme editor (`docs/07` Q16).
- **Reagent bank, warband bank.** They do not exist on Forever (`agents.md`).
- **Bag shopping UI.** Empty-bag, affinity compaction and gated bulk sell are in v1; buying and
  upgrading bags is the player's business, we only make the vanilla bags reachable.
- **Vendor integration beyond selling.** No price awareness, no restock logic, no merchant-specific
  behaviour. Auto-sell of a trash category or greys is v1.x (`FR-65b`), and it is the only vendor
  feature on the roadmap — vendor buyback is limited, so anything that sells in bulk stays gated.
- **A minimap icon.** Refused rather than deferred: the home is the Addon Compartment plus Options →
  AddOns, so LibDBIcon never enters the tree (`FR-123`).
- **Cross-character search as a feature of this addon.** Bank-while-closed is in scope for v1.x;
  alts, alt banks and guild banks read an existing maintained store when one is installed
  (`FR-111`), and a full "search everything offline" product is its **own addon** (`docs/07` Q15).
- **Auctioning, mail, crafting queue integration.**
- **Tooltip replacement.**
- **Localization beyond enUS.**
- **A plugin API for third parties.** Internal module boundaries are designed so a plugin API is
  possible later; we do not ship or stabilize one.

## Success criteria (how we know it worked)

1. A new user with zero config gets a usable bag layout on first login (preset), and can name
   their first custom window without opening a settings dialog.
2. Creating a category that matches exactly the items you intend takes **one interaction chain**,
   not a dialog round trip: drag item → name category → see the match list → done.
3. No config action requires knowing a term we invented. If the UI says "section", the UI also
   shows what a section is the first time you can change one.
4. `docs/02-requirements.md` Must items all have a passing in-game checklist entry in
   `docs/06-milestones.md`.
5. Config changes are visible in the bags in < 250 ms for a full backpack (measured, not hoped).
6. A Baggins-scale layout — dozens of categories, a few hundred rules, ~12 windows with a mirrored
   bank half (`docs/01`) — can be rebuilt here without ever opening a settings window.

## Non-goals that are not omissions

- We are not trying to be faster than Baggins at the expense of clarity; a 20 ms slower refresh
  that explains itself is a win.
- We are not trying to be feature-equal to BetterBags. Its grid is a different product.
- We are not preserving Baggins' SavedVariables. Migration is **deferred** (`docs/07` Q5): ship
  good default profiles instead. If anything is migrated later, the target is Bagnon/AdiBags-shaped
  data, not Baggins'.
