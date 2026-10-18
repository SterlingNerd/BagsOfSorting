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

--- 2 — the bank arithmetic issue #9 is blocked on. Stand at an open bank with bank bags equipped.
probes[2] = function()
  print('constants', NUM_BAG_SLOTS, NUM_REAGENTBAG_SLOTS, NUM_TOTAL_EQUIPPED_BAG_SLOTS,
    ITEM_INVENTORY_BANK_BAG_OFFSET, NUM_CHARACTER_BANK_SLOTS)
  if C_Bank then
    print('usePlayerBagsInBank', C_Bank.ShouldUsePlayerBagsInBank())
    local tabs = C_Bank.FetchPurchasedBankTabData(Enum.BankType.Character) or {}
    print('purchased tabs', #tabs, 'max', C_Bank.FetchMaxNumBankTabs(Enum.BankType.Character))
    for _, tab in ipairs(tabs) do
      print('  tab', tab.ID, tab.name, tab.icon, tab.depositFlags,
        C_Container.GetContainerNumSlots(tab.ID))
    end
  end
  if C_Bank.BankBagTypeAndIDToInvSlot then
    -- Nine slots reported, eight visible in the UI. This says which of the two the client treats as
    -- real bank bags: a nil inventory slot means the ninth is not a bag.
    for i = 1, (NUM_CHARACTER_BANK_SLOTS or 0) do
      print('  bank bag', i, tostring(C_Bank.BankBagTypeAndIDToInvSlot(Enum.BankType.Character, i)))
    end
  end
  -- The decisive number: every container index the client answers for, and what they sum to.
  -- If the sum is short by the base grid you counted by eye, the grid is not a container index.
  local total = 0
  for index = -3, 23 do
    local okName, name = pcall(C_Container.GetBagName, index)
    local okSlots, slots = pcall(C_Container.GetContainerNumSlots, index)
    if okSlots and slots then total = total + slots end
    print(string.format('  [%d] %s %s', index,
      okName and tostring(name) or 'ERR', okSlots and tostring(slots) or 'ERR'))
  end
  print('total container slots', total)
end

--- 7 — does the client keep the key the player bound? Run before a reload, after it, and after a
--- logout. Compare against `grep BAGSOF_SORTING ../account/bindings-cache.wtf`.
probes[7] = function()
  print('BAGSOF_SORTING_TOGGLE =', tostring(GetBinding('BAGSOF_SORTING_TOGGLE')))
  print('category', tostring(BINDING_HEADER_BAGSOF_SORTING),
    'label', tostring(BINDING_NAME_BAGSOF_SORTING_TOGGLE))
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
    print('probes: 2 bank arithmetic (#9) · 7 keybind persistence · 11 new-item textures · 13 clock + pipeline cost')
    return
  end
  local ok, err = pcall(probe)
  if not ok then print('probe ' .. tostring(n) .. ' failed: ' .. tostring(err)) end
end

return diag
