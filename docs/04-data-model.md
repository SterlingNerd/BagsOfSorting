# 04 — Data Model

SavedVariables: `BagsOfSortingDB`. One file, versioned, with our own profile store (no library).

Rule of the whole schema: **config is persisted, derived state is not.** Nothing about which item
is where is stored — that is computed from config + live inventory every refresh.

---

## Top level

```lua
BagsOfSortingDB = {
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
      priority = 1,                   -- reserved: nothing sorts on it. Array order IS the layout
                                      -- order; classification precedence lives in `categories`
                                      -- alone (issue #28 decision 4)
      openWithAll = true,             -- reserved: no code reads it yet
      hidden   = false,                -- closed with the window's own X; absent means open
      columns  = 5,
      compact  = false,               -- reserved: shrink to content / hide when empty is FR-18,
                                      -- unread today
      scale    = 1.0,
      icon     = "INV_Misc_Bag_10",   -- bare Interface\ICONS\ name, from the client's icon picker
      overlay  = nil,                 -- optional our-own-art overlay drawn on top of `icon`
      position = { point="BOTTOMLEFT", x=..., y=... },   -- reserved: unused while windows are placed, not dragged (FR-41, Q24)
      anchor   = { enabled=false, corner="auto" },
      copyFrom = nil,                 -- window id this one was created from (FR-10b): provenance
                                      -- only, NOT inheritance. Editing the source never edits this.
      link     = nil,                 -- window id to stay in step with (FR-10c). Shares the section
                                      -- list and its category bindings; does NOT share kind, columns,
                                      -- scale, position, compact or icon. Explicit, visible, breakable.
                                      -- The usual shape: a bank window linked to its backpack twin.
      sections = {                    -- ordered array
        { id="s1", categories={"Herbs"},         collapsed=false, hidden=false },
        { id="s2", categories={"Ores","Metals"}, collapsed=false, hidden=false },
        { id="s3", categories={"Tradeskills.Enchanting*"}, collapsed=false },  -- trailing `*` = bind
                                      -- the whole dotted group: every category under that prefix
                                      -- (FR-11b). Resolved at classify time from names, so renaming
                                      -- a category out of the prefix moves it out of the section.
        { id="s4", categories={"__catchall"},    collapsed=true },
      },
    },
  },

  categories = {                       -- keyed by name; name is the identity
    ["Herbs"] = {
      priority = 10,
      kind     = "rules",             -- "rules" | "manual" | "dynamic"
      rules    = <ruleTree>,
      dynamicField = nil,
      itemIDs  = nil,                 -- kind="manual": { [itemID]=true }. For kind="rules" the IDs
                                      -- live as an `itemID in {…}` leaf inside the tree instead.
      duplicate = false,
      enabled  = true,
      affinity = nil,                 -- "herbalism"|"mining"|"engineering"|"soul"|"quiver"|… →
                                      -- preferred physical container for compaction (FR-66)
      bagFamily = nil,                -- the client's specialty-bag family bit this category's own
                                      -- free-slot count reads (FR-44, issue #44): 32 herb bag, 1024
                                      -- mining bag. Not `affinity`: that is a compaction label, this
                                      -- is the value C_Container.GetContainerNumFreeSlots answers.
      color    = nil,                 -- optional section title color
    },
    ["Recent Items"] = { priority = 1, kind = "rules",
      rules = { op="all", children={ {field="isNew", cmp="=", value=true} } } },
    ["__catchall"] = { priority = 999, kind = "rules",
      rules = { op="all", children={ {field="none", cmp="=", value=true} } } },
  },

  settings = {
    display   = {
      -- quality / rarity presentation (FR-45)
      qualityOn     = { [0]=true,[1]=true,[2]=true,[3]=true,[4]=true,[5]=true,[6]=true,[7]=true },
      qualityMode   = "border"|"tint"|"both"|"off",   -- "off" leaves the client's own look alone
      qualityThreshold  = 2, qualityIntensity = 0.3,
      -- item level presentation (FR-45b)
      showIlvl = true, ilvlOnGearOnly = true, ilvlMin = 0, ilvlPos = "bottomright",
      ilvlQualityColor = false,        -- hides entirely for an item not in the cache (FR-103)
      showNew=true, newDuration=420,
      clearNewOnClose = true,          -- FR-47: false keeps the highlight until cleared by
                                       -- keybind / context menu / `/bos new`
      showQuestMarker=true,
      showEmptySlots="compact"|"slots"|"off", emptySlotFamilyIcons=true },
    stacking  = { showStacks="merged"|"always"|"session"|"vendor",  -- FR-43; "session" = merged but
                  -- a Show-stacks toggle un-merges until the bags close; "vendor" un-merges while a
                  -- vendor is open
                  mergeUnstackable=false, dontMergePartial=true,
                  dontMergeTransmog=true, preferAffinityBags=true },
    sorting   = { section="manual"|"name"|"sizeDesc"|"sizeAsc",
                  item="nameThenQuality"|"qualityThenName"|"ilvl"|"expansion" },
    interaction = { sectionBulkActions=true, itemMenuModifier="CTRL",  -- FR-60b; our item menu, the
                    -- stock item menu keeps naked right-click
                    sellSections=false, sellableCategories={},  -- FR-65: bulk sell is opt-in per category
                    upgradeArrow=false, emptyBagConfirm=true },
    bagBar    = { mode="sorting"|"vanilla", showVanillaToggle=true },
    search    = { inBag=true, dsl=true },   -- no bankSnapshot key: nothing is persisted but the
                                            -- item cache (FR-109)
    undo      = { depth=50 },
    debug     = false,
  },
}
```

