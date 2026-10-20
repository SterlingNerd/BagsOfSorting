-- Phase 1: which containers exist, and what is in them (FR-14).
--
-- The container list is discovered by probing at load, never enumerated from Enum.BagIndex:
-- Forever has no BankBag_* enum values while Camelot computes bank-bag indices
-- arithmetically, and indices read under two names count the same items twice (agents.md,
-- issues #9/#10/#11). Every probe is pcall'd: an index that errors and an index that returns
-- 0 are both answers, neither is a crash.
--
-- shortcut: backpack side only. Issue #9 (closed 2026-10-18) settled the bank side: index 6 is the
-- 48-slot grid, 7..14 are the bank bag slots, and index 6 answers 0 slots while the bank is closed —
-- so bank containers enter the discovered list on BANKFRAME_OPENED and leave on BANKFRAME_CLOSED.
-- A purchased bank bag (measured 2026-10-19, issue #25) is a second container in that same paged grid:
-- index 7 answers the slot count of the bag item placed in it (6 -> 0 -> 8 across a swap), `GetBagName`
-- calls it `Bank` like every other bank container, and its contents read at index 7 with bag-relative
-- slots. Harvesting the bank is therefore containers 6..14, nothing special-cased per bag. Wiring it is
-- M5 work.

local _, addon = ...

---@class Harvest: BoSModule
local harvest = addon:NewModule('Harvest')

local constants = addon:GetModule('Constants')

---@class BoSContainer
---@field index number
---@field name string
---@field slots number
---@field kind string   -- 'backpack' | 'keyring'

---@class BoSFreeSlot
---@field bagID number
---@field slot number

---@class BoSItem
---@field bagID number
---@field slot number
---@field itemID number
---@field name string?
---@field quality number?
---@field icon number?
---@field link string?
---@field stackCount number
---@field isBound boolean?
---@field isLocked boolean?
---@field hasLoot boolean?
---@field isQuestItem boolean?
---@field type string?
---@field subtype string?
---@field equipSlot string?
---@field classID number?
---@field subClassID number?
---@field ilvl number?
---@field expansion number?
---@field dataReady boolean
---@field owner string?
---@field trace any

---@type BoSContainer[]
local discovered

---@type table<string, number>?
local freeSlots
---@type BoSFreeSlot?
local firstFree

local function probe(index, kind)
  if index == nil then return nil end
  local okSlots, slots = pcall(C_Container.GetContainerNumSlots, index)
  if not okSlots or type(slots) ~= 'number' or slots <= 0 then return nil end
  local okName, name = pcall(C_Container.GetBagName, index)
  return { index = index, slots = slots, kind = kind, name = (okName and name) or '' }
end

--- Build the container list. Called at login and whenever a bag is equipped or removed.
---@return BoSContainer[]
function harvest.Discover()
  local seen, list = {}, {}
  local function add(index, kind)
    local container = probe(index, kind)
    if container and not seen[container.index] then
      seen[container.index] = true
      list[#list + 1] = container
    end
  end

  add(constants.BACKPACK, 'backpack')
  for i = 1, constants.NUM_BAG_SLOTS do
    add(constants.BACKPACK + i, 'backpack')
  end
  add(constants.REAGENTBAG_INDEX, 'backpack')
  add(constants.KEYRING, 'keyring')

  table.sort(list, function(a, b) return a.index < b.index end)
  discovered = list
  return list
end

---@return BoSContainer[]
function harvest.Containers()
  return discovered or harvest.Discover()
end

--- Read every slot once. GetContainerItemInfo is the cheap tier: it carries
--- itemName, quality and iconFileID for items the client already has in inventory, with no
--- round trip (docs/03 §Item data is not always there). Visiting every slot is also where the
--- free-slot count comes from (issue #36), so the count and the items cannot disagree.
---@return BoSItem[]
function harvest.Items()
  local items = {}
  local free, freeFirst = {}, nil
  for _, container in ipairs(harvest.Containers()) do
    for slot = 1, container.slots do
      local ok, info = pcall(C_Container.GetContainerItemInfo, container.index, slot)
      if ok and info and info.itemID then
        local questOK, quest = pcall(C_Container.GetContainerItemQuestInfo, container.index, slot)
        items[#items + 1] = {
          bagID = container.index,
          slot = slot,
          itemID = info.itemID,
          name = info.itemName,
          quality = info.quality,
          icon = info.iconFileID,
          link = info.hyperlink,
          stackCount = info.stackCount or 1,
          isBound = info.isBound,
          isLocked = info.isLocked,
          hasLoot = info.hasLoot,
          isQuestItem = (questOK and quest and quest.isQuestItem) or false,
          containerName = container.name,
          containerKind = container.kind,
          dataReady = false,
        }
      else
        -- A slot the client reports no item for is a free slot: ContainerItemInfo.itemID is
        -- documented non-nullable, so an occupied slot always answers one.
        free[container.kind] = (free[container.kind] or 0) + 1
        -- The first one is the slot the free-slot indicator points at (issue #36): a real empty
        -- slot, so the client's own click and drop handlers work on it. Backpack family only —
        -- the keyring sorts first and is not the player's bags.
        if not freeFirst and container.kind == 'backpack' then
          freeFirst = { bagID = container.index, slot = slot }
        end
      end
    end
  end
  freeSlots, firstFree = free, freeFirst
  return items
end

--- Free slots in one container family, counted in the same pass that read the items (issue #36).
---@param kind string  -- 'backpack' | 'keyring'
---@return number
function harvest.FreeSlots(kind)
  return (freeSlots or {})[kind] or 0
end

---@return BoSFreeSlot?
function harvest.FirstFreeSlot()
  return firstFree
end

--- AC-14: harvested totals a human can compare against the stock bags.
---@return string[]
function harvest.Summary()
  local lines = {}
  for _, container in ipairs(harvest.Containers()) do
    local filled = 0
    for slot = 1, container.slots do
      local ok, info = pcall(C_Container.GetContainerItemInfo, container.index, slot)
      if ok and info and info.itemID then filled = filled + 1 end
    end
    lines[#lines + 1] = string.format('  [%d] %s slots=%d filled=%d kind=%s',
      container.index, container.name, container.slots, filled, container.kind)
  end
  if #lines == 0 then lines[1] = '  (no containers discovered)' end
  return lines
end

function harvest.Invalidate()
  discovered = nil
end

return harvest
