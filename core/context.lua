-- A refresh runs inside a Context (BetterBags pattern): a burst of BAG_UPDATE events or a
-- late ITEM_DATA_LOAD_RESULT must not let an old chunked refresh paint over a newer one.
-- Creating a context invalidates every older one; async work checks IsStale.

local _, addon = ...

---@class Context: BoSModule
local context = addon:NewModule('Context')

---@class BoSContext
---@field reason string
---@field generation number
---@field started number
---@field phases table<string, number>
local current

local generation = 0

---@param reason string
---@return BoSContext
function context.New(reason)
  generation = generation + 1
  current = {
    reason = reason,
    generation = generation,
    started = GetTime(),
    phases = {},
    requestsIssued = 0,
  }
  return current
end

---@return BoSContext?
function context.Current()
  return current
end

---@param ctx BoSContext
---@return boolean
function context.IsStale(ctx)
  return ctx.generation ~= generation
end

--- Phase timing for `/bos perf` (AC-100/101: numbers recorded, not asserted).
---@param ctx BoSContext
---@param phase string
function context.MarkPhase(ctx, phase)
  ctx.phases[phase] = (GetTime() - ctx.started) * 1000
end

---@param ctx BoSContext
---@return string
function context.Format(ctx)
  local parts = { string.format('refresh(%s) total=%.1fms', ctx.reason, (GetTime() - ctx.started) * 1000) }
  local order = { 'harvest', 'enrich', 'classify', 'assign', 'sort', 'flow', 'render' }
  local last = 0
  for _, phase in ipairs(order) do
    local t = ctx.phases[phase]
    if t then
      parts[#parts + 1] = string.format('%s=%.1f', phase, t - last)
      last = t
    end
  end
  if ctx.requestsIssued > 0 then
    parts[#parts + 1] = string.format('tier3=%d', ctx.requestsIssued)
  end
  return table.concat(parts, ' ')
end

return context
