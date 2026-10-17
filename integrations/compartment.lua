-- Addon Compartment entry (FR-120): the native home on Forever, no LibDBIcon anywhere
-- in this tree (FR-123).
--
-- M1 has no configure mode yet, so the compartment entry toggles the sorting windows.
-- It becomes the configure-mode entry at M4 (docs/06).

local _, addon = ...

---@class Compartment: BoSModule
local compartment = addon:NewModule('Compartment')

---@diagnostic disable-next-line: lowercase-global
function BagsOfSorting_OnAddonCompartmentClick()
  addon:GetModule('Init').Toggle()
end

return compartment
