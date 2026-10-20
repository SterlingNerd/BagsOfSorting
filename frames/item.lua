-- Phase 8, item buttons. Pooled (FR-42), built from the client's own bag pieces so a skinning
-- addon the user already runs reaches our bags with no code from us (FR-49, docs/07 Q16).
--
-- Each button carries a wrapper frame whose ID is the real container index, because
-- ContainerFrameItemButtonMixin:GetBagID() falls back to GetParent():GetID() and every stock
-- handler (click, drag, tooltip, modified click, stack split) resolves the real slot from
-- bagID+slot. That is why normal item interaction is unchanged (FR-60, AC-60): we are running
-- Blizzard's own handlers on our own buttons, not reimplementing them.

local _, addon = ...

---@class ItemFrames: BoSModule
local itemFrames = addon:NewModule('ItemFrames')

local constants = addon:GetModule('Constants')
local pool = addon:GetModule('Pool')

local SIZE = constants.BUTTON_SIZE

local buttonCount = 0

---@class BoSItemEntry
---@field parent Frame
---@field button ItemButton
---@field item BoSItem?

local function create()
  -- The button needs a global name: ContainerFrameItemButtonTemplate anchors its child
  -- textures with $parent, which only resolves for named frames.
  buttonCount = buttonCount + 1
  local name = 'BagsOfSortingItemButton' .. buttonCount

  local parent = CreateFrame('Frame', name .. 'Parent')
  parent:SetSize(SIZE, SIZE)
  -- ContainerFrameItemButtonMixin:Initialize asks its parent this; we are never a combined bag.
  parent.IsCombinedBagContainer = function() return false end

  local button = CreateFrame('ItemButton', name, parent, 'ContainerFrameItemButtonTemplate')
  button:SetAllPoints(parent)

  return { parent = parent, button = button }
end

local function reset(entry)
  entry.item = nil
  entry.button:SetItemLocation(nil)
  entry.button:SetID(0)
  entry.button:Hide()
  entry.parent:ClearAllPoints()
  entry.parent:SetParent(nil)
  entry.parent:Hide()
end

itemFrames.pool = pool.Named('itemButton', create, reset)

---@return BoSItemEntry
function itemFrames.Acquire()
  return itemFrames.pool:Acquire()
end

---@param entry BoSItemEntry
function itemFrames.Release(entry)
  itemFrames.pool:Release(entry)
end

--- Point the button at the real slot, then paint from our record rather than from the
--- client's item cache, so an item whose tier-3 data has not arrived still shows its icon
--- (FR-103: uncached item data is a normal state, not an error).
---
--- bagID travels as the wrapper frame's ID, not as the `bagid` attribute:
--- GetBagID() reads self.bagID first, and a pooled button reused across bags would then
--- answer with whichever bag it last held. The parent's ID is always the one we just set.
---@param entry BoSItemEntry
---@param item BoSItem
---@param parent Frame
function itemFrames.Paint(entry, item, parent)
  entry.item = item

  entry.parent:SetParent(parent)
  entry.parent:SetID(item.bagID)
  entry.button:SetID(item.slot)
  entry.button:SetItemLocation(ItemLocation:CreateFromBagAndSlot(item.bagID, item.slot))

  SetItemButtonTexture(entry.button, entry.item.icon or 0)
  SetItemButtonQuality(entry.button, item.quality, item.link, false, item.isBound)
  SetItemButtonCount(entry.button, item.stackCount > 1 and item.stackCount or nil)
  -- shortcut: Blizzard's UpdateContainerButtonInfo also runs UpdateNewItem, UpdateQuestItem,
  -- UpdateJunkItem, UpdateItemContextMatching, UpdateCooldown and SetReadable on its own buttons.
  -- M1 only needs the icon, quality border and count to prove the pipeline; the overlays arrive
  -- with the milestone that owns each one (FR-47 new items, FR-45 quest, FR-65 junk).

  entry.parent:Show()
  entry.button:Show()
end

--- The free-slot indicator (issue #36): the same pooled button, drawn as an empty slot with the
--- number of free slots in it. `SetItemButtonTexture(button, nil)` is what produces the client's
--- own empty-slot look — `ContainerFrameItemButtonTemplate` carries `emptyBackgroundAtlas =
--- "bags-item-slot64"` and `ItemButtonMixin:GetItemButtonBackgroundTexture` falls back to it when
--- there is no icon. `minDisplayCount` goes below Blizzard's threshold of 1 so a single free slot
--- still reads "1".
---@param entry BoSItemEntry
---@param slot BoSFreeSlot
---@param count number
---@param parent Frame
function itemFrames.PaintEmpty(entry, slot, count, parent)
  entry.item = nil

  entry.parent:SetParent(parent)
  entry.parent:SetID(slot.bagID)
  entry.button:SetID(slot.slot)
  -- A real empty slot, not a placeholder: the client's own click and drop handlers work on it, so
  -- dropping an item here puts it in the bag the way an empty backpack slot does.
  entry.button:SetItemLocation(ItemLocation:CreateFromBagAndSlot(slot.bagID, slot.slot))

  SetItemButtonTexture(entry.button, nil)
  SetItemButtonQuality(entry.button, nil)
  entry.button:SetHasItem(false)
  entry.button.minDisplayCount = 0
  SetItemButtonCount(entry.button, count)

  entry.parent:Show()
  entry.button:Show()
end

--- Pre-warm the pool so a combat loot event does not have to create a secure button
--- (agents.md hard rule 3). Called once at login from the harvested item count.
---@param count number
function itemFrames.Warm(count)
  local held = {}
  for i = 1, count do
    held[i] = itemFrames.Acquire()
  end
  for i = count, 1, -1 do
    itemFrames.Release(held[i])
  end
end

return itemFrames
