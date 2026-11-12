# Pending — spike triage #1–#10

Fresh-session entry point for the open spikes. The live build on `local` is **behind `main`** — deploy
before running the one test left.

## Run this

```bash
cd /home/josh/Projects/wow && ./deploy.sh BagsOfSorting local     # explicit go-ahead required
```

| id | issue | pre-conditions | steps |
|---|---|---|---|
| `/bos test 4` | #4 | out of combat at step a; our windows open with real items; a trainer or mob to pull; a character you don't mind dying on | 20 steps, captured a–k: arm the blocked-action log, then a state read on either side of each lockdown attempt (hide/show, button pickup, our key, CTRL-B), a `/eventtrace` review, mid-combat `/reload`, then the deliberate `GetBagsShown()` trap **followed by two real button attempts** — ours, then Blizzard's — and the state they leave |
| ~~`/bos test 1`~~ | #1 | — | **done 2026-11-11** (scan run), entry + its helpers deleted, capture on the issue |
| ~~`/bos test 10`~~ | #10 | — | **done 2026-11-11** (currency run), entry + its helpers deleted, capture on the issue |
| ~~`/bos test 8`~~ | #8 | — | **done 2026-11-11**, entry deleted |

Loop per test (`bos-test-capture` skill): `/reload` → `/bos test <id>` → follow the sheet, one action
per step → `/reload` → `./retrieve.sh BagsOfSorting local` → paste the `[<id>]` bucket as a dated
comment on the issue → write the verdict into the reference or `docs/` row that owns it → **delete the
entry from `core/diag.lua`** → `luacheck .` + `lua5.1 tests/run.lua` + commit.

**Test 4's last run is half-done and un-ingested.** `BagsOfSortingDB.diag[4]` on `local` (51 lines) holds a
completed 4a–4f pass from the fixed sheet; it stalled at the `/console` review step, which opens nothing
on this client. Saved in `../account/bos-history/BagsOfSorting-test4-half-20261111.lua` because the next
run overwrites the bucket. What it already says: out of combat, Blizzard's 7 container frames exist and
none is shown, suppression off, `itemButton` pool 51/51 idle → in combat, `/bos hide` + `/bos show` leaves
**our 6 windows shown** and allocates 11 section buttons and 33 item buttons (idle 51 → 18); a button
pickup attempt leaves `cursor=nil` (nothing reached the cursor) with no blocked-action line anywhere; our
own key changes nothing during lockdown; and CTRL-B brings up **Blizzard's own windows during lockdown**
(`ContainerFrameCombinedBags true`, one container frame shown). Open questions those numbers cannot
answer: whether each attempt was refused by the client or simply did nothing, and which function any
refusal names — which is what the armed log at step b is for.

`../test1.lua`, `../test4.lua`, `../test8.lua`, `../test10.lua` are scratch from the 2026-11-11 runs —
every bucket in them is on its issue, so they are deleted.

## Per-issue state

| issue | state | what's left |
|---|---|---|
| **#1** item data | open, measurement done | Tier 1 answers 19 of 26 sampled Classic-era ids on its own (type/subclass/inventory type/**icon**); name, quality and ilvl need the full read, and a tier-3 request answers them **permanently** (`requested=8 resolved=8 pending=0`, still answered at the next login). Nothing answers above the Classic-era band. **AC-97** and the client half of **AC-103** pass. Left: 10 sampled ids answered between logins with **zero** requests from us — who asked is unmeasured; and the play half of AC-103 (loot a never-seen item, watch it move out of the catch-all). Close candidate. |
| **#3** EditMode | open, blocked | `frames/movemode.lua` does not exist. A-vs-B (`RegisterSystemFrame` with a variable window count) and the settings-dialog verdict (`FR-71`, `AC-54`, Q13). |
| **#4** taint / combat | open, half-measured | The only pending run, rewritten to 20 steps after a run stalled on `/console`. `issecure()` is unreadable from a slash path, so verdicts come from lockdown state, who is showing bags, and `ADDON_ACTION_BLOCKED` / `ADDON_ACTION_FORBIDDEN` — which the log now records on a frame we own, and which may or may not reach an addon at all. Whether `GetBagsShown()` taints Blizzard's code is still unmeasured; the trap half now ends in two real button attempts. Standing pass at every milestone exit. |
| **#5** layout stress | open, blocked | Superseded by #48 (no river packing, no `layout/sizing.lua`), #49 (unscaled heights vs per-window scale), #61 (fixed). Measure when #48's packer exists; `AC-40`'s numbers belong on #48. Consider closing here with that pointer. |
| **#6** physical moves | open, blocked | `actions/moves.lua` is M6. Census must cover containers 6–14; bank containers exist only while the bank is open. |
| **#8** perf + SavedVariables | **close candidate** | Harness exists and produced numbers: rows flat, `itemButton` pool flat (50/50), bench **1.14 ms per refresh**, `GetAddOnMemoryUsage` useless (0.0 KB), AC-26's "never seen" item never actually exercised. |
| **#10** bank deposit + money | open, deposit half only | **Currency half measured**: this client carries nothing — `GetBackpackCurrencyInfo` 0 entries, `GetCurrencyListSize` **0** — and its own `BackpackTokenFrame` is `shown true`, 0 watched, 8 max, **1 px** wide, i.e. laid out for zero chips; after CTRL-B it reads `shown false`, so it lives and dies with Blizzard's own container windows. Our money bar draws on the backpack window only. **Deposit half blocked on M6**: no `AutoDepositFrame` on this bank panel, the bank moves items not coin, `IsItemAllowedInBankType` refuses nothing. Title still reads as the old scope. The chip half needs a character that actually carries a token — that is a new entry, not this one. |
| #2, #7, #9 | closed | — |

## Decisions waiting on you

1. Close **#1** and **#8**? Rename/narrow **#10** to the deposit half (its money half is now measured)?
   Close or fold **#5** into #48?
2. `BagsOfSortingDB.diag` is never pruned — 11 buckets, 948 lines, sit in SavedVariables and are the
   only thing that grows the file. Ten of them have no pending test. Prune on load, or leave?
3. ~~`docs/06` item 5 names `/bos test clock`~~ — not a bug: `clock` is a helper name in `diag.Command`
   (`HELPERS.clock = probes[13]`), so both spellings work.
4. Issue #4's body still says "`/console eventTrace 1` or `/events` open in a chat frame" and names
   `ADDON_ACTION_FORBIDDEN` in `/events` (its test plan predates the client check). Body rewrite when the
   20-step sheet has produced a full capture.

## Where an answer lives

raw capture → the issue comment · client fact → `../.agents/skills/wow-forever-api/references/`
(`item-and-spell-data.md`, `containers-and-bags.md`, `ui-templates.md`, `taint-and-secure.md`,
`client-identity.md`) · our rule → `docs/NN-*.md` · run-sheet traps → `bos-test-capture` Gotchas ·
`agents.md` → nothing, it's the index (170-line budget, currently at 170). `.agents` is **not** under
git: reference and skill edits are uncommitted there by design.

Checks before committing: `luacheck .` · `lua5.1 tests/run.lua` (316 checks; this box has `luajit` or
`lua`, not `lua5.1`) · `bash tests/check-docs.sh`.
