-- One owned frame plus a dispatch table (docs/03: replaces AceEvent, and never touches a
-- protected frame). Also carries our own internal events, which is how data tells frames
-- that the model changed without data ever touching a frame (NFR-4).

local _, addon = ...

---@class Events: BoSModule
local events = addon:NewModule('Events')

events.frame = CreateFrame('Frame')

---@type table<string, {fn: function}[]>
local handlers = {}
---@type table<string, boolean>
local registered = {}

-- Internal event names are prefixed so they are never RegisterEvent'd on the game frame.
local INTERNAL_PREFIX = 'BOS_'

local function isGameEvent(name)
  return name:sub(1, #INTERNAL_PREFIX) ~= INTERNAL_PREFIX
end

---@param name string
---@param fn function
function events.On(name, fn)
  local list = handlers[name]
  if not list then
    list = {}
    handlers[name] = list
  end
  list[#list + 1] = { fn = fn }
  if isGameEvent(name) and not registered[name] then
    registered[name] = true
    events.frame:RegisterEvent(name)
  end
end

---@param name string
---@param fn function
function events.Off(name, fn)
  local list = handlers[name]
  if not list then return end
  for i = #list, 1, -1 do
    if list[i].fn == fn then
      table.remove(list, i)
    end
  end
end

--- Emit to subscribers. Game events arrive through the frame below and use the same path,
--- so there is one dispatch implementation.
---@param name string
---@param ... any
function events.Emit(name, ...)
  local list = handlers[name]
  if not list then return end
  for i = 1, #list do
    list[i].fn(...)
  end
end

events.frame:SetScript('OnEvent', function(_, event, ...)
  events.Emit(event, ...)
end)

--- Coalesce a burst of events into one call (docs/03: events:BucketEvent('BAG_UPDATE', 0.2)).
---@param name string
---@param duration number
---@param fn function
function events.Bucket(name, duration, fn)
  local args, count, scheduled
  events.On(name, function(...)
    args, count = { ... }, select('#', ...)
    if scheduled then return end
    scheduled = true
    C_Timer.After(duration, function()
      scheduled = nil
      if args then
        local pending, n = args, count
        args, count = nil, nil
        fn(unpack(pending, 1, n))
      end
    end)
  end)
end

return events
