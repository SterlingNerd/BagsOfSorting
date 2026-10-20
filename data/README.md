# data

Phases 1-7 of the pipeline. Pure data: nothing here creates or touches a frame (NFR-4), which
is what makes the classifier testable (`lua5.1 tests/run.lua`) and what will make the
category editor's live match list cheap.

| File | Phase | What it does |
|---|---|---|
| `harvest.lua` | 1 | discovers the container list by probing (never `Enum.BagIndex`), reads every slot: the items and the free-slot count come out of the same pass (issue #36) |
| `enrich.lua` | 2 | tier 1 (`GetItemInfoInstant`) + tier 2 (cache) + tier 3 (`RequestLoadItemDataByID`) |
| `itemcache.lua` | 2 | the persisted, bounded item cache — the only derived state we store (FR-97, FR-109) |
| `rules.lua` | 3 | `any/all/none` tree: validate, evaluate, render as one sentence |
| `classify.lua` | 3 | categories by priority, first match owns the item, per-item `trace` for the inspector |
| `sort.lua` | 6 | item order within a section (FR-46) |
| `pipeline.lua` | 4,5,7 + orchestration | category → section → window, duplicate policy, group bindings (`*`), chunking decision |

Phase 5 (virtual stacks) is M2 (`data/stacks.lua`): the prototype maps one button to one real
slot, so nothing is merged and nothing is fabricated.
