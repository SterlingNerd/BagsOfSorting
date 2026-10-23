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
  -- Three real items, copied from the live item cache. 5411 is the one that matters: it is **type
  -- Armor and a quest item**, so where it lands is a priority question, not a rule question.
  {
    itemID = 5411, name = 'Winterhoof Cleansing Totem', quality = 1, ilvl = 1, expansion = 0,
    type = 'Armor', subtype = 'Miscellaneous', equipSlot = 'INVTYPE_NON_EQUIP',
    isQuestItem = true, stackCount = 1, bagID = 0, slot = 5, dataReady = true,
  },
  {
    itemID = 2901, name = 'Mining Pick', quality = 1, ilvl = 4, expansion = 0,
    type = 'Weapon', subtype = 'Miscellaneous', equipSlot = 'INVTYPE_WEAPON',
    isQuestItem = false, stackCount = 1, bagID = 0, slot = 6, dataReady = true,
  },
  {
    itemID = 6948, name = 'Hearthstone', quality = 1, ilvl = 1, expansion = 0,
    type = 'Miscellaneous', subtype = 'Junk', equipSlot = 'INVTYPE_NON_EQUIP',
    isQuestItem = false, stackCount = 1, bagID = 1, slot = 3, dataReady = true,
  },
  -- Issue #41. The first six are copied out of the live item cache
  -- (`WTF/Account/<account>/SavedVariables/BagsOfSorting.lua`, read 2026-10-20), so their
  -- type/subtype pair is what the Forever client itself reports: the class is **"Trade Goods"**,
  -- not retail's "Tradeskill", and potions, food and bandages are one class ("Consumable") with
  -- subtypes "Potions", "Food & Drink" and "Bandages".
  {
    itemID = 765, name = 'Silverleaf', quality = 1, ilvl = 5, expansion = 0,
    type = 'Trade Goods', subtype = 'Herb', equipSlot = 'INVTYPE_NON_EQUIP',
    classID = 7, subClassID = 9, isQuestItem = false, stackCount = 20, bagID = 5, slot = 1, dataReady = true,
  },
  {
    itemID = 2770, name = 'Copper Ore', quality = 1, ilvl = 10, expansion = 0,
    type = 'Trade Goods', subtype = 'Metal & Stone', equipSlot = 'INVTYPE_NON_EQUIP',
    classID = 7, subClassID = 7, isQuestItem = false, stackCount = 20, bagID = 0, slot = 7, dataReady = true,
  },
  {
    itemID = 2672, name = 'Stringy Wolf Meat', quality = 1, ilvl = 5, expansion = 0,
    type = 'Trade Goods', subtype = 'Cooking', equipSlot = 'INVTYPE_NON_EQUIP',
    classID = 7, subClassID = 8, isQuestItem = false, stackCount = 1, bagID = 0, slot = 8, dataReady = true,
  },
  {
    itemID = 118, name = 'Minor Healing Potion', quality = 1, ilvl = 5, expansion = 0,
    type = 'Consumable', subtype = 'Potions', equipSlot = 'INVTYPE_NON_EQUIP',
    isQuestItem = false, stackCount = 1, bagID = 0, slot = 9, dataReady = true,
  },
  {
    itemID = 159, name = 'Refreshing Spring Water', quality = 1, ilvl = 5, expansion = 0,
    type = 'Consumable', subtype = 'Food & Drink', equipSlot = 'INVTYPE_NON_EQUIP',
    isQuestItem = false, stackCount = 5, bagID = 0, slot = 10, dataReady = true,
  },
  {
    itemID = 1251, name = 'Linen Bandage', quality = 1, ilvl = 1, expansion = 0,
    type = 'Consumable', subtype = 'Bandages', equipSlot = 'INVTYPE_NON_EQUIP',
    isQuestItem = false, stackCount = 5, bagID = 0, slot = 11, dataReady = true,
  },
  -- The last four stand in for subtypes this character carries nothing of. `/bos test 41` measured
  -- these names against the client's own subclass table (build 1.60.1 70450). Only the type/subtype
  -- pair is load-bearing here; ilvl is a placeholder that deliberately stays below the 20 the sort
  -- tests key on.
  {
    itemID = 2320, name = 'Heavy Leather', quality = 1, ilvl = 1, expansion = 0,
    type = 'Trade Goods', subtype = 'Leather', equipSlot = 'INVTYPE_NON_EQUIP',
    isQuestItem = false, stackCount = 10, bagID = 1, slot = 4, dataReady = true,
  },
  {
    itemID = 2578, name = 'Linen Cloth', quality = 1, ilvl = 1, expansion = 0,
    type = 'Trade Goods', subtype = 'Cloth', equipSlot = 'INVTYPE_NON_EQUIP',
    isQuestItem = false, stackCount = 20, bagID = 1, slot = 5, dataReady = true,
  },
  {
    itemID = 3355, name = 'Elemental Earth', quality = 1, ilvl = 1, expansion = 0,
    type = 'Trade Goods', subtype = 'Elemental', equipSlot = 'INVTYPE_NON_EQUIP',
    isQuestItem = false, stackCount = 20, bagID = 5, slot = 2, dataReady = true,
  },
  {
    itemID = 3434, name = 'Strange Dust', quality = 1, ilvl = 1, expansion = 0,
    type = 'Trade Goods', subtype = 'Enchanting', equipSlot = 'INVTYPE_NON_EQUIP',
    isQuestItem = false, stackCount = 20, bagID = 5, slot = 3, dataReady = true,
  },
  -- 1006 and 26042 above keep retail's "Tradeskill" spelling on purpose: the rule-grammar tests
  -- read those strings. The client's own class name is "Trade Goods".

  -- Issue #47: four items that exist **only in the bank**, so "no backpack window leaks bank
  -- contents" has an unambiguous answer. One each for the sections the bank mirror has to fill:
  -- junk, the catch-all, ore, and a herb in a herb-family bag sitting in a bank slot.
  {
    itemID = 1007, name = 'Cracked Greaves', quality = 0, ilvl = 1, expansion = 0,
    type = 'Armor', subtype = 'Mail', equipSlot = 'INVTYPE_CHEST', classID = 4, subClassID = 6,
    isQuestItem = false, stackCount = 1, bagID = 6, slot = 1, dataReady = true,
  },
  {
    itemID = 1008, name = 'Iron Ore', quality = 1, ilvl = 15, expansion = 0,
    type = 'Trade Goods', subtype = 'Metal & Stone', equipSlot = 'INVTYPE_NON_EQUIP',
    classID = 7, subClassID = 7, isQuestItem = false, stackCount = 5, bagID = 6, slot = 3, dataReady = true,
  },
  {
    itemID = 1009, name = 'Notched Blade', quality = 1, ilvl = 15, expansion = 0,
    type = 'Weapon', subtype = 'Sword', equipSlot = 'INVTYPE_WEAPON', classID = 2, subClassID = 1,
    isQuestItem = false, stackCount = 1, bagID = 6, slot = 2, dataReady = true,
  },
  {
    itemID = 1010, name = 'Khadgar Pine', quality = 1, ilvl = 10, expansion = 0,
    type = 'Trade Goods', subtype = 'Herb', equipSlot = 'INVTYPE_NON_EQUIP',
    classID = 7, subClassID = 9, isQuestItem = false, stackCount = 8, bagID = 8, slot = 1, dataReady = true,
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