Design notes:

- **`windows` is an array, `categories` is a map.** Window order is meaningful and structural;
  category order is not (priority is a number, so it survives map iteration).
- **Stable `id` for windows/sections**, name for categories. Renaming a window must not orphan its
  sections; renaming a category must rewrite every section reference (that is a command with an
  inverse, so undo works).
- **A section holds a list of categories** (`docs/07` Q3, resolved: B). Inside one section the
  categories lay out in category-priority order, then by the section's sort rule; the section title
  is the section's own name, not a category name. This is what real Baggins configs use it for
  (`Metals and Ores` → `Tradeskills.Metals` + `Tradeskills.Ore`).
- **A trailing `*` on a binding means "the whole dotted group"** (`FR-11b`, `docs/07` Q8):
  `Tradeskills.Enchanting*` binds every category whose name starts with that prefix. It is resolved
  from names at classify time, so it costs nothing to add a child category — but renaming a category
  out of the prefix silently moves it out of the section, which the rename UI must say out loud.
- **`copyFrom` is provenance, not inheritance.** It exists so "make the bank half of this window" is
  one action, and so a later *re-copy* can be offered. Nothing reads through it at runtime — runtime
  inheritance is how configs become spooky action at a distance. If real inheritance is ever wanted
  (`docs/07` Q11) it is a separate field with its own rules.
- **`__catchall` is a real category**, not a special-cased code path. It has the lowest priority
  and a rule that matches "nothing else matched". This keeps `FR-16` inside the normal model.
- **No `hideduplicates` global.** `FR-15` is per-category `duplicate = false`, default false. A
  global tri-state is how Baggins got 57 profile keys.
- **Per-window `columns`**, not a global `columns`.
- **No `theme` key.** We use the client's bag visuals (`docs/07` Q16).

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
- `value` is validated against the field's `valueKind`. `valueKind = "idlist"` (the `itemID` field)
  accepts a set of numbers and is rendered as `itemID in {Linen Glyph +41 more}` in a chip, never as
  42 chips.
- an empty group is invalid: it is rendered as "matches nothing" and reported.
- a `none` group renders as **`EXCEPT …`**, not as a negative-sounding rule type. In the measured
  Baggins configs `NOT` is used 320 times against `AND`'s 44; "except" is the refinement users
  reach for and the UI must lead with it.

### Precedence semantics (normative)

1. Categories are sorted by `priority` ascending (1 wins), then by name for determinism.
2. First category whose tree matches owns the item.
3. `duplicate = true` categories do not consume ownership: they add a second placement.
4. `kind = "dynamic"` categories expand at classify time into one virtual category per distinct
   field value, inheriting the parent's priority.
5. `__catchall` matches only if no other category owned the item.
6. The full ordered list of categories tested, and each match/reject reason, is recorded in the
   per-harvest `trace` for the inspector (`FR-27`).
7. A section bound to several categories does **not** re-run classification: ownership is decided
   globally by priority, then each category's items are laid out inside the section in category
   priority order. Two categories in one section are a *display* grouping, never a precedence rule.

`itemID in {…}` leaves are checked before the rest of their own tree (cheapest field, and the most
likely to be the whole rule), and a manual-only category is equivalent to a single
`all{ itemID in {…} }` tree — one concept, one editor, one explanation in the inspector.

## Item ID entry (`FR-24b`)

`util/idlist.lua` is the one parser, used by the category editor's paste box, the "make a category
from these items" flow, preset installation and import. Accepted in one blob, mixed freely:

- bare IDs: `26042 26044 4378`
- commas, semicolons, tabs, newlines, or any mix as separators
- item links (`[Linen Glyph]`), from a chat link or a dragged item
- `id:26042` for the rare case where a name is also a number

Rejected tokens are reported, not skipped silently: `43 IDs, 2 unknown to this client` with the two
tokens listed. An ID the client has never seen is **kept** (it is valid config, it just cannot be
named yet — `FR-103` resolves it later); a token that is not an ID at all is dropped with a reason.
Output is a set, so pasting the same block twice is a no-op, and the whole paste is one command with
one inverse.

## Not persisted

