# tests

Headless only. `tests/` is **not in the TOC**, so the addon loads none of it (FR-106).

| File | What it is |
|---|---|
| `fixtures.lua` | fake items shaped exactly like a harvested+enriched record |
| `selftest.lua` | the assertions: ownership, precedence and tie-breaks, duplicate policy, the `itemID` leaf, rule validation, sentence rendering, every sort mode, flow boundaries |
| `run.lua` | the runner: `lua5.1 tests/run.lua`. Loads the **real modules** against a stubbed `C_Container`/`C_Item`, then runs the pipeline end to end. Possible because phases 1-7 never touch a frame (NFR-4) |
| `CHECKLIST.md` | the manual half: numbered in-game steps for everything a frame, a keybind or a live Blizzard API makes untestable here |

CI runs it on every push (`.github/workflows/check.yml`).

This harness proves the classifier. It proves nothing about the Forever API surface — the
in-game checklist in `docs/06` and the spike issues are what do that (agents.md hard rule 1).
