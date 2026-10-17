-- Chunked work across frames (FR-102: a refresh cannot lock the UI thread).
-- Jobs are {ctx, items, fn}; the driver runs a fixed number of items per frame and stops
-- ticking entirely when the queue is empty, so an idle addon has no OnUpdate cost.

local _, addon = ...

---@class Async: BoSModule
local async = addon:NewModule('Async')

local constants = addon:GetModule('Constants')
local context = addon:GetModule('Context')

---@class BoSJob
---@field ctx BoSContext
---@field items any[]
---@field fn fun(item: any)
---@field i number

---@type BoSJob[]
local queue = {}
---@type function[]
local idleCallbacks = {}

local driver = CreateFrame('Frame', nil, UIParent)
driver:Hide()

local function FinishJob(job)
  if job.done then return end
  job.done = true
  job.items = nil
end

local function FlushIdle()
  local callbacks = idleCallbacks
  idleCallbacks = {}
  for i = 1, #callbacks do callbacks[i]() end
end

local function Tick()
  local budget = constants.ASYNC_ITEMS_PER_FRAME
  while budget > 0 and #queue > 0 do
    local job = queue[1]
    if context.IsStale(job.ctx) then
      -- A newer refresh superseded this one; drop it rather than paint stale data.
      FinishJob(job)
      table.remove(queue, 1)
    else
      local remaining = #job.items - job.i
      local take = math.min(budget, remaining)
      for _ = 1, take do
        job.i = job.i + 1
        job.fn(job.items[job.i])
      end
      budget = budget - take
      if job.i >= #job.items then
        FinishJob(job)
        table.remove(queue, 1)
      end
    end
  end

  if #queue == 0 then
    driver:Hide()
    FlushIdle()
  end
end

driver:SetScript('OnUpdate', Tick)

--- Enqueue work over `items`. Runs to completion across frames.
---@param ctx BoSContext
---@param items any[]
---@param fn fun(item: any)
function async.Batch(ctx, items, fn)
  queue[#queue + 1] = { ctx = ctx, items = items, fn = fn, i = 0 }
  driver:Show()
end

--- Runs when the queue drains. Callbacks added while draining run on the next drain.
---@param fn function
function async.OnIdle(fn)
  idleCallbacks[#idleCallbacks + 1] = fn
end

---@return number
function async.Queued()
  return #queue
end

return async
