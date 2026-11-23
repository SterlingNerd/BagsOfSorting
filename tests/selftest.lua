-- Headless assertions: `lua5.1 tests/run.lua` (CI runs them).
--
-- Not loaded by the addon. Phases 1-7 never touch a frame (docs/03, NFR-4), so the whole
-- classifier, sort and layout layer runs off the client against the stubs in run.lua.

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
    kind = 'rules', enabled = true,
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
    ['Junk'] = { kind = 'rules', enabled = true,
      rules = { op = 'all', children = { { field = 'quality', cmp = '=', value = 0 } } } },
    ['Quests'] = { kind = 'rules', enabled = true,
      rules = { op = 'all', children = { { field = 'isQuestItem', cmp = '=', value = true } } } },
    ['Good Gear'] = { kind = 'rules', enabled = true, rules = GEAR },
    ['Linens'] = { kind = 'manual', enabled = true, itemIDs = { [26042] = true } },
    ['Unmatched Items'] = catchall()
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
  check(state, 'EXCEPT row excludes the item', ownerOf(items, 1003), 'Unmatched Items')
  check(state, 'manual ID list owns its ID', ownerOf(items, 26042), 'Linens')
  check(state, 'quest item wins its category', ownerOf(items, 1004), 'Quests')
  check(state, 'unmatched item lands in catch-all', ownerOf(items, 1006), 'Unmatched Items')
  check(state, 'item with no data lands in catch-all (FR-103)', ownerOf(items, 1005), 'Unmatched Items')

  -- FR-27: the trace names what was tested and what matched.
  local item = fixtures.Find(items, 1002)
  check(state, 'trace records the owner', item and item.trace.matched, 'Good Gear')
  check(state, 'trace records a rejected category', item and item.trace.tested[1], 'Junk')
end