- per-slot classification results, `trace`, stack groupings, section layouts (computed),
  item button pool contents, "recent item" timestamps beyond the duration anchor
  (`settings.newDuration` + a small map of `slotkey → time` that is debounced and pruned).
- Anything character-specific that belongs in per-character state lives in the per-character
  profile, not in `global`.

**Two deliberate exceptions**, both because the alternative is a worse product:

| Persisted | Why | Bound |
|---|---|---|
| `itemCache` (`itemID → name, quality, type, subtype, ilvl, icon`) | the client only knows items it has seen (`FR-103`); without this, a 40-ID manual category re-requests every ID at every login and the category editor is blank for a minute | bounded (≤ ~4000 entries, LRU), debounced, rebuildable, safe to delete |
| ~~`snapshot`~~ — **deleted** | every earlier draft of this spec carried a persisted bank/alt item list. It has no reason to exist: `C_Bank` exposes no item-reading API, so bank contents arrive through the same container API as backpack contents and the harvest loop is already the only reader. Offline search — closed bank, alts, guild bank — is out of the product (`docs/07` Q15) | **`FR-109`: the item cache is the only derived state we persist.** Nothing else here is derived, cached or stored |

## Export / import (`FR-92`)

Payload = windows + sections + categories only. Never `settings` (style is personal), never
positions, never item GUIDs.

```
BOS1.<base64( json-ish serialize({windows, categories}) )>
```

- `BOS1` prefix carries the format version; a mismatched prefix is a hard, explained refusal.
- **Nothing here is stable before 1.0.** The grammar, the schema and this format are all expected to move
  while the addon is pre-1.0; the version marker exists so our own migrations fail loudly rather than
  silently misreading a file, not to promise anyone else compatibility (`docs/07` Q22).
- The model is kept **plain data** — no closures in the schema, names as identities — so that publishing
  it later is a transport decision rather than a rewrite (`FR-113`). That is a reason we want this
  regardless of whether anyone else ever reads it: import/export, migration and the test fixtures all
  depend on the same property.
- Manual categories and `itemID in {…}` leaves export their IDs, which are account-agnostic. Window
  `icon` exports (a bare `Interface\ICONS\` name is not character-specific); `overlay` does not.
- Import is a **command batch**: it runs through the same command layer as the UI, so import is
  undone by one Undo and cannot half-apply.
- Import collision policy: existing category name → ask once (merge / rename incoming / skip),
  reported in the result toast.

## Migration

`core/db.Migrate()` runs when `version < CURRENT`. Migrations are numbered, additive, and each one
is a pure function over the profile table. No migration ever runs inside `OnEnable` business
logic (Baggins' `hideduplicates` boolean→string coercion in `OnEnable` is the anti-pattern).

**A preset field added to the schema is backfilled by a migration.** While one user owns every
deployed file, `CURRENT_VERSION` would otherwise stay at **1**, the schema changes **breakingly**, and
the game-side file is deleted or replaced out-of-band (`tests/CHECKLIST.md` setup — the file is
`WTF/Account/<account>/SavedVariables/BagsOfSorting.lua`, and the client must be closed or it rewrites
the edit at logout). That works until a preset field feeds a feature: a profile written before the
field exists would leave the feature silently off for the one player who has a file, so issue #44
bumped `CURRENT_VERSION` to **2** with one additive migration that puts `bagFamily` on the tradeskill
presets. `db.Migrate()` and the version loop are the machinery M3 needs; migration **2** is the first
one it holds.

**Importing from other addons is deferred** (`docs/07` Q5, `FR-94` = Won't for v1): ship two
sensible default profiles instead. The table below stays in the spec as the answer to "if we ever
do it", and the target then is Bagnon/AdiBags-shaped data, which is where the users are.

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

Rough, from a real heavy config (`docs/01`): dozens of categories, a few hundred rules, ~12 windows,
over a hundred sections, hundreds of manual item IDs. At ~120 bytes/rule and ~40 bytes/ID that is
still trivial — SavedVariables size is not a design driver, and the item cache is the only blob worth
watching.

- The expensive thing is **classification cost**: `categories × items × leaves`. At that size —
  ~70 categories × ~120 items × ~2.5 leaves — call it **~20k leaf evaluations per full refresh**.
  Fine, but only if `read(item)` reads a pre-enriched record and never `GetItemInfo` per leaf. Hence
  phase 2 (`enrich`) materializes every field the registry can ask for, once per item per harvest.
- Field registry declares `read` as O(1) on the enriched record. A field that needs a network-ish
  lookup (tooltip text) is enriched lazily and marked `expensive = true` so the classifier can
  short-circuit (`any` groups evaluate cheap fields first — sort leaves by `field.expensive`).
- `itemID in {…}` is a hash lookup, not a loop: cost is O(1) per item regardless of how many IDs a
  user pasted. This matters because item-ID rules are 30% of the rules people actually write.
- A 100-plus-section layout is the layout-engine stress case (`AC-40` is 12 sections in one window;
  the spike issue has the ~100-section case).
