# BagsOfSorting — Agent Context

A WoW: **Forever** (Blizzard codename *Camelot*) bag addon. Baggins' multi-window virtual-bag shape,
with a configuration model and UI that a human can actually use.

**Current phase: prototype (M0 + M1 done, M2 in progress).** The pipeline, the rule grammar, five
rendered windows (`Backpack`, `Quests`, `Consumables`, `Tradeskills`, `Tools`) and the `FR-41` placement
rule exist. The configuration UI does not. `docs/` is the source of truth for what to build; change the
spec there before changing direction in code.

This file is an **index and a rulebook**. It is not a fact cache — see "Where an answer lives" below.

---

## Read this order

| File | What it is |
|---|---|
| `readme.md` | Human-facing pitch + status |
| `docs/00-vision-and-scope.md` | Problem statement, design thesis, in/out of scope |
| `docs/01-reference-analysis.md` | Feature inventory of Baggins + BetterBags, steal/adapt/skip, and what a real heavy config looks like |
| `docs/02-requirements.md` | Numbered FR/NFR with MoSCoW priority + acceptance criteria |
| `docs/03-architecture.md` | Modules, pipeline, load order, file tree |
| `docs/04-data-model.md` | SavedVariables schema, rule grammar, migration/export |
| `docs/05-config-ui.md` | The differentiator: config UX design |
| `docs/06-milestones.md` | M0→M7 plan with exit criteria + in-game test checklists |
| `docs/07-open-questions.md` | Open decisions, each with a recommendation |
| `docs/08-window-behavior.md` | What our windows do on the live client: placement, suppression, chrome, money bar, item state |
| `tests/CHECKLIST.md` | Standing in-game acceptance checklist |

If a task contradicts `docs/02-requirements.md` or `docs/05-config-ui.md`, stop and ask.

---

## Where an answer lives

Append nothing here. Put the fact in the file that owns it, then get back to the code.

| Question | Home |
|---|---|
| Does this API exist on Forever, what does it return, what did the live client measure (bags, bank, containers, events, item data, constants, SavedVariables, keybindings, timing) | `../.agents/skills/wow-forever-api/` — `references/containers-and-bags.md`, `references/item-and-spell-data.md`, `references/ui-templates.md`, `references/client-identity.md`, `references/taint-and-secure.md`, `references/editmode-move-mode.md`, `references/wow-ui-source.md` |
| Choosing a widget or template, options-panel API, frame levels, chrome art | `references/ui-templates.md` |
| Combat lockdown, secure buttons, taint, deferred init | `references/taint-and-secure.md` (and hard rule 2 below) |
| What our windows and UI do, and the rules we chose | `docs/08-window-behavior.md`, `docs/05-config-ui.md` |
| Whether a feature is in scope, and why | `docs/00-vision-and-scope.md`, `docs/07-open-questions.md` |
| A raw in-game capture, dated | the GitHub issue, as a comment |
| A milestone's status | `docs/06-milestones.md`, and only at a milestone boundary |

**This is the anti-bloat rule.** A client fact that lands here is a fact nobody will find again: the
skill is what the next addon in this workspace reads, and `docs/` is what this project reads.
`tests/check-docs.sh` fails CI if `agents.md` outgrows its budget or a doc stops being indexed.

### Reference source

- `../wow-ui-source` — cloned `Gethe/wow-ui-source`. Forever UI lives on `origin/forever`:
  `git show origin/forever:Interface/AddOns/Blizzard_MainMenuBarBagButtons/Camelot/...`
- `../addons/Baggins` — the shape we want, `../addons/BetterBags` — the ergonomics we want (`docs/01`)
- `../account` — symlink to live `WTF/Account/1071383#1/` for SavedVariables inspection

---

## Hard rules

1. **Syntax checks prove nothing.** `luacheck`/`lua -p` passing is necessary, not sufficient.
   Every behavior change must be confirmed in-game on the Forever client. This repo's parent
   `../agents.md` states this because the API surface differs per client.
2. **Never perform protected actions.** No `RegisterEvent` on Blizzard/protected frames, no
   showing/hiding Blizzard container frames outside a lockdown-safe path, no secure-button
   attribute writes while `InCombatLockdown()`. Deferred init uses a plain
   `CreateFrame("Frame")` + `PLAYER_REGEN_ENABLED`, never an AceEvent-mediated deferral
   (that pattern already bit this workspace — see parent `../agents.md` §Debugging).
3. **Item buttons are secure.** Pool them, reuse them, and never re-create a button in combat.
   If a button must be created during lockdown, mark it `tainted` and replace it on regen.
4. **No AceConfig waterfall.** The config UI is hand-built per `docs/05-config-ui.md`. Adding
   `AceConfigDialog` back to solve a config problem is a spec change — argue it in
   `docs/07-open-questions.md` first.
5. **Config edits are model edits.** UI widgets never touch frames directly; they send commands
   to the model, the model emits change events, the view re-renders. Undo is a model concern.
6. **Every non-trivial branch gets a self-check.** A small assert-based test or `/bos test`
   path. Trivial changes need none.
