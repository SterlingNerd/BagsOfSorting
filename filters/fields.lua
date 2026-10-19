-- The v1 field set (FR-21), registered as data.
--
-- M1's seven: type, subtype, quality, ilvl, name, equipSlot, isQuestItem.
-- `expansion` is measured out, not missing (`/bos test 14`, 2026-10-19): position 15 of
-- C_Item.GetItemInfo is confirmed as expansionID, but every item this Vanilla-ruleset client knows
-- reports 0 (Classic), so a rule on it can never discriminate. Recorded in docs/02 FR-21.
-- Plus two the model needs to be expressible at all:
--   itemID  — `itemID in {…}` is a leaf inside a rule tree (FR-24) and the most-used rule
--             type in the measured configs (docs/01)
--   none    — makes `__catchall` a real category instead of a code path (docs/04)

local _, addon = ...

---@class Fields: BoSModule
local fields = addon:NewModule('Fields')

local registry = addon:GetModule('FieldRegistry')

local Q = (Enum and Enum.ItemQuality) or {
  Poor = 0, Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5, Artifact = 6, Heirloom = 7,
}

local QUALITY_LABELS = {
  [Q.Poor] = 'Poor', [Q.Common] = 'Common', [Q.Uncommon] = 'Uncommon', [Q.Rare] = 'Rare',
  [Q.Epic] = 'Epic', [Q.Legendary] = 'Legendary', [Q.Artifact] = 'Artifact', [Q.Heirloom] = 'Heirloom',
}


local function qualityName(value)
  return QUALITY_LABELS[value] or tostring(value)
end

local function cmpSymbol(cmp)
  if cmp == '>=' then return '≥' end
  if cmp == '<=' then return '≤' end
  if cmp == '!=' then return '≠' end
  return cmp
end

--- Shared sentence builder for the string/number/enum fields. Sentences use the lowercase
--- field key, which is what a chip shows (docs/05 §Screen 2); label is for pickers.
local function simpleSentence(field, rule)
  local value = rule.value
  if type(value) == 'string' then value = string.format('%q', value) end
  return string.format('%s %s %s', field.key, cmpSymbol(rule.cmp), tostring(value))
end

--- Shared read/sentence wiring for fields whose value lives straight on the record.
local function register(def)
  def.sentence = def.sentence or function(rule) return simpleSentence(def, rule) end
  return registry.Register(def)
end

register({
  key = 'type', label = 'Type', valueKind = 'string',
  cmps = { '=', '!=', 'contains', 'startsWith' },
  read = function(item) return item.type end,
})

register({
  key = 'subtype', label = 'Subtype', valueKind = 'string',
  cmps = { '=', '!=', 'contains', 'startsWith' },
  read = function(item) return item.subtype end,
})

register({
  key = 'quality', label = 'Quality', valueKind = 'enum',
  cmps = { '=', '!=', '>=', '<=' },
  values = function()
    local out = {}
    for _, v in ipairs({ Q.Poor, Q.Common, Q.Uncommon, Q.Rare, Q.Epic, Q.Legendary, Q.Artifact, Q.Heirloom }) do
      out[#out + 1] = { v = v, label = qualityName(v) }
    end
    return out
  end,
  read = function(item) return item.quality end,
  sentence = function(rule) return string.format('quality %s %s', cmpSymbol(rule.cmp), qualityName(rule.value)) end,
})

register({
  key = 'ilvl', label = 'Item level', valueKind = 'number',
  cmps = { '=', '>=', '<=' },
  read = function(item) return item.ilvl end,
  sentence = function(rule) return string.format('item level %s %s', cmpSymbol(rule.cmp), tostring(rule.value)) end,
})

register({
  key = 'name', label = 'Name', valueKind = 'string',
  cmps = { '=', '!=', 'contains', 'startsWith' },
  read = function(item) return item.name end,
})


register({
  key = 'equipSlot', label = 'Equip slot', valueKind = 'string',
  cmps = { '=', '!=', 'contains' },
  read = function(item) return item.equipSlot end,
})

register({
  key = 'isQuestItem', label = 'Quest item', valueKind = 'bool',
  cmps = { '=' },
  read = function(item) return item.isQuestItem end,
  sentence = function(rule) return rule.value and 'is a quest item' or 'is not a quest item' end,
})

-- `itemID in {…}`: value is a set { [itemID] = true }, so the read is a hash lookup and the
-- cost is O(1) no matter how many IDs were pasted (docs/04 §Size & performance notes).
register({
  key = 'itemID', label = 'Item ID', valueKind = 'idlist',
  cmps = { 'in' },
  read = function(item) return item.itemID end,
  sentence = function(rule)
    local ids = rule.value or {}
    local count, first = 0, nil
    for id in pairs(ids) do
      count = count + 1
      if not first or id < first then first = id end
    end
    if count == 0 then return 'item ID in {empty list}' end
    if count == 1 then return string.format('item ID = %d', first) end
    return string.format('item ID in {%d +%d more}', first, count - 1)
  end,
})

-- The catch-all's only leaf: "nothing else owned this item" (docs/04 §Precedence 5).
register({
  key = 'none', label = 'Nothing else matched', valueKind = 'bool',
  cmps = { '=' },
  read = function(item) return item.owner == nil end,
  sentence = function() return 'no other category matched' end,
})

return fields
