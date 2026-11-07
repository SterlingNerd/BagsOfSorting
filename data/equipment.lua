-- Equipment Manager integration: dynamic categories per equipment set.
--
-- Queries C_EquipmentSet for all sets and their itemIDs, builds a category per set.
-- Falls back to tooltip parsing (equippable items only) if the API doesn't return itemIDs.
-- Listens to EQUIPMENT_SETS_CHANGED to rebuild categories.

local _, addon = ...

---@class Equipment: BoSModule
local equipment = addon:NewModule('Equipment')

local db = addon:GetModule('DB')
local log = addon:GetModule('Log')
local events = addon:GetModule('Events')

---@type table<number, {name: string, icon: number, itemIDs: table<number, boolean>}>
local equipmentSets = {}

---@type table<string, BoSCategory>
local dynamicCategories = {}

--- Current equipment set -> itemID mapping for tooltip fallback.
---@type table<string, table<number, boolean>>
local setItemMap = {}

--- Scan an equippable item's tooltip for "Equipment Sets: <name>, <name2>"
---@param item BoSItem
---@return table<string, boolean>?
function equipment.scanTooltipForEquipmentSets(item)
  if not item.link or not item.equipSlot or item.equipSlot == '' then return nil end

  local scanner = _G.BagsOfSortingTooltipScanner
  if not scanner then
    scanner = CreateFrame('GameTooltip', 'BagsOfSortingTooltipScanner', nil, 'GameTooltipTemplate')
    scanner:SetOwner(UIParent, 'ANCHOR_NONE')
    _G.BagsOfSortingTooltipScanner = scanner
  end

  scanner:ClearLines()
  scanner:SetHyperlink(item.link)

  for i = 2, scanner:NumLines() do
    local line = _G['BagsOfSortingTooltipScannerTextLeft' .. i]
    if line then
      local text = line:GetText()
      if text and text:match('^Equipment Sets:') then
        local setsText = text:match('^Equipment Sets:%s*(.+)')
        if setsText then
          local sets = {}
          for rawName in setsText:gmatch('([^,]+)') do
            local cleanName = rawName:match('^%s*(.-)%s*$')
            if cleanName and cleanName ~= '' then
              sets[cleanName] = true
            end
          end
          return sets
        end
      end
    end
  end
  return nil
end

