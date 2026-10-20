-- Headless pipeline test: `lua5.1 tests/run.lua`. The addon does not load tests/, so this is
-- the only test path.
--
-- Phases 1-7 are pure functions over data and never touch a frame (docs/03), so harvest,
-- enrich, classify, assign, sort and flow can be run off the client against a stubbed
-- container API. This proves the classifier and the pipeline wiring. It proves nothing about
-- the Forever API surface — the in-game checklist in docs/06 and the spike issues do that
-- (agents.md hard rule 1).

_G.NUM_BAG_SLOTS = 4
_G.NUM_REAGENTBAG_SLOTS = 1
_G.NUM_TOTAL_EQUIPPED_BAG_SLOTS = 5
_G.KEYRING_CONTAINER = -1

-- Minimal stand-ins for the two things the pure modules touch at load time: a frame object
-- for core/events + core/async, and Enum.ItemQuality for filters/fields.
_G.CreateFrame = function()
  return setmetatable({}, { __index = function() return function() end end })
end
_G.UIParent = {}
_G.GetTime = os.clock
-- The capture stamp (core/diag.lua) reads these; the harness answers them so a captured step can
-- run headless.
_G.GetBuildInfo = function() return '1.16.0', 1, 'x86_64' end
_G.UnitName = function() return 'Tester' end
_G.GetRealmName = function() return 'Test Realm' end
_G.Enum = {
  ItemQuality = {
    Poor = 0, Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5, Artifact = 6, Heirloom = 7,
  },
}

local ORDER = {
  'core/boot.lua',
  'core/log.lua',
  'core/client.lua',
  'core/constants.lua',
  'core/locale.lua',
  'core/events.lua',
  'core/context.lua',
  'core/async.lua',
  'core/pool.lua',
  'core/db.lua',
  'filters/registry.lua',
  'filters/fields.lua',
  'data/harvest.lua',
  'data/itemcache.lua',
  'data/enrich.lua',
  'data/rules.lua',
  'data/classify.lua',
  'data/sort.lua',
  'data/pipeline.lua',
  'layout/flow.lua',
  'layout/anchors.lua',
  'config/keybinds.lua',
  'core/diag.lua',
  'tests/fixtures.lua',
  'tests/selftest.lua',
}

local addon = {}
for _, path in ipairs(ORDER) do
  local chunk, err = loadfile(path)
  if not chunk then
    print('LOAD ERROR ' .. path .. ': ' .. tostring(err))
    os.exit(2)
  end
  chunk('BagsOfSorting', addon)
end

local checks, failures = addon.modules['SelfTest'].Run()

