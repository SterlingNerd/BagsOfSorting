# Bag of Sorting

A bag addon for **World of Warcraft: Forever** (Camelot) that keeps the *Baggins* feel — several
separate bag windows, each split into labeled sections, plus user-defined custom bags — and
fixes the thing Baggins is bad at: configuring it.

Status: **spec / pre-code.** This repo currently contains the design, not the addon. Start with
[`docs/00-vision-and-scope.md`](docs/00-vision-and-scope.md), review
[`docs/02-requirements.md`](docs/02-requirements.md) and
[`docs/05-config-ui.md`](docs/05-config-ui.md) (the two docs that decide whether this is worth
building), then [`docs/06-milestones.md`](docs/06-milestones.md) for the build order.

---

## The itch

Baggins (`../addons/baggins`) gives you a genuinely better inventory *shape* than stock bags:

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

BetterBags (`../addons/BetterBags`) proves the other half is solvable: a real settings window
built from a form system, drag-a-category-to-pin, search-based categories, import/export strings,
profiles. But it collapses your inventory into one category grid — you lose the multi-window,
per-bag control that made Baggins worth using.

**This addon is the intersection:** Baggins' windows/sections/custom-bags model, with a config
UI where you edit the layout *on the bags themselves* and every rule shows you, live, which of
your items it matches.

## The one-line thesis

> Configure the inventory by manipulating the inventory, not a settings tree.

## Planned surface

```
/bos            open the settings window
/bos configure  toggle on-bag edit mode (rename, reorder, drag items to categories)
/bos move       move our windows inside Blizzard's own EditMode ("move mode") on Forever
/bos why        click an item to see which category/rule placed it
/bos test       self-test the classifier against fixture items
```

**No vendored libraries.** Forever ships every widget we need (`WowScrollBox`, `MinimalScrollBar`,
`WowStyle1DropdownTemplate`, `UISliderTemplate`, `SearchBoxTemplate`, `ButtonFrameTemplate`,
`StackSplitFrame`, `UIDropDownMenu`), and Forever's EditMode is joinable by addons — ThreatMeter
already does it here (`../addons/ThreatMeter/editmode.lua`). We build the profile store and the
form layer ourselves rather than carry Ace3.

No screenshots yet — there is no UI to screenshot. Placeholder for M3+.

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
| [07 open questions](docs/07-open-questions.md) | the decisions that need a human answer |

## Contributing to the spec

Edit the doc that owns the decision, not the code. Requirements are numbered (`FR-12`) so
review comments can point at one line. Open questions carry a recommendation — disagreeing means
updating that entry with the alternative you'd take and why.
