-- Wiring: what loads, what listens, and the slash command that doubles as the Forever fact
-- verification tool (docs/06 M0).

local _, addon = ...

---@class Init: BoSModule
local init = addon:NewModule('Init')

local log = addon:GetModule('Log')
local events = addon:GetModule('Events')
local client = addon:GetModule('Client')
local context = addon:GetModule('Context')
local db = addon:GetModule('DB')
local harvest = addon:GetModule('Harvest')
local enrich = addon:GetModule('Enrich')
local pipeline = addon:GetModule('Pipeline')
local windows = addon:GetModule('WindowFrames')
local options = addon:GetModule('AddonOptions')
local itemFrames = addon:GetModule('ItemFrames')
local pool = addon:GetModule('Pool')
local diag = addon:GetModule('Diag')
local keybinds = addon:GetModule('Keybinds')
local equipment = addon:GetModule('Equipment')

init.started = false

local function printLines(lines)
  for _, line in ipairs(lines) do print(line) end
end

---@param models BoSWindowModel[]
---@param shown table<string, boolean>
---@param ctx BoSContext
events.On('BOS_REFRESH_DONE', windows.RenderAll)

local function listen()
  -- A loot burst is one refresh, not twenty (docs/03 §The pipeline).
  events.Bucket('BAG_UPDATE', 0.2, function() pipeline.Refresh('bag-update') end)
  events.On('BAG_CONTAINER_UPDATE', function()
    harvest.Invalidate()
    pipeline.Refresh('container')
  end)
  events.On('PLAYER_EQUIPMENT_CHANGED', function()
    harvest.Invalidate()
    pipeline.Refresh('equipment')
  end)
  -- Tier-3 answers re-classify through the same bucketed path (FR-26's entry point).
  events.Bucket('BOS_ITEM_DATA', 0.3, function() pipeline.Refresh('item-data') end)
  events.On('ITEM_DATA_LOAD_RESULT', function(itemID, success)
    if enrich.OnItemDataLoaded(itemID, success) then
      events.Emit('BOS_ITEM_DATA')
    end
  end)
  events.On('BOS_MODEL_CHANGED', function() pipeline.Refresh('model') end)
  -- Everything a lockdown deferred lands here (docs/07 Q23).
  events.On('PLAYER_REGEN_ENABLED', function()
    windows.FlushReleases()
    pipeline.Refresh('regen')
  end)
end

function init.Start()
  if init.started then return end
  init.started = true

  -- Insurance for the one measured case where the client drops our binding: it re-applies our
  -- copy only when the client holds none (issue #13).
  keybinds.Restore()
  harvest.Discover()
  -- Pre-warm the button pool from the real inventory so a combat loot event does not have to
  -- create a secure button (agents.md hard rule 3).
  itemFrames.Warm(math.min(200, #harvest.Items() + 20))

  -- Initial equipment set scan
  equipment.Refresh()

  listen()
  pipeline.Refresh('login')
end

--- Plain-frame deferral, never an AceEvent-mediated one (the `debugging-wow-addons` skill).
function init.Enable()
  if InCombatLockdown() then
    log.Debug('combat lockdown, deferring enable until PLAYER_REGEN_ENABLED')
    local f = CreateFrame('Frame')
    f:RegisterEvent('PLAYER_REGEN_ENABLED')
    f:SetScript('OnEvent', function(self)
      self:UnregisterAllEvents()
      init.Enable()
    end)
    return
  end
  init.Start()
end

---@return boolean
function init.IsShowing()
  return windows.Count() > 0
end

function init.Show()
  db.SetWindowsOpen(true)
  -- Render pipeline now handles combat internally (renders structure only in lockdown)
  pipeline.Refresh('show')
end

function init.Toggle()
  if init.IsShowing() then
    db.SetWindowsOpen(false)
    windows.HideAll()
  else
    init.Show()
  end
end

local HELP = {
  '/bos               client capability dump + harvested containers',
  '/bos perf          last refresh timings, pool and item-cache stats',
  '/bos test          pending manual tests, then the helper names',
  '/bos test <id>     the numbered run sheet for one test (one action per step)',
  '/bos test <id><l>  run one captured step of that test, e.g. /bos test 15b',
  '/bos test <name>   a helper on its own: dump · log · flags · keybind · newitem · clock · expansion · windows · freeslots',
  '/bos find <id>     which container index holds that item',
  '/bos refresh       re-run the pipeline',
  '/bos show|hide     show or hide the sorting windows',
  '/bos unplace       drop dragged windows back on the layout rule',
  '/bos debug         toggle debug logging',
}

---@param input string?
function init.Slash(input)
  local cmd = ((input or ''):match('^(%S+)') or ''):lower()

  if cmd == 'perf' then
    local ctx = pipeline.Last()
    print(ctx and context.Format(ctx) or 'no refresh has run yet')
    print(pool.Stats())
    print(enrich.Stats())
  elseif cmd == 'test' then
    diag.Command((input or ''):match('^%s*test%s*(.*)$'))
  elseif cmd == 'find' then
    diag.Find(tonumber((input or ''):match('(%d+)')))
  elseif cmd == 'refresh' then
    pipeline.Refresh('slash')
  elseif cmd == 'show' then
    init.Show()
  elseif cmd == 'hide' then
    db.SetWindowsOpen(false)
    windows.HideAll()
  elseif cmd == 'unplace' then
    -- A saved drag point is the only thing that overrides the layout rule, and the placement tests
    -- need the default placement (FR-41).
    print(string.format('%d window(s) released to the layout rule', db.ClearPositions()))
    pipeline.Refresh('unplace')
  elseif cmd == 'debug' then
    local settings = db.Settings()
    settings.debug = not settings.debug
    log.SetDebug(settings.debug)
    print('debug ' .. tostring(settings.debug))
  elseif cmd == 'autotest' then
    local classify = addon:GetModule('Classify')
    -- Capture to SavedVariables bucket 'autotest57' like diag tests do
    db.sv.diag = db.sv.diag or {}
    local bucket = 'autotest57'
    db.sv.diag[bucket] = {}
    local function capture(...) local parts = { ... } for i = 1, #parts do parts[i] = tostring(parts[i]) end local line = table.concat(parts, ' ') print(line) db.sv.diag[bucket][#db.sv.diag[bucket] + 1] = line end

    local iface, build = GetBuildInfo()
    capture(string.format('--- autotest57 start | build %s (%s) | %s - %s ---', iface, tostring(build), tostring(UnitName('player')), tostring(GetRealmName())))
    capture('=== AUTO TEST 57 START ===')
    equipment.Refresh()
    capture('Equipment module', tostring(equipment ~= nil))
    capture('C_EquipmentSet.GetEquipmentSetIDs', tostring(type(C_EquipmentSet.GetEquipmentSetIDs)))
    local ids = C_EquipmentSet.GetEquipmentSetIDs()
    capture('setIDs', #ids)
    for _, setID in ipairs(ids) do
      local name, icon, setID2, isEquipped, numItems, numEquipped, numInInventory, numLost, numIgnored = C_EquipmentSet.GetEquipmentSetInfo(setID)
      capture('  set', setID, name, icon, 'equipped='..tostring(isEquipped), 'items='..numItems, 'equipped='..numEquipped, 'inInv='..numInInventory, 'lost='..numLost, 'ignored='..numIgnored)
      local itemIDs = C_EquipmentSet.GetItemIDs(setID)
      local itemIDList = {}
      if itemIDs then for _, id in pairs(itemIDs) do itemIDList[#itemIDList + 1] = id end end
      capture('    GetItemIDs', #itemIDList, #itemIDList > 0 and table.concat(itemIDList, ',') or 'nil')
      local locations = C_EquipmentSet.GetItemLocations(setID)
      local locList = {}
      if locations then for _, loc in pairs(locations) do locList[#locList + 1] = loc end end
      capture('    GetItemLocations', #locList, #locList > 0 and table.concat(locList, ',') or 'nil')
    end

    init.Show()
    local models = pipeline.Model()
    for _, m in ipairs(models) do
      capture('window', m.id, m.name, m.kind, 'sections='..#m.sections)
      for _, s in ipairs(m.sections) do
        capture('  section', s.id, s.name, 'cats='..table.concat(s.categories, ','), 'items='..#s.items)
      end
    end

    local eqCats = db.Categories()
    for name, cat in pairs(eqCats) do
      if name:match('^Equipment%.') then
        local count = 0
        if cat.itemIDs then for _ in pairs(cat.itemIDs) do count = count + 1 end end
        capture('category', name, 'priority='..cat.priority, 'kind='..cat.kind, 'items='..count, 'setID='..tostring(cat._equipmentSetID))
      end
    end

    local placements = classify.Run(harvest.Items(), db.Categories())
    for catName, items in pairs(placements) do
      if catName:match('^Equipment%.') then
        capture('placement', catName, #items, 'items')
        for _, item in ipairs(items) do
          capture('  item', item.itemID, item.name, 'bag='..item.bagID..'.'..item.slot)
        end
      end
    end

    local found = 0
    local items = harvest.Items()
    for _, item in ipairs(items) do
      if item.link and item.equipSlot and item.equipSlot ~= '' then
        local sets = equipment.scanTooltipForEquipmentSets(item)
        if sets then
          local setNames = {}
          for k in pairs(sets) do setNames[#setNames+1] = k end
          capture('bag tooltip hit', item.itemID, item.name, 'sets='..table.concat(setNames, ','))
          found = found + 1
        end
      end
    end
    for slot = 1, 19 do
      local itemLink = GetInventoryItemLink('player', slot)
      if itemLink then
        local itemID = GetInventoryItemID('player', slot)
        local fakeItem = { link = itemLink, equipSlot = 'INVSLOT_' .. slot, itemID = itemID }
        local sets = equipment.scanTooltipForEquipmentSets(fakeItem)
        if sets then
          local setNames = {}
          for k in pairs(sets) do setNames[#setNames+1] = k end
          capture('equipped tooltip hit', itemID, itemLink, 'sets='..table.concat(setNames, ','))
          found = found + 1
        end
      end
    end
    capture('tooltip scan complete, items with equipment sets:', found)
    capture('=== AUTO TEST 57 COMPLETE ===')
    printLines(HELP)
  else
    print(string.format('%s %s', addon.title, addon.version))
    printLines(client.Probe())
    print('containers:')
    printLines(harvest.Summary())
  end
end

SLASH_BAGSOFsorting1 = '/bos'
SlashCmdList['BAGSOFsorting'] = init.Slash

events.On('ADDON_LOADED', function(loaded)
  if loaded ~= addon.name then return end
  db.Initialize()
  options.Register()
end)

events.On('PLAYER_LOGIN', init.Enable)

return init
