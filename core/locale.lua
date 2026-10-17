-- One locale table, key falls back to itself (NFR-5). enUS is the key source.

local _, addon = ...

---@type table<string,string>
local L = setmetatable({}, {
  __index = function(t, key)
    t[key] = key
    return key
  end,
})

addon.L = L

L['Everything else'] = 'Everything else'
L['Junk'] = 'Junk'
L['Armor'] = 'Armor'
L['Backpack'] = 'Backpack'
