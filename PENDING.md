# Pending — spike triage #1–#10

Fresh-session entry point for the open spikes. The live build on `local` is **behind `main`** (the diag
rewrites are not deployed yet) — deploy before running any pending test.

## Run these first (in this order)

```bash
cd /home/josh/Projects/wow && ./deploy.sh BagsOfSorting local     # explicit go-ahead required
```

| id | issue | pre-conditions | steps |
|---|---|---|---|
| `/bos test 8` | ~~#8~~ | — | **done 2026-11-11**, entry deleted. Nothing to run. |
| `/bos test 10` | #10 | nothing to shuffle, out of combat | 5: catalogue + `BackpackTokenFrame` read → Currency tab / watch a currency (if the tab is empty, say so on the issue) → read again → CTRL-B → read again |
| `/bos test 1` | #1 | **fresh login**, cold cache, bags closed, nothing hovered | 6: id scan → tier-3 requests for the ids the scan picked → wait 10s → read them again → log out and back in → read again |
| `/bos test 4` | #4 | out of combat at step a; our windows open with real items; a trainer or mob to pull; a character you don't mind dying on | 16: state read on either side of each lockdown attempt (hide/show, button pickup, our key, CTRL-B), `/console` reviews, mid-combat `/reload`, then the deliberate `GetBagsShown()` trap **last** |

Loop per test (`bos-test-capture` skill): `/reload` → `/bos test <id>` → follow the sheet, one action
per step → `/reload` → `./retrieve.sh BagsOfSorting local` → paste the `[<id>]` bucket as a dated
comment on the issue → write the verdict into the reference or `docs/` row that owns it → **delete the
entry from `core/diag.lua`** → `luacheck .` + `lua5.1 tests/run.lua` + commit.

`../test1.lua`, `../test4.lua`, `../test8.lua`, `../test10.lua` are scratch from the 2026-11-11 runs —
all four buckets are on the issues, so they're safe to delete.

## Per-issue state

| issue | state | what's left |
|---|---|---|
| **#1** item data | open | tier 1 for an id the client **has data for but has not seen** — the rewritten scan answers it. AC-97 **passes**. Ids outside the client's item database are dead at every tier, and `GetItemIconByID` answers 134400 (question mark) for them. |
| **#3** EditMode | open, blocked | `frames/movemode.lua` does not exist. A-vs-B (`RegisterSystemFrame` with a variable window count) and the settings-dialog verdict (`FR-71`, `AC-54`, Q13). |
| **#4** taint / combat | open | Re-run with the fixed sheet. `issecure()` is unreadable from a slash path, so verdicts come from lockdown state, who is showing bags, and `ADDON_ACTION_FORBIDDEN` in `/console`. Whether `GetBagsShown()` taints Blizzard's code is still unmeasured. Standing pass at every milestone exit. |
| **#5** layout stress | open, blocked | Superseded by #48 (no river packing, no `layout/sizing.lua`), #49 (unscaled heights vs per-window scale), #61 (fixed). Measure when #48's packer exists; `AC-40`'s numbers belong on #48. Consider closing here with that pointer. |
| **#6** physical moves | open, blocked | `actions/moves.lua` is M6. Census must cover containers 6–14; bank containers exist only while the bank is open. |
| **#8** perf + SavedVariables | **close candidate** | Harness exists and produced numbers: rows flat, `itemButton` pool flat (50/50), bench **1.14 ms per refresh**, `GetAddOnMemoryUsage` useless (0.0 KB), AC-26's "never seen" item never actually exercised. |
| **#10** bank deposit + money | open, narrowed | Currency half: is there any carried currency on this client, and does the client's own `BackpackTokenFrame` already draw it. Deposit half: **blocked on M6** — the bank has no auto-deposit affordance, moves items not money, and `IsItemAllowedInBankType` refuses nothing. Title still reads as the old scope. |
| #2, #7, #9 | closed | — |

## Decisions waiting on you

1. Close **#8**? Rename/narrow **#10** to the currency half with the deposit half marked blocked on M6?
   Close or fold **#5** into #48?
2. `BagsOfSortingDB.diag` is never pruned — 8 buckets from closed issues (845 lines) sit in
   SavedVariables and are the only thing that grows the file. Prune buckets with no pending test, or leave?
3. `docs/06` item 5 still names `/bos test clock`; the command is `/bos test 13`.

## Where an answer lives

raw capture → the issue comment · client fact → `../.agents/skills/wow-forever-api/references/`
(`item-and-spell-data.md`, `containers-and-bags.md`, `ui-templates.md`, `taint-and-secure.md`,
`client-identity.md`) · our rule → `docs/NN-*.md` · run-sheet traps → `bos-test-capture` Gotchas ·
`agents.md` → nothing, it's the index (170-line budget, currently at 170). `.agents` is **not** under
git: reference and skill edits are uncommitted there by design.

Checks before committing: `luacheck .` · `lua5.1 tests/run.lua` (322 checks; this box has `luajit` or
`lua`, not `lua5.1`) · `bash tests/check-docs.sh`.