---@param state BoSTestState
local function testPrecedence(state)
  local classify = addon:GetModule('Classify')
  local fixtures = addon:GetModule('Fixtures')

  -- AC-23 moved to section level: priority is a section concept (docs/04 §Precedence),
  -- decided in pipeline.Assign. classify walks categories in name order, so the category
  -- priority field no longer decides which category owns an item.
  local categories = baseCategories()
  categories['Also Gear'] = { kind = 'rules', enabled = true,
    rules = { op = 'all', children = { { field = 'type', cmp = '=', value = 'Weapon' } } } }

  local items = fixtures.Clone()
  classify.Run(items, categories)
  -- Name order: 'Also Gear' < 'Good Gear', so Also Gear is the first match and the owner.
  check(state, 'owner is the first match in classify order', ownerOf(items, 1002), 'Also Gear')

  -- Flipping the priority field must not move ownership.
  categories['Also Gear'].priority = 1
  categories['Good Gear'].priority = 99
  items = fixtures.Clone()
  classify.Run(items, categories)
  check(state, 'category priority does not move ownership', ownerOf(items, 1002), 'Also Gear')

  -- duplicate = true adds a placement without consuming ownership (docs/04 §Precedence 3).
  -- Duplicate lives on the section; classify marks every matching category's placement and the
  -- first match is owner. pipeline.Assign decides whether the item is drawn twice.
  categories = baseCategories()
  categories['Shown Twice'] = { kind = 'rules', enabled = true,
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

--- FR-46: every sort mode, over the same twenty-one fixtures. 1005 has no name, quality, ilvl or
--- expansion, so the `or ''` / `or 0` guards in data/sort.lua decide where it lands.
---@param state BoSTestState
local function testSort(state)
  local sort = addon:GetModule('Sort')
  local fixtures = addon:GetModule('Fixtures')

  local ENDS = {
    nameThenQuality = { 1005, 5411 },
    qualityThenName = { 1003, 1001 },
    ilvl = { 1003, 1004 },
    expansion = { 1005, 26042 },
  }

  for mode, ends in pairs(ENDS) do
    local items = fixtures.Clone()
    sort.Items(items, mode)
    check(state, mode .. ' puts ' .. ends[1] .. ' first', items[1].itemID, ends[1])
    check(state, mode .. ' puts ' .. ends[2] .. ' last', items[#items].itemID, ends[2])
  end

  local items = fixtures.Clone()
  sort.Items(items, 'nope')
  check(state, 'unknown mode falls back to nameThenQuality', items[1].itemID, 1005)

  local empty = {}
  sort.Items(empty, 'ilvl')
  check(state, 'sorting an empty list is a no-op', #empty, 0)

  check(state, 'every mode is listed for the UI', table.concat(sort.Modes(), ','),
    'expansion,ilvl,nameThenQuality,qualityThenName')
end

--- FR-40 boundaries: a section narrower than its item count, and a window with nothing in it.
---@param state BoSTestState
local function testFlow(state)
  local flow = addon:GetModule('Flow')
  local constants = addon:GetModule('Constants')
  local CELL = constants.BUTTON_SIZE + constants.BUTTON_GAP

  local items = {}
  for i = 1, 5 do items[i] = { itemID = i } end
  local window = flow.Layout({ id = 'w', name = 'w', columns = 2, sections = { { items = items } } })
  check(state, '5 items in 2 columns is 2 wide', window.sections[1].cols, 2)
  check(state, '5 items in 2 columns wraps to 3 rows', window.sections[1].rows, 3)

  local empty = flow.Layout({ id = 'e', name = 'e', columns = 3, sections = { { items = {} } } })
  -- The one section flow is handed with nothing in it is the one pipeline.Assign kept alive on
  -- purpose (`_showEmpty`): a title band, the window's column budget wide, no body rows.
  check(state, 'a kept-but-empty section is a header band',
    empty.sections[1].cols .. '/' .. empty.sections[1].rows .. '/' .. empty.sections[1].height,
    '3/0/' .. constants.SECTION_TITLE_HEIGHT)
  check(state, 'an empty window is still its column grid wide', empty.width,
    3 * CELL + constants.WINDOW_PADDING * 2)
  -- Issue #43: with nothing in it a window draws no body, and its height is the chrome floor — the art
  -- `HeldBagLayout` draws is 95 px end to end and the client cannot shrink its bottom corners below 72.
  check(state, 'an empty window is floored at the chrome height, not a body cell', empty.height,
    constants.WINDOW_CHROME_HEIGHT)
  -- FR-48 (issue #32): the money bar sits 8 px in from the window's bottom edge and is 13 px
  -- tall, so the window that carries it has to be taller than its own padding or the bar covers
  -- the last row. Issue #42: only the window the model gave the bar to reserves that band.
  local one = { { items = { { itemID = 1 } } } }
  local body = constants.WINDOW_TITLE_HEIGHT + CELL
  local money = flow.Layout({ id = 'm', name = 'm', columns = 3, showMoney = true, sections = one })
  local plain = flow.Layout({ id = 'p', name = 'p', columns = 3, sections = one })
  check(state, 'the money window is one row tall plus the money band', money.height > body, true)
  check(state, 'the window bottom clears a 13 px money bar inset 8 px (FR-48)',
    money.height - body > 8 + 13, true)
  check(state, 'a window without the money bar does not reserve the band',
    money.height - plain.height, constants.MONEY_BAR_SPACE)
end

--- `/bos perf` says plainly that a single-frame refresh cannot be timed here, and still keeps the
--- captured total for a cross-frame harness (AC-100, issue #20).
---@param state BoSTestState
local function testContext(state)
  local context = addon:GetModule('Context')
  local ctx = context.New('test')
  context.MarkPhase(ctx, 'harvest')
  context.Finish(ctx)
  check(state, 'format says a single-frame refresh is untimed instead of printing 0.00',
    context.Format(ctx):match('unmeasurable in one frame') ~= nil, true)
  check(state, 'the refresh total is still captured', ctx.totalMs ~= nil, true)
  check(state, 'a phase is recorded', ctx.phases.harvest ~= nil, true)
end

--- Run everything and return (checks, failures).
---@return number checks
---@return string[] failures
--- pipeline.ResolveBindings: wildcard expansion, `!` excludes, dedup, case canonicalization.
---@param state BoSTestState
local function testResolveBindings(state)
  local pipeline = addon:GetModule('Pipeline')
  local db = addon:GetModule('DB')
  db.Initialize()

  local origCats = db.Profile().categories
  db.Profile().categories = {
    ['Armor'] = { kind = 'rules', enabled = true },
    ['Equipment.Heals'] = { kind = 'rules', enabled = true },
    ['Equipment.Herbalism'] = { kind = 'rules', enabled = true },
    ['Equipment.Tank'] = { kind = 'rules', enabled = true },
    ['Consumables.Potions'] = { kind = 'rules', enabled = true },
    ['Consumables.Food'] = { kind = 'rules', enabled = true },
    ['Unmatched Items'] = { kind = 'rules', enabled = true },
  }

  -- Wildcard include expands to all prefixed categories
  local inc, exc = pipeline.ResolveBindings({ 'Equipment.*' })
  check(state, 'include wildcard expands to all prefixed categories', #inc, 3)
  check(state, 'include wildcard has no excludes', #exc, 0)

  -- Wildcard exclude
  inc, exc = pipeline.ResolveBindings({ '!Equipment.*' })
  check(state, 'exclude wildcard has no includes', #inc, 0)
  check(state, 'exclude wildcard expands to all prefixed categories', #exc, 3)

  -- Case canonicalization: lowercase wildcard matches same categories
  inc, exc = pipeline.ResolveBindings({ '!equipment.*' })
  check(state, 'lowercase exclude wildcard expands same', #exc, 3)

  -- Mixed include + exclude
  inc, exc = pipeline.ResolveBindings({ 'Armor', '!Equipment.*' })
  check(state, 'include Armor only', #inc, 1)
  check(state, 'include Armor is Armor', inc[1], 'Armor')
  check(state, 'exclude expands all Equipment categories', #exc, 3)

  -- Exact-match dedup
  inc, exc = pipeline.ResolveBindings({ 'Armor', 'Armor' })
  check(state, 'duplicate include deduped', #inc, 1)

  -- Case-variant wildcard dedup: !equipment.* and !Equipment.* are the same binding
  inc, exc = pipeline.ResolveBindings({ '!equipment.*', '!Equipment.*' })
  check(state, 'case-variant wildcard deduped', #exc, 3)

  -- Unknown category produces nothing
  inc, exc = pipeline.ResolveBindings({ 'NoSuchCategory' })
  check(state, 'unknown category produces no include', #inc, 0)
  check(state, 'unknown category produces no exclude', #exc, 0)

  db.Profile().categories = origCats
end

--- pipeline.Assign: item-level exclusion. `!Equipment.*` keeps items matching any
--- Equipment.* category out of a section even if they also match an included category.
---@param state BoSTestState
local function testAssignItemExclusion(state)
  local pipeline = addon:GetModule('Pipeline')
  local classify = addon:GetModule('Classify')
  local fixtures = addon:GetModule('Fixtures')
  local db = addon:GetModule('DB')
  db.Initialize()

  local origCats = db.Profile().categories
  db.Profile().categories = {
    ['Armor'] = { kind = 'rules', enabled = true,
      rules = { op = 'all', children = { { field = 'type', cmp = '=', value = 'Armor' } } } },
    ['Equipment.Heals'] = { kind = 'rules', enabled = true,
      rules = { op = 'all', children = { { field = 'subtype', cmp = '=', value = 'Cloth' } } } },
    ['Unmatched Items'] = { kind = 'rules', enabled = true,
      rules = { op = 'all', children = { { field = 'none', cmp = '=', value = true } } } },
  }

  local origWins = db.Profile().windows
  db.Profile().windows = {
    {
      id = 'w1', name = 'Backpack', kind = 'backpack', columns = 5,
      sections = {
        { id = 's1', name = 'Armor No Heals', categories = { 'Armor', '!Equipment.*' }, priority = 0 },
        { id = 's2', name = 'Catchall', categories = { 'Unmatched Items' }, priority = 0 },
      },
    },
  }

  local items = fixtures.Clone()
  local placements = classify.Run(items, db.Profile().categories)

  -- 1001 Rusty Chainmail: Armor + Mail → matches Armor only
  -- 1003 Frayed Vestments: Armor + Cloth → matches Armor AND Equipment.Heals
  -- 5411 Winterhoof Cleansing Totem: Armor + Miscellaneous → matches Armor only
  -- 1007 Cracked Greaves: Armor + Mail → matches Armor only
  check(state, '4 items match Armor', #(placements['Armor'] or {}), 4)
  check(state, '3 items match Equipment.Heals', #(placements['Equipment.Heals'] or {}), 3)

  local models = pipeline.Assign(placements)

  -- Find the Armor No Heals section
  local window = models[1]
  local section
  for _, s in ipairs(window.sections) do
    if s.name == 'Armor No Heals' then section = s break end
  end
  check(state, 'Armor No Heals section found', section ~= nil, true)

  if section then
    -- 1001, 5411, 1007 (Armor only, not Cloth) should be in the section
    -- 1003 matches both Armor and Equipment.Heals; !Equipment.* excludes it
    local has1001, has5411, has1007, has1003 = false, false, false, false
    for _, item in ipairs(section.items) do
      if item.itemID == 1001 then has1001 = true end
      if item.itemID == 5411 then has5411 = true end
      if item.itemID == 1007 then has1007 = true end
      if item.itemID == 1003 then has1003 = true end
    end
    check(state, '1001 (Armor only) in section', has1001, true)
    check(state, '5411 (Armor only) in section', has5411, true)
    check(state, '1007 (Armor only) in section', has1007, true)
    -- 1003 matches both Armor and Equipment.Heals; !Equipment.* excludes it
    check(state, '1003 (Armor + Cloth) excluded by !Equipment.*', has1003, false)
  end

  db.Profile().categories = origCats
  db.Profile().windows = origWins
end

function selftest.Run()
  local state = newState()

  testOwnership(state)
  testPrecedence(state)
  testItemIDLeaf(state)
  testRules(state)
  testSort(state)
  testFlow(state)
  testContext(state)
  testResolveBindings(state)
  testAssignItemExclusion(state)

  return state.checks, state.failures
end

return selftest
