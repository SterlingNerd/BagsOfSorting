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

--- Capture the refresh's own total. `/bos perf` runs long after the refresh it reports, so
--- measuring at print time reports the time since the refresh started, not the refresh.
---@param ctx BoSContext
function context.Finish(ctx)
  ctx.totalMs = (GetTime() - ctx.started) * 1000
end

---@param ctx BoSContext
---@return string
function context.Format(ctx)
  -- No phase deltas and no total: GetTime is frame-quantized on Forever, and every phase plus the
  -- refresh total happens inside one frame, so each of them prints 0.00 and reads as a pass. A
  -- number that is always zero is worse than no number (issue #20). The figure AC-100/AC-101
  -- records is the across-frames one from `/bos test 13`; MarkPhase stays as the hook a
  -- cross-frame harness would use.
  local parts = { string.format(
    'refresh(%s) timings: unmeasurable in one frame (GetTime is frame-quantized) — /bos test 13 measures across frames',
    ctx.reason) }
  if ctx.requestsIssued > 0 then
    parts[#parts + 1] = string.format('tier3=%d', ctx.requestsIssued)
  end
  return table.concat(parts, ' ')
end

return context
