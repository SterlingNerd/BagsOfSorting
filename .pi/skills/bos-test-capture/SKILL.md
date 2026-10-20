---
name: bos-test-capture
description: Manual test capture for the BagsOfSorting WoW addon — writing a pending `/bos test` entry in core/diag.lua (issue-bound, ephemeral), running its in-game steps, syncing, and ingesting the capture into the GitHub issue plus agents.md, then deleting the entry. Use when adding or running an in-game measurement or manual QA pass, when a spike or story issue needs live-client data, when reading BagsOfSortingDB.diag, or before handing anyone a `/script` one-liner.
compatibility: BagsOfSorting repo + WoW Forever client. Capture files arrive via ../sync.sh into ../account/SavedVariables/BagsOfSorting.lua.
---

# Manual test capture (`/bos test`)

`/bos test` is the current list of in-game things we want measured: short QA or investigation tasks
tied to an open story or spike issue. It is **pending work only** — an entry exists because its issue
is open, and ingesting the capture deletes it. It is the reminder to run the tests without scanning
GitHub.

Everything a test captures goes to SavedVariables **and** to your own chat frame. Chat is a courtesy
readout; the synced Lua file is the capture. Nothing here calls `SendChatMessage`, so probe output is
never said, shouted or broadcast to another player.

## The loop

```
prepare the test (issue + entry)
../sync.sh
/reload
/bos test <id>        follow the printed sheet, top to bottom — one numbered step each
/reload
../sync.sh
ingest                issue comment → docs → delete the entry → commit
```

`/reload` twice because SavedVariables only flush on `/reload` or logout, and the addon you run must
be the addon the sheet came from.

## Commands

| Command | What it does |
|---|---|
| `/bos test` | the pending list: id, one-line purpose, preconditions, then the helper names |
| `/bos test 42` | the numbered run sheet for one test: description, pre-conditions, **one action per step** |
| `/bos test 42b` | run one **captured** step of that test |
| `/bos test dump` | containers -3..23: names, slot counts, bank grid, tab data, totals |
| `/bos test log` | start/stop event logging (toggle) |
| `/bos test flags` | `Enum.BagSlotFlags` on every equipped bag and bank container |
| `/bos test keybind` · `newitem` · `clock` · `expansion` | the other reusable captures |
| `/bos find <itemID>` | which container index holds that item (writes to its own `find` bucket) |

Helpers are for test steps to reuse. Only `log` is a thing you run on its own often.

## Writing a test

Entry lives in the `tests` table at the bottom of `core/diag.lua`:

```lua
[42] = {
  issue = 42,
  what = 'bag creation (FR-10)',
  needs = 'no pre-conditions',
  steps = {
    { text = 'setup: scratch window + seeded config', run = setup },
    { text = 'click "add bag"' },
    { text = 'type the name into the dialog' },
    { text = 'accept the dialog' },
    { text = 'capture: window list + config shape', run = capture },
  },
},
```

Rules:

- **The id is the issue number.** `/bos test 42` ↔ `gh issue view 42`.
- **One entry per issue at a time.** A story may need several rounds: ingest, delete the entry, add
  the next one for the same story. The list stays short on purpose.
- `text` is the line the sheet prints. A step with **no `run` is a manual action** and gets no letter.
- **One action per step.** The sheet numbers every step, so each line is one thing the runner does.
  "deposit one item, then withdraw it" is two steps. Compound steps lose their second half: the
  runner's eye lands on the command printed after them. Issue #27 lost its withdraw this way, twice.
- **Every manual action sits between two captured steps.** Without brackets on both sides you are
  guessing which event or which dump belongs to which action — that is the single hardest thing to
  read back out of a capture.
- Captured steps are lettered `a`, `b`, `c…` in order. Letters are positional: reorder the steps and
  they renumber.
- Step `a` is setup: it verifies the preconditions, prints what it found, and seeds **our own** state
  only. Anything touching the player's inventory — buying a bank slot, equipping a bag, looting,
  depositing — is a protected call and stays a manual step.
- Keep the capture honest: a step that reads nothing is still a step, and "no bank bag owned yet" is
  a result worth recording.
- Verify an API exists before writing a step that calls it (`wow-forever-api` skill: `git grep` against
  `origin/forever`). Source-verified is not in-game-verified.

## What the capture looks like

Each captured step writes a header, then its output, into one bucket per test
(`BagsOfSortingDB.diag[42]`). The first step opens the bucket; later steps append to it. The last
captured step writes the ingest reminder, so the cleanup instruction is sitting in front of you when
you read the data:

```
--- 42a setup: scratch window + seeded config | build 1.16.0 (12345) | Zheak Idd - Stormpike ---
--- 42b capture: window list + config shape | build 1.16.0 (12345) | Zheak Idd - Stormpike ---
captured 42b — paste the [42] bucket into issue #42, then remove test 42 from core/diag.lua
```

Storage rule, which is what makes deleting an entry safe:

| Where | Role |
|---|---|
| `BagsOfSortingDB.diag` | scratch. Overwritten by the next round, no apology |
| the issue comment | the raw capture, dated, durable |
| `agents.md`, `docs/` | the verdict, present tense |

## Ingesting a capture

1. `../sync.sh`, then read `../account/SavedVariables/BagsOfSorting.lua` → `BagsOfSortingDB.diag[<id>]`.
2. Paste the bucket verbatim as a dated comment on the issue.
3. Write the verdicts into `agents.md` (measured-fact table) and the relevant `docs/` row. Present and
   future tense: docs describe what the project does, git records what changed.
4. Close the question or narrow it to what is genuinely still open, and say what blocks the rest.
5. **Delete the test entry from `core/diag.lua`.** This is part of ingesting, not a later tidy-up.
6. `lua5.1 tests/run.lua` and `luacheck .`, then commit.

## Don't

- No `/script` handouts in a run sheet. It is one line capped near 255 characters, which truncates a
  real probe and reports `'end' expected near '<eof>'` — that reads like a Lua bug and is not one.
- No copy/paste from chat as the primary capture. Long dumps truncate.
- No status fields, "captured" flags, or history tables. Deleting the entry is the done marker.
- No assertions or expected values inside a test step. Off-client assertions live in `tests/run.lua`;
  in-game steps measure, they do not judge.
- No new test framework. The table plus the dispatcher is the whole design.

## Gotchas that already cost us time

- A helper run on its own replaces its bucket, so run the dump **after** the actions, not before and
  after, unless the sheet says which state each run must be in. Inside a test step it does not reset
  anything — the test owns the bucket.
- Two buckets can describe different worlds: a `dump` captured before a purchase and one after sit in
  the same bucket, and the older one is gone. One bucket per test, one state per test.
- `log` is a **toggle**. A logger left running from an earlier step or session turns the next setup
  step's log call into a **stop**, and the actions that follow log nothing. `/reload` before starting
  a test.
- Event logs are noisy: `BAG_UPDATE 0` and `BAG_UPDATE -1` (backpack and keyring) fire constantly.
  Read them as background, not as findings.
- `ITEM_LOCK_CHANGED` with one argument is an **inventory** slot, not a container and slot pair.
  `PLAYERBANKSLOTS_CHANGED` carries a **bank bag slot 1..9**, not a container index.
- `sync.sh` pulls `WTF/Account` with `-u`: a locally edited `BagsOfSorting.lua` silently wins and you
  analyse a stale capture. Never edit that file locally.
- `MAX_LINES` caps a bucket at 400 lines; a long investigation is several tests, not one.
