-- Field registry (docs/03 §Classification). A field is data: label, value kind, allowed
-- comparisons, an O(1) read over the enriched record, and the sentence it renders as.
--
-- `sentence` is mandatory and enforced here: it is what a chip renders and what the preview
-- header prints, so a rule type the UI cannot explain cannot be registered (FR-20).

local _, addon = ...

---@class FieldRegistry: BoSModule
local registry = addon:NewModule('FieldRegistry')

local log = addon:GetModule('Log')

---@class BoSField
---@field key string
---@field label string
---@field valueKind string        -- enum | number | string | bool | idlist
---@field cmps string[]
---@field read fun(item: BoSItem): any
---@field sentence fun(rule: BoSRule): string
---@field values? fun(): {v: any, label: string}[]
---@field expensive? boolean      -- needs tier-3/tooltip data; evaluated last (docs/04)

---@type table<string, BoSField>
registry.fields = {}

---@param def BoSField
---@return boolean
function registry.Register(def)
  if not def.key or not def.label or not def.valueKind or not def.cmps or not def.read or not def.sentence then
    log.Error('field rejected (missing key/label/valueKind/cmps/read/sentence):', def and def.key)
    return false
  end
  registry.fields[def.key] = def
  return true
end

---@param key string
---@return BoSField?
function registry.Get(key)
  return registry.fields[key]
end

---@return string[]
function registry.Keys()
  local keys = {}
  for key in pairs(registry.fields) do keys[#keys + 1] = key end
  table.sort(keys)
  return keys
end

return registry