local function check(desc, got, want)
  checks = checks + 1
  if got ~= want then
    failures[#failures + 1] = string.format('%s: got %s, want %s', desc, tostring(got), tostring(want))
  end
end

-- ---------------------------------------------------------------------------
-- End-to-end pipeline over a stubbed container API.
-- ---------------------------------------------------------------------------

local fixtures = addon.modules['Fixtures']
local byID = {}
for _, item in ipairs(fixtures.items) do byID[item.itemID] = item end

-- bag index -> slot -> itemID. The keyring, the backpack and one bag hold things; the
-- remaining probed indices are empty, which is a result harvest must tolerate.
local contents = {
  [-1] = { 1005 },
  [0] = { 1001, 1002, 1003, 1004, 5411, 2901 },
  [1] = { 26042, 1006, 6948 },
}

-- index -> total slots, at the sizes the live client reports (agents.md storage shape): a 20-slot
-- backpack, a 6-slot bag, the 32-slot keyring. Real bags have free space, and issue #36 is about
-- what the addon does with it, so the fixture has some.
local slotCounts = { [-1] = 32, [0] = 20, [1] = 6 }

-- 1005 is the item the client has never seen: container info knows its name and quality,
-- GetItemInfo knows nothing (FR-103).
local NEVER_SEEN = 1005

_G.C_Container = {
  GetContainerNumSlots = function(index)
    return slotCounts[index] or (contents[index] and #contents[index] or 0)
  end,
  GetBagName = function(index)
    return contents[index] and ('Bag ' .. index) or ''
  end,
  GetContainerItemInfo = function(bag, slot)
    local itemID = contents[bag] and contents[bag][slot]
    local fixture = itemID and byID[itemID]
    if not fixture then return nil end
    return {
      itemID = itemID,
      itemName = fixture.name or ('Unknown ' .. itemID),
      quality = fixture.quality or 1,
      iconFileID = 1000 + itemID,
      hyperlink = '|cffffffff|Hitem:' .. itemID .. '|h[x]|h|r',
      stackCount = fixture.stackCount,
      isBound = false,
    }
  end,
  GetContainerItemQuestInfo = function(bag, slot)
    local itemID = contents[bag] and contents[bag][slot]
    local fixture = itemID and byID[itemID]
    return { isQuestItem = fixture and fixture.isQuestItem or false }
  end,
}

_G.C_Item = {
  GetItemInfoInstant = function(itemID)
    local fixture = byID[itemID]
    if not fixture or itemID == NEVER_SEEN then return nil end
    return itemID, fixture.type, fixture.subtype, fixture.equipSlot, 1000 + itemID, fixture.classID, fixture.subClassID
  end,
  GetItemInfo = function(itemID)
    local fixture = byID[itemID]
    if not fixture or itemID == NEVER_SEEN then return nil end
    return fixture.name, 'link', fixture.quality, fixture.ilvl, 0, fixture.type, fixture.subtype,
      fixture.stackCount, fixture.equipSlot, 1000 + itemID, 0, fixture.classID, fixture.subClassID,
      0, fixture.expansion
  end,
  RequestLoadItemDataByID = function() end,
}

addon.modules['DB'].Initialize()

local harvest = addon.modules['Harvest']
local pipeline = addon.modules['Pipeline']

harvest.Invalidate()
local containers = harvest.Discover()
check('containers discovered (keyring, backpack, one bag)', #containers, 3)

local items = harvest.Items()
check('harvested slot count', #items, 10)

pipeline.Refresh('smoke')
local model = pipeline.Model()

-- Issue #28: three hard-coded backpack windows. Array order in profile.windows IS screen order
-- (bottom-most first); a category is referenced by whichever window owns it (FR-12).
local function windowIn(models, name)
  for _, window in ipairs(models) do
    if window.name == name then return window end
  end
end

local function sectionIn(window, name)
  for _, section in ipairs(window and window.sections or {}) do
    if section.name == name then return section end
  end
end

local function countSection(window, name)
  local section = sectionIn(window, name)
  return section and #section.items or 0
end

local function binds(window)
  local out = {}
  for _, section in ipairs(window.sections) do out[#out + 1] = table.concat(section.categories, '+') end
  return table.concat(out, ',')
end

check('three windows in the model', #model, 3)
check('profile order is model order',
  model[1].name .. ',' .. model[2].name .. ',' .. model[3].name, 'Backpack,Quests,Tools')
local backpack = windowIn(model, 'Backpack')
local quests = windowIn(model, 'Quests')
local tools = windowIn(model, 'Tools')

check('Backpack keeps its three sections', #backpack.sections, 3)
check('Quests is one section', #quests.sections, 1)
check('Tools is one section', #tools.sections, 1)
check('Backpack binds neither moved category', binds(backpack), 'Junk,Armor,__catchall')
check('Quests binds Quest Items', binds(quests), 'Quest Items')
check('Tools binds Tools', binds(tools), 'Tools')

check('Junk holds the grey item', countSection(backpack, 'Junk'), 1)
check('Armor holds the cloth armour', countSection(backpack, 'Armor'), 1)
check('catch-all holds the rest', countSection(backpack, 'Everything else'), 4)
check('Quest Items holds both quest items', countSection(quests, 'Quest Items'), 2)
check('Tools holds the mining pick and the hearthstone', countSection(tools, 'Tools'), 2)

local catchall = sectionIn(backpack, 'Everything else')
check('catch-all packs 4 items into 4 columns', catchall and catchall.cols, 4)
check('catch-all needs one row', catchall and catchall.rows, 1)

-- Each window is sized by flow from its own content, not from a shared template.
local CELL = 38
local MONEY = 17 -- constants.MONEY_BAR_SPACE: the band the money bar claims (issue #32)
check('window is never narrower than its column budget', backpack.width, 5 * CELL + 16)
check('Quests is sized to its one 2-item section', quests.height, 26 + (18 + CELL) + 6 + 8 + MONEY)
check('Backpack is sized to its three sections and its free-slot cell',
  backpack.height, 26 + 3 * (18 + CELL) + 3 * 6 + CELL + 8 + MONEY)
check('windows are sized independently', quests.height ~= backpack.height, true)

-- Issue #36: the free-slot indicator. One slot at the end of the default backpack window carrying
-- the number of slots the player's bags still have open, and nothing at all when they have none.
check('the backpack family has 17 free slots', harvest.FreeSlots('backpack'), 17)
check('the keyring is counted apart from the bags', harvest.FreeSlots('keyring'), 31)
check('the indicator points at a real empty slot, and not the keyring slot before it',
  harvest.FirstFreeSlot().bagID .. ':' .. harvest.FirstFreeSlot().slot, '0:7')
check('the default backpack window carries the count', backpack.emptySlots, 17)
check('the slot it points at travels with the count',
  backpack.emptySlot.bagID .. ':' .. backpack.emptySlot.slot, '0:7')
check('the other backpack windows do not repeat the same number', quests.emptySlots, nil)
check('the indicator gets its own cell after the last section',
  backpack.emptyOffsetY, 3 * (18 + CELL + 6))
check('Quests is not sized for a cell it does not draw',
  quests.height, 26 + (18 + CELL) + 6 + 8 + MONEY)

-- Priority ladder, measured against the real item that motivated it: Winterhoof Cleansing Totem is
-- type Armor *and* a quest item. Junk (10) also matches nothing here, Armor (20) does. The ladder is
-- unchanged by windows (#28 decision 4), so 5411 lands in the Quests window, not in w1's Armor.
local function placeOf(itemID)
  for _, window in ipairs(model) do
    for _, section in ipairs(window.sections) do
      for _, item in ipairs(section.items) do
        if item.itemID == itemID then return window.name .. '/' .. section.name end
      end
    end
  end
end
check('a quest item that is also Armor wins on priority (5411)', placeOf(5411), 'Quests/Quest Items')
check('the manual list beats the type rule (2901 is a Weapon)', placeOf(2901), 'Tools/Tools')
check('grey armour is still junk (1001 is quality 0 Armor)', placeOf(1001), 'Backpack/Junk')
check('an ordinary weapon is not a tool', placeOf(1002), 'Backpack/Everything else')

-- FR-15: with duplication off, every harvested item is drawn exactly once **across every window**.
local drawn, seen = 0, {}
for _, window in ipairs(model) do
  for _, section in ipairs(window.sections) do
    for _, item in ipairs(section.items) do
      drawn = drawn + 1
      local key = item.bagID .. ':' .. item.slot
      if seen[key] then
        failures[#failures + 1] = 'duplicate placement for slot ' .. key
      end
      seen[key] = true
    end
  end
end
checks = checks + 1
if drawn ~= #items then
  failures[#failures + 1] = string.format('drawn %d of %d harvested items', drawn, #items)
end

-- AC-97 shape: only the never-seen ID costs a tier-3 request.
check('tier-3 requests issued', pipeline.Last().requestsIssued, 1)

-- /bos find: which container index holds an item. 1001 sits in the backpack, 999999 nowhere.
check('find locates an item across container indices', addon.modules['Diag'].Find(1001), 1)
check('find reports nothing for an absent item', addon.modules['Diag'].Find(999999), 0)
-- /bos test 3: the PLAYERBANKSLOTS_CHANGED payload is a **bank bag slot 1..9**, not a container
-- index (measured 2026-10-19), so the probe converts it the way Camelot does.
local diag = addon.modules['Diag']
_G.ITEM_INVENTORY_BANK_BAG_OFFSET = 5
contents[7] = {}
check('bank bag slot payload converts to its container index',
  diag.ExplainBankSlot(2), 'bank bag slot 2 -> container [7] Bag 7 0 slots')
check('bank slot payload ignores a non-number', diag.ExplainBankSlot(nil), nil)

-- /bos test: pending list, run sheet, and captured steps lettered a, b, c… A fixture stands in for
-- a real pending test so deleting one never breaks the harness.
local captured = 0
diag.Add(900, {
  issue = 900,
  what = 'fixture',
  needs = 'none',
  steps = {
    { text = 'a manual action' },
    { text = 'first capture', run = function() captured = captured + 1 end },
    { text = 'second capture', run = function() captured = captured + 1 end },
  },
})
check('the first captured step is letter a', diag.Test(900, 'a'), 'first capture')
check('the second is letter b', diag.Test(900, 'b'), 'second capture')
check('a letter past the last captured step runs nothing', diag.Test(900, 'c'), nil)
check('an unknown test id runs nothing', diag.Test(9001), nil)
check('captured steps ran', captured, 2)
-- One bucket per test, opened by the first captured step: two step headers plus the ingest reminder.
check('one bucket per test', #addon.modules['DB'].sv.diag['900'], 3)
check('the bucket opens with the first step header',
  addon.modules['DB'].sv.diag['900'][1]:match('^--- 900a'), '--- 900a')
-- The build stamp is what makes a capture comparable across clients (issue #24), so the header
-- carries the interface version **and** the build number.
check('the step header carries the build and its build number',
  addon.modules['DB'].sv.diag['900'][1]:match('build [%d%.]+ %(%d+%)'), 'build 1.16.0 (1)')
-- The run sheet is what a human follows in game, so its shape is a check: one numbered line per
-- step, manual steps included, and the closing /reload and sync as steps of their own. A compound
-- step is how a manual action gets skipped.
local sheet, realPrint = {}, print
_G.print = function(...) sheet[#sheet + 1] = table.concat({ ... }, ' ') end
local sheetName = diag.Test(900)
_G.print = realPrint
check('the run sheet answers with the test name', sheetName, 'fixture')
check('title, pre-conditions, one numbered line per step, /reload and sync', #sheet, 7)
check('a manual step gets a number and no command', sheet[3], '1. a manual action')
check('a captured step carries its command', sheet[4], '2. /bos test 900a  first capture')
check('the sheet ends with the sync step', sheet[7], '5. ../sync.sh')
diag.Command('900b')
check('the slash dispatcher reaches the same step', captured, 3)

-- The keybind mirror (issue #13): the client writes our action to bindings-cache.wtf and it
-- survives a restart, but /reload re-registers Bindings.xml and can drop it. Whatever the client
-- has at login is stored; if the client has nothing, ours goes back.
local keybinds = addon.modules['Keybinds']
local sv = addon.modules['DB'].sv
local bound, applied
_G.GetBindingKey = function() return bound end
_G.SetBinding = function(_, action) applied = action; return true end

keybinds.Restore()
check('nothing bound and nothing stored forces nothing', applied, nil)

bound = 'F6'
keybinds.Restore()
check('what the client has at login is stored', sv.global.keybinds.BAGSOF_SORTING_TOGGLE, 'F6')
check('a binding the client already holds is not re-set', applied, nil)

bound = nil
applied = nil
keybinds.Restore()
check('a binding the client lost is restored from our copy', applied, 'BAGSOF_SORTING_TOGGLE')

bound = 'F7'
addon.modules['Events'].Emit('UPDATE_BINDINGS')
check('a rebind in the panel is captured', sv.global.keybinds.BAGSOF_SORTING_TOGGLE, 'F7')

bound = nil
addon.modules['Events'].Emit('PLAYER_LOGOUT')
check('an unbind is stored as an unbind, not re-applied from an old value',
  sv.global.keybinds.BAGSOF_SORTING_TOGGLE, nil)

-- ITEM_DATA_LOAD_RESULT also fires for requests Blizzard or another addon made. Caching that data
-- is free and correct; counting it as one of ours is what made `pending` go negative.
local enrich = addon.modules['Enrich']
enrich.OnItemDataLoaded(1001, true)
check('an unrequested item-data result is not counted as ours',
  tonumber(enrich.Stats():match('pending=(-?%d+)')), 1)

-- A window closed by its own X is out of the model, so a refresh cannot reopen it (FR-41).
-- Through DB.SetWindowsOpen rather than poking the flag: that is the function the keybind,
-- `/bos show` and `/bos hide` all call.
local function testWindowVisibility()
  local db = addon.modules['DB']
  db.SetWindowsOpen(false)
  pipeline.Refresh('close')
  check('closed windows leave the model', #pipeline.Model(), 0)
  db.SetWindowsOpen(true)
  pipeline.Refresh('reopen')
  check('reopened windows are back in the model', #pipeline.Model(), 3)
  check('reopen clears the flag rather than setting it', db.Windows()[1].hidden, nil)
end

testWindowVisibility()

-- One category bound by two windows is still placed once: the first window in array order wins
-- (FR-15 + #28 decision 4), and the window left with nothing still renders (#28 decision 2).
local function testDuplicateBinding()
  local db = addon.modules['DB']
  table.insert(db.Windows()[1].sections, { id = 's9', name = 'Tools copy', categories = { 'Tools' } })
  pipeline.Refresh('duplicate-binding')
  local models = pipeline.Model()
  check('the first window in array order gets the items',
    countSection(windowIn(models, 'Backpack'), 'Tools copy'), 2)
  check('the later window keeps its slot with no sections', #models, 3)
  check('and holds nothing', #models[3].sections, 0)
  table.remove(db.Windows()[1].sections)
  pipeline.Refresh('unduplicate')
end

testDuplicateBinding()

-- Issue #36, the negative half: a character with no free space gets no count, no slot and no cell.
-- Its refreshes replace the last context, so it sits with the other state-changing cases rather
-- than next to the free-space assertions above.
local function testFullBags()
  local saved = slotCounts
  slotCounts = { [-1] = 1, [0] = 6, [1] = 3 }
  harvest.Invalidate()
  pipeline.Refresh('full-bags')
  local full = windowIn(pipeline.Model(), 'Backpack')
  check('a full inventory has no free slots', harvest.FreeSlots('backpack'), 0)
  check('and no empty slot to point at', harvest.FirstFreeSlot(), nil)
  check('the window carries no count', full.emptySlots, nil)
  check('the window carries no slot', full.emptySlot, nil)
  check('no cell, so the window is the size it was before the indicator existed',
    full.height, 26 + 3 * (18 + CELL) + 3 * 6 + 8 + MONEY)
  slotCounts = saved
  harvest.Invalidate()
  pipeline.Refresh('free-space')
  check('free space puts the cell back',
    windowIn(pipeline.Model(), 'Backpack').emptyOffsetY ~= nil, true)
end

testFullBags()

-- Bank windows are M5: the gate in pipeline.Assign is what keeps them out of the frames layer.
local function testBankWindow()
  local db = addon.modules['DB']
  table.insert(db.Windows(), {
    id = 'w9', name = 'Bank', kind = 'bank', columns = 5,
    sections = { { id = 's9', name = 'Everything else', categories = { '__catchall' } } },
  })
  pipeline.Refresh('bank-window')
  local models = pipeline.Model()
  check('a bank window stays out of the model', #models, 3)
  local bank = false
  for _, window in ipairs(models) do
    if window.kind == 'bank' then bank = true end
  end
  check('no bank window reaches the frames layer', bank, false)
  table.remove(db.Windows())
  pipeline.Refresh('unbank')
end

testBankWindow()

-- /bos unplace: a saved drag point is the only thing that overrides the layout rule, and the
-- placement tests need the default placement (FR-41).
local function testClearPositions()
  local db = addon.modules['DB']
  db.Windows()[3].position = { point = 'TOP', relativePoint = 'TOP', x = 295.2, y = -191.7 }
  check('a saved position is counted as cleared', db.ClearPositions(), 1)
  check('the window keeps everything else about itself',
    db.Windows()[3].id .. '/' .. tostring(db.Windows()[3].position), 'w3/nil')
  check('nothing saved means nothing cleared', db.ClearPositions(), 0)
end

testClearPositions()

-- layout/anchors.lua: Blizzard's bag layout ported (issue #28). Pure math over the model, so the
-- whole rule is testable off the client.
local anchors = addon.modules['Anchors']
local GAP, COLUMN_GAP = 8, 11

---@return BoSWindowModel[]
local function stack(heights, screenHeight, allowance)
  local models = {}
  for i, height in ipairs(heights) do models[i] = { id = 'w' .. i, width = 206, height = height } end
  anchors.Place(models, screenHeight, allowance)
  return models
end

local function overlaps(a, b)
  return a.x < b.x + b.width and b.x < a.x + a.width and a.y < b.y + b.height and b.y < a.y + a.height
end

local stacked = stack({ 100, 100, 100 }, 1200, 45)
check('the first column starts at the anchor', stacked[1].x, 0)
check('the first window sits on the anchor', stacked[1].y, 0)
check('the second window is GAP above the first', stacked[2].y, 100 + GAP)
check('the third stacks the same way', stacked[3].y, 2 * (100 + GAP))
check('a 1200-high client holds all three in one column', stacked[3].x, 0)

local overlapping = 0
for i = 1, #stacked do
  for j = i + 1, #stacked do
    if overlaps(stacked[i], stacked[j]) then overlapping = overlapping + 1 end
  end
end
check('no two windows share a rectangle', overlapping, 0)

-- The cap is screenHeight - allowance, honoured exactly: full is not over.
local exact = stack({ 50, 50 }, 200, 92)
check('a column exactly full at the boundary does not wrap', exact[2].x, 0)
local over = stack({ 50, 50 }, 200, 93)
check('one pixel over wraps to a new column', over[2].x, -(206 + COLUMN_GAP))
check('the wrapped column resets its height', over[2].y, 0)

local wrapped = stack({ 400, 400, 400 }, 1200, 45)
check('a column that cannot hold the next window wraps left', wrapped[3].x, -(206 + COLUMN_GAP))
check('the wrapped window starts at the bottom of its column', wrapped[3].y, 0)
check('the wrapped column is clear of the first',
  overlaps(wrapped[1], wrapped[3]) or overlaps(wrapped[2], wrapped[3]), false)

-- Blizzard starts no new column for a single too-tall frame (`framesInColumn == 1`); it shrinks
-- scale instead. We do not shrink, so the equivalent is: keep the slot, let the clamp handle it.
local giant = stack({ 2000 }, 1200, 45)
check('a single window taller than the cap never gets a phantom column',
  giant[1].x .. '/' .. giant[1].y, '0/0')

-- Decision 2: an empty window still occupies a slot. 72 is what flow gives a window with no sections.
local empty = stack({ 26 + 38 + 8, 100 }, 1200, 45)
check('an empty window still consumes its slot in the column', empty[2].y, (26 + 38 + 8) + GAP)


for _, failure in ipairs(failures) do
  print('FAIL ' .. failure)
end
print(string.format('selftest: %d checks, %d failures', checks, #failures))
os.exit(#failures == 0 and 0 or 1)
