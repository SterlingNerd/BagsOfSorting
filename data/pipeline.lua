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

--- The free-slot count a section claims from the specialty bags its categories pair with
--- (issue #44). Two categories on one family count that bag once, and a family with no bag
--- equipped counts nothing — the AC's "hidden when no corresponding tradeskill bag is equipped".
--- A disabled category contributes nothing here either, exactly as it owns no items.
---@param names string[]
---@param side string  -- which half of the character the window draws: 'backpack' | 'bank'
---@return number free
---@return BoSFreeSlot? slot
local function sectionFreeSlots(names, side)
  local categories, seen = db.Categories(), {}
  local total, first = 0, nil
  for _, name in ipairs(names) do
    local category = categories[name]
    local family = category and category.enabled ~= false and category.bagFamily
    if family and not seen[family] then
      seen[family] = true
      total = total + harvest.FreeSlotsForFamily(family, side)
      first = first or harvest.FirstFreeSlotForFamily(family, side)
    end
  end
  return total, first
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
  local counted = false

  for _, config in ipairs(db.Windows()) do
    -- config.hidden is the window's own X: closed windows are not in the model at all, which
    -- is what keeps windows.Prune from reopening them on the next refresh.
    -- A bank window is in the model only while the bank is open (issue #47, AC-13): the harvest
    -- drops containers 6..14 on BANKFRAME_CLOSED, so past that a bank window is a frame around
    -- nothing.
    local isBank = config.kind == 'bank'
    if not config.hidden and (not isBank or harvest.BankOpen()) then
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
          -- Issue #47: a window draws its own side of the character. The harvest is one flat list and
          -- the classifier does not know about containers, so without this the default backpack
          -- window's catch-all claims the bank's items and the bank windows draw the leftovers
          -- (AC-13: "no backpack window leaks bank contents").
          for _, categoryName in ipairs(names) do
            local category = db.Categories()[categoryName]
            for _, item in ipairs(placements[categoryName] or {}) do
              if (item.containerKind == 'bank') == isBank
                and (not placed[item] or (category and category.duplicate)) then
                placed[item] = true
                items[#items + 1] = item
              end
            end
          end
          -- Issue #44: the section's own count comes from the bag its category pairs with, and a
          -- bag with free slots keeps its section on screen even when the category holds nothing —
          -- the cell is the drop target, and a hidden section hides it (`/bos test 44d`). The
          -- whole-bag-set number stays on the default backpack window (#36).
          local free, slot = sectionFreeSlots(names, config.kind)
          if #items > 0 or free > 0 then
            local section = {
              id = sectionConfig.id,
              name = sectionConfig.name,
              categories = names,
              items = items,
            }
            if free > 0 then
              section.emptySlots = free
              section.emptySlot = slot
            end
            window.sections[#window.sections + 1] = section
          end
        end
      end

      -- Issue #36 and #42: the bag-level chrome — the free-slot count and the money bar — belongs
      -- to one window: the first **backpack** window in screen order, which is the default Backpack
      -- window. The same number on all five would read as five sets of bags, and a coin row on
      -- each as five purses; on a bank window both numbers are the wrong player's (issue #47). When
      -- that window is closed the chrome travels with it.
      -- shortcut: which window carries it is a rule, not a setting. The setting is docs/04's
      -- `showEmptySlots`, and it arrives with the pane that edits it (docs/05).
      if not counted and not isBank then
        counted = true
        window.showMoney = true
        local free = harvest.FreeSlots('backpack')
        if free > 0 then
          window.emptySlots = free
          window.emptySlot = harvest.FirstFreeSlot()
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
