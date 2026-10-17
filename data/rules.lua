-- Rule grammar + evaluator (docs/04 §Rule tree).
--
--   <group> = { op = 'any'|'all'|'none', children = { <group>|<leaf> } }
--   <leaf>  = { field, cmp, value }
--
-- A `none` group renders as EXCEPT, because in the measured configs NOT is used 320 times
-- against AND's 44 (docs/01) — "except" is the refinement users reach for.

local _, addon = ...

---@class Rules: BoSModule
local rules = addon:NewModule('Rules')

local constants = addon:GetModule('Constants')
local registry = addon:GetModule('FieldRegistry')
local log = addon:GetModule('Log')

---@class BoSRule
---@field op? string
---@field children? BoSRule[]
---@field field? string
---@field cmp? string
---@field value any

local OPS = { any = true, all = true, none = true }

local function lower(s)
  return string.lower(tostring(s))
end

local function equal(actual, expected)
  if type(actual) == 'string' and type(expected) == 'string' then
    return lower(actual) == lower(expected)
  end
  return actual == expected
end

--- FR-22 operators. String comparisons are case-insensitive.
local CMP = {
  ['='] = equal,
  ['!='] = function(a, b) return not equal(a, b) end,
  ['>='] = function(a, b) return type(a) == 'number' and a >= (tonumber(b) or 0) end,
  ['<='] = function(a, b) return type(a) == 'number' and a <= (tonumber(b) or math.huge) end,
  ['contains'] = function(a, b)
    return string.find(lower(a), lower(b), 1, true) ~= nil
  end,
  ['startsWith'] = function(a, b)
    return lower(a):sub(1, #lower(b)) == lower(b)
  end,
  -- `in` takes a set { [value] = true }; a bare value is accepted so a one-ID list works too.
  ['in'] = function(a, b)
    if type(b) == 'table' then return b[a] == true end
    return equal(a, b)
  end,
}

---@param rule BoSRule
---@return boolean
local function isGroup(rule)
  return rule.op ~= nil
end

--- Validate on load and on every command (docs/04). An unknown field or cmp is reported and
--- the rule disabled, never a silent false (FR-29, FR-107).
---@param tree BoSRule
---@param depth? number
---@return boolean ok
---@return string? error
function rules.Validate(tree, depth)
  depth = depth or 1
  if type(tree) ~= 'table' then return false, 'rule is not a table' end

  if not isGroup(tree) then
    local field = registry.Get(tree.field or '')
    if not field then return false, 'unknown field ' .. tostring(tree.field) end
    local allowed = false
    for _, cmp in ipairs(field.cmps) do
      if cmp == tree.cmp then allowed = true break end
    end
    if not allowed then
      return false, string.format('field %s does not allow %s', tostring(tree.field), tostring(tree.cmp))
    end
    return true
  end

  if not OPS[tree.op] then return false, 'unknown op ' .. tostring(tree.op) end
  if type(tree.children) ~= 'table' or #tree.children == 0 then
    return false, 'empty ' .. tree.op .. ' group matches nothing'
  end
  if depth > constants.MAX_RULE_DEPTH then
    return false, 'rule nesting exceeds ' .. constants.MAX_RULE_DEPTH .. ' levels'
  end
  for _, child in ipairs(tree.children) do
    local ok, err = rules.Validate(child, depth + 1)
    if not ok then return false, err end
  end
  return true
end

---@param leaf BoSRule
---@param item BoSItem
---@return boolean
local function evalLeaf(leaf, item)
  local field = registry.Get(leaf.field or '')
  if not field then return false end
  local fn = CMP[leaf.cmp or '']
  if not fn then return false end
  local actual = field.read(item)
  if actual == nil and leaf.cmp ~= '!=' then return false end
  return fn(actual, leaf.value) and true or false
end

--- Evaluate a tree. Returns the result and the leaf that decided it, which is what the
--- inspector names (FR-27).
---@param tree BoSRule
---@param item BoSItem
---@return boolean matched
---@return BoSRule? decidedBy
function rules.Evaluate(tree, item)
  if not isGroup(tree) then
    if evalLeaf(tree, item) then return true, tree end
    return false
  end

  if tree.op == 'all' then
    local last
    for _, child in ipairs(tree.children) do
      local matched, decidedBy = rules.Evaluate(child, item)
      -- A failed child carries its blocking leaf when it is a `none` group: that is the
      -- exclusion the inspector should name (FR-27).
      if not matched then return false, decidedBy end
      last = decidedBy or last
    end
    return true, last
  end

  if tree.op == 'any' then
    for _, child in ipairs(tree.children) do
      local matched, decidedBy = rules.Evaluate(child, item)
      if matched then return true, decidedBy end
    end
    return false
  end

  -- none: the group is true when no child matches; the child that would have matched is the
  -- one worth naming ("EXCEPT tooltip contains Bind on Equip").
  for _, child in ipairs(tree.children) do
    local matched, decidedBy = rules.Evaluate(child, item)
    if matched then return false, decidedBy end
  end
  return true
end

local nodeSentence

--- `none` children render as EXCEPT clauses hanging off the end of their parent, because
--- "A and B except C" is how a user reads a rule with exclusions (docs/04 §Rule tree).
local function groupSentence(group)
  local positive, except = {}, {}
  for _, child in ipairs(group.children) do
    if isGroup(child) and child.op == 'none' then
      except[#except + 1] = nodeSentence(child)
    else
      positive[#positive + 1] = nodeSentence(child)
    end
  end

  local text
  if group.op == 'any' then
    text = #positive > 1 and '(' .. table.concat(positive, ' or ') .. ')' or table.concat(positive, ' or ')
  elseif group.op == 'all' then
    text = table.concat(positive, ' and ')
  else
    local parts = {}
    for _, part in ipairs(except) do parts[#parts + 1] = part end
    for _, part in ipairs(positive) do parts[#parts + 1] = part end
    text = #parts > 1 and '(' .. table.concat(parts, ' or ') .. ')' or parts[1]
    return 'except ' .. text
  end

  if #except > 0 then
    local exclusions = table.concat(except, ' or ')
    text = #text > 0 and (text .. ' ' .. exclusions) or exclusions
  end
  return text
end

nodeSentence = function(node)
  if isGroup(node) then return groupSentence(node) end
  local field = registry.Get(node.field or '')
  if not field then return '?? ' .. tostring(node.field) end
  local ok, sentence = pcall(field.sentence, node)
  if not ok then
    log.Error('field sentence failed for', node.field)
    return tostring(node.field) .. ' ' .. tostring(node.cmp) .. ' ' .. tostring(node.value)
  end
  return sentence
end

--- One readable sentence for the whole tree (FR-20).
---@param tree BoSRule
---@return string
function rules.Sentence(tree)
  if type(tree) ~= 'table' then return 'no rules' end
  return nodeSentence(tree)
end

return rules
