-- Phase 1: which containers exist, and what is in them (FR-14).
--
-- The container list is discovered by probing at load, never enumerated from Enum.BagIndex:
-- Forever has no BankBag_* enum values while Camelot computes bank-bag indices
-- arithmetically, and indices read under two names count the same items twice
-- (wow-forever-api skill: references/containers-and-bags.md, issues #9/#10/#11). Every probe is
-- pcall'd: an index that errors and an index that returns
-- 0 are both answers, neither is a crash.
--
-- shortcut: the bank half is present only while the bank window is open. Issue #9 (closed
-- 2026-10-18) settled the shape: index 6 is the 48-slot grid, 7..14 are the bank bag slots, and index
-- 6 answers 0 slots while the bank is closed — so bank containers enter the discovered list on
-- BANKFRAME_OPENED and leave on BANKFRAME_CLOSED (AC-13). A purchased bank bag (measured 2026-10-19,
-- issue #25) is a second container in that same paged grid: index 7 answers the slot count of the bag
-- item placed in it (6 -> 0 -> 8 across a swap), `GetBagName` calls it `Bank` like every other bank
-- container, and its contents read at index 7 with bag-relative slots. Harvesting the bank is
-- therefore containers 6..14, nothing special-cased per bag.

local _, addon = ...

---@class Harvest: BoSModule
local harvest = addon:NewModule('Harvest')

local constants = addon:GetModule('Constants')

---@class BoSContainer
---@field index number
---@field name string
---@field slots number
---@field kind string   -- 'backpack' | 'reagent' | 'keyring' | 'bank'
---@field family number  -- the client's specialty-bag bit for this container (constants.BAG_FAMILY)

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
---@field stackedCount number?  -- the total a merged cell shows (FR-43, #59): written by Pipeline, never by the harvest
---@field isBound boolean?
---@field isLocked boolean?
---@field hasLoot boolean?
---@field isQuestItem boolean?
---@field questID number?
---@field type string?
---@field subtype string?
---@field equipSlot string?
---@field classID number?
---@field subClassID number?
---@field ilvl number?
---@field expansion number?
---@field containerName string?
---@field containerKind string?  -- the kind of the container it came from; pipeline.Assign uses it to keep the bank out of the backpack windows
---@field dataReady boolean
---@field isNew boolean?  -- the client's own new-item flag for this slot, as data/harvest.lua records it; the field registry exposes it as `isNew` and the New category binds it (issue #39)
---@field owner string?
---@field trace any

---@type BoSContainer[]
local discovered

-- Session record of which slots held new items, keyed `bagID:slot` -> the itemID that was new there.
-- The client's own flag is too fragile to build a section on (it dies on a hover and on every
-- container-frame hide, and `C_NewItems` cannot put one back), so this record is what the New section
-- follows. Only `core/interactions.lua` removes from it: closing the bags, or a hover when the window
-- menu's Clear New on Close is off. The itemID is what stops a different item moving into a slot that
-- once held something new from inheriting the flag.
---@type table<string, number>
local newItemSession = {}

--- Slots that held new items and were hovered this session. Hovering marks a slot here
--- but does not remove it from newItemSession: items stay in the New section during the
--- session (no reflow on hover) and leave on close instead. Only core/interactions.lua
--- removes from it: closing the bags clears hovered slots when Clear New on Close is off.
---@type table<string, boolean>
local hoveredNewItems = {}

---@type table<string, number>?
local freeSlots
---@type table<string, BoSFreeSlot>?
local firstFreeByKind
---@type table<number, number>?
local freeSlotsByFamily
---@type table<number, BoSFreeSlot>?
local firstFreeByFamily

--- True while the bank window is open, and therefore while containers 6..14 exist to be read.
local bankOpen = false

local function probe(index, kind)
  if index == nil then return nil end
  local okSlots, slots = pcall(C_Container.GetContainerNumSlots, index)
  if not okSlots or type(slots) ~= 'number' or slots <= 0 then return nil end
  local okName, name = pcall(C_Container.GetBagName, index)
  -- The client's own specialty bit for this container (issue #44). Read-only, and the client uses
  -- it the same way: EquipmentManager.lua:22 and Blizzard_CatalogShop.lua:827 both compare the
  -- second return against 0 to mean "a normal bag". One that answers nothing is a plain bag.
  local okFamily, _, family = pcall(C_Container.GetContainerNumFreeSlots, index)
  return {
    index = index, slots = slots, kind = kind, name = (okName and name) or '',
    family = (okFamily and family) or 0,
  }
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
  -- Its own family, not a backpack bag: the free-slot count covers the backpack and the four bag
  -- slots, which is the same set the client's own number covers (issue #36). The pouch's items are
  -- still harvested and still drawn.
  -- shortcut: its free slots are counted apart and shown nowhere; how an empty reagent pouch reads
  -- in a window is FR-44's per-family design (docs/02), open on issue #36.
  add(constants.REAGENTBAG_INDEX, 'reagent')
  add(constants.KEYRING, 'keyring')

  -- The bank half (issue #47): the grid plus the nine bank bag slots, and only while the bank is
  -- open. Opening the bank fires no container event, so nothing but SetBankOpen puts them here.
  if bankOpen then
    for i = 1, constants.NUM_CHARACTER_BANK_SLOTS do
      add(constants.ITEM_INVENTORY_BANK_BAG_OFFSET + i, 'bank')
    end
  end

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
  local free, freeFirst = {}, {}
  local byFamily, firstByFamily = {}, {}
  for _, container in ipairs(harvest.Containers()) do
    -- Which side of the character a container is on (issue #47): a bank bag's free space belongs to
    -- the bank windows and an equipped bag's to the backpack windows, so the two never add up into
    -- one number on either side.
    local side = container.kind == 'bank' and 'bank' or 'backpack'
    for slot = 1, container.slots do
      local ok, info = pcall(C_Container.GetContainerItemInfo, container.index, slot)
      if ok and info and info.itemID then
        local questOK, quest = pcall(C_Container.GetContainerItemQuestInfo, container.index, slot)
        -- Issue #39: the client's flag is how we learn a slot went new; what the New section
        -- **follows** is our record, because the flag is not durable. `C_NewItems.RemoveNewItem` runs
        -- on a hover (`ContainerFrameItemButton_OnEnter`, ContainerFrame.lua:1724) *and* on every
        -- `ContainerFrame_OnHide` (`UpdateNewItemList`, :817, :393) — including the container frames our
        -- own vendor/bank suppression hides — and `C_NewItems` offers no way to put a flag back.
        -- Which record the hover and the close paths clear is `display.clearNewOnClose`'s business
        -- (core/interactions.lua); this function only reports what is new now.
        local isNew = harvest.IsNewItem(container.index, slot)
        if isNew then harvest.MarkNewItemSession(container.index, slot, info.itemID) end
        isNew = isNew or harvest.WasNewInSession(container.index, slot, info.itemID)
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
          questID = (questOK and quest and quest.questID) or nil,
          containerName = container.name,
          containerKind = container.kind,
          dataReady = false,
          isNew = isNew,
        }
      else
        -- A slot the client reports no item for is a free slot: ContainerItemInfo.itemID is
        -- documented non-nullable, so an occupied slot always answers one.
        free[container.kind] = (free[container.kind] or 0) + 1
        -- The same slots, grouped by the specialty family the client reported for the container
        -- (issue #44): an herb bag's free space is the Herbs section's number.
        local fams = byFamily[side] or {}
        byFamily[side] = fams
        local firsts = firstByFamily[side] or {}
        firstByFamily[side] = firsts
        fams[container.family] = (fams[container.family] or 0) + 1
        if not firsts[container.family] then
          firsts[container.family] = { bagID = container.index, slot = slot }
        end
        -- The first one per container kind is the slot that kind's free-slot indicator points at
        -- (issue #36, and #47 for the bank side): a real empty slot, so the client's own click and
        -- drop handlers work on it.
        if not freeFirst[container.kind] then
          freeFirst[container.kind] = { bagID = container.index, slot = slot }
        end
      end
    end
  end
  freeSlots, firstFreeByKind = free, freeFirst
  freeSlotsByFamily, firstFreeByFamily = byFamily, firstByFamily
  return items
end

--- Free slots in one container family, counted in the same pass that read the items (issue #36).
---@param kind string  -- 'backpack' | 'keyring' | 'reagent' | 'bank'
---@return number
function harvest.FreeSlots(kind)
  return (freeSlots or {})[kind] or 0
end

--- Free slots in the containers the client reports as one specialty-bag family (issue #44): the
--- herb bag's space is the Herbs section's number, the mining bag's is Ore's. Family 0 is every
--- plain bag in the set. `side` is which half of the character the count is for — 'backpack' or
--- 'bank' (issue #47) — because a section counts the bag on its own side, not every bag of that
--- family the character owns.
---@param family number
---@param side string  -- 'backpack' | 'bank'
---@return number
function harvest.FreeSlotsForFamily(family, side)
  return ((freeSlotsByFamily or {})[side] or {})[family] or 0
end

---@param family number
---@param side string  -- 'backpack' | 'bank'
---@return BoSFreeSlot?
function harvest.FirstFreeSlotForFamily(family, side)
  return ((firstFreeByFamily or {})[side] or {})[family]
end

--- The first free slot of one container kind — the slot that kind's free-slot indicator points at.
---@param kind string  -- 'backpack' | 'bank'
---@return BoSFreeSlot?
function harvest.FirstFreeSlot(kind)
  return (firstFreeByKind or {})[kind or 'backpack']
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
  freeSlotsByFamily, firstFreeByFamily = nil, nil
end

--- Open or close the bank half of the container list (issue #47, AC-13). Opening the bank fires no
--- container event and closing it fires none either, so this is the only thing that adds indices
--- 6..14 and the only thing that takes them away — which is also what takes the bank windows off
--- screen: a bank window over a container list that no longer holds the bank is a frame around
--- nothing.
---@param open boolean
function harvest.SetBankOpen(open)
  open = open and true or false
  if open == bankOpen then return end
  bankOpen = open
  harvest.Invalidate()
end

---@return boolean
function harvest.BankOpen()
  return bankOpen
end

--- Issue #39: the client's own answer for "is this slot new", read-only — we never call
--- RemoveNewItem or AddNewItem ourselves. Hovering our button runs the client's own
--- ContainerFrameItemButton_OnEnter, which does clear it (AC-39).
---@param bagID number
---@param slot number
---@return boolean
function harvest.IsNewItem(bagID, slot)
  if C_NewItems and C_NewItems.IsNewItem then
    local ok, isNew = pcall(C_NewItems.IsNewItem, bagID, slot)
    if ok then return isNew end
  end
  return false
end

--- Record that this slot held a new item, tagged with the item that was new there.
---@param bagID number
---@param slot number
---@param itemID number
function harvest.MarkNewItemSession(bagID, slot, itemID)
  newItemSession[bagID .. ':' .. slot] = itemID
end

--- True when this slot held *this* item while it was new. The itemID comparison is what stops a
--- different item moving into a slot that once held something new from being listed as new.
---@param bagID number
---@param slot number
---@param itemID number
---@return boolean
function harvest.WasNewInSession(bagID, slot, itemID)
  return newItemSession[bagID .. ':' .. slot] == itemID
end

--- Forget one slot: this is the hover path, where the player cleared the client's flag themselves
--- and the window menu's Clear New on Close is off, so a hover is the only thing that clears.
---@param bagID number
---@param slot number
function harvest.ForgetNewItemSession(bagID, slot)
  newItemSession[bagID .. ':' .. slot] = nil
end

--- Empty the record. Closing the bags with Clear New on Close on does this (issue #39, AC-39),
--- and it is what makes the New section mean "new since you last closed your bags".
function harvest.ClearNewItemSession()
  newItemSession = {}
end

--- Mark this slot as hovered while new. On close (with Clear New on Close off) hovered slots are
--- removed from newItemSession so they leave the New section then, not when they were hovered.
---@param bagID number
---@param slot number
function harvest.MarkHoveredNewItem(bagID, slot)
  hoveredNewItems[bagID .. ':' .. slot] = true
end

--- Remove every hovered slot from newItemSession, then clear the hovered set. Called on bag close
--- when Clear New on Close is off: hovered items leave the New section then, not when hovered.
function harvest.ClearHoveredNewItems()
  for key in pairs(hoveredNewItems) do
    newItemSession[key] = nil
  end
  hoveredNewItems = {}
end

return harvest
