# 09 — Section category bindings

Screen 4 — Section editor (`✎` on a section header in configure mode) currently binds categories
through a checkbox list. This spec replaces it with a token/pill editor: a textbox with validation
and syntax completion, wildcards, `!` excludes, green/red pills, a side list of categories to drag
from, and a right-click menu on pills.

## The binding language

A section's `categories` list stays an array of strings (docs/04); each string is one binding:

| Binding | Meaning |
|---|---|
| `Consumables` | Bind that exact category. |
| `Consumables.*` or `Consumables.` | Bind the whole dotted group — every category whose name starts with `Consumables.` (`Consumables.Food`, `Consumables.Water`, …). Resolved at classify time from live category names, so a category added later is bound automatically; renaming a category out of the prefix moves it out of the section. |
| `!Consumables.Potions` | Exclude: keep `Consumables` in the section but keep potions out of it. Excludes subtract from includes. |

Matching is case-insensitive while typing; bindings are stored canonically (real category name/case). `Unmatched Items` can be bound or excluded like any other category.

## Screen 4 — Section editor (revised)

```
┌ Section: Consumables ───────────────────────────── ⌫ ┐
│ name  [ Consumables                              ]  │
│                                                      │
│ bindings                                             │
│ ┌ Consumables ● ┌ !Consumables.Potions ✕ ┌ …        │  ← pills: green = include, red = exclude
│ │               │                        │          │    right-click pill: Include / Exclude / Remove
│ └───────────────┴────────────────────────┘          │
│ ┌ tr…                                           ┐   │   ← textbox: type a binding, Enter or comma commits
│ │ consumables.f…                                │   │    invalid token: red edge + reason, Save blocked
│ └───────────────────────────────────────────────┘   │
│                                                      │
│ ┌────────────────────────────────────────────────┐ │
│ │ Categories (drag here)                         │ │
│ │ ▸ Armor                                        │ │    bound categories tinted; click or drag adds
│ │ ▸ Consumables.Food   ●                         │ │    an include pill.
│ │ ▸ Consumables.Potions                          │ │
│ │ ▸ …                                            │ │
│ └────────────────────────────────────────────────┘ │
│                                                      │
│ ☐ allow duplicates   ☐ collapse by default    ☐ hidden │
│                  [ Cancel ] [ Save ]                 │
└──────────────────────────────────────────────────────┘
```

**Add textbox.** Type a category binding (`Consumables`, `Consumables.*`,
`!Consumables.Potions`) or an item ID, press Enter to commit it into the bound list below.
Input is canonicalized to real category case (e.g. `!equipment.*` → `!Equipment.*`) and
de-duplicated against what is already bound. Invalid bindings get red text and a chat warning.
Drag an item from your bags onto the add textbox to bind it by item ID.

**Bound items / categories list.** Flows like a comma-separated text area, wrapping to fit,
prefilled with the section's current bindings and item IDs. Green tint = include,
red tint = exclude, blue tint = direct item ID. Right-click any entry → Remove (context menu;
no X button).

**Search.** A box above the category browser filters the list as you type (25% narrower than
the left column). Categories already bound to the section — including wildcard children of an
excluded `*` group — are hidden from the browser. Clicking a row puts its name into the add
textbox.

**Save.** The bound list is split into `sectionConfig.categories` (category bindings) and
`sectionConfig.items` (direct item IDs), validated, and written back;
`db.NotifyModelChanged()` + `pipeline.Refresh('section-edit')`. Cancel discards everything.
Name/priority/delete behave as before. Priority slider spans the full left-column width.

## Behavior (classify / assign)

`pipeline.ResolveBindings(bindings)` now returns two arrays: `includes` and `excludes` (both sorted,
deduped; a `*`/`.` trailing binding expands to the prefix group).

- Phase A claims items for include categories that are not in the exclude set.
- Phase B (`Unmatched Items`) counts only when `Unmatched Items` is included and not excluded.
- Specialty-bag free slots (`sectionFreeSlots`) are counted from the effective set only, so an
  excluded tradeskill category does not add its bag family to the section.
- A section flagged `duplicate = true` may claim an item another section already placed, so an
  item can be drawn in two sections (FR-15, e.g. the New section draws a new item alongside its
  own category). The category no longer carries `duplicate`; it is a section property.

No other consumer of `sectionConfig.categories` exists, so no frame changes are needed.
