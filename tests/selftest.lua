-- `/bos selftest` (FR-106): fixture items x rule trees -> expected category.
-- Runs in-game and headless (tests/run.lua), because phases 1-7 never touch a frame.

local _, addon = ...

---@class SelfTest: BoSModule
local selftest = addon:NewModule('SelfTest')

---@class BoSTestState
---@field checks number
---@field failures string[]

local function newState()
  return { checks = 0, failures = {} }
end

local function check(state, desc, got, want)
  state.checks = state.checks + 1
  if got ~= want then
    state.failures[#state.failures + 1] = string.format('%s: got %s, want %s',
      desc, tostring(got), tostring(want))
  end
end

local function ownerOf(items, itemID)
  local item = addon:GetModule('Fixtures').Find(items, itemID)
  return item and item.owner or nil
end

local function catchall()
  return {
    priority = 999, kind = 'rules', enabled = true,
    rules = { op = 'all', children = { { field = 'none', cmp = '=', value = true } } },
  }
end

--- The AC-20 shape: any of type, quality floor, EXCEPT a name.
local GEAR = {
  op = 'all',
  children = {
    { op = 'any', children = {
      { field = 'type', cmp = '=', value = 'Armor' },
      { field = 'type', cmp = '=', value = 'Weapon' },
    } },
    { field = 'quality', cmp = '>=', value = 3 },
    { op = 'none', children = { { field = 'name', cmp = 'contains', value = 'Frayed' } } },
  },
}

local function baseCategories()
  return {
    ['Junk'] = { priority = 10, kind = 'rules', enabled = true,
      rules = { op = 'all', children = { { field = 'quality', cmp = '=', value = 0 } } } },
    ['Quests'] = { priority = 15, kind = 'rules', enabled = true,
      rules = { op = 'all', children = { { field = 'isQuestItem', cmp = '=', value = true } } } },
    ['Good Gear'] = { priority = 20, kind = 'rules', enabled = true, rules = GEAR },
    ['Linens'] = { priority = 30, kind = 'manual', enabled = true, itemIDs = { [26042] = true } },
    ['__catchall'] = catchall(),
  }
end

---@param state BoSTestState
local function testOwnership(state)
  local classify = addon:GetModule('Classify')
  local fixtures = addon:GetModule('Fixtures')
  local items = fixtures.Clone()
  classify.Run(items, baseCategories())

  check(state, 'grey armour is junk', ownerOf(items, 1001), 'Junk')
  check(state, 'epic weapon is gear', ownerOf(items, 1002), 'Good Gear')
  check(state, 'EXCEPT row excludes the item', ownerOf(items, 1003), '__catchall')
  check(state, 'manual ID list owns its ID', ownerOf(items, 26042), 'Linens')
  check(state, 'quest item wins its category', ownerOf(items, 1004), 'Quests')
  check(state, 'unmatched item lands in catch-all', ownerOf(items, 1006), '__catchall')
  check(state, 'item with no data lands in catch-all (FR-103)', ownerOf(items, 1005), '__catchall')

  -- FR-27: the trace names what was tested and what matched.
  local item = fixtures.Find(items, 1002)
  check(state, 'trace records the owner', item and item.trace.matched, 'Good Gear')
  check(state, 'trace records a rejected category', item and item.trace.tested[1], 'Junk')
end

