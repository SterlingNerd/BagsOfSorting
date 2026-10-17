-- Tier 2 of the item lookup (docs/03 §Item data is not always there): the persisted cache
-- that makes a 40-ID manual category usable on first login (FR-97, AC-97).
--
-- This is the only derived state the addon persists (FR-109). It is bounded, debounced and
-- safe to delete: deleting it costs re-requests, not correctness.

local _, addon = ...

---@class ItemCache: BoSModule
local itemcache = addon:NewModule('ItemCache')

local constants = addon:GetModule('Constants')

---@class BoSCachedItem
---@field name string?
---@field quality number?
---@field ilvl number?
---@field expansion number?
---@field icon number?
---@field type string?
---@field subtype string?

---@return table<number, BoSCachedItem>
local function store()
  return addon:GetModule('DB').ItemCache()
end

---@param itemID number
---@return BoSCachedItem?
function itemcache.Get(itemID)
  return store()[itemID]
end

---@param itemID number
---@param entry BoSCachedItem
function itemcache.Put(itemID, entry)
  local cache = store()
  if cache[itemID] == nil and itemcache.Count() >= constants.MAX_ITEM_CACHE then
    -- shortcut: over the cap we stop caching new IDs rather than evicting, because a
    -- rebuild is free (it is a cache, not a store). Upgrade to LRU if the cap is ever hit.
    return
  end
  cache[itemID] = entry
end

---@return number
function itemcache.Count()
  local n = 0
  for _ in pairs(store()) do n = n + 1 end
  return n
end

return itemcache
