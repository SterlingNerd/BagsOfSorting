# 04 — Data Model

SavedVariables: `BagOfSortingDB`. One file, versioned, with our own profile store (no library).

Rule of the whole schema: **config is persisted, derived state is not.** Nothing about which item
is where is stored — that is computed from config + live inventory every refresh.

---

## Top level

```lua
BagOfSortingDB = {
  version   = 1,                       -- schema version, drives core/db.Migrate()
  global    = {
    presetsInstalled = { leveling = true },
    firstRunDone     = true,
  },
  profiles = {
    Default = <profile>,
    <characterName> = <profile>,       -- per-character profile
  },
}
```

## Profile

```lua
<profile> = {
  windows = {                          -- ordered array: order IS priority for display
    {
      id       = "w1",                -- stable opaque id, survives rename/reorder
      name     = "Crafting",
      kind     = "backpack",          -- "backpack" | "bank"
      priority = 1,                   -- tiebreak within same kind
      openWithAll = true,
      columns  = 5,
      compact  = false,               -- shrink to content, hide when empty
      scale    = 1.0,
      position = { point="BOTTOMLEFT", x=..., y=... },   -- saved drag position
      anchor   = { enabled=false, corner="auto" },
      sections = {                    -- ordered array
        { id="s1", category="Herbs",     collapsed=false, hidden=false },
        { id="s2", category="Ores",      collapsed=false, hidden=false },
        { id="s3", category="__catchall", collapsed=true },
      },
    },
  },

  categories = {                       -- keyed by name; name is the identity
    ["Herbs"] = {
      priority = 10,
      kind     = "rules",             -- "rules" | "manual" | "dynamic"
      rules    = <ruleTree>,
      dynamicField = nil,
      itemIDs  = nil,                 -- kind="manual": { [itemID]=true }
      duplicate = false,
      enabled  = true,
      color    = nil,                 -- optional section title color
    },
    ["Recent Items"] = { priority = 1, kind = "rules",
      rules = { op="all", children={ {field="isNew", cmp="=", value=true} } } },
    ["__catchall"] = { priority = 999, kind = "rules",
      rules = { op="all", children={ {field="none", cmp="=", value=true} } } },
  },

  settings = {
    display   = { qualityColor=true, qualityThreshold=2, qualityIntensity=0.3,
                  showNew=true, newDuration=420, showQuestMarker=true,
                  showEmptySlots="compact"|"slots"|"off", emptySlotFamilyIcons=true },
    stacking  = { mergeStacks=true, mergeUnstackable=false, dontMergePartial=true,
                  dontMergeTransmog=true },
    sorting   = { section="manual"|"name"|"sizeDesc"|"sizeAsc",
                  item="nameThenQuality"|"qualityThenName"|"ilvl"|"expansion" },
    interaction = { sectionBulkActions=true, itemMenu="default", upgradeArrow=false },
    search    = { inBag=false, dsl=true },
    theme     = "stock",
    debug     = false,
  },
}
```

Design notes:

- **`windows` is an array, `categories` is a map.** Window order is meaningful and structural;
  category order is not (priority is a number, so it survives map iteration).
- **Stable `id` for windows/sections**, name for categories. Renaming a window must not orphan its
  sections; renaming a category must rewrite references (that is a command with an inverse, so
  undo works).
- **`__catchall` is a real category**, not a special-cased code path. It has the lowest priority
  and a rule that matches "nothing else matched". This keeps `FR-16` inside the normal model.
- **No `hideduplicates` global.** `FR-15` is per-category `duplicate = false`, default false. A
  global tri-state is how Baggins got 57 profile keys.
- **Per-window `columns`**, not a global `columns`.

## Rule tree

```lua
<ruleTree>  = <group>
<group>     = { op = "any"|"all"|"none", children = { <group> | <leaf>, ... } }
<leaf>      = { field = <string>, cmp = <string>, value = <any> }
```

Constraints enforced by `data/rules.lua` on load and on every command:

- max depth 2 (`all` of `any` groups). Deeper nesting is where rule editors become unreadable;
  `shortcut: depth capped at 2, upgrade when a real use case appears with a UI that can show it`.
- a leaf's `field` must exist in the field registry and its `cmp` must be in that field's allowed
  `cmps`; unknown field/`cmp` → rule disabled + reported (`FR-29`, `FR-107`), never a silent false.
