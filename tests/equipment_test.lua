-- Automated test runner for issue #57: Equipment bag with per-set categories
-- Run with: /script LoadAddOn('BagsOfSorting') dofile('Interface/AddOns/BagsOfSorting/tests/equipment_test.lua')

local _, addon = ...

local function record(...)
  local parts = { ... }
  for i = 1, #parts do parts[i] = tostring(parts[i]) end
  print(table.concat(parts, ' '))
end

local function runTest()
  local eq = addon:GetModule('Equipment')
  local db = addon:GetModule('DB')
  local pipeline = addon:GetModule('Pipeline')
  local classify = addon:GetModule('Classify')
  local harvest = addon:GetModule('Harvest')
  local init = addon:GetModule('Init')

  record('=== TEST 57 START ===')

  -- Step 57a: Verify Equipment module loaded and dump equipment set API
  record('57a: Equipment module', tostring(eq ~= nil))
  eq.Refresh()
  record('57a: C_EquipmentSet.GetEquipmentSetIDs', tostring(type(C_EquipmentSet.GetEquipmentSetIDs)))
  local ids = C_EquipmentSet.GetEquipmentSetIDs()
  record('57a: setIDs', #ids)
  for _, setID in ipairs(ids) do
    local name, icon, setID2, isEquipped, numItems, numEquipped, numInInventory, numLost, numIgnored = C_EquipmentSet.GetEquipmentSetInfo(setID)
    record('57a:   set', setID, name, icon, 'equipped='..tostring(isEquipped), 'items='..numItems, 'equipped='..numEquipped, 'inInv='..numInInventory, 'lost='..numLost, 'ignored='..numIgnored)
    local itemIDs = C_EquipmentSet.GetItemIDs(setID)
    record('57a:     GetItemIDs', itemIDs and #itemIDs or 0, itemIDs and table.concat(itemIDs, ',') or 'nil')
    local locations = C_EquipmentSet.GetItemLocations(setID)
    record('57a:     GetItemLocations', locations and #locations or 0, locations and table.concat(locations, ',') or 'nil')
  end

  -- Step 57b: Open BoS windows
  record('57b: Opening BoS windows')
  init.Show()

  -- Step 57c: Verify Equipment bag appears between Tradeskills and Tools
  record('57c: Verifying window layout')
  local models = pipeline.Model()
  for _, m in ipairs(models) do
    record('57c: window', m.id, m.name, m.kind, 'sections='..#m.sections)
    for _, s in ipairs(m.sections) do
      record('57c:   section', s.id, s.name, 'cats='..table.concat(s.categories, ','), 'items='..#s.items)
    end
  end

  -- Step 57d: Verify dynamic categories created
  record('57d: Verifying dynamic categories')
  local cats = db.Categories()
  for name, cat in pairs(cats) do
    if name:match('^Equipment%.') then
      local count = 0
      if cat.itemIDs then for _ in pairs(cat.itemIDs) do count = count + 1 end end
      record('57d: category', name, 'priority='..cat.priority, 'kind='..cat.kind, 'items='..count, 'setID='..tostring(cat._equipmentSetID))
    end
  end

  -- Step 57e: Verify items from equipment sets land in correct categories
  record('57e: Verifying item placement')
  local placements = classify.Run(harvest.Items(), db.Categories())
  for catName, items in pairs(placements) do
    if catName:match('^Equipment%.') then
      record('57e: placement', catName, #items, 'items')
      for _, item in ipairs(items) do
        record('57e:   item', item.itemID, item.name, 'bag='..item.bagID..'.'..item.slot)
      end
    end
  end

  -- Step 57f: Scan ALL equippable items (bags + equipped) for equipment set membership
  record('57f: Scanning all equippable items for equipment sets')
  local found = 0
  local items = harvest.Items()

  -- Scan bag items
  for _, item in ipairs(items) do
    if item.link and item.equipSlot and item.equipSlot ~= '' then
      local sets = eq.scanTooltipForEquipmentSets(item)
      if sets then
        local setNames = {}
        for k in pairs(sets) do setNames[#setNames+1] = k end
        record('57f: bag tooltip hit', item.itemID, item.name, 'sets='..table.concat(setNames, ','))
        found = found + 1
      end
    end
  end

  -- Scan equipped slots
  for slot = 1, 19 do
    local itemLink = GetInventoryItemLink('player', slot)
    if itemLink then
      local itemID = GetInventoryItemID('player', slot)
      local fakeItem = { link = itemLink, equipSlot = 'INVSLOT_' .. slot, itemID = itemID }
      local sets = eq.scanTooltipForEquipmentSets(fakeItem)
      if sets then
        local setNames = {}
        for k in pairs(sets) do setNames[#setNames+1] = k end
        record('57f: equipped tooltip hit', itemID, itemLink, 'sets='..table.concat(setNames, ','))
        found = found + 1
      end
    end
  end

  record('57f: tooltip scan complete, items with equipment sets:', found)

  record('=== TEST 57 COMPLETE ===')
  record('Paste output into issue #57, then remove test from core/diag.lua')
end

runTest()