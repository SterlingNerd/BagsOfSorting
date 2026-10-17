-- Diagnostics, gated by settings.debug (NFR-6: no bare print in shipped code).

local _, addon = ...

---@class Log: BoSModule
local log = addon:NewModule('Log')

log.debugEnabled = false

function log.SetDebug(on)
  log.debugEnabled = on and true or false
end

---@param ... any
function log.Debug(...)
  if not log.debugEnabled then return end
  print('|cff6699ff' .. addon.title .. '|r', ...)
end

--- Always reported: a rule that errored, a container we could not read, a bad import.
---@param ... any
function log.Error(...)
  print('|cffcc3333' .. addon.title .. '|r', ...)
end