--- Build itemID -> setName map from tooltip scanning (fallback path).
--- Scans bag items AND equipped items (since equipment set items are often equipped).
local function buildTooltipMap()
  setItemMap = {}

  -- Scan bag items
  local items = addon:GetModule('Harvest').Items()
  for _, item in ipairs(items) do
    local sets = equipment.scanTooltipForEquipmentSets(item)
    if sets then
      for setName in pairs(sets) do
        if not setItemMap[setName] then setItemMap[setName] = {} end
        setItemMap[setName][item.itemID] = true
      end
    end
  end

  -- Scan equipped slots (INVSLOT_* constants)
  for slot = 1, 19 do
    local itemLink = GetInventoryItemLink('player', slot)
    if itemLink then
      local itemID = GetInventoryItemID('player', slot)
      local fakeItem = { link = itemLink, equipSlot = 'INVSLOT_' .. slot, itemID = itemID }
      local sets = equipment.scanTooltipForEquipmentSets(fakeItem)
      if sets then
        for setName in pairs(sets) do
          if not setItemMap[setName] then setItemMap[setName] = {} end
          setItemMap[setName][itemID] = true
        end
      end
    end
  end

  log.Debug('Equipment tooltip map built, sets:', table.concat((function() local t={} for k in pairs(setItemMap) do t[#t+1]=k end return t end)(), ', '))
end

--- Query C_EquipmentSet for all sets and their itemIDs.
---@return table<number, {name: string, icon: number, itemIDs: table<number, boolean>}>
local function queryEquipmentSets()
  local sets = {}
  local setIDs = C_EquipmentSet.GetEquipmentSetIDs()
  if not setIDs or #setIDs == 0 then return sets end

  for _, setID in ipairs(setIDs) do
    local name, icon, _, isEquipped, _, _, _, numLost = C_EquipmentSet.GetEquipmentSetInfo(setID)
    if name then
      local itemIDs = C_EquipmentSet.GetItemIDs(setID)
      local idSet = {}
      if itemIDs and type(itemIDs) == 'table' then
        for _, id in pairs(itemIDs) do
          -- Filter out -1 (empty equipment slot sentinel)
          if id and id > 0 then idSet[id] = true end
        end
      end
      sets[setID] = { name = name, icon = icon, itemIDs = idSet, isEquipped = isEquipped, numLost = numLost }
    end
  end
  return sets
end

--- Create or update a dynamic category for one equipment set.
---@param setID number
---@param info {name: string, icon: number, itemIDs: table<number, boolean>}
local function upsertCategory(setID, info)
  local catName = 'Equipment.' .. info.name
  local category = {
    priority = 14, -- Between Consumables (12) and Tradeskills (15)
    kind = 'manual',
    enabled = true,
    duplicate = false, -- Handled specially: items in multiple sets added post-classify
    itemIDs = info.itemIDs,
    _equipmentSetID = setID,
    -- Equipment categories show even when empty so users can see their sets
    _showEmpty = true,
  }
  dynamicCategories[catName] = category

  -- Merge into live categories table
  local categories = db.Categories()
  categories[catName] = category
end

--- Remove dynamic categories for sets that no longer exist.
---@param currentSetIDs table<number, boolean>
local function pruneCategories(currentSetIDs)
  local categories = db.Categories()
  for catName, cat in pairs(categories) do
    if cat._equipmentSetID and not currentSetIDs[cat._equipmentSetID] then
      categories[catName] = nil
      dynamicCategories[catName] = nil
    end
  end
end

--- Full rebuild: query API, build tooltip fallback map only if needed, create categories.
function equipment.Refresh()
  equipmentSets = queryEquipmentSets()

  -- Check if any set has empty itemIDs (API returned nil/empty)
  local needsTooltip = false
  for _, info in pairs(equipmentSets) do
    if not next(info.itemIDs) then
      needsTooltip = true
      break
    end
  end

  -- Only build tooltip map if API data is missing
  if needsTooltip then
    buildTooltipMap()
    for setID, info in pairs(equipmentSets) do
      if not next(info.itemIDs) then
        local tooltipIDs = setItemMap[info.name]
        if tooltipIDs and next(tooltipIDs) then
          info.itemIDs = tooltipIDs
          log.Debug('Equipment set', info.name, 'got', (function() local c=0 for _ in pairs(tooltipIDs) do c=c+1 end return c end)(), 'itemIDs from tooltip fallback')
        else
          log.Debug('Equipment set', info.name, 'has no tooltip itemIDs yet')
        end
      else
        log.Debug('Equipment set', info.name, 'using API itemIDs (', (function() local c=0 for _ in pairs(info.itemIDs) do c=c+1 end return c end)(), ')')
      end
    end
  else
    for setID, info in pairs(equipmentSets) do
      log.Debug('Equipment set', info.name, 'using API itemIDs (', (function() local c=0 for _ in pairs(info.itemIDs) do c=c+1 end return c end)(), ')')
    end
  end

  -- Upsert categories
  local currentSetIDs = {}
  for setID, info in pairs(equipmentSets) do
    currentSetIDs[setID] = true
    upsertCategory(setID, info)
  end

  pruneCategories(currentSetIDs)

  -- Trigger full pipeline refresh
  addon:GetModule('Pipeline').Refresh('equipment')
end

--- Get the dynamic categories for binding in sections (wildcard "Equipment.*").
---@return table<string, BoSCategory>
function equipment.GetCategories()
  return dynamicCategories
end

--- Get equipment set info by setID.
---@param setID number
---@return {name: string, icon: number, itemIDs: table<number, boolean>}?
function equipment.GetSetInfo(setID)
  return equipmentSets[setID]
end

--- Distribute items that belong to multiple equipment sets into all matching categories.
--- Called after classify.Run so items appear in all their sets but not in Armor/catch-all.
function equipment.DistributeMultiSetItems()
  local placements = addon:GetModule('Pipeline').Model()
  if not placements then return end
  -- Build itemID -> setNames map from equipment categories
  local itemToSets = {}
  for catName, cat in pairs(db.Categories()) do
    if catName:match('^Equipment%.') and cat.itemIDs then
      local setName = catName:match('^Equipment%.(.+)$')
      for itemID in pairs(cat.itemIDs) do
        if not itemToSets[itemID] then itemToSets[itemID] = {} end
        itemToSets[itemID][#itemToSets[itemID] + 1] = catName
      end
    end
  end
  -- For items in multiple sets, ensure they appear in all matching equipment categories
  for _, window in ipairs(placements) do
    for _, section in ipairs(window.sections) do
      for _, item in ipairs(section.items) do
        local sets = itemToSets[item.itemID]
        if sets and #sets > 1 then
          for _, catName in ipairs(sets) do
            local cat = db.Categories()[catName]
            if cat and cat.itemIDs and not cat.itemIDs[item.itemID] then
              cat.itemIDs[item.itemID] = true
            end
          end
        end
      end
    end
  end
end

-- Event handler
events.On('EQUIPMENT_SETS_CHANGED', function()
  log.Debug('EQUIPMENT_SETS_CHANGED fired')
  equipment.Refresh()
end)

return equipment