-- Tier 2 of the item lookup (docs/03 §Item data is not always there): the in-memory cache
-- seeded once from SavedVariables on load, then detached. No cross-session persistence.
-- Login inventory scan (data/enrich.lua) primes it for items in your bags.
--
-- This is derived state we no longer persist (FR-109). Safe to delete: costs re-requests,
-- not correctness. Cap is kept as a memory guard; no eviction (rebuild is free).

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

---@type table<number, BoSCachedItem>?
local memoryCache = nil

---@return table<number, BoSCachedItem>
local function store()
  if memoryCache == nil then
    -- One-time seeding from SavedVariables, then detach so the 230 KB can be GC'd.
    memoryCache = addon:GetModule('DB').DetachItemCache() or {}
  end
  return memoryCache
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

--- Prime the cache with items currently in the player's bags.
--- Called once on PLAYER_LOGIN from enrich.lua.
---@param items BoSItem[]
function itemcache.PrimeFromInventory(items)
  local cache = store()
  local enrich = addon:GetModule('Enrich')
  for _, item in ipairs(items) do
    if cache[item.itemID] == nil then
      local full = enrich.ReadFull(item.itemID)
      if full then
        cache[item.itemID] = full
      end
    end
  end
end

return itemcache