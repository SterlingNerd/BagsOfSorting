# Bags of Sorting

A bag addon for **World of Warcraft: Forever** (Camelot) that keeps the *Baggins* feel — several
separate bag windows, each split into labeled sections, plus user-defined custom bags — and
fixes the thing Baggins is bad at: configuring it.

Status: **prototype (M0 + M1 done, M2 in progress).** The pipeline runs — harvest → enrich →
classify → assign → sort → render — on the Forever client, and renders three windows (Backpack,
Quests, Tools) stacked above the client's bags bar. The configuration UI that is this project's
reason to exist is still spec. Start with
[`docs/00-vision-and-scope.md`](docs/00-vision-and-scope.md), review
[`docs/02-requirements.md`](docs/02-requirements.md) and
[`docs/05-config-ui.md`](docs/05-config-ui.md) (the two docs that decide whether this is worth
building), then [`docs/06-milestones.md`](docs/06-milestones.md) for the build order.

### What exists today

```bash
lua5.1 tests/run.lua   # 58 headless checks: rule grammar, precedence, sort modes, flow, pipeline
luacheck .             # CI runs both
```

In-game: `/bos` (capability dump + harvested containers), `/bos perf`,
`/bos show|hide|refresh|debug|help`. See the open draft PR for what is proven and what is only
written down.

Name is plural on purpose: the product *is* several bags. `BagsOfSorting`, `BagsOfSortingDB`, `/bos`.

---

## The itch

Baggins (`../addons/Baggins`) gives you a genuinely better inventory *shape* than stock bags:

- multiple independent bag windows instead of one long strip
- each window split into labeled **sections**
- **custom bags** — you define a window ("Crafting", "Collections", "Sell") and say which
  categories land in it
- rule-based categories (quality, item type, expansion, tooltip text, item name, …)

It is also 13,000 lines of Lua whose configuration is a **waterfall of nested AceConfig
dialogs**: to move a section you open *Bag/Category Config*, pick a bag from a dropdown, click
`^`/`v`/`X` buttons, add a rule from a dropdown of rule types, then close the dialog and open
your bags to see whether the rule did what you meant. There is no preview, no feedback, no
explanation of why an item is where it is.

And the configs people actually build are big. A long-lived personal Baggins setup runs to **dozens of
categories, a few hundred rules, ~12 windows and over a hundred sections** — a set of purpose windows
and a near-mirror set of bank windows (`docs/01`). That is the config this UI has to make manageable.

BetterBags (`../addons/BetterBags`) proves the other half is solvable: a real settings window
built from a form system, drag-a-category-to-pin, search-based categories, import/export strings,
profiles. But it collapses your inventory into one category grid — you lose the multi-window,
per-bag control that made Baggins worth using.

**This addon is the intersection:** Baggins' windows/sections/custom-bags model, with a config
UI where you edit the layout *on the bags themselves* and every rule shows you, live, which of
your items it matches.

## The one-line thesis

> Configure the inventory by manipulating the inventory, not a settings tree.

Taken seriously, that means: **there is no config window for organizing.** Windows, sections,
categories and rules are edited on the bags — context menus, in-place names, drag, and a handful of
small modals whose body is your real inventory. Blizzard's EditMode carries window placement and the
boring numeric knobs. One small utility window survives for the four things with no physical
counterpart: find, presets, import/export, profiles.

## Planned surface

```
/bos            toggle configure mode — the bags become the editor
/bos settings   the utility window: find, presets, import/export, profiles
/bos configure  same as /bos, explicit
/bos move       arrange our windows inside Blizzard's own EditMode ("move mode") on Forever
/bos why        click an item to see which category/rule placed it
/bos perf       per-phase timings, pool stats, item-data requests
/bos test       self-test the classifier against fixture items
```

Undo is a button, not `Ctrl+Z` — those keys sit next to WASD and are plausibly someone's spell or
macro. Keybinds live in the client's own Key Bindings panel, and the first-run experience has to deal
with the fact that `B` is already taken.

**No vendored libraries.** Forever ships every widget we need (`WowScrollBox`, `MinimalScrollBar`,
`WowStyle1DropdownTemplate`, `UISliderTemplate`, `SearchBoxTemplate`, `ButtonFrameTemplate`,
`StackSplitFrame`, `UIDropDownMenu`, `IconDataProviderMixin`), and Forever's EditMode is joinable by
addons — ThreatMeter already does it here (`../addons/ThreatMeter/editmode.lua`). We build the
profile store and the form layer ourselves rather than carry Ace3, and we say out loud what that
costs (`docs/07` Q2): no minimap icon at all — refused, not deferred — and Masque/Pawn as opt-in hooks
rather than free rides on shared libraries. Settings that genuinely need a window go in the client's
own **Options → AddOns** panel, which Forever ships (`docs/07` Q2, `FR-88`).

**No theme system.** The windows are built from Blizzard's own bag visuals, so whatever skinning
addon you run works on our bags too (`docs/07` Q16).

![project icon](Media/Icon.png)

---

## Docs

| Doc | Review it for |
|---|---|
| [00 vision & scope](docs/00-vision-and-scope.md) | are we solving the right problem, what's deliberately out |
| [01 reference analysis](docs/01-reference-analysis.md) | what we steal from Baggins / BetterBags and what we refuse |
| [02 requirements](docs/02-requirements.md) | numbered FR/NFR, priorities, acceptance criteria |
| [03 architecture](docs/03-architecture.md) | modules, pipeline, file tree, load order |
| [04 data model](docs/04-data-model.md) | SavedVariables schema, rule grammar, export format |
| [05 config UI](docs/05-config-ui.md) | the actual UX design — the reason this project exists |
| [06 milestones](docs/06-milestones.md) | build order, exit criteria, in-game test checklists |
| [07 open questions](docs/07-open-questions.md) | the decisions, each with a recommendation or a decision |

Open work lives in **[GitHub issues](https://github.com/SterlingNerd/BagsOfSorting/issues)**, not in a
docs file: eight `spike` issues hold the runnable `/script` checks that must be answered before the code
that depends on them is written (`docs/07` Q21).

## License

WTFPL — see [LICENSE](LICENSE). Do what the fuck you want to public license. `## X-License: WTFPL`
in the TOC once it exists.

Publishing: GitHub (`SterlingNerd/BagsOfSorting`), CurseForge project `1745962`, Wago `bGoYJY60` —
uploaded once something marginally usable exists.

## Contributing to the spec

Edit the doc that owns the decision, not the code. Requirements are numbered (`FR-12`) so
review comments can point at one line. Open questions carry a recommendation — disagreeing means
updating that entry with the alternative you'd take and why.
