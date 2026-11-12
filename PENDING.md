# Pending — spike triage #1–#10

**Nothing is pending.** `/bos test` prints an empty list: the entries for #1, #8 and #10 went in the
2026-11-11 round and #4's went tonight, each with its capture on the issue and its probes deleted from
`core/diag.lua`. `../test1.lua`, `../test4.lua`, `../test8.lua`, `../test10.lua` are gone, and every
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
| **#1** item data | open, measured | Tier 1 answers 19 of 26 sampled Classic-era ids on its own (type/subclass/inventory type/**icon**); name, quality and ilvl need the full read, and a tier-3 request answers them **permanently**. Nothing answers above the Classic-era band. **AC-97** and the client half of **AC-103** pass. Left: 10 sampled ids answered between logins with **zero** requests from us — who asked is unmeasured; and the play half of AC-103. Close candidate. |
| **#3** EditMode | open, blocked | `frames/movemode.lua` does not exist. A-vs-B (`RegisterSystemFrame` with a variable window count) and the settings-dialog verdict (`FR-71`, `AC-54`, Q13). |
| **#4** taint / combat | open, measured once | Full pass done (2026-11-11): our key works during lockdown, hide defers the button release and regen completes it, the client shows its own windows during lockdown (60 visible buttons while shown), mid-combat `/reload` leaves nothing broken, and `GetBagsShown()` produced no observable consequence on the button path. **Two open threads:** (a) `ADDON_ACTION_BLOCKED`/`FORBIDDEN` never reached our logger, and the pass has **no positive control**, so "no blocked-action lines" is uninterpretable — the standing pass needs one before it can certify "no taint"; (b) an in-combat button attempt changed bags 5 and 1, and nothing proves whether an item really moved — decide whether our buttons must refuse movement during lockdown (`FR-4`) and settle it with a census on either side. Standing pass at every milestone exit — the entry comes back at the next milestone boundary. |
| **#5** layout stress | open, blocked | Superseded by #48 (no river packing, no `layout/sizing.lua`), #49 (unscaled heights vs per-window scale), #61 (fixed). Measure when #48's packer exists; `AC-40`'s numbers belong on #48. Consider closing here with that pointer. |
| **#6** physical moves | open, blocked | `actions/moves.lua` is M6. Census must cover containers 6–14; bank containers exist only while the bank is open. |
| **#8** perf + SavedVariables | **close candidate** | Harness exists and produced numbers: rows flat, `itemButton` pool flat (50/50), bench **1.14 ms per refresh**, `GetAddOnMemoryUsage` useless (0.0 KB), AC-26's "never seen" item never actually exercised. |
| **#10** bank deposit + money | open, deposit half only | Currency half measured: this client carries **nothing** (`GetBackpackCurrencyInfo` 0, `GetCurrencyListSize` 0) and its own `BackpackTokenFrame` is 0 watched / 8 max / **1 px** wide, shown only while Blizzard's own container windows are. Our money bar draws on the backpack window only. Deposit half **blocked on M6** (no `AutoDepositFrame`, bank moves items not coin, `IsItemAllowedInBankType` refuses nothing). Title still reads as the old scope. |
| #2, #7, #9 | closed | — |

## Decisions waiting on you

1. Close **#1** and **#8**? Rename/narrow **#10** to the deposit half? Close or fold **#5** into #48?
2. Issue #4's two open threads above. The positive control is the cheap one: it needs a *manual* step
   that guarantees a refusal, and the obvious candidates (a `/script` protected call — the skill forbids
   it; an Ace3 addon's `OnEnable` hit by a mid-combat `/reload` — the reload destroys our logger first)
   both have a reason they do not work. Say which rule you want and the entry gets written.
3. `BagsOfSortingDB.diag` is never pruned — 11 buckets, 948 lines, sit in SavedVariables and every one of
   them now has its capture on an issue. Prune on load, or leave?
4. Issue #4's body still names `/console eventTrace 1`, `/events`, and `ADDON_ACTION_FORBIDDEN` in
   `/events`; its step list is the pre-client-check one. Body rewrite (the 11-step measured pass is now
   the record).
5. ~~`docs/06` item 5 names `/bos test clock`~~ — not a bug: `clock` is a helper name in `diag.Command`
   (`HELPERS.clock = probes[13]`), so both spellings work.

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
