-- The in-game half of manual testing. Two things live here:
--
--   tests    short QA or investigation tasks tied to an open issue. `/bos test` lists the pending
--            ones, `/bos test 42` prints its run sheet, `/bos test 42b` runs one captured step.
--            An entry is added when a story needs measuring and deleted as part of ingesting the
--            capture. The workflow is `.pi/skills/bos-test-capture/SKILL.md`.
--   helpers  reusable captures a test step calls (dump, log, flags, keybind, newitem, clock,
--            expansion). Reachable from chat for ad-hoc investigation; they are not pending tests.
--
-- Everything a test captures goes to SavedVariables (`BagsOfSortingDB.diag.<issue>`) as well as to
-- chat. Off-client assertions live in `tests/run.lua`; these are the ones that need the live client.
-- Nothing here runs through `/script`: it is one line capped near 255 characters, which truncates a
-- real probe and reports `'end' expected near '<eof>'` — that reads like a Lua bug and is not one.

local _, addon = ...

---@class Diag: BoSModule
local diag = addon:NewModule('Diag')

-- Internal numeric keys. The names in HELPERS at the bottom of this file are what you type.
local probes = {}
local db = addon:GetModule('DB')

-- Probe output goes to SavedVariables as well as to chat (`BagsOfSortingDB.diag`), because pasting
-- a 60-line probe out of the chat window truncates it. After a /reload or a logout the whole run is
-- readable off disk: `../account/SavedVariables/BagsOfSorting.lua`.
-- shortcut: a dev artifact inside user data, capped per bucket. Issue #21 decides whether
-- core/diag.lua ships at all; if it becomes dev-only, this goes with it.
local MAX_LINES = 400
local bucket = 'probe'
-- True while a test step runs. A helper that resets its own bucket must not wipe the capture of the
-- test that called it.
local inTest = false

