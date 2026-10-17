# tests

| File | What it is |
|---|---|
| `fixtures.lua` | fake items shaped exactly like a harvested+enriched record |
| `selftest.lua` | the assertions `/bos selftest` runs: ownership, precedence and tie-breaks, duplicate policy, the `itemID` leaf, rule validation, sentence rendering |
| `run.lua` | headless runner: `lua5.1 tests/run.lua`. Possible because phases 1-7 never touch a frame |

Excluded from the release package by `.pkgmeta`, but loadable in a dev checkout so
`/bos selftest` works in-game (FR-106).

This harness proves the classifier. It proves nothing about the Forever API surface — the
in-game checklist in `docs/06` and the spike issues are what do that (agents.md hard rule 1).
