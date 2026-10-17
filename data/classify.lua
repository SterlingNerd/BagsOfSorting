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
---@field duplicate boolean?
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

--- Categories sorted by priority ascending, then name for determinism (docs/04 §Precedence 1).
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
    local pa, pb = a.cat.priority or 100, b.cat.priority or 100
    if pa ~= pb then return pa < pb end
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

--- Ownership is decided globally by category priority. Several categories in one section is a
--- display grouping, never a precedence rule (docs/04 §Precedence 7).
---@param items BoSItem[]
---@param categories table<string, BoSCategory>
---@return table<string, BoSItem[]> placements
function classify.Run(items, categories)
  local ordered = classify.Ordered(categories)

  local anyDuplicate = false
  for _, entry in ipairs(ordered) do
    if entry.cat.duplicate then anyDuplicate = true break end
  end

  local placements = {}

  for _, item in ipairs(items) do
    item.owner = nil
    ---@type BoSTrace
    local trace = { tested = {} }

    for _, entry in ipairs(ordered) do
      local ok, matched, decidedBy = pcall(rules.Evaluate, entry.tree, item)
      if not ok then
        log.Error('category', entry.name, 'errored during classify:', matched)
      elseif matched then
        trace.matched = entry.name
        trace.matchedBy = decidedBy and rules.Sentence(decidedBy) or nil
        if entry.cat.duplicate then
          place(placements, entry.name, item)
        elseif not item.owner then
          item.owner = entry.name
          place(placements, entry.name, item)
        end
        if item.owner and not anyDuplicate then break end
      else
        trace.tested[#trace.tested + 1] = entry.name
      end
    end

    item.trace = trace
  end

  return placements
end

return classify
