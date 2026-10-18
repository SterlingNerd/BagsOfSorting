-- Keybind display text + the entry point Bindings.xml calls (FR-64).
--
-- The binding itself is declared in Bindings.xml, which is how it appears in the client's own
-- Key Bindings panel: the panel reads every binding the C++ knows about (ForEachBinding ->
-- GetBinding) and groups them by the binding's category, whose label is _G[category].
-- No default key is set: B is Blizzard's OPENALLBAGS and we do not steal it (docs/07 Q4).

local _, addon = ...

---@class Keybinds: BoSModule
local keybinds = addon:NewModule('Keybinds')

BINDING_HEADER_BAGSOF_SORTING = 'Bags of Sorting'
BINDING_NAME_BAGSOF_SORTING_TOGGLE = 'Toggle sorting bags'

--- Bound by BAGSOF_SORTING_TOGGLE in Bindings.xml.
---@diagnostic disable-next-line: lowercase-global
function BagsOfSorting_Toggle()
  addon:GetModule('Init').Toggle()
end

return keybinds
