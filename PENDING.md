# Pending — spike triage #1–#10

**Nothing is pending.** `/bos test` prints an empty list: the entries for #1, #8 and #10 went in the 2026-11-11
round and #4's the same night, each with its capture on the issue, its probes deleted from `core/diag.lua`, and —
together with the runs from earlier rounds — **all four of those spikes are now closed** with a closing note naming
what was measured and what was left. `../test1.lua`, `../test4.lua`, `../test8.lua`, `../test10.lua` are gone, and every
bucket they held is on its issue.

## The loop, for the next entry

```bash
cd /home/josh/Projects/wow && ./deploy.sh BagsOfSorting local     # explicit go-ahead required
```

Write the entry in the `tests` table at the bottom of `core/diag.lua` (`bos-test-capture` skill: id =
issue number, one action per step, every manual action bracketed by captured steps, `text` is what the
sheet prints). Then: `/reload` → `/bos test <id>` → follow the sheet → `/reload` →
`./retrieve.sh BagsOfSorting local` → paste the `[<id>]` bucket verbatim as a dated comment on the issue
→ write the verdict into the reference or `docs/` row that owns it → **delete the entry** →
`luacheck .` + `lua5.1 tests/run.lua` + commit.

## Per-issue state

| issue | state | what's left |
|---|---|---|
| **#3** EditMode | open, blocked | `frames/movemode.lua` does not exist. A-vs-B (`RegisterSystemFrame` with a variable window count) and the settings-dialog verdict (`FR-71`, `AC-54`, Q13). The A-vs-B choice is **ours to decide**, not the client's to be asked — which makes it a design decision sitting inside a spike. |
| **#5** layout stress | open, blocked | Superseded by #48 (no river packing, no `layout/sizing.lua`), #49 (unscaled heights vs per-window scale), #61 (fixed). Measure when #48's packer exists; `AC-40`'s numbers belong on #48. **Close candidate** — fold it into #48 with that pointer. |
| **#6** physical moves | open, blocked | `actions/moves.lua` is M6. Census must cover containers 6–14; bank containers exist only while the bank is open. |
| #1, #2, #4, #7, #8, #9, #10 | **closed** | Captures, verdicts and closing notes are on the issues; client facts in `../.agents/skills/wow-forever-api/references/`; our rules in `docs/`. Re-runnable sheets if a milestone pass wants them: `git show b736df8^:core/diag.lua` (#8), `git show 8697cd7^:core/diag.lua` (#4). |

## What the closed spikes left recorded (not open, not forgotten)

- **AC-26's two halves were never exercised** — a one-rule edit measured as a `/bos perf` delta, and a genuinely
  never-seen looted item. They are **M3 exit criteria** (`docs/06`), where rules exist to edit.
- **`FR-100`'s stated inventory condition (≥ 100 slots, ≥ 60 distinct items) has never been met here** — 31 items in 60
  bag slots. Refresh cost is recorded (1.14 ms/refresh on build 70888, 2.20 ms on 70450); the budget is not tested at
  size. Needs a character with more bags and more loot.
- **An empty blocked-action log is not proof of no taint** — no positive control exists, and the two obvious ways to
  stage one are blocked by our own rules (`docs/06` §Standing test discipline, `references/taint-and-secure.md`).
- **`FR-4`'s "read-only display in combat" is descriptive, not enforced**: our buttons run Blizzard's own handler and the
  client engaged with an in-combat drag without refusing it. Enforcing it would be a story issue.
- **Currency chips** need a character that carries a token; coin-on-the-bag-window is measured and shipped.
- **10 sampled ids answered between logins with zero requests from us** — a fact about the client's own store,
  unmeasured in detail, and nothing in `data/enrich.lua` changes whichever way it goes.

## Decisions waiting on you

1. **Fold #5 into #48?** It is the only open spike with nothing left that its superseding issues do not already own.
2. **#3 — is the EditMode A-vs-B choice still a spike?** The client cannot answer it; it is a design decision that has to
   be made before `frames/movemode.lua` exists. Either decide it here and let the story carry the rest, or move the
   question into that story and close the spike.
3. `BagsOfSortingDB.diag` is never pruned — 12 buckets, 1,075 lines (1, 4, 8, 10, 38, 41, 43, 44, 47, 52, 57 and
   `autotest57`), and every one of them now has its capture on an issue. Prune on load, or leave?
4. The build on `local` is one commit behind `main` and still carries the deleted test-4 entry in its `core/diag.lua`.
   Deploy on your go-ahead only.

## Where an answer lives

raw capture → the issue comment · client fact → `../.agents/skills/wow-forever-api/references/`
(`item-and-spell-data.md`, `containers-and-bags.md`, `ui-templates.md`, `taint-and-secure.md`,
`client-identity.md`) · our rule → `docs/NN-*.md` · run-sheet traps → `bos-test-capture` Gotchas ·
`agents.md` → nothing, it's the index (170-line budget, currently at 170). `.agents` is **not** under
git: reference and skill edits are uncommitted there by design.

Checks before committing: `luacheck .` · `lua5.1 tests/run.lua` (307 checks; this box has `luajit` or
`lua`, not `lua5.1`) · `bash tests/check-docs.sh`.

The half-run guard: a capture that must survive being overwritten lives in the account dir's git repo
under `bos-history/` (`BagsOfSorting-test4-half-20261111.lua` is the 4a–4f pass that stalled on
`/console`, kept next to the full pass that replaced it).
