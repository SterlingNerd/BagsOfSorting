-- Fixture items shaped exactly like a harvested+enriched record, so the classifier is tested
-- against the same data shape it will read in-game (FR-106).

local _, addon = ...

---@class Fixtures: BoSModule
local fixtures = addon:NewModule('Fixtures')

---@type BoSItem[]
fixtures.items = {
  {
    itemID = 1001, name = 'Rusty Chainmail', quality = 0, ilvl = 1, expansion = 0,
    type = 'Armor', subtype = 'Mail', equipSlot = 'INVTYPE_CHEST', classID = 4, subClassID = 6,
    isQuestItem = false, stackCount = 1, bagID = 0, slot = 1, dataReady = true,
  },
  {
    itemID = 1002, name = 'Virtuous Blade', quality = 4, ilvl = 20, expansion = 0,
    type = 'Weapon', subtype = 'Sword', equipSlot = 'INVTYPE_WEAPON', classID = 2, subClassID = 1,
    isQuestItem = false, stackCount = 1, bagID = 0, slot = 2, dataReady = true,
  },
  -- Matches the gear rule's shape but is excluded by the EXCEPT row (AC-20, AC-24).
  {
    itemID = 1003, name = 'Frayed Vestments', quality = 4, ilvl = 20, expansion = 0,
    type = 'Armor', subtype = 'Cloth', equipSlot = 'INVTYPE_CHEST', classID = 4, subClassID = 2,
    isQuestItem = false, stackCount = 1, bagID = 0, slot = 3, dataReady = true,
  },
  {
    itemID = 26042, name = 'Linen Glyph', quality = 2, ilvl = 0, expansion = 2,
    type = 'Tradeskill', subtype = 'Inscription Reagent', equipSlot = 'INVTYPE_NON_EQUIP',
    classID = 7, subClassID = 17, isQuestItem = false, stackCount = 20, bagID = 1, slot = 1, dataReady = true,
  },
  {
    itemID = 1004, name = 'Sealed Mission', quality = 1, ilvl = 0, expansion = 0,
    type = 'Key', subtype = 'Key', equipSlot = 'INVTYPE_NON_EQUIP', classID = 9, subClassID = 1,
    isQuestItem = true, stackCount = 1, bagID = 0, slot = 4, dataReady = true,
  },
  -- An item the client has no data for yet: no name, no quality, no type (FR-103).
  {
    itemID = 1005, name = nil, quality = nil, ilvl = nil, expansion = nil,
    type = nil, subtype = nil, equipSlot = nil, isQuestItem = false,
    stackCount = 1, bagID = 0, slot = 5, dataReady = false,
  },
  {
    itemID = 1006, name = 'Linen Cloth', quality = 1, ilvl = 0, expansion = 0,
    type = 'Tradeskill', subtype = 'Cloth', equipSlot = 'INVTYPE_NON_EQUIP', classID = 7, subClassID = 5,
    isQuestItem = false, stackCount = 8, bagID = 1, slot = 2, dataReady = true,
  },
}

---@return BoSItem[]
function fixtures.Clone()
  local out = {}
  for _, src in ipairs(fixtures.items) do
    local copy = {}
    for key, value in pairs(src) do copy[key] = value end
    out[#out + 1] = copy
  end
  return out
end

---@param itemID number
---@return BoSItem?
function fixtures.Find(items, itemID)
  for _, item in ipairs(items) do
    if item.itemID == itemID then return item end
  end
  return nil
end

return fixtures