7. `shortcut: <limit>, <when to upgrade>` comment on any deliberate limitation.
8. **Do not call a Blizzard container manager just to read it.** `ContainerFrameSettingsManager:GetBagsShown()`
   *builds and stores* the list; calling it from addon code tainted Blizzard's bag code on this client
   until `UseContainerItem` was refused (`../addons/ForeverPlus/Modules/BagWindow.lua`). Call a
   Blizzard function only after reading its source and finding that it writes nothing.
9. **No default `Ctrl+Z`/`Ctrl+Y` bindings** (`FR-76`). Undo is a button; those keys sit next to WASD.
10. **No theme/skin system, no `settings.theme`** (`docs/07` Q16). Build from `ItemButton` /
    `ContainerFrameItemButtonTemplate` / the client's bag atlases.
11. **Facts go to their home file, never here.** Client fact → the matching `wow-forever-api`
    reference; product verdict → the matching `docs/NN`; raw capture → the issue. `bash
    tests/check-docs.sh` before committing a doc change.

---

## Conventions

- **Language:** Lua 5.1 (WoW). No `goto`, no `#` on tables with nil holes.
- **Style:** 2-space indent, `local x = 1`, module tables as `local mod = addon:NewModule('Mod')`.
  Follow BetterBags' annotation style (`---@class`, `---@field`) — it is the readable half of
  the two references.
- **Naming:** addon folder / `addonName` / repo = **`BagsOfSorting`**, TOC title **`Bags of Sorting`**
  (plural decided, `docs/07` Q1), SavedVariables `BagsOfSortingDB`, slash command `/bos`. The client
  writes the file as `SavedVariables/BagsOfSorting.lua`, named after the folder whatever the TOC
  declares (`client-identity.md`, issue #14); settle the path before the SavedVariables growth harness
  (issue #8) baselines it.
- **File layout:** one concern per file, `core/`, `data/`, `layout/`, `frames/`, `config/`,
  `filters/`, `integrations/`, `util/`. **No `themes/`** (`docs/07` Q16: use the client's own bag
  visuals so the user's skinning addon works). Each directory gets a `README.md` (BetterBags does
  this; it is why BetterBags is navigable).
- **Locales:** single `L` table from `core/locale.lua` (key-falls-back-to-itself); enUS is the key
  source. Do not hand-write other locales at spec/prototype phase.
- **No new dependencies** without a `docs/07` entry. v1 target dependency set is **zero vendored
  libraries** (`docs/03` §Dependencies, `docs/07` Q2).
- **Milestone docs are planning documents.** `docs/06` changes when a milestone changes, not when a story
  inside one closes. A deliverable stays written as the plan wrote it; the verdict from its run goes to
  the reference file or `docs/` row that owns it, plus the issue. Only a milestone's own `Status:` line
  moves, and only at a milestone boundary.

## Repo boundary

This repo ships **one addon and nothing else**. Wow-wide assets (the `wow-forever-api` skill,
`wow-ui-source`, installed addons, the account symlink) live outside it and are reached by relative
paths from the parent workspace — never vendored here.

```bash
ls -a .   # LICENSE  Media/  agents.md  readme.md  docs/  .gitignore  .agents -> ../.agents (ignored)
```

`.agents` is a symlink to `../.agents` and is gitignored. Do not add shared scripts, shared docs, or
another addon under this tree. `LICENSE` (WTFPL) and `Media/Icon.png` are shipped content — they are
not in the `.pkgmeta` ignore list.

## Commands

```bash
luacheck .                      # lint (see .luacheckrc; WoW globals declared)
lua5.1 tests/run.lua            # headless pipeline + classifier checks (phases 1-7 touch no frames)
bash tests/check-docs.sh        # docs budget: agents.md size, every doc indexed, no dead doc links
lua5.1 -e "loadfile('X.lua')"   # syntax-only smoke
# install for in-game test: copy/symlink into ../addons/BagsOfSorting/
# in-game manual tests: /bos test  (core/diag.lua) — the pending list; /bos test <id> prints its numbered run sheet, one action per step
# capture workflow: .pi/skills/bos-test-capture/SKILL.md; the standing acceptance list: tests/CHECKLIST.md
# API questions: the `spike` issues, and the wow-forever-api skill before writing any code path
```

The harness in `tests/` is the smallest one M0 calls for: `luacheck` plus `lua5.1 tests/run.lua`, which
loads the real modules against a stubbed container API. `tests/` is **not in the TOC**, so the addon loads
no test code in a dev checkout or in a release zip. It proves the classifier and the pipeline wiring — not
the Forever API calls (hard rule 1).

The in-game half is the `/bos test` capture path, verified end-to-end on the live client (issue #27).
`core/diag.lua` holds the pending list; `.pi/skills/bos-test-capture/SKILL.md` is the whole workflow —
writing a test, running one action per step, syncing, ingesting the verdict to the file that owns it, and
deleting the entry.

---

## What not to do

- Do not fork Baggins or BetterBags. Read them for behavior; write our own.
- Do not add a filter/rule type without also adding its chip rendering + preview support in the
  config UI. A rule type that the UI cannot explain is a Baggins-style footgun.
- Do not add options that have no UI story. Every setting must answer: where does the user see
  it, and how do they learn it exists?
- Do not touch `../addons/Baggins` or `../addons/BetterBags` from this repo. They are read-only
  references (both are git clones of upstream).
- Do not paste a client fact into `agents.md`. Route it (hard rule 11).
