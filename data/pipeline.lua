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
  local counted = {}

  for _, config in ipairs(db.Windows()) do
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

      -- Equipment windows (w11 backpack, w12 bank): dynamically create one section per equipment set category
      local isEquipmentWindow = config.id == 'w11' or config.id == 'w12'
      local sectionConfigs = config.sections or {}
      if isEquipmentWindow then
        local cats = db.Categories()
        local equipmentCats = {}
        for name, cat in pairs(cats) do
          if name:match('^Equipment%.') then
            equipmentCats[#equipmentCats + 1] = { name = name, cat = cat }
          end
        end
        table.sort(equipmentCats, function(a, b) return a.name < b.name end)
        local newSectionConfigs = {}
        for i, ec in ipairs(equipmentCats) do
          local setName = ec.name:match('^Equipment%.(.+)$') or ec.name
          newSectionConfigs[#newSectionConfigs + 1] = {
            id = 's_eq_' .. ec.name:gsub('[^%w]', '_'),
            name = setName,
            categories = { ec.name },
            collapsed = false,
          }
        end
        config.sections = newSectionConfigs
      end

      -- For equipment windows: pre-collect equipment items so they appear in all matching sets
      local equipmentItemSets = {}
      if isEquipmentWindow then
        local cats = db.Categories()
        for catName, cat in pairs(cats) do
          if catName:match('^Equipment%.') and cat.itemIDs then
            for _, item in ipairs(harvest.Items()) do
              if (item.containerKind == 'bank') == isBank
                and cat.itemIDs[item.itemID] then
                local sets = equipmentItemSets[item]
                if not sets then sets = {} equipmentItemSets[item] = sets end
                sets[#sets + 1] = catName
              end
            end
          end
        end
      end

      for _, sectionConfig in ipairs(config.sections or {}) do
        if not sectionConfig.hidden then
          local names = pipeline.ResolveBindings(sectionConfig.categories)
          local items = {}
          if isEquipmentWindow then
            local catName = names[1]
            for item, sets in pairs(equipmentItemSets) do
              for _, s in ipairs(sets) do
                if s == catName then
                  items[#items + 1] = item
                  placed[item] = true
                  break
                end
              end
            end
          else
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
          end
          local free, slot = sectionFreeSlots(names, config.kind)
          local hasEmptyCategory = false
          for _, categoryName in ipairs(names) do
            local cat = db.Categories()[categoryName]
            if cat and cat._showEmpty then hasEmptyCategory = true break end
          end
          local showSection = isEquipmentWindow and (#items > 0) or (#items > 0 or free > 0 or hasEmptyCategory)
          if showSection then
            local section = { id = sectionConfig.id, name = sectionConfig.name, categories = names, items = items, collapsed = sectionConfig.collapsed or false }
            if free > 0 then section.emptySlots = free; section.emptySlot = slot end
            window.sections[#window.sections + 1] = section
          end
        end
      end

      local side = isBank and 'bank' or 'backpack'
      if not counted[side] then
        counted[side] = true
        if not isBank then window.showMoney = true end
        local free = harvest.FreeSlots(side)
        if free > 0 then window.emptySlots = free; window.emptySlot = harvest.FirstFreeSlot(side) end
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
  addon:GetModule('Equipment').DistributeMultiSetItems()
  local models, shown = pipeline.Assign(placements)
  context.MarkPhase(ctx, 'assign')
  local itemSort = db.Settings().sorting.item
  for _, window in ipairs(models) do
    for _, section in ipairs(window.sections) do sortmod.Items(section.items, itemSort) end
  end
  context.MarkPhase(ctx, 'sort')
  for _, window in ipairs(models) do addon:GetModule('Flow').Layout(window) end
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
  local function enrichOne(item) enrich.Enrich(item); enrich.RequestMissing(ctx, item) end
  if #items > constants.ASYNC_ITEM_THRESHOLD then
    async.Batch(ctx, items, enrichOne)
    async.OnIdle(function() if context.IsStale(ctx) then return end; pipeline.Finish(ctx, items) end)
  else
    for i = 1, #items do enrichOne(items[i]) end
    pipeline.Finish(ctx, items)
  end
end

function pipeline.Model() return model end
function pipeline.Visible() return visible end
function pipeline.Last() return last end
return pipeline