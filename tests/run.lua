-- Headless pipeline test: `lua5.1 tests/run.lua`.
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
  [0] = { 1001, 1002, 1003, 1004 },
  [1] = { 26042, 1006 },
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
check('harvested slot count', #items, 7)

pipeline.Refresh('smoke')
local model = pipeline.Model()

check('one window in the model', #model, 1)
local window = model[1]
check('window name', window and window.name, 'Backpack')
check('empty sections are skipped', window and #window.sections, 3)

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
check('catch-all holds the rest', countSection('Everything else'), 5)

local catchall = sectionByName('Everything else')
check('catch-all packs 5 items into 5 columns', catchall and catchall.cols, 5)
check('catch-all needs one row', catchall and catchall.rows, 1)
check('window is 5 columns wide', window and window.width, 5 * 38 + 16)

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

for _, failure in ipairs(failures) do
  print('FAIL ' .. failure)
end
print(string.format('selftest: %d checks, %d failures', checks, #failures))
os.exit(#failures == 0 and 0 or 1)
