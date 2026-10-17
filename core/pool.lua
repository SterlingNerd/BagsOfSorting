-- Object pool (FR-42, AC-42: button count stays flat across open/close cycles).
-- Shape copied from BetterBags' Pool module, minus the Context parameter: our context is
-- global-per-refresh and the reset functions do not need it.

local _, addon = ...

---@class Pool: BoSModule
local pool = addon:NewModule('Pool')

---@class BoSPool
---@field createFn fun(): any
---@field resetFn fun(item: any)
---@field items any[]
---@field created number
local poolItem = {}

function poolItem:Acquire()
  if #self.items == 0 then
    self.created = self.created + 1
    return self.createFn()
  end
  return table.remove(self.items)
end

---@param item any
function poolItem:Release(item)
  for i = 1, #self.items do
    if self.items[i] == item then
      error('double free: object already in pool')
    end
  end
  self.resetFn(item)
  self.items[#self.items + 1] = item
end

---@param createFn fun(): any
---@param resetFn fun(item: any)
---@return BoSPool
function pool.Create(createFn, resetFn)
  return setmetatable({
    createFn = createFn,
    resetFn = resetFn,
    items = {},
    created = 0,
  }, { __index = poolItem })
end

--- `/bos perf` reports this so pool flatness is measured, not hoped (AC-42).
---@return string
function pool.Stats()
  local parts = {}
  for name, p in pairs(pool.pools or {}) do
    parts[#parts + 1] = string.format('%s: created=%d idle=%d', name, p.created, #p.items)
  end
  return table.concat(parts, ' | ')
end

---@param name string
---@param createFn fun(): any
---@param resetFn fun(item: any)
---@return BoSPool
function pool.Named(name, createFn, resetFn)
  pool.pools = pool.pools or {}
  local p = pool.Create(createFn, resetFn)
  pool.pools[name] = p
  return p
end

return pool
