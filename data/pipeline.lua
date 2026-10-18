-- The phase runner (docs/03 §The pipeline). Phases 1-7 are pure over data and never touch a
-- frame; the finished model is published as an event and frames/window renders it (NFR-4).

local _, addon = ...

---@class Pipeline: BoSModule
local pipeline = addon:NewModule('Pipeline')

local constants = addon:GetModule('Constants')
local context = addon:GetModule('Context')
local async = addon:GetModule('Async')
local events = addon:GetModule('Events')
local db = addon:GetModule('DB')
local harvest = addon:GetModule('Harvest')
local enrich = addon:GetModule('Enrich')
local classify = addon:GetModule('Classify')
local sortmod = addon:GetModule('Sort')
local log = addon:GetModule('Log')

---@type BoSWindowModel[]
local model
---@type table<string, boolean>
local visible
---@type BoSContext?
local last

--- A trailing `*` binds the whole dotted group (FR-11b). Resolved from names at classify
--- time, so adding a child category needs no re-binding.
---@param bindings string[]?
---@return string[]
function pipeline.ResolveBindings(bindings)
  local categories = db.Categories()
  local out, seen = {}, {}

  for _, binding in ipairs(bindings or {}) do
    if binding:sub(-1) == '*' then
      local prefix = binding:sub(1, -2)
      for name in pairs(categories) do
        if name:sub(1, #prefix) == prefix and not seen[name] then
          seen[name] = true
          out[#out + 1] = name
        end
      end
    elseif not seen[binding] then
      if not categories[binding] then
        log.Debug('section binds unknown category', binding)
      end
      seen[binding] = true
      out[#out + 1] = binding
    end
  end

  -- Inside one section the categories lay out in category-priority order (FR-11).
  table.sort(out, function(a, b)
    local ca, cb = categories[a], categories[b]
    local pa, pb = (ca and ca.priority) or 100, (cb and cb.priority) or 100
    if pa ~= pb then return pa < pb end
    return a < b
  end)
  return out
end

--- Phase 4: category -> section -> window, applying the duplicate policy (FR-15).
--- An item is drawn once unless its owning category opted into duplication.
---@param placements table<string, BoSItem[]>
---@return BoSWindowModel[] models
---@return table<string, boolean> visible
function pipeline.Assign(placements)
  local models = {}
  local shown = {}
  local placed = {}

  for _, config in ipairs(db.Windows()) do
    -- Bank windows are M5: the bank container index space is issue #9's answer, not ours.
    -- config.hidden is the window's own X: closed windows are not in the model at all, which
    -- is what keeps windows.Prune from reopening them on the next refresh.
    if config.kind == 'backpack' and not config.hidden then
      local window = {
        id = config.id,
        name = config.name,
        kind = config.kind,
        columns = config.columns or 5,
        scale = config.scale or 1,
        config = config,
        sections = {},
      }

      for _, sectionConfig in ipairs(config.sections or {}) do
        if not sectionConfig.hidden then
          local names = pipeline.ResolveBindings(sectionConfig.categories)
          local items = {}
          for _, categoryName in ipairs(names) do
            local category = db.Categories()[categoryName]
            for _, item in ipairs(placements[categoryName] or {}) do
              if not placed[item] or (category and category.duplicate) then
                placed[item] = true
                items[#items + 1] = item
              end
            end
          end
          if #items > 0 then
            window.sections[#window.sections + 1] = {
              id = sectionConfig.id,
              name = sectionConfig.name,
              categories = names,
              items = items,
            }
          end
        end
      end

      models[#models + 1] = window
      shown[config.id] = true
    end
  end

  return models, shown
end

--- Phases 3-7 for an already-enriched item list.
---@param ctx BoSContext
---@param items BoSItem[]
function pipeline.Finish(ctx, items)
  context.MarkPhase(ctx, 'enrich')

  local placements = classify.Run(items, db.Categories())
  context.MarkPhase(ctx, 'classify')

  local models, shown = pipeline.Assign(placements)
  context.MarkPhase(ctx, 'assign')

  local itemSort = db.Settings().sorting.item
  for _, window in ipairs(models) do
    for _, section in ipairs(window.sections) do
      sortmod.Items(section.items, itemSort)
    end
  end
  context.MarkPhase(ctx, 'sort')

  for _, window in ipairs(models) do
    -- Resolved here rather than at load: layout/ loads after data/ (docs/03 load order).
    addon:GetModule('Flow').Layout(window)
  end
  context.MarkPhase(ctx, 'flow')

  model, visible, last = models, shown, ctx
  events.Emit('BOS_REFRESH_DONE', models, shown, ctx)
end

--- Phases 1-2, then 3-7 either inline or chunked across frames (FR-100, FR-102).
---@param reason string
function pipeline.Refresh(reason)
  local ctx = context.New(reason)
  local items = harvest.Items()
  context.MarkPhase(ctx, 'harvest')

  local function enrichOne(item)
    enrich.Enrich(item)
    enrich.RequestMissing(ctx, item)
  end

  if #items > constants.ASYNC_ITEM_THRESHOLD then
    -- shortcut: only enrich is chunked. Classify is ~O(categories x items x leaves) of pure
    -- table reads and measures in single-digit ms; chunk it if /bos perf ever says otherwise.
    async.Batch(ctx, items, enrichOne)
    async.OnIdle(function()
      if context.IsStale(ctx) then return end
      pipeline.Finish(ctx, items)
    end)
  else
    for i = 1, #items do
      enrichOne(items[i])
    end
    pipeline.Finish(ctx, items)
  end
end

function pipeline.Model()
  return model
end

function pipeline.Visible()
  return visible
end

function pipeline.Last()
  return last
end

return pipeline
