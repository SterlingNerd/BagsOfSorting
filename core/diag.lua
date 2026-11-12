-- The in-game half of manual testing. Two things live here:
--
--   tests    short QA or investigation tasks tied to an open issue. `/bos test` lists the pending
--            ones, `/bos test 42` prints its run sheet, `/bos test 42b` runs one captured step.
--            An entry is added when a story needs measuring and deleted as part of ingesting the
--            capture. The workflow is the `bos-test-capture` skill.
--   helpers  reusable captures a test step calls (dump, log, flags, keybind, newitem, clock,
--            expansion, windows). Reachable from chat for ad-hoc investigation; they are not pending
--            tests.
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

-- The client's interaction windows and the container traffic around them. Issue #9 filled the bank
-- half; issue #38 added the vendor half.
local INTERACTION_EVENTS = {
  'BANKFRAME_OPENED', 'BANKFRAME_CLOSED', 'PLAYERBANKSLOTS_CHANGED',
  'BANK_TABS_CHANGED', 'BANK_BAG_SLOT_FLAGS_UPDATED', 'BANK_TAB_SETTINGS_UPDATED',
  'PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED', 'ITEM_LOCK_CHANGED', 'BAG_UPDATE',
  'MERCHANT_SHOW', 'MERCHANT_CLOSED',
  -- Blocked-action events carry (isTainted, function) — the function name issue #4 asks for. Whether an
  -- addon-owned frame may register them at all is itself one of the measurements. Issue #4's run stalled at
  -- a `/console` review step: `/console` here is ConsoleExec, a cvar command that opens no window.
  'ADDON_ACTION_BLOCKED', 'ADDON_ACTION_FORBIDDEN',
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
  for _, name in ipairs(INTERACTION_EVENTS) do bankLogger:RegisterEvent(name) end
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
    -- A texture with nothing in it is shown at alpha 1 and draws nothing: the template's
    -- IconQuestTexture is in that state until something calls UpdateQuestItem (FR-45, issue #16).
    -- Reporting it as "lit" buried the one line this probe exists to find.
    local content = texture and (texture:GetAtlas() or texture:GetTexture())
    if content and texture:IsShown() and (texture:GetAlpha() or 0) > 0 then
      record(label, key, tostring(content), string.format('alpha=%.2f', texture:GetAlpha()))
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

  -- Blizzard's own buttons, read off the frame's own `Items` table (BaseContainerFrameMixin:
  -- EnumerateItems iterates self.Items). Not `.items`, which does not exist and is why the first
  -- run of this probe printed nothing here; and not GetBagsShown(), which hard rule 8 forbids.
  -- The buttons are unnamed CreateFramePool frames, so unlike ours they are not reachable by name.
  local bag = ContainerFrameCombinedBags
  local items = bag and bag.Items
  if not items then
    record('client bag buttons: ContainerFrameCombinedBags.Items not reachable')
    return
  end
  local shown = 0
  for _, button in ipairs(items) do
    if button and button:IsShown() then
      shown = shown + 1
      lit(button, 'client')
    end
  end
  -- A closed bag window has no visible buttons, which is the state a player who uses our windows is
  -- usually in. Say so, so an empty half of the capture is a result and not a failure.
  record('client bag buttons', 'window', bag:IsShown() and 'shown' or 'closed', 'visible', shown)
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
      -- record, not print: this is the only pipeline number this client can produce, and a test
      -- step's capture is read off disk, not out of the chat window (issue #8).
      record(string.format('bench: %d refreshes over %d frames, %.0fms total, %.2fms per refresh',
        runs, frames, ms, ms / runs))
      -- shortcut: 16ms is a 60fps frame, used only to say how much of the total is frame time.
      record(string.format('at least %.0fms of that is frame time, not pipeline', frames * 16))
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


--- windows — where our own windows sit and what each one holds (issue #28). Reads the layout model
--- *and* the frames it produced, so a placement bug and a paint bug are separable in the capture.
--- Read-only: nothing here moves a frame.
probes[16] = function()
  if not inTest then fresh('windows') end
  local pipeline = addon:GetModule('Pipeline')
  local windowFrames = addon:GetModule('WindowFrames')
  local models = pipeline.Model()
  if not models then record('no refresh has run yet') return end

  local bag = _G.ContainerFrameCombinedBags
  local anchor = (bag and bag:IsShown() and bag) or _G.MainMenuBarBackpackButton
  record('windows in the model', #models, 'shown', windowFrames.Count(),
    'anchor', anchor and tostring(anchor:GetName()) or 'none',
    'anchor bottom', anchor and tostring(anchor:GetBottom()) or '-',
    'anchor right', anchor and tostring(anchor:GetRight()) or '-',
    'screen', GetScreenWidth(), GetScreenHeight())

  for _, window in ipairs(models) do
    local items = 0
    record(string.format('  [%s] %s sections=%d %dx%d x=%s y=%s', window.id, window.name,
      #window.sections, tostring(window.width), tostring(window.height),
      tostring(window.x), tostring(window.y)))
    for _, section in ipairs(window.sections) do
      items = items + #section.items
      local ids = {}
      for _, item in ipairs(section.items) do ids[#ids + 1] = tostring(item.itemID) end
      record('    section', section.name, #section.items, table.concat(ids, ' '))
    end
    local frame = _G['BagsOfSortingWindow' .. window.id]
    if not frame then
      record('    frame: none')
    else
      local point, relativeTo, relativePoint, x, y = frame:GetPoint()
      record('    frame', tostring(frame:IsShown()), 'size', tostring(frame:GetWidth()),
        tostring(frame:GetHeight()), 'bottom', tostring(frame:GetBottom()),
        'right', tostring(frame:GetRight()),
        'point', tostring(point), tostring(relativeTo and relativeTo:GetName() or 'nil'),
        tostring(relativePoint), tostring(x), tostring(y),
        'saved', frame.config and frame.config.position and 'yes' or 'no')
      local bar = frame.MoneyFrame
      if not bar then
        record('    money: none')
      else
        -- The bar's own coin texts against the client's number: the bar is Blizzard's, so a mismatch
        -- is a bar that never refreshed, not arithmetic we got wrong (issue #32).
        record('    money', 'shown', tostring(bar:IsShown()), 'h', tostring(bar:GetHeight()),
          'coins', bar.GoldButton.Text:GetText(), bar.SilverButton.Text:GetText(),
          bar.CopperButton.Text:GetText(), 'GetMoney()', GetMoney())
      end
    end
  end
  record('pool', addon:GetModule('Pool').Stats())
end

--- freeslots — the numbers behind the free-slot indicator (issue #36). Our own count, the client's
--- own total, and the slot each window actually drew, so a wrong number and a wrong drawing are
--- separable in the capture. Read-only.
probes[17] = function()
  if not inTest then fresh('freeslots') end
  local constants = addon:GetModule('Constants')
  local harvest = addon:GetModule('Harvest')
  local pipeline = addon:GetModule('Pipeline')

  -- The client's own number, the one Blizzard puts on its backpack button. Source-verified
  -- (ContainerDocumentation.lua) and never yet measured on this client, so a `no answer` here is
  -- itself the result.
  local ok, total = pcall(C_Container.CalculateTotalNumberOfFreeBagSlots)
  record('C_Container.CalculateTotalNumberOfFreeBagSlots()', ok and tostring(total) or 'no answer')

  for _, container in ipairs(harvest.Containers()) do
    local filled = 0
    for slot = 1, container.slots do
      local infoOK, info = pcall(C_Container.GetContainerItemInfo, container.index, slot)
      if infoOK and info and info.itemID then filled = filled + 1 end
    end
    record(string.format('  [%d] %s slots=%d filled=%d free=%d kind=%s family=%s',
      container.index, container.name, container.slots, filled, container.slots - filled,
      container.kind, tostring(container.family)))
  end

  -- The family bits themselves (issue #44): what the client answered per container, and what our
  -- own per-family count made of it. Every container answering 0 is the result this probe exists to
  -- find — it means a tradeskill section has no bag to count. Issue #47 split the count per side, so
  -- the two halves print apart: an equipped herb bag feeds the backpack windows and a bank herb bag
  -- feeds the bank ones, never one shared number.
  local named, present = {}, {}
  for name, bit in pairs(constants.BAG_FAMILY) do named[bit] = name end
  for _, container in ipairs(harvest.Containers()) do
    present[container.family or 0] = true
  end
  local bits = {}
  for family in pairs(present) do bits[#bits + 1] = family end
  table.sort(bits)
  for _, family in ipairs(bits) do
    local function sideText(side)
      local slot = harvest.FirstFreeSlotForFamily(family, side)
      return string.format('free=%d first=%s', harvest.FreeSlotsForFamily(family, side),
        slot and (slot.bagID .. ':' .. slot.slot) or 'none')
    end
    record(string.format('  family %s (%s) | backpack %s | bank %s', tostring(family),
      named[family] or 'unknown', sideText('backpack'), sideText('bank')))
  end

  local function firstText(kind)
    local slot = harvest.FirstFreeSlot(kind)
    return slot and (slot.bagID .. ':' .. slot.slot) or 'none'
  end
  record('our counts', 'backpack', harvest.FreeSlots('backpack'),
    'first', firstText('backpack'),
    'reagent', harvest.FreeSlots('reagent'),
    'keyring', harvest.FreeSlots('keyring'),
    'bank', harvest.FreeSlots('bank'),
    'bank first', firstText('bank'))

  local models = pipeline.Model()
  if not models then record('no refresh has run yet') return end
  for _, window in ipairs(models) do
    record(string.format('  [%s] %s emptySlots=%s cell=%s', window.id, window.name,
      tostring(window.emptySlots), tostring(window.emptyOffsetY)))
    local shell = _G['BagsOfSortingWindow' .. window.id]
    local button = shell and shell.EmptySlot
    if not button then
      record('    indicator: none drawn')
    else
      local count = button.Count
      record('    indicator', 'shown', tostring(button:IsShown()),
        'bag', tostring(button:GetParent():GetID()), 'slot', tostring(button:GetID()),
        'count shown', tostring(count and count:IsShown()), 'text', count and count:GetText() or '-')
    end
    -- The per-section half (issue #44): the model's number, then the cell the section frame drew.
    -- Section frames are children of the window shell, and one that drew a cell carries it as
    -- frame.EmptySlot, the way the window's own indicator sits on the shell.
    for _, section in ipairs(window.sections) do
      if section.emptySlots or section.emptyOffsetY then
        record(string.format('    [%s] %s emptySlots=%s cell=%s', section.id, section.name,
          tostring(section.emptySlots), tostring(section.emptyOffsetY)))
      end
    end
    if shell then
      for _, child in ipairs(shell:GetChildren()) do
        local cell = child.EmptySlot
        if cell then
          local count = cell.Count
          record('    section cell drawn', 'shown', tostring(cell:IsShown()),
            'bag', tostring(cell:GetParent():GetID()), 'slot', tostring(cell:GetID()),
            'count text', count and count:GetText() or '-')
        end
      end
    end
  end
end

--- bags — who is showing bags right now (issue #38). Blizzard's bag windows, ours, the two
--- interaction windows, and whether the suppression rule is currently active. Read-only.
probes[22] = function()
  if not inTest then fresh('bags') end
  local interactions = addon:GetModule('Interactions')
  local windowFrames = addon:GetModule('WindowFrames')

  local combined = _G.ContainerFrameCombinedBags
  record('ContainerFrameCombinedBags', combined and tostring(combined:IsShown()) or 'no global')
  local shown, existing = {}, 0
  -- NUM_CONTAINER_FRAMES: bag slots + backpack + keyring (`ContainerFrame.lua:8-11`). A probe bounded
  -- at NUM_TOTAL_BAG_FRAMES cannot see the frame that stayed open on 2026-10-22.
  for i = 1, NUM_CONTAINER_FRAMES or ((NUM_TOTAL_EQUIPPED_BAG_SLOTS or 5) + 2) do
    local frame = _G['ContainerFrame' .. i]
    if frame then
      existing = existing + 1
      if frame:IsShown() then
        -- A container frame's own GetID is the container index it is showing — the number that names
        -- which bag this window is.
        shown[#shown + 1] = string.format('%s(container %s)', tostring(i),
          tostring(frame.GetID and frame:GetID()))
      end
    end
  end
  record('ContainerFrame1..' .. tostring(NUM_CONTAINER_FRAMES or 0), 'existing', existing,
    'shown', #shown, table.concat(shown, ' '))
  record('MerchantFrame', _G.MerchantFrame and tostring(_G.MerchantFrame:IsShown()) or 'no global')
  record('BankFrame', BankFrame and tostring(BankFrame:IsShown()) or 'no global')
  record('our windows shown', windowFrames.Count(),
    'suppression', interactions and tostring(interactions.Suppressing()) or 'no module')
end

--- newitems — what the client's own new-item list actually holds (issue #35). The acceptance
--- criterion is "nothing is new at login", and only the client can say what it flags. Read-only:
--- IsNewItem reads a list, it builds nothing (agents.md hard rule 8).
probes[18] = function()
  if not inTest then fresh('newitems') end
  if not (C_NewItems and C_NewItems.IsNewItem) then
    record('C_NewItems.IsNewItem: absent')
    return
  end
  local harvest = addon:GetModule('Harvest')
  local seen, flagged = 0, 0
  for _, container in ipairs(harvest.Containers()) do
    for slot = 1, container.slots do
      local okInfo, info = pcall(C_Container.GetContainerItemInfo, container.index, slot)
      if okInfo and info and info.itemID then
        seen = seen + 1
        local okNew, isNew = pcall(C_NewItems.IsNewItem, container.index, slot)
        if okNew and isNew then
          flagged = flagged + 1
          record(string.format('  flagged new [%d] slot %d  item %s', container.index, slot, tostring(info.itemID)))
        end
      end
    end
  end
  record('slots holding an item', seen, 'flagged new by the client', flagged)
end


--- portrait — the window chrome issue #34 is about, measured on the client's own bag window and on
--- ours in the same run. The opacity complaint and the overlap complaint are read off the same
--- frames: the background pieces' own colour, and where the portrait and the ring actually sit
--- against the window's top edge. Read-only: every call here reads a frame that already exists.
local function face(t)
  if not t then return 'none' end
  local r, g, b, a = t:GetVertexColor()
  local what = (t.GetColorTexture and t:GetColorTexture() and 'color') or t:GetAtlas() or t:GetTexture()
  return string.format('%s rgba %.2f %.2f %.2f %.2f', tostring(what or 'no texture'), r, g, b, a)
end

local function bounds(f)
  if not f then return '-' end
  -- `GetRect` (left, bottom, width, height) is the documented region call here. `GetAbsBounds` is not
  -- on this client: the first run of this probe died on it (`attempt to call a nil value`).
  local left, bottom, width, height = f:GetRect()
  return string.format('%dx%d @ %s,%s', tostring(width), tostring(height), tostring(left), tostring(bottom))
end

---@param label string
---@param frame Frame?
local function chrome(label, frame)
  if not frame then record(label, 'frame: none') return end
  record(label, bounds(frame), 'level', frame:GetFrameLevel(), 'strata', frame:GetFrameStrata())

  local container = frame.PortraitContainer
  local portrait = container and container.portrait
  record('  portrait', bounds(portrait), 'texture', portrait and tostring(portrait:GetTexture()) or '-',
    'mask', bounds(container and container.CircleMask))

  -- The ring is the nine-slice's top-left corner piece: HeldBagLayout draws the small one, the plain
  -- PortraitFrameTemplate layout draws the full-size one. Its bottom edge is what content has to clear.
  local ring = frame.NineSlice and frame.NineSlice.TopLeftCorner
  record('  ring', ring and tostring(ring:GetAtlas()) or '-', bounds(ring),
    'shown', ring and tostring(ring:IsShown()) or '-',
    'ring bottom below frame top', ring and ring:IsShown()
      and tostring(frame:GetTop() - ring:GetBottom()) or '-')

  -- Issue #43: the corner art a short window cannot hold. Region getters return **nil** on a hidden
  -- texture — the run that first hid the corners died on `GetTop` arithmetic here — so a hidden piece
  -- reports its shown state and nothing else.
  local nine = frame.NineSlice
  local corner = nine and nine.BottomLeftCorner
  record('  bottom corner', bounds(corner), 'shown', corner and tostring(corner:IsShown()) or '-',
    'corner top above frame bottom', corner and corner:IsShown()
      and tostring(corner:GetTop() - frame:GetBottom()) or '-',
    'left edge', bounds(nine and nine.LeftEdge))

  local bg = frame.Bg
  record('  bg', bg and ('level ' .. tostring(bg:GetFrameLevel())) or 'none',
    'TopSection', face(bg and bg.TopSection), 'BottomEdge', face(bg and bg.BottomEdge),
    'BottomLeft', face(bg and bg.BottomLeft))

  local title = frame.TitleContainer
  record('  title', bounds(title), 'text', title and title.TitleText and title.TitleText:GetText() or '-')
end

--- The frames a window can overlap, and the two numbers that decide who draws over whom. Levels only
--- compare inside one strata band, and a frame without a fixed strata follows its parent's, so both
--- are recorded (issue #34). Names and levels read off origin/forever: MainActionBar 50, BagsBar 52,
--- ContainerFrameItemButtonTemplate 10, ContainerFrameCombinedBags MEDIUM + toplevel.
local STACK = {
  'UIParent', 'MainActionBar', 'BagsBar', 'MicroButtonAndBagsBar',
  'MainMenuBarBackpackButton', 'ContainerFrameCombinedBags',
}

---@param label string
---@param frame Frame?
local function stack(label, frame)
  if not frame then record(label, 'absent') return end
  record(label, 'strata', frame:GetFrameStrata(), 'level', frame:GetFrameLevel(),
    'fixed strata', frame.HasFixedFrameStrata and tostring(frame:HasFixedFrameStrata()) or 'no api',
    'shown', tostring(frame:IsShown()))
end

--- The first item button we actually drew, so the capture reads the levels of a real painted entry
--- (button, wrapper, section) rather than the ones we intended.
local function paintedButton()
  for i = 1, 400 do
    local button = _G['BagsOfSortingItemButton' .. i]
    if button and button:IsShown() then return button end
  end
end

probes[19] = function()
  if not inTest then fresh('portrait') end
  local constants = addon:GetModule('Constants')

  local bag = _G.ContainerFrameCombinedBags
  if bag and bag:IsShown() then
    chrome('client bag window', bag)
    local top
    for _, button in ipairs(bag.Items or {}) do
      if button and button:IsShown() and (not top or button:GetTop() > top) then top = button:GetTop() end
    end
    record('  client top gap', top and tostring(bag:GetTop() - top) or 'no visible item buttons')
  else
    record('client bag window: closed')
  end

  record('stacking')
  for _, name in ipairs(STACK) do stack('  ' .. name, _G[name]) end

  local models = addon:GetModule('Pipeline').Model()
  if not models then record('no refresh has run yet') return end
  for _, window in ipairs(models) do
    local frame = _G['BagsOfSortingWindow' .. window.id]
    chrome('our window ' .. window.id .. ' ' .. window.name, frame)
    if frame and frame.PortraitContainer then
      -- The two numbers that decide the overlap: where our content starts, and how far the portrait
      -- reaches down. Content clears the portrait when the first is the larger.
      record('  our content top', constants.WINDOW_TITLE_HEIGHT,
        'portrait bottom below frame top',
        tostring(frame:GetTop() - frame.PortraitContainer.portrait:GetBottom()))
      -- Our own stack, top to bottom: chrome, content, background.
      local button = paintedButton()
      record('  our levels', 'shell', frame:GetFrameLevel(),
        'bg', frame.Bg and frame.Bg:GetFrameLevel() or '-',
        'money', frame.MoneyFrame and frame.MoneyFrame:GetFrameLevel() or '-',
        'button', button and button:GetFrameLevel() or '-',
        'wrapper', button and button:GetParent():GetFrameLevel() or '-',
        'section', button and button:GetParent():GetParent():GetFrameLevel() or '-',
        'portrait', frame.PortraitContainer:GetFrameLevel(),
        'border', frame.NineSlice and frame.NineSlice:GetFrameLevel() or '-',
        'title', frame.TitleContainer:GetFrameLevel(),
        'close', frame.CloseButton:GetFrameLevel())
    end
  end
end

--- The client's own item class and subclass names: the exact strings a `type`/`subtype` rule has to
--- match. Forever is a Vanilla-ruleset client, so they are not retail's — the persisted item cache
--- already reads "Trade Goods" (not "Tradeskill") and "Consumable" (not "Potion" or "Food"). This
--- asks the DBC directly, so it answers for the subtypes the character carries nothing of.
probes[20] = function()
  if inTest then record('classes') else fresh('subclasses') end
  if not (C_Item and C_Item.GetItemClassInfo) then
    record('no C_Item.GetItemClassInfo on this client')
    return
  end
  for class = 0, 20 do
    local okClass, className = pcall(C_Item.GetItemClassInfo, class)
    if okClass and className then
      local subs = {}
      for sub = 0, 25 do
        local okSub, subName = pcall(C_Item.GetItemSubClassInfo, class, sub)
        if okSub and subName then subs[#subs + 1] = sub .. '=' .. subName end
      end
      record(class, className, #subs > 0 and table.concat(subs, ' · ') or '(none)')
    end
  end
end

--- Where the pipeline actually put everything, with the type/subtype pair that decided it. This is
--- the capture that says whether a shipped category name is one this client uses.
probes[21] = function()
  local models = addon:GetModule('Pipeline').Model()
  if inTest then record('placements') else fresh('owners') end
  if not models then
    record('no refresh has run yet')
    return
  end
  for _, window in ipairs(models) do
    record(string.format('%s  %d sections', window.name, #window.sections))
    for _, section in ipairs(window.sections) do
      record(string.format('  %s  %d', section.name, #section.items))
      for _, item in ipairs(section.items) do
        record(string.format('    %d %s  %s / %s', item.itemID, tostring(item.name),
          tostring(item.type), tostring(item.subtype)))
      end
    end
  end
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
  clock = probes[13], expansion = probes[14], flags = flagsScan, windows = probes[16],
  freeslots = probes[17], newitems = probes[18], portrait = probes[19],
  subclasses = probes[20], owners = probes[21], bags = probes[22],
}

-- ---------------------------------------------------------------------------
-- Pending manual tests: one entry per open issue, added when a story needs measuring and deleted
-- when its capture is ingested. `issue` is the GitHub issue the run sheet answers; the id is what
-- you type. A step is { text = ..., run = ... }: text is the line the run sheet prints, and a step
-- with no run is a manual action and gets no letter — the captured steps on either side of it are
-- what make the capture readable.
-- ---------------------------------------------------------------------------
local tests = {}

-- Steps for the pending tests below. A step only ever reads and records: every pull, key press,
-- hide, Blizzard button click and item move in these sheets stays a manual step, because an addon
-- call inside the protected chain is exactly what issue #4 exists to keep out (agents.md rule 2).

---@return string
local function secureLine()
  -- `{ GetCursorInfo() }` not `tostring(GetCursorInfo())`: an empty cursor makes GetCursorInfo
  -- return **no values at all**, and tostring on no value is a Lua error (issue #4's first run died
  -- on exactly this, six times).
  local cursor = ({ GetCursorInfo() })[1]
  return string.format('secure=%s lockdown=%s cursor=%s', tostring(issecure()),
    tostring(InCombatLockdown()), tostring(cursor))
end

-- issecure() read from this path is not a verdict: a slash command runs through the chat frame,
-- which is tainted, so everything our code reads below it sits in a tainted chain and issecure()
-- reads false whatever we did (measured on issue #4 2026-11-11, where it read false before anything
-- was attempted). The signals that do mean something in these sheets are InCombatLockdown(), who is
-- showing bags, whether our buttons still pick items up, and the taint log in /console.

-- --------------------------------------------------------------------- issue #4
-- What issue #4 has never run: a state read on either side of each suspicious action made **during**
-- lockdown, and the `GetBagsShown()` trap verified by us rather than inherited from ForeverPlus. The
-- trap is the last captured step on purpose — a session it taints must not taint the steps before it.
local function combatState(label)
  record(label, secureLine(), 'our windows shown', addon:GetModule('WindowFrames').Count())
  record('pool', addon:GetModule('Pool').Stats())
  -- Who is showing bags is the behaviour that matters: Blizzard's own frames, ours, and whether the
  -- suppression rule is still active after the attempt.
  HELPERS.bags()
end

local function issue4Baseline()
  combatState('out of combat')
  record('ContainerFrameSettingsManager',
    ContainerFrameSettingsManager and 'frame exists' or 'no such global',
    '— step j calls its GetBagsShown() on purpose')
  record('our key', tostring(GetBindingKey('BAGSOF_SORTING_TOGGLE')),
    '— a manual step presses it during lockdown. It is a Bindings.xml snippet, so a refusal on that '
    .. 'path is ours, not the client\'s; it opens and closes our windows and never moves an item. '
    .. 'CTRL-B is the client\'s own open-all-bags')
end

--- The captured steps are the same state read at six points; the label is what separates them.
local function issue4Combat() combatState('in combat') end
local function issue4AfterToggle() combatState('after hide/show attempted in combat') end
local function issue4AfterPickup() combatState('after the in-combat button pickup attempt') end
local function issue4AfterKey()
  combatState('after one press of our own key — our windows were open before it')
end
local function issue4AfterCtrlB() combatState('after CTRL-B was pressed in combat') end

--- A pooled button created during lockdown is issue #4 step 5. Blizzard's buttons are readable off
--- the window's own `Items` table, ours off the pool's created count; neither touches the manager.
local function issue4PostCombat()
  combatState('after combat and the mid-combat /reload')
  local bag = ContainerFrameCombinedBags
  local shown = 0
  for _, button in ipairs((bag and bag.Items) or {}) do
    if button and button:IsShown() then shown = shown + 1 end
  end
  record('client bag window', bag and (bag:IsShown() and 'shown' or 'closed') or 'no global',
    'its visible buttons', shown)
  local ours = 0
  for i = 1, 400 do
    local button = _G['BagsOfSortingItemButton' .. i]
    if button and button:IsShown() then ours = ours + 1 end
  end
  record('our visible buttons', ours)
end

local function issue4Trap()
  record('the deliberate trap:', 'ContainerFrameSettingsManager:GetBagsShown()')
  record('before:', secureLine())
  local manager = ContainerFrameSettingsManager
  if not (manager and manager.GetBagsShown) then
    record('no manager, or no GetBagsShown method on this client')
  else
    local ok, shown = pcall(function() return manager:GetBagsShown() end)
    record('call', ok and 'returned' or ('errored: ' .. tostring(shown)),
      ok and (type(shown) == 'table' and tostring(#shown) or 'not a table') or '-', 'entries',
      '— an empty list while our windows suppress the client\'s is itself the number to read')
  end
  record('after:', secureLine())
  combatState('state after the trap')
  record('the secure readings are the slash-path value (always false); what a difference here would '
    .. 'mean is the manager call itself — ForeverPlus hit exactly this, and the next /reload clears it')
end

-- ---------------------------------------------------------------------------
-- The pending list. `/bos test` prints these; `/bos test <id>` prints one run sheet.
-- ---------------------------------------------------------------------------

--- The trap only matters if it changes behaviour, so the sheet follows it with two real attempts — one on
--- our own button, one on Blizzard's own bag window — and this step reads what they left behind. It also
--- stops the log armed at step i, so anything the client refused lands in this bucket with its name.
local function issue4TrapProbe()
  combatState('state after the two pickup attempts that follow the trap')
  HELPERS.log()
end

tests[4] = {
  issue = 4,
  what = 'a state read on either side of each action attempted during lockdown, the GetBagsShown trap ' ..
    'run by us, and what that trap leaves a button interaction doing',
  needs = 'out of combat at step a; our windows open with real items in them; a trainer or a mob you ' ..
    'can pull on a character you do not mind dying on. issecure() reads false for anything triggered ' ..
    'from a slash command, so the verdicts come from the lockdown, who is showing bags, and the ' ..
    'blocked-action log this sheet arms at step b and stops at step k. `/console` is ConsoleExec on this ' ..
    'client — a cvar command that opens no window — so Blizzard\'s own view is `/eventtrace`. Steps j and ' ..
    'k taint Blizzard bag code on purpose and are last for that reason.',
  steps = {
    { text = 'setup: baseline out of combat', run = issue4Baseline },
    { text = 'capture: arm the event log — it records ADDON_ACTION_BLOCKED / ADDON_ACTION_FORBIDDEN with ' ..
      'the function name each one names', run = HELPERS.log },
    { text = 'pull a mob or attack a trainer, and stay in combat' },
    { text = 'capture: in-combat state', run = issue4Combat },
    { text = 'while still in combat: /bos hide, then /bos show' },
    { text = 'capture: state after the open/close attempt', run = issue4AfterToggle },
    { text = 'while still in combat: pick an item up off one of our buttons and drop it into ' ..
      'another of our slots' },
    { text = 'capture: state after the button pickup attempt', run = issue4AfterPickup },
    { text = 'while still in combat: press your own bound key **once** — the windows are open from the '
      .. 'step above, so one press closing them is the reading' },
    { text = 'capture: state after our own key', run = issue4AfterKey },
    { text = 'while still in combat: press CTRL-B (the client\'s own open-all-bags) and watch ' ..
      'whether Blizzard\'s bag window appears' },
    { text = 'capture: state after CTRL-B', run = issue4AfterCtrlB },
    { text = 'type /eventtrace, Blizzard\'s own blocked-action window, and copy anything it shows there ' ..
      'into issue #4. There is no /events on this client' },
    { text = 'leave combat, wait for the regen flap, pull again, /reload while still in combat, ' ..
      'then wait for regen and run /bos test 4h' },
    { text = 'capture: post-combat state, both button pools, the client bag window\'s own buttons',
      run = issue4PostCombat },
    { text = 'capture: arm the log again — the reload killed the first one', run = HELPERS.log },
    { text = 'capture: the deliberate GetBagsShown trap, state before and after', run = issue4Trap },
    { text = 'out of combat: pick an item up off one of our buttons and drop it back where it came from' },
    { text = 'then press CTRL-B and pick an item up off Blizzard\'s own bag window, dropping it back ' ..
      'where it came from' },
    { text = 'capture: state after both pickup attempts, and stop the log', run = issue4TrapProbe },
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
  print('helpers: dump · log · flags · keybind · newitem · newitems · clock · expansion · windows · '
    .. 'freeslots · portrait · subclasses · owners · bags')
end

return diag
