-- Phase 3: for each item, walk the categories in priority order and record why each one won
-- or lost. The trace is per-harvest only and is what makes "why is this here?" a reading
-- task instead of a debugging task (FR-27).

local _, addon = ...

---@class Classify: BoSModule
local classify = addon:NewModule('Classify')

local rules = addon:GetModule('Rules')
local log = addon:GetModule('Log')

---@class BoSCategory
---@field priority number
---@field kind string        -- 'rules' | 'manual' | 'dynamic'
---@field rules BoSRule?
---@field itemIDs table<number, boolean>?
---@field enabled boolean?

---@class BoSCategoryEntry
---@field name string
---@field cat BoSCategory
---@field tree BoSRule

---@class BoSTrace
---@field tested string[]
---@field matched string?
---@field matchedBy string?

--- A manual category is exactly one `all{ itemID in {…} }` tree: one concept, one editor,
--- one explanation in the inspector (docs/04).
---@param name string
---@param cat BoSCategory
---@return BoSRule?
local function treeFor(name, cat)
  if cat.kind == 'manual' then
    if not cat.itemIDs then return nil end
    return { op = 'all', children = { { field = 'itemID', cmp = 'in', value = cat.itemIDs } } }
  end
  if not cat.rules then
    log.Error('category', name, 'has no rules')
    return nil
  end
  local ok, err = rules.Validate(cat.rules)
  if not ok then
    -- FR-107: reported and disabled, never a silent false.
    log.Error('category', name, 'rule rejected:', err)
    return nil
  end
  return cat.rules
end

--- Categories walked in name order for determinism. Category priority no longer decides
--- ownership: priority is a section-level concept, and sections compete for an item in
--- pipeline.Assign (docs/04 §Precedence). `Unmatched Items` is always walked last so it stays
--- the fallback for items no category matched.
---@param categories table<string, BoSCategory>
---@return BoSCategoryEntry[]
function classify.Ordered(categories)
  local ordered = {}
  for name, cat in pairs(categories) do
    if cat.enabled ~= false then
      local tree = treeFor(name, cat)
      if tree then
        ordered[#ordered + 1] = { name = name, cat = cat, tree = tree }
      end
    end
  end
  table.sort(ordered, function(a, b)
    if a.name == 'Unmatched Items' then return false end
    if b.name == 'Unmatched Items' then return true end
    return a.name < b.name
  end)
  return ordered
end

local function place(placements, name, item)
  local list = placements[name]
  if not list then
    list = {}
    placements[name] = list
  end
  list[#list + 1] = item
end

--- Ownership is reported as the first matching category in classify order; it does not
--- decide where an item goes. Sections, ranked by section priority, compete for the item
--- in pipeline.Assign. Several categories in one section is a display grouping, never a
--- precedence rule (docs/04 §Precedence 7).
---
-- A category consumes ownership when it is bound to at least one non-duplicate section;
-- categories bound only to duplicate sections (or to none) add a placement without
-- consuming it, so `Unmatched Items` can still claim the item (docs/04 §Precedence 3).
---@param items BoSItem[]
---@param categories table<string, BoSCategory>
---@param consumesOwnership fun(name: string): boolean  -- true if the category claims ownership; defaults to always true
---@return table<string, BoSItem[]> placements
function classify.Run(items, categories, consumesOwnership)
  local ordered = classify.Ordered(categories)
  if not consumesOwnership then
    consumesOwnership = function() return true end
  end

  local placements = {}

  for _, item in ipairs(items) do
    item.owner = nil
    ---@type BoSTrace
    local trace = { tested = {} }

    -- Walk every category so an item is eligible for every one it matches. Sections,
    -- ranked by section priority, then compete for it in pipeline.Assign; a section flagged
    -- `duplicate` may claim an item another section already placed (docs/04 §Precedence 3).
    -- item.owner stays the first match of a category that consumes ownership, so the
    -- `none`/catch-all rule and the trace report a single owner; duplicate sections re-draw
    -- the item in pipeline.Assign.
    for _, entry in ipairs(ordered) do
      local ok, matched, decidedBy = pcall(rules.Evaluate, entry.tree, item)
      if not ok then
        log.Error('category', entry.name, 'errored during classify:', matched)
      elseif matched then
        if not trace.matched then
          trace.matched = entry.name
          trace.matchedBy = decidedBy and rules.Sentence(decidedBy) or nil
        end
        place(placements, entry.name, item)
        -- Only a category that consumes ownership sets item.owner; a category bound only to
        -- duplicate sections adds a placement without consuming it (docs/04 §Precedence 3).
        if consumesOwnership(entry.name) and not item.owner then item.owner = entry.name end
      else
        trace.tested[#trace.tested + 1] = entry.name
      end
    end

    item.trace = trace
  end

  return placements
end

return classify
