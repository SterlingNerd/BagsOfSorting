-- Phase 6: order items within a section (FR-46). Section order is the window's own section
-- order; the section sort modes (manual/name/size) arrive with the UI that edits them (FR-80).

local _, addon = ...

---@class Sort: BoSModule
local sort = addon:NewModule('Sort')

local function nameThenQuality(a, b)
  local an, bn = a.name or '', b.name or ''
  if an ~= bn then return an < bn end
  local aq, bq = a.quality or 0, b.quality or 0
  if aq ~= bq then return aq > bq end
  return a.itemID < b.itemID
end

local function qualityThenName(a, b)
  local aq, bq = a.quality or 0, b.quality or 0
  if aq ~= bq then return aq > bq end
  local an, bn = a.name or '', b.name or ''
  if an ~= bn then return an < bn end
  return a.itemID < b.itemID
end

local function byIlvl(a, b)
  if (a.ilvl or 0) ~= (b.ilvl or 0) then return (a.ilvl or 0) > (b.ilvl or 0) end
  return nameThenQuality(a, b)
end

local function byExpansion(a, b)
  if (a.expansion or 0) ~= (b.expansion or 0) then return (a.expansion or 0) < (b.expansion or 0) end
  return nameThenQuality(a, b)
end

local MODES = {
  nameThenQuality = nameThenQuality,
  qualityThenName = qualityThenName,
  ilvl = byIlvl,
  expansion = byExpansion,
}

---@param items BoSItem[]
---@param mode string?
function sort.Items(items, mode)
  table.sort(items, MODES[mode] or nameThenQuality)
end

---@return string[]
function sort.Modes()
  local modes = {}
  for mode in pairs(MODES) do modes[#modes + 1] = mode end
  table.sort(modes)
  return modes
end

return sort
