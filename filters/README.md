# filters

The field registry: what a rule leaf may ask about an item, and how it says so in English.

| File | What it is |
|---|---|
| `registry.lua` | `Register{key,label,valueKind,cmps,read,sentence,values?,expensive?}`. A field without `sentence` is refused — that is how FR-20's "readable sentence" is enforced in code |
| `fields.lua` | the v1 fields: `type`, `subtype`, `quality`, `ilvl`, `name`, `expansion`, `equipSlot`, `isQuestItem`, plus `itemID` (the `itemID in {…}` leaf, FR-24) and `none` (which makes `__catchall` a real category) |

`read` is O(1) on the enriched record. A field that needs tier-3 data is `expensive = true`.