--- Write one captured line: to your own chat frame via `print`, and to the current bucket in
--- SavedVariables. `print` is local-only — nothing here calls SendChatMessage, so no probe output is
--- ever said, shouted or broadcast to another player.
local function record(...)
  local parts = { ... }
  for i = 1, #parts do parts[i] = tostring(parts[i]) end
  local line = table.concat(parts, ' ')
  print(line)
  db.sv.diag = db.sv.diag or {}
  local lines = db.sv.diag[bucket] or {}
  db.sv.diag[bucket] = lines
  lines[#lines + 1] = line
  if #lines > MAX_LINES then table.remove(lines, 1) end
end

--- Start a fresh bucket so repeated runs replace instead of piling up.
---@param name string
local function fresh(name)
  bucket = name
  db.sv.diag = db.sv.diag or {}
  db.sv.diag[name] = {}
end

--- dump — the bank arithmetic issue #9 is blocked on. Stand at an open bank with bank bags equipped.
probes[2] = function()
  -- Run it twice standalone — once with the bank open, once closed — and the two runs land in two
  -- buckets, so the diff is readable off disk without a paste. Inside a test step the bucket belongs
  -- to the test, so the bank state is recorded inline instead of switching buckets.
  local state = BankFrame and BankFrame:IsShown() and 'bankOpen' or 'bankClosed'
  if inTest then record('dump while', state) else fresh(state) end
  record('constants', NUM_BAG_SLOTS, NUM_REAGENTBAG_SLOTS, NUM_TOTAL_EQUIPPED_BAG_SLOTS,
    ITEM_INVENTORY_BANK_BAG_OFFSET, NUM_CHARACTER_BANK_SLOTS)
  record('bank window shown', BankFrame and tostring(BankFrame:IsShown()) or 'no BankFrame global')
  if C_Bank then
    record('usePlayerBagsInBank', C_Bank.ShouldUsePlayerBagsInBank())
    record('viewable bank types', table.concat(C_Bank.FetchViewableBankTypes() or {}, ','))
    record('tabs', 'max', C_Bank.FetchMaxNumBankTabs(Enum.BankType.Character),
      'hasMax', C_Bank.HasMaxBankTabs(Enum.BankType.Character),
      'purchased', C_Bank.FetchNumPurchasedBankTabs(Enum.BankType.Character),
      'canPurchase', C_Bank.CanPurchaseBankTab(Enum.BankType.Character),
      'lockedReason', tostring(C_Bank.FetchBankLockedReason(Enum.BankType.Character)))
    local tabs = C_Bank.FetchPurchasedBankTabData(Enum.BankType.Character) or {}
    record('purchased tab data', #tabs)
    for _, tab in ipairs(tabs) do
      record('  tab', tab.ID, tab.name, tab.icon, tab.depositFlags,
        C_Container.GetContainerNumSlots(tab.ID))
    end
    -- The client's own answer to "is the grid one container or several": Camelot's BankPanel
    -- builds the 6x8 grid by concatenating these containers, 8 columns, 88 slots per page
    -- (Camelot/BankFrame.xml:88). Read-only, and only populated while the bank is open.
    local panel = BankFrame and BankFrame.BankPanel
    local grid = panel and panel.purchasedBankTabData
    if grid then
      local ok, sum, perPage, page = pcall(function()
        return panel:GetTotalSlotsInAllTabs(), panel:GetMaximumTotalSlotsPerPage(), panel.currentPage
      end)
      record('grid containers', #grid, 'total slots', ok and sum or 'ERR',
        'per page', ok and perPage or 'ERR', 'page', ok and page or 'ERR')
      for _, tab in ipairs(grid) do
        record('  grid', tab.ID, C_Container.GetContainerNumSlots(tab.ID))
      end
    else
      record('grid containers: BankPanel.purchasedBankTabData unreachable — is the bank open?')
    end
    if C_Bank.BankBagTypeAndIDToInvSlot then
      -- Nine slots reported, eight visible. Camelot's RefreshBagButtons draws buttons for bag
      -- slots 2..max and skips 1 ("we start with the first bag purchased"), so which of these 9
      -- has an inventory slot is the 9-vs-8 answer.
      for i = 1, (NUM_CHARACTER_BANK_SLOTS or 0) do
        record('  bank bag', i, tostring(C_Bank.BankBagTypeAndIDToInvSlot(Enum.BankType.Character, i)))
      end
    end

    -- Purchased-bag shape (issue #25, measured 2026-10-19): the bag sits at index 7, is named `Bank`
    -- like every other bank container, and answers the slot count of whatever bag item is placed in it
    -- (6 -> 0 -> 8 across a swap). The panel lists it as a second container in the same paged grid.
    -- What these lines still watch for: paging past one 88-slot page, and a second bag slot appearing.
    local gridIndex = (ITEM_INVENTORY_BANK_BAG_OFFSET or 5) + 1
    local bankTotal = 0
    for index = gridIndex, gridIndex + (NUM_CHARACTER_BANK_SLOTS or 9) - 1 do
      local okName, name = pcall(C_Container.GetBagName, index)
      local okSlots, slots = pcall(C_Container.GetContainerNumSlots, index)
      if okSlots and slots then bankTotal = bankTotal + slots end
      record(string.format('  bank slot [%d] %s %s', index,
        okName and tostring(name) or 'ERR', okSlots and tostring(slots) or 'ERR'))
    end
    record('grid + bags 6..14 total slots', bankTotal,
      bankTotal > 88 and '— more than one 88-slot page' or '— still one page')
    local ids = C_Bank.FetchPurchasedBankTabIDs
      and C_Bank.FetchPurchasedBankTabIDs(Enum.BankType.Character)
    record('purchased tab ids', table.concat(ids or {}, ','))
    local nextTab = C_Bank.FetchNextPurchasableBankTabData
      and C_Bank.FetchNextPurchasableBankTabData(Enum.BankType.Character)
    if nextTab then
      record('next purchasable tab cost', tostring(nextTab.tabCost), 'canAfford',
        tostring(nextTab.canAfford), 'title', tostring(nextTab.purchasePromptTitle))
    end

  end
  -- The decisive number: every container index the client answers for, and what they sum to.
  -- If the sum is short by the base grid you counted by eye, the grid is not a container index.
  local total = 0
  for index = -3, 23 do
    local okName, name = pcall(C_Container.GetBagName, index)
    local okSlots, slots = pcall(C_Container.GetContainerNumSlots, index)
    if okSlots and slots then total = total + slots end
    record(string.format('  [%d] %s %s', index,
      okName and tostring(name) or 'ERR', okSlots and tostring(slots) or 'ERR'))
  end
  record('total container slots', total)
end

local BANK_EVENTS = {
  'BANKFRAME_OPENED', 'BANKFRAME_CLOSED', 'PLAYERBANKSLOTS_CHANGED',
  'BANK_TABS_CHANGED', 'BANK_BAG_SLOT_FLAGS_UPDATED', 'BANK_TAB_SETTINGS_UPDATED',
  'PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED', 'ITEM_LOCK_CHANGED', 'BAG_UPDATE',
}

--- PLAYERBANKSLOTS_CHANGED carries a **bank bag slot number 1..9**, not a container index (measured
--- 2026-10-19: payload 2 twice, once per change of the bag in bank slot 2). Camelot converts it the
--- same way — `ITEM_INVENTORY_BANK_BAG_OFFSET + bagSlot` — so the probe prints the container it means.
---@param bagSlot number?
---@return string? asContainer
function diag.ExplainBankSlot(bagSlot)
  if type(bagSlot) ~= 'number' then return nil end
  local container = (ITEM_INVENTORY_BANK_BAG_OFFSET or 5) + bagSlot
  local _, name = pcall(C_Container.GetBagName, container)
  local okSlots, slots = pcall(C_Container.GetContainerNumSlots, container)
  local asContainer = okSlots
    and string.format('bank bag slot %d -> container [%d] %s %s slots',
      bagSlot, container, tostring(name), tostring(slots))
    or string.format('bank bag slot %d -> container [%d] not a container', bagSlot, container)
  record(asContainer)
  return asContainer
end

--- log — what drives a bank refresh (issue #9 steps 10-11). Run at the bank to start logging, do
--- **one action at a time**, run it again to stop. It lives in the addon rather than in /script
--- because the logger snippet is longer than the client's ~255-character /script line.
local bankLogger
probes[3] = function()
  if bankLogger then
    bankLogger:UnregisterAllEvents()
    bankLogger = nil
    record('bank event logging off')
    return
  end
  if not inTest then fresh(bucket) end
  bankLogger = CreateFrame('Frame')
  local count = 0
  bankLogger:SetScript('OnEvent', function(self, event, ...)
    count = count + 1
    local args = { ... }
    for i = 1, #args do args[i] = tostring(args[i]) end
    record(string.format('#%d %s %s', count, event, table.concat(args, ' ')))
    if event == 'PLAYERBANKSLOTS_CHANGED' then diag.ExplainBankSlot((...)) end
  end)
  for _, name in ipairs(BANK_EVENTS) do bankLogger:RegisterEvent(name) end
  record('bank event logging on — one action at a time, then run the log helper again to stop')
end

--- keybind — does the client keep the key the player bound? Run before a reload, after it, and after a
--- logout. Compare against `grep BAGSOF_SORTING ../account/bindings-cache.wtf`.
probes[7] = function()
  bucket = 'keybind'
  record('--- probe 7 run ---')
  record('BAGSOF_SORTING_TOGGLE =', tostring(GetBindingKey('BAGSOF_SORTING_TOGGLE')))
  record('category', tostring(BINDING_HEADER_BAGSOF_SORTING),
    'label', tostring(BINDING_NAME_BAGSOF_SORTING_TOGGLE))
  -- Which side is broken: the client's binding table, or only its bindings file. `stored` is ours;
  -- if it survives while the client's key does not, the mirror is doing the work, and
  -- `grep BAGSOF_SORTING ../account/bindings-cache.wtf` says whether the client ever wrote it.
  record('binding set', GetCurrentBindingSet(),
    'registered index', tostring(C_KeyBindings.GetBindingIndex('BAGSOF_SORTING_TOGGLE')),
    'stored', tostring((db.sv.global.keybinds or {}).BAGSOF_SORTING_TOGGLE))
end

local LIT = {
  'NewItemTexture', 'flash', 'IconQuestTexture', 'IconOverlay', 'IconOverlay2',
  'ProfessionQualityOverlay', 'IconBorder', 'UpgradeIcon', 'JunkIcon',
}

local function lit(button, label)
  for _, key in ipairs(LIT) do
    local texture = button[key]
    if texture and texture:IsShown() and (texture:GetAlpha() or 0) > 0 then
      record(label, key, texture:GetAtlas() or tostring(texture:GetTexture() or ''),
        string.format('alpha=%.2f', texture:GetAlpha()))
    end
  end
end

--- newitem — what is actually glowing, on our buttons and on the client's own. Loot something new
--- first, then run this **before** hovering anything: hovering is what clears the state.
probes[11] = function()
  local ours = 0
  for i = 1, 400 do
    local button = _G['BagsOfSortingItemButton' .. i]
    if button and button:IsShown() then
      ours = ours + 1
      lit(button, 'ours ' .. i)
    end
  end
  record('our visible buttons', ours)

  local blizzard = ContainerFrameCombinedBags and ContainerFrameCombinedBags.items
  if not blizzard then
    record('client bag buttons: ContainerFrameCombinedBags.items not reachable, compare by eye')
    return
  end
  for _, slots in pairs(blizzard) do
    for _, button in pairs(slots or {}) do
      if button and button:IsShown() then lit(button, 'client') end
    end
  end
end

--- Many refreshes spread over frames, timed across the span. A refresh measured inside one frame
--- always reads 0.00 on this client (see probe 13), which is what makes the pipeline measurable at
--- all for AC-100/AC-101.
---@param perFrame number?
---@param frames number?
function diag.Bench(perFrame, frames)
  perFrame = tonumber(perFrame) or 100
  frames = tonumber(frames) or 10
  local pipeline = addon:GetModule('Pipeline')
  local started = GetTime()
  local done = 0
  local function step()
    for _ = 1, perFrame do pipeline.Refresh('bench') end
    done = done + 1
    if done < frames then
      C_Timer.After(0, step)
    else
      local ms = (GetTime() - started) * 1000
      local runs = perFrame * frames
      print(string.format('bench: %d refreshes over %d frames, %.0fms total, %.2fms per refresh',
        runs, frames, ms, ms / runs))
      -- shortcut: 16ms is a 60fps frame, used only to say how much of the total is frame time.
      print(string.format('at least %.0fms of that is frame time, not pipeline', frames * 16))
    end
  end
  step()
end

--- clock — how fine a clock this client hands us, then the pipeline cost measured with it.
probes[13] = function()
  -- Every timing recorded from now on carries the build it was measured on (issue #24).
  print('build:', GetBuildInfo())

  local started = GetTime()
  local sum = 0
  for _ = 1, 1e6 do sum = sum + 1 end
  print(string.format('clock: 1e6 Lua iterations measured %.1fms — 0 means GetTime is frame-quantized',
    (GetTime() - started) * 1000))
  diag.Bench()
end

--- expansion — is the `expansion` field readable here, and is position 15 of C_Item.GetItemInfo really the
--- expansion ID? `data/enrich.lua` reads it as the 15th return, so a wrong position misclassifies
--- every expansion rule without ever erroring. M1's risk list asks whether expansion is cheap enough
--- to keep in the v1 field set (docs/02 FR-21). Run it with items in your bags: it only reads.
probes[14] = function()
  fresh('expansion')
  local harvest = addon:GetModule('Harvest')
  local enrich = addon:GetModule('Enrich')
  local field = addon:GetModule('FieldRegistry').Get('expansion')
  local labels = {}
  for _, v in ipairs(field and field.values() or {}) do labels[v.v] = v.label end

  local items = harvest.Items()
  record('harvested items', #items)
  if #items == 0 then
    record('nothing in the bags to read — pick up an item first')
    return
  end

  -- The whole return list, numbered, for one item: position 15 has to be checked against the
  -- name/quality/ilvl around it, not trusted from another client's ordering.
  local first = items[1].itemID
  local rets = { pcall(C_Item.GetItemInfo, first) }
  if rets[1] then
    record(string.format('C_Item.GetItemInfo(%d) returns by position:', first))
    for i = 2, #rets do record(string.format('  %d %s', i - 1, tostring(rets[i]))) end
  else
    record(string.format('C_Item.GetItemInfo(%d) errored: %s', first, tostring(rets[2])))
  end

  local full = enrich.ReadFull(first)
  record('enrich.ReadFull position 15 -> expansion', full and tostring(full.expansion) or 'nil',
    labels[full and full.expansion or -1] or '')

  -- The free read only: ReadFull never issues a request, so this is what a refresh can know
  -- without waiting for tier 3.
  local answered, withExpansion, values = 0, 0, {}
  for _, item in ipairs(items) do
    local read = enrich.ReadFull(item.itemID)
    if read then
      answered = answered + 1
      if read.expansion ~= nil then
        withExpansion = withExpansion + 1
        values[read.expansion] = (values[read.expansion] or 0) + 1
      end
    end
  end
  record('free read answered', answered, 'of', #items, 'items; expansion present', withExpansion)
  for id, count in pairs(values) do
    record(string.format('  expansion %s (%s) x%d', tostring(id), labels[id] or 'unknown', count))
  end
  record('verdict: expansion is',
    answered == 0 and 'NOT readable without a request — drop the field (docs/02 FR-21)'
    or (withExpansion == 0 and 'readable but always nil — drop the field (docs/02 FR-21)'
      or 'readable for items the client already knows'))
end


--- Which container index holds this item? Answers "is the base grid a container?" with an item you
--- can see and place on purpose, rather than with slot arithmetic. Read-only: `GetContainerItemInfo`
--- reads, it builds nothing (agents.md hard rule 8).
---@param itemID number
---@return number containersFound
function diag.Find(itemID)
  if not itemID then print('usage: /bos find <itemID>') return end
  bucket = 'find'
  local found = 0
  for index = -3, 23 do
    local okSlots, slots = pcall(C_Container.GetContainerNumSlots, index)
    if okSlots and slots and slots > 0 then
      for slot = 1, slots do
        local ok, info = pcall(C_Container.GetContainerItemInfo, index, slot)
        if ok and info and info.itemID == itemID then
          found = found + 1
          record(string.format('  [%d] slot %d  %s x%s', index, slot,
            tostring(info.itemName), tostring(info.stackCount or 1)))
        end
      end
    end
  end
  record(string.format('containers holding item %d: %d', itemID, found))
  return found
end

--- One container's specialty flags, read from `Enum.BagSlotFlags` rather than guessed (FR-19).
---@param index number
local function flagsOne(index)
  local found = {}
  for name, flag in pairs(Enum.BagSlotFlags or {}) do
    if C_Container.GetBagSlotFlag(index, flag) then found[#found + 1] = name end
  end
  record(index, tostring(C_Container.GetBagName(index)), table.concat(found, ','))
end

--- Equipped bags, then the bank containers. This is what issue #2 measured with two /script lines;
--- a test step calls it instead.
local function flagsScan()
  for index = 0, (NUM_TOTAL_EQUIPPED_BAG_SLOTS or 5) do flagsOne(index) end
  local grid = (ITEM_INVENTORY_BANK_BAG_OFFSET or 5) + 1
  for index = grid, grid + (NUM_CHARACTER_BANK_SLOTS or 9) - 1 do flagsOne(index) end
end

-- The names you type. A test step calls the same functions.
local HELPERS = {
  dump = probes[2], log = probes[3], keybind = probes[7], newitem = probes[11],
  clock = probes[13], expansion = probes[14], flags = flagsScan,
}

-- ---------------------------------------------------------------------------
-- Pending manual tests: one entry per open issue, added when a story needs measuring and deleted
-- when its capture is ingested. `issue` is the GitHub issue the run sheet answers; the id is what
-- you type. A step is { text = ..., run = ... }: text is the line the run sheet prints, and a step
-- with no run is a manual action and gets no letter — the captured steps on either side of it are
-- what make the capture readable.
-- ---------------------------------------------------------------------------
local tests = {
  [15] = {
    issue = 15,
    what = 'what draws the new-item glow on our buttons (FR-47)',
    needs = 'loot one new item first, then hover nothing before step a',
    steps = {
      { text = 'setup: which of our buttons are lit, and the client buttons too', run = probes[11] },
      { text = 'hover the glowing button' },
      { text = 'look at the slot two seconds later' },
      { text = 'capture: which buttons are lit now', run = probes[11] },
    },
  },
  [22] = {
    issue = 22,
    what = "BetterBags' combat behaviour (input to the Q23 decision)",
    needs = 'BetterBags loaded with its bags open, and a target to attack',
    steps = {
      { text = 'setup: which addons are loaded, then start event logging', run = function()
          record('BetterBags', tostring(IsAddOnLoaded('BetterBags')),
            'Leatrix_Plus', tostring(IsAddOnLoaded('Leatrix_Plus')),
            'ForeverPlus', tostring(IsAddOnLoaded('ForeverPlus')))
          probes[3]()
        end },
      { text = 'attack a target until you take damage' },
      { text = 'open a BetterBags window during combat' },
      { text = 'close that window' },
      { text = 'capture: stop event logging', run = probes[3] },
    },
  },
}

local function letterOf(n) return string.char(96 + n) end

local function capturedCount(id)
  local n = 0
  for _, step in ipairs(tests[id].steps) do
    if step.run then n = n + 1 end
  end
  return n
end

--- The pending list.
---@return {id:number, what:string, needs:string}[]
function diag.Tests()
  local out = {}
  for id, t in pairs(tests) do out[#out + 1] = { id = id, what = t.what, needs = t.needs } end
  table.sort(out, function(a, b) return a.id < b.id end)
  return out
end

--- Add a test at runtime. The off-client harness uses it to exercise the dispatcher without
--- borrowing an entry from the pending list.
function diag.Add(id, spec) tests[id] = spec end

--- Print the numbered run sheet (no letter) or run one captured step. Every step is one action.
--- Captured steps are lettered a, b, c… in order, and the first one opens the bucket for this test;
--- later ones append to it.
---@param id number
---@param letter string?
---@return string? the step text that ran, the test name when the sheet was printed, nil for a bad letter
function diag.Test(id, letter)
  local t = tests[id]
  if not t then return nil end

  if not letter then
    print(string.format('Test %d (issue #%d): %s', id, t.issue, t.what))
    print('pre-conditions: ' .. t.needs)
    local n, line = 0, 0
    for _, step in ipairs(t.steps) do
      line = line + 1
      if step.run then
        n = n + 1
        print(string.format('%d. /bos test %d%s  %s', line, id, letterOf(n), step.text))
      else
        print(string.format('%d. %s', line, step.text))
      end
    end
    print(string.format('%d. /reload', line + 1))
    print(string.format('%d. ../sync.sh', line + 2))
    return t.what
  end

  local want, n, total = letter:byte() - 96, 0, capturedCount(id)
  for _, step in ipairs(t.steps) do
    if step.run then
      n = n + 1
      if n == want then
        if n == 1 then fresh(tostring(id)) else bucket = tostring(id) end
        local iface, build = GetBuildInfo()
        record(string.format('--- %d%s %s | build %s (%s) | %s - %s ---', id, letterOf(n), step.text,
          iface, tostring(build), tostring(UnitName('player')), tostring(GetRealmName())))
        inTest = true
        local ok, err = pcall(step.run)
        inTest = false
        if not ok then record('step failed: ' .. tostring(err)) end
        if n == total then
          record(string.format('captured %d%s — paste the [%d] bucket into issue #%d, then remove '
            .. 'test %d from core/diag.lua', id, letterOf(n), id, t.issue, id))
        end
        return step.text
      end
    end
  end
  return nil
end

--- `/bos test` with whatever follows it: nothing (the list), an id, an id + letter, or a helper name.
---@param rest string?
function diag.Command(rest)
  rest = rest or ''

  local id = tonumber(rest:match('^(%d+)'))
  if id then
    if not tests[id] then
      print('no test ' .. id .. ' — /bos test lists the pending ones')
      return
    end
    local letter = rest:match('^%d+(%a)')
    if not diag.Test(id, letter and letter:lower()) then print('no such step: ' .. rest) end
    return
  end

  local name = rest:match('^(%a+)')
  local helper = name and HELPERS[name]
  if helper then
    bucket = name
    inTest = false
    local ok, err = pcall(helper)
    if not ok then print('helper ' .. name .. ' failed: ' .. tostring(err)) end
    return
  end

  local pending = diag.Tests()
  print(string.format('pending tests (%d)', #pending))
  for _, t in ipairs(pending) do
    print(string.format('  %d  %s  —  %s', t.id, t.what, t.needs))
  end
  print('helpers: dump · log · flags · keybind · newitem · clock · expansion')
end

return diag
