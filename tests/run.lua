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

-- 1005 is the item the client has never seen: container info knows its name and quality,
-- GetItemInfo knows nothing (FR-103).
local NEVER_SEEN = 1005

_G.C_Container = {
  GetContainerNumSlots = function(index)
    return contents[index] and #contents[index] or 0
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

check('one window in the model', #model, 1)
local window = model[1]
check('window name', window and window.name, 'Backpack')
check('every shipped section has something in it', window and #window.sections, 5)

local function sectionByName(name)
  for _, section in ipairs(window.sections or {}) do
    if section.name == name then return section end
  end
end

local function countSection(name)
  local section = sectionByName(name)
  return section and #section.items or 0
end

check('Junk holds the grey item', countSection('Junk'), 1)
check('Armor holds the cloth armour', countSection('Armor'), 1)
check('Quest Items holds both quest items', countSection('Quest Items'), 2)
check('Tools holds the mining pick and the hearthstone', countSection('Tools'), 2)
check('catch-all holds the rest', countSection('Everything else'), 4)

local catchall = sectionByName('Everything else')
check('catch-all packs 4 items into 4 columns', catchall and catchall.cols, 4)
check('catch-all needs one row', catchall and catchall.rows, 1)
check('window is never narrower than its column budget', window and window.width, 5 * 38 + 16)

-- Priority ladder, measured against the real item that motivated it: Winterhoof Cleansing Totem is
-- type Armor *and* a quest item. Junk (10) also matches nothing here, Armor (20) does.
local function sectionOf(itemID)
  for _, section in ipairs(window.sections) do
    for _, item in ipairs(section.items) do
      if item.itemID == itemID then return section.name end
    end
  end
end
check('a quest item that is also Armor wins on priority (5411)', sectionOf(5411), 'Quest Items')
check('the manual list beats the type rule (2901 is a Weapon)', sectionOf(2901), 'Tools')
check('grey armour is still junk (1001 is quality 0 Armor)', sectionOf(1001), 'Junk')
check('an ordinary weapon is not a tool', sectionOf(1002), 'Everything else')

-- FR-15: with duplication off, every harvested item is drawn exactly once.
local drawn, seen = 0, {}
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
check('the run sheet answers with the test name', diag.Test(900), 'fixture')
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
  check('reopened windows are back in the model', #pipeline.Model(), 1)
  check('reopen clears the flag rather than setting it', db.Windows()[1].hidden, nil)
end

testWindowVisibility()

-- Migration 1→2 is the code that touches a player's existing file: it must add the new categories
-- and land their sections before the catch-all without renumbering or reordering what they had.
local function testMigration()
  local db = addon.modules['DB']
  db.sv.version = 1
  db.sv.profiles.Default = {
    windows = { { id = 'w1', name = 'Backpack', kind = 'backpack', sections = {
      { id = 's1', name = 'Junk', categories = { 'Junk' } },
      { id = 's2', name = 'Armor', categories = { 'Armor' } },
      { id = 's3', name = 'Everything else', categories = { '__catchall' } },
    } } },
    categories = {
      ['Junk'] = { priority = 10, kind = 'rules', enabled = true,
        rules = { op = 'all', children = { { field = 'quality', cmp = '=', value = 0 } } } },
      ['Armor'] = { priority = 20, kind = 'rules', enabled = true,
        rules = { op = 'all', children = { { field = 'type', cmp = '=', value = 'Armor' } } } },
      ['__catchall'] = { priority = 999, kind = 'rules', enabled = true,
        rules = { op = 'all', children = { { field = 'none', cmp = '=', value = true } } } },
    },
  }
  db.Migrate()
  check('migration bumps the schema version', db.sv.version, 2)
  check('the new categories arrive',
    db.Profile().categories['Quest Items'] ~= nil and db.Profile().categories['Tools'] ~= nil, true)
  local order = {}
  for _, section in ipairs(db.Profile().windows[1].sections) do order[#order + 1] = section.name end
  check('new sections land before the catch-all, existing ones keep their place',
    table.concat(order, ','), 'Junk,Armor,Quest Items,Tools,Everything else')
  db.Migrate()
  check('migrating twice changes nothing', #db.Profile().windows[1].sections, 5)
end

testMigration()


for _, failure in ipairs(failures) do
  print('FAIL ' .. failure)
end
print(string.format('selftest: %d checks, %d failures', checks, #failures))
os.exit(#failures == 0 and 0 or 1)