- `value` is validated against the field's `valueKind`.
- an empty group is invalid: it is rendered as "matches nothing" and reported.

### Precedence semantics (normative)

1. Categories are sorted by `priority` ascending (1 wins), then by name for determinism.
2. First category whose tree matches owns the item.
3. `duplicate = true` categories do not consume ownership: they add a second placement.
4. `kind = "dynamic"` categories expand at classify time into one virtual category per distinct
   field value, inheriting the parent's priority.
5. `__catchall` matches only if no other category owned the item.
6. The full ordered list of categories tested, and each match/reject reason, is recorded in the
   per-snapshot `trace` for the inspector (`FR-27`).

Manual membership (`kind = "manual"`) is checked **before** rules for that category, and a manual
category with no priority advantage still loses to a higher-priority rule category — this is the
one place users will be surprised, so the inspector must show it explicitly.

## Not persisted

- per-slot classification results, `trace`, stack groupings, section layouts (computed),
  item button pool contents, harvested item info cache, "recent item" timestamps beyond the
  duration anchor (`settings.newDuration` + a small map of `slotkey → time` that is debounced and
  pruned).
- Anything character-specific that belongs in `per-character` state lives in the per-character
  profile, not in `global`.

## Export / import (`FR-92`)

Payload = windows + sections + categories only. Never `settings` (style is personal), never
positions, never item GUIDs.

```
BOS1.<base64( json-ish serialize({windows, categories}) )>
```

- `BOS1` prefix carries the format version; a mismatched prefix is a hard, explained refusal.
- Manual categories export `itemIDs`, which are account-agnostic.
- Import is a **command batch**: it runs through the same command layer as the UI, so import is
  undoable in one `Ctrl+Z` and cannot half-apply.
- Import collision policy: existing category name → ask once (merge / rename incoming / skip),
  reported in the result toast.

## Migration

`core/db.Migrate()` runs when `version < CURRENT`. Migrations are numbered, additive, and each one
is a pure function over the profile table. No migration ever runs inside `OnEnable` business
logic (Baggins' `hideduplicates` boolean→string coercion in `OnEnable` is the anti-pattern).

`FR-94` Baggins import is a separate opt-in path, not a schema migration:

| Baggins | maps to | lossy? |
|---|---|---|
| `profile.bags[i]` | `windows[i]` | name/priority/openWithAll/isBank map; `columns` is global in Baggins → replicated per window |
| `bag.sections[j] = {name, cats={...}}` | a section referencing **one** category each; multi-cat Baggins sections become N sections, or one category whose tree is `any` of the referenced categories | yes — pick one, decide in `docs/07` Q5 |
| `categories[name] = {rule,...}` | `categories[name].rules` | `OR` chain → `any{...}`; `AND` chain → `all{...}`; a `NOT` rule → `none{ leaf }` **only if it is the sole/last rule**, otherwise it becomes `all{ none{leaf} }` and the report flags the semantic shift |
| rule types with no field equivalent (`Scrap`, `Keystone`, `Conduit`, `Anima`, `Profession`, `PeriodicTable`) | dropped, listed in the report | yes |
| `rule.ids` manual membership | `kind = "manual"` `itemIDs` | partial (Baggins stores itemIDs per include/NOT rule) |

The migration report is a required deliverable: a list of what mapped, what changed meaning, and
what was dropped. Silent migration is worse than no migration.

## Size & performance notes

- A heavy Baggins-style config is ~30 categories × ~3 rules. At ~120 bytes/rule that is trivial;
  SavedVariables size is not a design driver.
- The expensive thing is **classification cost**: `categories × items × leaves`. With 30 categories
  and 120 items that is ~10k leaf evaluations per full refresh — fine, but only if `read(item)`
  reads a pre-enriched record and not `GetItemInfo` per leaf. Hence phase 2 (`enrich`) materializes
  every field the registry can ask for, once per item per snapshot.
- Field registry declares `read` as O(1) on the enriched record. A field that needs a network-ish
  lookup (tooltip text) is enriched lazily and marked `expensive = true` so the classifier can
  short-circuit (`any` groups evaluate cheap fields first — sort leaves by `field.expensive`).
