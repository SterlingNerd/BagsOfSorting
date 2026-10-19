-- `/bos test <n>`: the in-game half of the checklist (`tests/CHECKLIST.md`). Each probe prints
-- what a human pastes into the milestone entry in `docs/06` or into the spike issue it answers.
-- Off-client assertions live in `tests/run.lua`; these are the ones that need the live client.
--
-- They live in the addon rather than in `/script` because `/script` is a single line capped near
-- 255 characters — long enough to truncate a probe and report `'end' expected near '<eof>'`, which
-- reads like a Lua bug and is not one.

local _, addon = ...

---@class Diag: BoSModule
local diag = addon:NewModule('Diag')

local probes = {}
local db = addon:GetModule('DB')

-- Probe output goes to SavedVariables as well as to chat (`BagsOfSortingDB.diag`), because pasting
-- a 60-line probe out of the chat window truncates it. After a /reload or a logout the whole run is
-- readable off disk: `../account/SavedVariables/BagsOfSorting.lua`.
-- shortcut: a dev artifact inside user data, capped per bucket. Issue #21 decides whether
-- core/diag.lua ships at all; if it becomes dev-only, this goes with it.
local MAX_LINES = 400
local bucket = 'probe'

local function say(...)
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

--- 2 — the bank arithmetic issue #9 is blocked on. Stand at an open bank with bank bags equipped.
probes[2] = function()
  -- Run it twice — once with the bank open, once closed — and the two runs land in two buckets,
  -- so the diff is readable off disk without a paste.
  fresh(BankFrame and BankFrame:IsShown() and 'bankOpen' or 'bankClosed')
  say('constants', NUM_BAG_SLOTS, NUM_REAGENTBAG_SLOTS, NUM_TOTAL_EQUIPPED_BAG_SLOTS,
    ITEM_INVENTORY_BANK_BAG_OFFSET, NUM_CHARACTER_BANK_SLOTS)
  say('bank window shown', BankFrame and tostring(BankFrame:IsShown()) or 'no BankFrame global')
  if C_Bank then
    say('usePlayerBagsInBank', C_Bank.ShouldUsePlayerBagsInBank())
    say('viewable bank types', table.concat(C_Bank.FetchViewableBankTypes() or {}, ','))
    say('tabs', 'max', C_Bank.FetchMaxNumBankTabs(Enum.BankType.Character),
      'hasMax', C_Bank.HasMaxBankTabs(Enum.BankType.Character),
      'purchased', C_Bank.FetchNumPurchasedBankTabs(Enum.BankType.Character),
      'canPurchase', C_Bank.CanPurchaseBankTab(Enum.BankType.Character),
      'lockedReason', tostring(C_Bank.FetchBankLockedReason(Enum.BankType.Character)))
    local tabs = C_Bank.FetchPurchasedBankTabData(Enum.BankType.Character) or {}
    say('purchased tab data', #tabs)
    for _, tab in ipairs(tabs) do
      say('  tab', tab.ID, tab.name, tab.icon, tab.depositFlags,
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
      say('grid containers', #grid, 'total slots', ok and sum or 'ERR',
        'per page', ok and perPage or 'ERR', 'page', ok and page or 'ERR')
      for _, tab in ipairs(grid) do
        say('  grid', tab.ID, C_Container.GetContainerNumSlots(tab.ID))
      end
    else
      say('grid containers: BankPanel.purchasedBankTabData unreachable — is the bank open?')
    end
    if C_Bank.BankBagTypeAndIDToInvSlot then
      -- Nine slots reported, eight visible. Camelot's RefreshBagButtons draws buttons for bag
      -- slots 2..max and skips 1 ("we start with the first bag purchased"), so which of these 9
      -- has an inventory slot is the 9-vs-8 answer.
      for i = 1, (NUM_CHARACTER_BANK_SLOTS or 0) do
        say('  bank bag', i, tostring(C_Bank.BankBagTypeAndIDToInvSlot(Enum.BankType.Character, i)))
      end
    end
  end
  -- The decisive number: every container index the client answers for, and what they sum to.
  -- If the sum is short by the base grid you counted by eye, the grid is not a container index.
  local total = 0
  for index = -3, 23 do
    local okName, name = pcall(C_Container.GetBagName, index)
    local okSlots, slots = pcall(C_Container.GetContainerNumSlots, index)
    if okSlots and slots then total = total + slots end
    say(string.format('  [%d] %s %s', index,
      okName and tostring(name) or 'ERR', okSlots and tostring(slots) or 'ERR'))
  end
  say('total container slots', total)
end

local BANK_EVENTS = {
  'BANKFRAME_OPENED', 'BANKFRAME_CLOSED', 'PLAYERBANKSLOTS_CHANGED',
  'BANK_TABS_CHANGED', 'BANK_BAG_SLOT_FLAGS_UPDATED', 'BANK_TAB_SETTINGS_UPDATED',
  'PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED', 'ITEM_LOCK_CHANGED', 'BAG_UPDATE',
}

--- Is the number in PLAYERBANKSLOTS_CHANGED a container index or a slot inside the grid? Read it
--- both ways at fire time, so the paste carries the answer instead of a number a human has to
--- cross-reference against probe 2 afterwards.
---@param slot number?
---@return string? asContainer
---@return string? asGridSlot
function diag.ExplainBankSlot(slot)
  if type(slot) ~= 'number' then return nil end
  local gridIndex = (ITEM_INVENTORY_BANK_BAG_OFFSET or 5) + 1
  local _, name = pcall(C_Container.GetBagName, slot)
  local okSlots, slots = pcall(C_Container.GetContainerNumSlots, slot)
  local asContainer = okSlots
    and (tostring(name) .. ' [' .. slot .. '] ' .. tostring(slots) .. ' slots')
    or ('[' .. slot .. '] not a container')
  local okItem, info = pcall(C_Container.GetContainerItemInfo, gridIndex, slot)
  local asGridSlot = (okItem and info and info.itemID)
    and (tostring(info.itemName) .. ' x' .. tostring(info.stackCount or 1)) or 'empty'
  say('    as container index: ' .. asContainer)
  say(string.format('    as slot in grid [%d]: %s', gridIndex, asGridSlot))
  return asContainer, asGridSlot
end

--- 3 — what drives a bank refresh (issue #9 steps 10-11). Run at the bank to start logging, do
--- **one action at a time**, run it again to stop. It lives in the addon rather than in /script
--- because the logger snippet is longer than the client's ~255-character /script line.
local bankLogger
probes[3] = function()
  if bankLogger then
    bankLogger:UnregisterAllEvents()
    bankLogger = nil
    say('bank event logging off')
    return
  end
  fresh('bankEvents')
  bankLogger = CreateFrame('Frame')
  local count = 0
  bankLogger:SetScript('OnEvent', function(self, event, ...)
    count = count + 1
    local args = { ... }
    for i = 1, #args do args[i] = tostring(args[i]) end
    say(string.format('#%d %s %s', count, event, table.concat(args, ' ')))
    if event == 'PLAYERBANKSLOTS_CHANGED' then diag.ExplainBankSlot((...)) end
  end)
  for _, name in ipairs(BANK_EVENTS) do bankLogger:RegisterEvent(name) end
  say('bank event logging on — one action at a time, then /bos test 3 again to stop')
end

--- 7 — does the client keep the key the player bound? Run before a reload, after it, and after a
--- logout. Compare against `grep BAGSOF_SORTING ../account/bindings-cache.wtf`.
probes[7] = function()
  bucket = 'keybind'
  say('--- probe 7 run ---')
  say('BAGSOF_SORTING_TOGGLE =', tostring(GetBindingKey('BAGSOF_SORTING_TOGGLE')))
  say('category', tostring(BINDING_HEADER_BAGSOF_SORTING),
    'label', tostring(BINDING_NAME_BAGSOF_SORTING_TOGGLE))
  -- Which side is broken: the client's binding table, or only its bindings file. `stored` is ours;
  -- if it survives while the client's key does not, the mirror is doing the work, and
  -- `grep BAGSOF_SORTING ../account/bindings-cache.wtf` says whether the client ever wrote it.
  say('binding set', GetCurrentBindingSet(),
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
      print(label, key, texture:GetAtlas() or tostring(texture:GetTexture() or ''),
        string.format('alpha=%.2f', texture:GetAlpha()))
    end
  end
end

--- 11 — what is actually glowing, on our buttons and on the client's own. Loot something new first,
--- then run this **before** hovering anything: hovering is what clears the state.
probes[11] = function()
  local ours = 0
  for i = 1, 400 do
    local button = _G['BagsOfSortingItemButton' .. i]
    if button and button:IsShown() then
      ours = ours + 1
      lit(button, 'ours ' .. i)
    end
  end
  print('our visible buttons', ours)

  local blizzard = ContainerFrameCombinedBags and ContainerFrameCombinedBags.items
  if not blizzard then
    print('client bag buttons: ContainerFrameCombinedBags.items not reachable, compare by eye')
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

--- 13 — how fine a clock this client hands us, then the pipeline cost measured with it.
probes[13] = function()
  local started = GetTime()
  local sum = 0
  for _ = 1, 1e6 do sum = sum + 1 end
  print(string.format('clock: 1e6 Lua iterations measured %.1fms — 0 means GetTime is frame-quantized',
    (GetTime() - started) * 1000))
  diag.Bench()
end

--- 14 — is the `expansion` field readable here, and is position 15 of C_Item.GetItemInfo really the
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
  say('harvested items', #items)
  if #items == 0 then
    say('nothing in the bags to read — pick up an item first')
    return
  end

  -- The whole return list, numbered, for one item: position 15 has to be checked against the
  -- name/quality/ilvl around it, not trusted from another client's ordering.
  local first = items[1].itemID
  local rets = { pcall(C_Item.GetItemInfo, first) }
  if rets[1] then
    say(string.format('C_Item.GetItemInfo(%d) returns by position:', first))
    for i = 2, #rets do say(string.format('  %d %s', i - 1, tostring(rets[i]))) end
  else
    say(string.format('C_Item.GetItemInfo(%d) errored: %s', first, tostring(rets[2])))
  end

  local full = enrich.ReadFull(first)
  say('enrich.ReadFull position 15 -> expansion', full and tostring(full.expansion) or 'nil',
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
  say('free read answered', answered, 'of', #items, 'items; expansion present', withExpansion)
  for id, count in pairs(values) do
    say(string.format('  expansion %s (%s) x%d', tostring(id), labels[id] or 'unknown', count))
  end
  say('verdict: expansion is',
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
  local found = 0
  for index = -3, 23 do
    local okSlots, slots = pcall(C_Container.GetContainerNumSlots, index)
    if okSlots and slots and slots > 0 then
      for slot = 1, slots do
        local ok, info = pcall(C_Container.GetContainerItemInfo, index, slot)
        if ok and info and info.itemID == itemID then
          found = found + 1
          print(string.format('  [%d] slot %d  %s x%s', index, slot,
            tostring(info.itemName), tostring(info.stackCount or 1)))
        end
      end
    end
  end
  print(string.format('containers holding item %d: %d', itemID, found))
  return found
end

--- Run one probe by number.
---@param n number?
function diag.Run(n)
  local probe = probes[n]
  if not probe then
    print('probes: 2 bank containers (#9) · 3 bank events (#9) · 7 keybind persistence '
      .. '· 11 new-item textures · 13 clock + pipeline cost · 14 expansion field')
    return
  end
  local ok, err = pcall(probe)
  if not ok then print('probe ' .. tostring(n) .. ' failed: ' .. tostring(err)) end
end

return diag
