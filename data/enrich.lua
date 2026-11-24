-- Phase 2: turn a harvested slot into a record the classifier can read in O(1) per leaf.
--
-- Three tiers (docs/03 §Item data is not always there). C_Item.GetItemInfo is
-- MayReturnNothing on Forever: the client only knows items it has seen this session.
--   tier 1  C_Item.GetItemInfoInstant  local, safe in a loop: type/subtype/equipLoc/icon/classIDs
--   tier 2  data/itemcache             persisted: name/quality/ilvl/expansion for known IDs
--   tier 3  RequestLoadItemDataByID    one request per unknown ID, answered by ITEM_DATA_LOAD_RESULT
--
-- Nothing here blocks a refresh (FR-103): an item with no tier-3 answer yet classifies on
-- tier 1/2 and is re-classified when the answer arrives.

local _, addon = ...

---@class Enrich: BoSModule
local enrich = addon:NewModule('Enrich')

local itemcache = addon:GetModule('ItemCache')

---@type table<number, boolean>
local requested = {}   -- session-only: never re-ask for an ID we already asked for
local requestedCount = 0
local resolved = 0

--- Tier 1 + tier 2, merged onto the harvested record.
---@param item BoSItem
function enrich.Enrich(item)
  local ok, _, itemType, itemSubType, itemEquipLoc, icon, classID, subClassID =
    pcall(C_Item.GetItemInfoInstant, item.itemID)
  if ok then
    item.type = itemType or item.type
    item.subtype = itemSubType or item.subtype
    item.equipSlot = itemEquipLoc or item.equipSlot
    item.classID = classID or item.classID
    item.subClassID = subClassID or item.subClassID
    item.icon = item.icon or icon
  end

  local cached = itemcache.Get(item.itemID)
  if cached then
    item.name = item.name or cached.name
    item.quality = item.quality or cached.quality
    item.ilvl = cached.ilvl
    item.expansion = cached.expansion
    item.icon = item.icon or cached.icon
    item.type = item.type or cached.type
    item.subtype = item.subtype or cached.subtype
  end

  -- The tier-3 *read* is free when the client already knows the item; only IDs it has never
  -- seen fall through to a request. That is what makes AC-97 (zero requests on the second
  -- login for cached IDs) true rather than aspirational.
  if item.ilvl == nil and item.expansion == nil then
    local full = enrich.ReadFull(item.itemID)
    if full then
      itemcache.Put(item.itemID, full)
      item.name = item.name or full.name
      item.quality = item.quality or full.quality
      item.ilvl = full.ilvl
      item.expansion = full.expansion
      item.icon = item.icon or full.icon
      item.type = item.type or full.type
      item.subtype = item.subtype or full.subtype
    end
  end

  item.dataReady = item.ilvl ~= nil or item.expansion ~= nil
  return item
end

--- C_Item.GetItemInfo is MayReturnNothing on Forever: the client only knows items it has
--- seen. Returns nil when this item is one of those.
---@param itemID number
---@return BoSCachedItem?
function enrich.ReadFull(itemID)
  local ok, name, _, quality, level, _, itemType, itemSubType, _, _, icon,
    _, _, _, _, expansionID = pcall(C_Item.GetItemInfo, itemID)
  if not ok or not name then return nil end
  return {
    name = name,
    quality = quality,
    ilvl = (type(level) == 'number' and level > 0) and level or nil,
    expansion = expansionID,
    icon = icon,
    type = itemType,
    subtype = itemSubType,
  }
end

--- Tier 3, batched by the caller's chunking and deduplicated per session.
---@param ctx BoSContext
---@param item BoSItem
---@return boolean requested
function enrich.RequestMissing(ctx, item)
  if item.dataReady or requested[item.itemID] then return false end
  requested[item.itemID] = true
  requestedCount = requestedCount + 1
  pcall(C_Item.RequestLoadItemDataByID, item.itemID)
  ctx.requestsIssued = ctx.requestsIssued + 1
  return true
end

--- Called from ITEM_DATA_LOAD_RESULT. Returns true when the cache gained something, so the
--- caller knows a re-classify is worth doing.
---@param itemID number
---@param success boolean
---@return boolean
function enrich.OnItemDataLoaded(itemID, success)
  if not success then return false end

  local full = enrich.ReadFull(itemID)
  if not full then return false end

  itemcache.Put(itemID, full)
  -- ITEM_DATA_LOAD_RESULT is a global event: Blizzard and other addons request data too. Only an
  -- ID we asked for counts against the tier-3 accounting, otherwise `pending` goes negative.
  if requested[itemID] then resolved = resolved + 1 end
  return true
end

---@return string
function enrich.Stats()
  return string.format('item cache=%d, tier3 requested=%d resolved=%d pending=%d',
    itemcache.Count(), requestedCount, resolved, requestedCount - resolved)
end

return enrich
