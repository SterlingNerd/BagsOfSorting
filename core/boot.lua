-- Module lifecycle without AceAddon (docs/03: zero vendored libraries).
-- Load order is the TOC; core/init.lua loads last so every module exists here.

local addonName, frame = ...

---@class BagsOfSorting
local addon = frame

addon.name = addonName
addon.title = 'Bags of Sorting'
addon.version = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(addonName, 'Version') or 'dev'

---@class BoSModule
---@field name string

---@param name string
---@return BoSModule
function addon:NewModule(name)
  local mod = { name = name }
  addon.modules = addon.modules or {}
  addon.modules[name] = mod
  return mod
end

---@param name string
---@return BoSModule?
function addon:GetModule(name)
  return addon.modules and addon.modules[name]
end