---@param state BoSTestState
local function testPrecedence(state)
  local classify = addon:GetModule('Classify')
  local fixtures = addon:GetModule('Fixtures')

  -- AC-23 shape: two categories match the same epic sword; the lower number owns it.
  local categories = baseCategories()
  categories['Also Gear'] = { priority = 25, kind = 'rules', enabled = true,
    rules = { op = 'all', children = { { field = 'type', cmp = '=', value = 'Weapon' } } } }

  local items = fixtures.Clone()
  classify.Run(items, categories)
  check(state, 'priority 20 beats priority 25', ownerOf(items, 1002), 'Good Gear')

  categories['Good Gear'].priority = 30
  items = fixtures.Clone()
  classify.Run(items, categories)
  check(state, 'moving priority 20->30 hands the item to the other category', ownerOf(items, 1002), 'Also Gear')

  -- Tie-break is priority then name (docs/04 §Precedence 1).
  categories['Good Gear'].priority = 20
  categories['Also Gear'].priority = 20
  items = fixtures.Clone()
  classify.Run(items, categories)
  check(state, 'equal priority breaks by name', ownerOf(items, 1002), 'Also Gear')

  -- duplicate = true adds a placement without consuming ownership (docs/04 §Precedence 3).
  categories = baseCategories()
  categories['Shown Twice'] = { priority = 50, kind = 'rules', enabled = true, duplicate = true,
    rules = { op = 'all', children = { { field = 'quality', cmp = '>=', value = 2 } } } }
  items = fixtures.Clone()
  local placements = classify.Run(items, categories)
  check(state, 'duplicate category gets its own placement list', #(placements['Shown Twice'] or {}), 3)
  check(state, 'duplicate category does not steal ownership', ownerOf(items, 1002), 'Good Gear')
end

---@param state BoSTestState
local function testItemIDLeaf(state)
  -- FR-24: `itemID in {…}` is a leaf inside a tree, so "Tradeskill EXCEPT these IDs" is one rule.
  local classify = addon:GetModule('Classify')
  local fixtures = addon:GetModule('Fixtures')
  local categories = baseCategories()
  categories['Tradeskill (not glyphs)'] = { priority = 5, kind = 'rules', enabled = true,
    rules = { op = 'all', children = {
      { field = 'type', cmp = '=', value = 'Tradeskill' },
      { op = 'none', children = { { field = 'itemID', cmp = 'in', value = { [26042] = true } } } },
    } } }

  local items = fixtures.Clone()
  classify.Run(items, categories)
  check(state, 'itemID leaf excludes the listed ID', ownerOf(items, 26042), 'Linens')
  check(state, 'itemID leaf keeps the unlisted ID', ownerOf(items, 1006), 'Tradeskill (not glyphs)')
end

---@param state BoSTestState
local function testRules(state)
  local rules = addon:GetModule('Rules')
  local fixtures = addon:GetModule('Fixtures')

  check(state, 'sentence renders the tree as one line', rules.Sentence(GEAR),
    '(type = "Armor" or type = "Weapon") and quality ≥ Rare except name contains "Frayed"')

  local ok, err = rules.Validate(GEAR)
  check(state, 'AC-20 tree validates', ok, true)
  if not ok then state.failures[#state.failures + 1] = 'AC-20 tree rejected: ' .. tostring(err) end

  ok = rules.Validate({ op = 'all', children = { { op = 'any', children = { { op = 'all',
    children = { { field = 'type', cmp = '=', value = 'Armor' } } } } } } })
  check(state, 'nesting deeper than 2 is refused', ok, false)

  ok = rules.Validate({ op = 'all', children = { { field = 'nope', cmp = '=', value = 1 } } })
  check(state, 'unknown field is refused', ok, false)

  ok = rules.Validate({ op = 'all', children = { { field = 'isQuestItem', cmp = '>=', value = 1 } } })
  check(state, 'cmp the field does not allow is refused', ok, false)

  ok = rules.Validate({ op = 'any', children = {} })
  check(state, 'empty group is refused', ok, false)

  -- The leaf that blocked a `none` group is the one worth naming (FR-27).
  local blocked = addon:GetModule('Fixtures').Find(fixtures.Clone(), 1003)
  local matched, decidedBy = rules.Evaluate(GEAR, blocked)
  check(state, 'gear tree does not match the excluded item', matched, false)
  check(state, 'EXCEPT names the leaf that blocked it',
    decidedBy and rules.Sentence(decidedBy), 'name contains "Frayed"')

  matched = rules.Evaluate({ op = 'all', children = { { field = 'name', cmp = 'contains', value = 'frayed' } } }, blocked)
  check(state, 'string comparisons are case-insensitive (FR-22)', matched, true)

  matched = rules.Evaluate({ op = 'all', children = { { field = 'quality', cmp = '>=', value = 3 } } }, blocked)
  check(state, 'quality >= 3 matches epic', matched, true)
end

--- Run everything and return (checks, failures).
---@return number checks
---@return string[] failures
function selftest.Run()
  local state = newState()

  testOwnership(state)
  testPrecedence(state)
  testItemIDLeaf(state)
  testRules(state)

  return state.checks, state.failures
end

---@return string[]
function selftest.Report()
  local checks, failures = selftest.Run()
  local lines = {}
  for _, failure in ipairs(failures) do
    lines[#lines + 1] = '|cffff5555FAIL|r ' .. failure
  end
  lines[#lines + 1] = string.format('selftest: %d checks, %d failures', checks, #failures)
  return lines
end

return selftest
