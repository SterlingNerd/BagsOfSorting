-- Keybind display text, the entry point Bindings.xml calls, and the persistence mirror the
-- client's own bindings file does not give us (FR-64, issue #13).
--
-- The binding itself is declared in Bindings.xml, which is how it appears in the client's own
-- Key Bindings panel: the panel enumerates every binding the C++ knows about (ForEachBinding)
-- and groups them by the binding's category, whose label is _G[category].
-- No default key is set: B is Blizzard's OPENALLBAGS and we do not steal it (docs/07 Q4).

local _, addon = ...

---@class Keybinds: BoSModule
local keybinds = addon:NewModule('Keybinds')

local db = addon:GetModule('DB')
local events = addon:GetModule('Events')

local ACTION = 'BAGSOF_SORTING_TOGGLE'

BINDING_HEADER_BAGSOF_SORTING = 'Bags of Sorting'
BINDING_NAME_BAGSOF_SORTING_TOGGLE = 'Toggle sorting bags'

local function stored()
  db.sv.global.keybinds = db.sv.global.keybinds or {}
  return db.sv.global.keybinds
end

--- Measured 2026-10-19: the client writes our action to `bindings-cache.wtf`
--- (`bind CTRL-B BAGSOF_SORTING_TOGGLE`), holds it in its own binding table
--- (`C_KeyBindings.GetBindingIndex` = 287), and it survives `/reload` twice and a game restart. The
--- 2026-10-17 failure to survive `/reload` does not reproduce: in that session the line never
--- reached the bindings file, so the panel edit was never committed. The key lives in
--- `Enum.BindingSet.Account` (`GetCurrentBindingSet()` = 1), i.e. one key per account — the same
--- scope as `db.sv.global`.
--- This mirror is therefore insurance for that one measured case, not the mechanism: whatever the
--- client has at login becomes our stored value, and only when the client has nothing do we put ours
--- back. In both measured runs the client held the key, so `SetBinding` never ran.
--- shortcut: one key per action; the panel's second key slot is not mirrored. `/bos test 7` prints
--- both sides.
function keybinds.Restore()
  -- GetBindingKey, not GetBinding: on this client GetBinding takes a binding INDEX and errors on a
  -- string (measured 2026-10-19 — it is what made /bos test 7 die after its first line).
  local key = GetBindingKey(ACTION)
  if key and key ~= '' then
    stored()[ACTION] = key
    return
  end
  local saved = stored()[ACTION]
  if saved then
    SetBinding(saved, ACTION)
  end
end

--- `UPDATE_BINDINGS` covers binds, rebinds and unbinds made in the client's panel; `PLAYER_LOGOUT`
--- records the state the session ends with. Both store what the client currently holds, so an
--- unbind is remembered instead of re-applied from an old value.
local function capture()
  local key = GetBindingKey(ACTION)
  stored()[ACTION] = (key and key ~= '') and key or nil
end

events.On('UPDATE_BINDINGS', capture)
events.On('PLAYER_LOGOUT', capture)

--- Bound by BAGSOF_SORTING_TOGGLE in Bindings.xml.
---@diagnostic disable-next-line: lowercase-global
function BagsOfSorting_Toggle()
  addon:GetModule('Init').Toggle()
end

return keybinds
