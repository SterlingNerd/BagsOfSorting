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
-- The bank arithmetic core/constants.lua reads at load (issue #9): offset 5, nine bank bag slots,
-- so the bank containers are indices 6..14.
_G.ITEM_INVENTORY_BANK_BAG_OFFSET = 5
_G.NUM_CHARACTER_BANK_SLOTS = 9

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

-- Issue #38 stands-ins. Off the client there is no FrameXML, so the frames Blizzard owns and the
-- global calls a vendor and the bank make are replaced by tables that remember being hidden.
_G.InCombatLockdown = function() return false end

local function fakeFrame(name)
  return {
    shown = true,
    GetName = function(self) return name end,
    IsShown = function(self) return self.shown end,
    Show = function(self) self.shown = true end,
    Hide = function(self) self.shown = false end,
  }
end

_G.ContainerFrameCombinedBags = fakeFrame('ContainerFrameCombinedBags')
_G.ContainerFrame1 = fakeFrame('ContainerFrame1')
-- NUM_TOTAL_BAG_FRAMES + backpack + keyring: the range Blizzard itself iterates
-- (ContainerFrame.lua:8-11, :140). Frame 6 is the one a loop bounded at NUM_TOTAL_BAG_FRAMES misses.
_G.NUM_CONTAINER_FRAMES = 7
_G.ContainerFrame6 = fakeFrame('ContainerFrame6')

--- Blizzard's own "show every bag", and hooksecurefunc's semantics: the hook runs after the
--- original, with the same arguments.
_G.OpenAllBags = function()
  _G.ContainerFrameCombinedBags:Show()
  _G.ContainerFrame1:Show()
  _G.ContainerFrame6:Show()
end
_G.hooksecurefunc = function(name, hook)
  local original = _G[name]
  _G[name] = function(...)
    local results = { original(...) }
    hook(...)
    return unpack(results)
  end
end

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
  'core/interactions.lua',
  'core/diag.lua',
  'tests/fixtures.lua',
  'tests/selftest.lua',
}

local addon = {}
-- The frames layer is not loaded off the client (docs/03: phases 1-7 never touch a frame), so the
-- one frames call issue #38 wires gets a counting stand-in. boot.lua keeps a table already here.
local windowFramesStandIn = { hides = 0 }
windowFramesStandIn.HideAll = function() windowFramesStandIn.hides = windowFramesStandIn.hides + 1 end
addon.modules = { WindowFrames = windowFramesStandIn }
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

-- bag index -> slot -> itemID. The keyring, the backpack, one equipped bag and the reagent pouch
-- hold things; the remaining probed indices are empty, which is a result harvest must tolerate.
-- Issue #41 spreads its materials across three of those containers on purpose: where an item sits
-- is not what decides its section.
-- Issue #44 adds index 2: a 6-slot herb bag holding the fixture's one herb, and index 3: an empty
-- 6-slot engineering bag. The client names a specialty bag by the family bit
-- C_Container.GetContainerNumFreeSlots answers with (32 herb, 128 engineering, 0 a plain one), so
-- `families` below is this stub's answer to that call.
--
-- Issue #47 adds the bank side, at the shape issues #9 and #25 measured: the 48-slot grid at index 6,
-- a purchased 10-slot bank bag at 7, and a 10-slot herb-family bag at 8. Harvest only probes them
-- while the bank is open, so their contents are invisible until a test opens it.
local contents = {
  [-1] = { 1005 },
  [0] = { 1001, 1002, 1003, 1004, 5411, 2901, 2770, 2672, 118, 159, 1251 },
  [1] = { 26042, 1006, 6948, 2320, 2578 },
  [2] = { 765 },
  [3] = {},
  [5] = { 3355, 3434 },
  [6] = { 1007, 1009, 1008 },
  [7] = {},
  [8] = { 1010 },
}

-- index -> total slots, at the sizes the live client reports (references/containers-and-bags.md
-- storage shape): a 20-slot
-- backpack, a 6-slot bag, a 4-slot reagent pouch, the 32-slot keyring. Real bags have free space,
-- and issue #36 is about what the addon does with it, so the fixture has some.
-- index -> the specialty family bit the client would report for it. The herb bag and the
-- engineering bag are specialty bags; the rest of the set is plain.
local families = { [2] = 32, [3] = 128, [8] = 32 }

local slotCounts = { [-1] = 32, [0] = 20, [1] = 6, [2] = 6, [3] = 6, [5] = 4, [6] = 48, [7] = 10, [8] = 10 }

-- 1005 is the item the client has never seen: container info knows its name and quality,
-- GetItemInfo knows nothing (FR-103).
local NEVER_SEEN = 1005

_G.C_Container = {
  GetContainerNumSlots = function(index)
    return slotCounts[index] or (contents[index] and #contents[index] or 0)
  end,
  GetContainerNumFreeSlots = function(index)
    local slots = slotCounts[index] or (contents[index] and #contents[index] or 0)
    local filled = 0
    for slot = 1, slots do
      if contents[index] and contents[index][slot] then filled = filled + 1 end
    end
    return slots - filled, families[index] or 0
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
check('containers discovered (keyring, backpack, three bags, the reagent pouch)', #containers, 6)

local items = harvest.Items()
check('harvested slot count', #items, 20)

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

---@return BoSContainer?
local function containerAt(index)
  for _, container in ipairs(harvest.Containers()) do
    if container.index == index then return container end
  end
end

check('five windows in the model', #model, 5)
local names = {}
for _, window in ipairs(model) do names[#names + 1] = window.name end
check('profile order is model order', table.concat(names, ','),
  'Backpack,Quests,Consumables,Tradeskills,Tools')   -- issue #41 inserted two between Quests and Tools
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
local TITLE = 40 -- constants.WINDOW_TITLE_HEIGHT: the band that clears the window portrait (issue #34)
check('window is never narrower than its column budget', backpack.width, 5 * CELL + 16)
check('Quests is sized to its one 2-item section and no money band',
  quests.height, TITLE + (18 + CELL) + 6 + 8)
check('Backpack is sized to its three sections and its free-slot cell',
  backpack.height, TITLE + 3 * (18 + CELL) + 3 * 6 + CELL + 8 + MONEY)
check('windows are sized independently', quests.height ~= backpack.height, true)

-- Issue #36: the free-slot indicator. One slot at the end of the default backpack window carrying
-- the number of slots the player's bags still have open, and nothing at all when they have none.
check('the backpack family has 21 free slots', harvest.FreeSlots('backpack'), 21)
check('the keyring is counted apart from the bags', harvest.FreeSlots('keyring'), 31)
check('the reagent pouch is its own family, 2 free slots', harvest.FreeSlots('reagent'), 2)
check('and its free space is not in the number the window shows', backpack.emptySlots, 21)
check('the indicator points at a real empty slot, and not the keyring slot before it',
  harvest.FirstFreeSlot().bagID .. ':' .. harvest.FirstFreeSlot().slot, '0:12')
check('the default backpack window carries the count', backpack.emptySlots, 21)
check('the slot it points at travels with the count',
  backpack.emptySlot.bagID .. ':' .. backpack.emptySlot.slot, '0:12')
check('the other backpack windows do not repeat the same number', quests.emptySlots, nil)
check('the indicator gets its own cell after the last section',
  backpack.emptyOffsetY, 3 * (18 + CELL + 6))
check('Quests is not sized for a cell it does not draw',
  quests.height, TITLE + (18 + CELL) + 6 + 8)

-- Priority ladder, measured against the real item that motivated it: Winterhoof Cleansing Totem is
-- type Armor *and* a quest item. Junk (10) also matches nothing here, Armor (20) does. The ladder is
-- unchanged by windows (#28 decision 4), so 5411 lands in the Quests window, not in w1's Armor.
local function placeIn(models, itemID)
  for _, window in ipairs(models) do
    for _, section in ipairs(window.sections) do
      for _, item in ipairs(section.items) do
        if item.itemID == itemID then return window.name .. '/' .. section.name end
      end
    end
  end
end

local function placeOf(itemID) return placeIn(model, itemID) end
check('a quest item that is also Armor wins on priority (5411)', placeOf(5411), 'Quests/Quest Items')
check('the manual list beats the type rule (2901 is a Weapon)', placeOf(2901), 'Tools/Tools')
check('grey armour is still junk (1001 is quality 0 Armor)', placeOf(1001), 'Backpack/Junk')
check('an ordinary weapon is not a tool', placeOf(1002), 'Backpack/Everything else')

-- Issue #41: the two new windows and the two rules that decide where a material lands.
local consumables = windowIn(model, 'Consumables')
local tradeskills = windowIn(model, 'Tradeskills')

check('Consumables binds its one category', binds(consumables), 'Consumables')
check('Tradeskills binds one category per section', binds(tradeskills),
  'Tradeskills.Herbs,Tradeskills.Ore,Tradeskills.Leather,Tradeskills.Cloth,'
    .. 'Tradeskills.Elements,Tradeskills.Parts,Tradeskills.Cooking')
check('Consumables holds the potion, the water and the bandage',
  countSection(consumables, 'Consumables'), 3)
check('Herbs holds one and Elements holds two',
  countSection(tradeskills, 'Herbs') .. '/' .. countSection(tradeskills, 'Elements'), '1/2')

-- Sorting follows what the item is, not which container holds it. 765 and 3434 sit in the reagent
-- pouch (index 5), 2320 and 1210 in an equipped bag, 2770 in the backpack: all three containers
-- feed the same Tradeskills window.
check('a herb in the reagent pouch sorts with the herbs (765)', placeOf(765), 'Tradeskills/Herbs')
check('enchanting reagents share Elements with elemental ones (3434)', placeOf(3434), 'Tradeskills/Elements')
check('ore (2770)', placeOf(2770), 'Tradeskills/Ore')
check('leather (2320)', placeOf(2320), 'Tradeskills/Leather')
check('cloth (2578)', placeOf(2578), 'Tradeskills/Cloth')
check('a cooking ingredient (2672)', placeOf(2672), 'Tradeskills/Cooking')
check('nothing matches the Engineering section, so only its bag draws it',
  countSection(tradeskills, 'Engineering'), 0)
-- The Engineering section is the empty-category case: the fixture's engineering bag (family 128)
-- holds nothing, and its six free slots are what keeps the section on screen — the cell is where
-- the item goes, so hiding the category would hide the drop target.
local engineering = sectionIn(tradeskills, 'Engineering')
check('the engineering bag carries the client engineering family bit', containerAt(3).family, 128)
check('the empty Engineering section is drawn because its bag has free slots',
  engineering ~= nil, true)
check('its own count is the bag\'s 6 free slots', engineering.emptySlots, 6)
check('and its cell points at that bag\'s first free slot',
  engineering.emptySlot.bagID .. ':' .. engineering.emptySlot.slot, '3:1')
check('the cell is the whole block: a title band and one row', engineering.height, 18 + CELL)
check('the cell sits directly under the title', engineering.emptyOffsetY, 18)
check('an empty section takes the window column budget as its width, so its title reads like the others',
  engineering.width, 5 * CELL)
-- The tradeskill rules pin `type` as well as `subtype`: 'Cloth' is an Armor subtype too, and a
-- cloth shirt is not tailoring material.
check('cloth armour stays Armor, not cloth material (1003)', placeOf(1003), 'Backpack/Armor')

-- The priority half: Consumables (12) outranks every tradeskill category (15).
check('a potion is a consumable, not an alchemy reagent (118)', placeOf(118), 'Consumables/Consumables')
check('food and drink (159)', placeOf(159), 'Consumables/Consumables')
check('bandages (1251)', placeOf(1251), 'Consumables/Consumables')

check('Consumables is sized to its one 3-item section and no money band',
  consumables.height, TITLE + (18 + CELL) + 6 + 8)
check('Tradeskills is sized to its seven sections, their gaps and the herb-bag cell',
  tradeskills.height, TITLE + 7 * (18 + CELL) + 7 * 6 + CELL + 8)
check('neither new window repeats the free-slot count',
  tostring(consumables.emptySlots) .. '/' .. tostring(tradeskills.emptySlots), 'nil/nil')

-- Issue #44: a tradeskill section counts the free slots of the specialty bag its category pairs
-- with, not the whole bag set. The fixture equips one 6-slot herb bag (family 32) holding one herb,
-- so Herbs has a count of its own and every other tradeskill section has none: no bag of that
-- family is equipped.
local herbs = sectionIn(tradeskills, 'Herbs')
check('the herb bag carries the client\'s herb family bit', containerAt(2).family, 32)
check('a plain bag carries none', containerAt(0).family, 0)
check('the herb family has 5 free slots', harvest.FreeSlotsForFamily(32, 'backpack'), 5)
check('the Herbs section carries its own count', herbs.emptySlots, 5)
check('and points at a real free slot in that bag, not the first free slot anywhere',
  herbs.emptySlot.bagID .. ':' .. herbs.emptySlot.slot, '2:2')
check('the sections with no bag of their own carry no count',
  tostring(sectionIn(tradeskills, 'Ore').emptySlots) .. '/'
    .. tostring(sectionIn(tradeskills, 'Leather').emptySlots) .. '/'
    .. tostring(sectionIn(tradeskills, 'Cloth').emptySlots) .. '/'
    .. tostring(sectionIn(tradeskills, 'Elements').emptySlots) .. '/'
    .. tostring(sectionIn(tradeskills, 'Cooking').emptySlots),
  'nil/nil/nil/nil/nil')
check('the cell is one more row inside the section block', herbs.height, 18 + 2 * CELL)
check('the cell sits after the section\'s one item row', herbs.emptyOffsetY, 18 + CELL)
check('the window-level count is still the whole bag set, specialty bags included',
  windowIn(model, 'Backpack').emptySlots, 21)

-- Issue #42: the money bar belongs to the default backpack window alone. The other windows are
-- views over the same bags, so a coin row on each would read as five separate purses.
check('the default backpack window carries the money bar', backpack.showMoney, true)
check('no other backpack window carries it',
  tostring(quests.showMoney) .. '/' .. tostring(consumables.showMoney)
  .. '/' .. tostring(tradeskills.showMoney) .. '/' .. tostring(tools.showMoney),
  'nil/nil/nil/nil')
check('the backpack window is the only one sized for the money band',
  backpack.height - (3 * (18 + CELL) + 3 * 6 + CELL + 8 + TITLE), MONEY)

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
contents[7] = {}
check('bank bag slot payload converts to its container index',
  diag.ExplainBankSlot(2), 'bank bag slot 2 -> container [7] Bag 7 10 slots')
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
  check('reopened windows are back in the model', #pipeline.Model(), 5)
  check('reopen clears the flag rather than setting it', db.Windows()[1].hidden, nil)
end

testWindowVisibility()

-- Issue #42, the negative half: with the default backpack window closed, the bar travels to the
-- next backpack window in screen order. Exactly one window carries it, never all four.
local function testMoneyBarOwner()
  local db = addon.modules['DB']
  db.Windows()[1].hidden = true
  pipeline.Refresh('closed-backpack')
  local carriers = {}
  for _, window in ipairs(pipeline.Model()) do
    if window.showMoney then carriers[#carriers + 1] = window.name end
  end
  check('a closed default backpack window leaves exactly one carrier', table.concat(carriers, ','), 'Quests')
  db.Windows()[1].hidden = nil
  pipeline.Refresh('open-backpack')
  check('the bar goes back to the default backpack window',
    windowIn(pipeline.Model(), 'Backpack').showMoney, true)
end

testMoneyBarOwner()

-- One category bound by two windows is still placed once: the first window in array order wins
-- (FR-15 + #28 decision 4), and the window left with nothing still renders (#28 decision 2).
local function testDuplicateBinding()
  local db = addon.modules['DB']
  table.insert(db.Windows()[1].sections, { id = 's9', name = 'Tools copy', categories = { 'Tools' } })
  pipeline.Refresh('duplicate-binding')
  local models = pipeline.Model()
  check('the first window in array order gets the items',
    countSection(windowIn(models, 'Backpack'), 'Tools copy'), 2)
  check('the later window keeps its slot with no sections', #models, 5)
  check('and holds nothing', #models[5].sections, 0)
  table.remove(db.Windows()[1].sections)
  pipeline.Refresh('unduplicate')
end

testDuplicateBinding()

-- Issue #36, the negative half: a character with no free space gets no count, no slot and no cell.
-- Its refreshes replace the last context, so it sits with the other state-changing cases rather
-- than next to the free-space assertions above.
local function testFullBags()
  local saved = slotCounts
  slotCounts = { [-1] = 1, [0] = 6, [1] = 3, [2] = 1, [5] = 3 }
  harvest.Invalidate()
  pipeline.Refresh('full-bags')
  local full = windowIn(pipeline.Model(), 'Backpack')
  check('a full inventory has no free slots', harvest.FreeSlots('backpack'), 0)
  check('even with one reagent pouch slot still open', harvest.FreeSlots('reagent'), 1)
  check('and no empty slot to point at', harvest.FirstFreeSlot(), nil)
  check('the window carries no count', full.emptySlots, nil)
  check('the window carries no slot', full.emptySlot, nil)
  check('no cell, so the window is the size it was before the indicator existed',
    full.height, TITLE + 3 * (18 + CELL) + 3 * 6 + 8 + MONEY)
  slotCounts = saved
  harvest.Invalidate()
  pipeline.Refresh('free-space')
  check('free space puts the cell back',
    windowIn(pipeline.Model(), 'Backpack').emptyOffsetY ~= nil, true)
end

testFullBags()

-- Issue #44, the negative half. The count belongs to the bag, so a bag set with no specialty bag
-- in it, and a specialty bag with nothing open in it, both leave the section with no count and no
-- cell — the AC's "hidden when no corresponding tradeskill bag is equipped".
local function testNoSpecialtyBag()
  local savedFamilies, savedSlots = families, slotCounts

  families = {}
  harvest.Invalidate()
  pipeline.Refresh('no-specialty-bags')
  local plain = sectionIn(windowIn(pipeline.Model(), 'Tradeskills'), 'Herbs')
  check('no specialty bag means no count for the section it would belong to', plain.emptySlots, nil)
  check('and no slot to point at', plain.emptySlot, nil)
  check('and no cell', plain.emptyOffsetY, nil)
  check('the section is the height it was before the count existed', plain.height, 18 + CELL)
  check('a section with no items and no bag of its own is still not drawn',
    sectionIn(windowIn(pipeline.Model(), 'Tradeskills'), 'Engineering'), nil)

  families = savedFamilies
  slotCounts = { [-1] = 32, [0] = 20, [1] = 6, [2] = 1, [3] = 6, [5] = 4 }
  harvest.Invalidate()
  pipeline.Refresh('full-herb-bag')
  local full = sectionIn(windowIn(pipeline.Model(), 'Tradeskills'), 'Herbs')
  check('a full tradeskill bag has no free slot to count', harvest.FreeSlotsForFamily(32, 'backpack'), 0)
  check('so the section carries no count', full.emptySlots, nil)
  check('and the section is not sized for a cell it does not draw', full.height, 18 + CELL)

  slotCounts = savedSlots
  harvest.Invalidate()
  pipeline.Refresh('herb-bag-open')
  local back = sectionIn(windowIn(pipeline.Model(), 'Tradeskills'), 'Herbs')
  check('free space in the bag puts the count and the cell back',
    back.emptySlots .. '/' .. tostring(back.emptyOffsetY), '5/56')
end

testNoSpecialtyBag()

-- /bos unplace: a saved drag point is the only thing that overrides the layout rule, and the
-- placement tests need the default placement (FR-41).
local function testClearPositions()
  local db = addon.modules['DB']
  db.Windows()[5].position = { point = 'TOP', relativePoint = 'TOP', x = 295.2, y = -191.7 }
  check('a saved position is counted as cleared', db.ClearPositions(), 1)
  check('the window keeps everything else about itself',
    db.Windows()[5].id .. '/' .. tostring(db.Windows()[5].position), 'w3/nil')
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

-- Decision 2: an empty window still occupies a slot. 95 is what flow gives a window with no sections —
-- the chrome floor, not a body cell (#43).
local empty = stack({ 95, 100 }, 1200, 45)
check('an empty window still consumes its slot in the column', empty[2].y, 95 + GAP)


-- Issue #41's negative half. The shipped rules are disjoint — no item is type "Consumable" *and*
-- type "Trade Goods" — so the ladder only gets exercised the way a user will break it: an Alchemy
-- category with the potion's ID pasted into its curated list.
local function testConsumablesBeatTradeskills()
  local db = addon.modules['DB']
  db.Categories()['Tradeskills.Alchemy'] = {
    priority = 15, kind = 'manual', enabled = true, duplicate = false, itemIDs = { [118] = true },
  }
  table.insert(db.Windows()[4].sections,
    { id = 's15', name = 'Alchemy', categories = { 'Tradeskills.Alchemy' } })
  pipeline.Refresh('alchemy-list')
  local models = pipeline.Model()
  check('Consumables still owns the potion a tradeskill list claims (118)',
    placeIn(models, 118), 'Consumables/Consumables')
  check('the Alchemy section gets nothing, so it is not drawn',
    sectionIn(windowIn(models, 'Tradeskills'), 'Alchemy'), nil)
  db.Categories()['Tradeskills.Alchemy'] = nil
  table.remove(db.Windows()[4].sections)
  pipeline.Refresh('unalchemy')
end

testConsumablesBeatTradeskills()

-- The enable/disable option (docs/05's `category.setEnabled`): a disabled category stops owning its
-- items, they fall to the catch-all, and re-enabling puts them back where they were.
local function testCategoryEnabled()
  local db = addon.modules['DB']
  check('an unknown category is refused', db.SetCategoryEnabled('Nope', false), false)
  check('disabling Herbs is a change', db.SetCategoryEnabled('Tradeskills.Herbs', false), true)
  check('disabling it a second time is not', db.SetCategoryEnabled('Tradeskills.Herbs', false), false)
  pipeline.Refresh('disable-herbs')
  local models = pipeline.Model()
  check('the Herbs section is gone', sectionIn(windowIn(models, 'Tradeskills'), 'Herbs'), nil)
  check('a disabled category does not keep its section alive through its bag',
    harvest.FreeSlotsForFamily(32, 'backpack') > 0, true)
  check('its herb falls to the catch-all', placeIn(models, 765), 'Backpack/Everything else')
  check('re-enabling is a change', db.SetCategoryEnabled('Tradeskills.Herbs', true), true)
  pipeline.Refresh('enable-herbs')
  check('and the herb is back in its own section', placeIn(pipeline.Model(), 765), 'Tradeskills/Herbs')
end

testCategoryEnabled()

-- Issue #44's schema half. The pairing lives in the saved profile, so a profile written before it
-- existed gets it from migration 2 — otherwise the per-section count is silently off for anyone
-- already playing.
local function testBagFamilyMigration()
  local db = addon.modules['DB']
  db.sv.version = 1
  db.Profile().categories['Tradeskills.Herbs'].bagFamily = nil
  db.Migrate()
  check('a version-1 profile is migrated to the current schema', db.sv.version, 3)
  check('the preset pairing arrives on the category that has one',
    db.Profile().categories['Tradeskills.Herbs'].bagFamily, 32)
  check('and nothing is invented for the category that has none',
    db.Profile().categories['Tradeskills.Cloth'].bagFamily, nil)
  pipeline.Refresh('migrated')
  check('the migrated profile drives the same count',
    sectionIn(windowIn(pipeline.Model(), 'Tradeskills'), 'Herbs').emptySlots, 5)
end

testBagFamilyMigration()

-- Issue #43: an empty window draws no body — no blank cell, no grid — and its height is floored at the
-- chrome the client's own bag layout needs (constants.WINDOW_CHROME_HEIGHT, measured 95 px). It still
-- draws and still consumes its slot in the column (#28 decision 2).
local function testEmptyWindowCollapses()
  local db = addon.modules['DB']
  local PADDING = 8 -- constants.WINDOW_PADDING
  local CHROME = 95 -- constants.WINDOW_CHROME_HEIGHT

  check('disabling Tools empties its window', db.SetCategoryEnabled('Tools', false), true)
  pipeline.Refresh('empty-tools')
  local collapsed = windowIn(pipeline.Model(), 'Tools')
  check('the empty window is still in the model', collapsed ~= nil, true)
  check('it has no sections', #collapsed.sections, 0)
  check('it is its chrome height, not chrome plus a body cell', collapsed.height, CHROME)
  check('it keeps its full width', collapsed.width, 5 * CELL + 2 * PADDING)
  check('and it draws no cell', collapsed.emptyOffsetY, nil)

  -- The negative half: items are content, and the window is sized for them again, above the floor.
  check('re-enabling Tools is a change', db.SetCategoryEnabled('Tools', true), true)
  pipeline.Refresh('tools-back')
  local full = windowIn(pipeline.Model(), 'Tools')
  check('the window expands back for its two items', full.height, TITLE + (18 + CELL) + 6 + PADDING)

  -- The floor does not eat the bands a window with content carries.
  local flow = addon.modules['Flow']
  local one = { { items = { { itemID = 1 } } } }
  local money = flow.Layout({ id = 'm', name = 'm', columns = 5, showMoney = true, sections = one })
  local plain = flow.Layout({ id = 'p', name = 'p', columns = 5, sections = one })
  check('a window with content still reserves the money bar it carries', money.height - plain.height, MONEY)
  check('and the floor is the chrome, not a row of slots',
    flow.Layout({ id = 'e', name = 'e', columns = 5, showMoney = true, sections = {} }).height, CHROME)
end

testEmptyWindowCollapses()

-- Issue #38: a vendor or the bank opens our windows instead of Blizzard's bag window, and closing
-- the interaction closes the windows it opened. Blizzard's own panels already open and close its
-- bags around an interaction (MerchantFrame.lua:149/:163, BankFrameTemplates.lua:99/:104), so the
-- only thing changed is who is showing them.
local interactions = addon.modules['Interactions']
local windowFramesStub = addon.modules['WindowFrames']
local combined = _G.ContainerFrameCombinedBags
local individual = _G.ContainerFrame1
local eventsMod = addon.modules['Events']

local function blizzardOpensBags() OpenAllBags() end

local function testVendorOpensOurBags()
  local db = addon.modules['DB']
  db.SetWindowsOpen(false)
  pipeline.Refresh('38-vendor-start')
  blizzardOpensBags()
  check('start state: Blizzard bags shown, ours closed',
    tostring(combined.shown) .. '/' .. #pipeline.Model(), 'true/0')

  eventsMod.Emit('MERCHANT_SHOW')
  check('a vendor opens our windows', #pipeline.Model(), 5)
  check('a vendor hides Blizzard bag window', combined.shown, false)
  check('suppression is on while the vendor is open', interactions.Suppressing(), true)

  -- MerchantFrame_OnShow calls OpenAllBags after the MERCHANT_SHOW event we react to.
  blizzardOpensBags()
  check('Blizzard re-opening its bags in its own OnShow is hidden again', combined.shown, false)
  check('and the individual container frames with it', individual.shown, false)
  check('and the frames past NUM_TOTAL_BAG_FRAMES — the backpack, keyring and specialty bag windows',
    _G.ContainerFrame6.shown, false)

  eventsMod.Emit('MERCHANT_CLOSED')
  check('closing the vendor hides the windows it opened', windowFramesStub.hides, 1)
  pipeline.Refresh('38-after-vendor')
  check('and no refresh brings them back', #pipeline.Model(), 0)
  check('suppression is off once the vendor is closed', interactions.Suppressing(), false)

  blizzardOpensBags()
  check('outside an interaction Blizzard keeps its bags', combined.shown, true)
  check('and the individual frames too', individual.shown, true)
end

testVendorOpensOurBags()

-- The negative half: windows the player opened themselves are not the interaction's to close.
local function testInteractionLeavesPlayerWindowsAlone()
  local db = addon.modules['DB']
  db.SetWindowsOpen(true)
  pipeline.Refresh('38-player-open')
  local hides = windowFramesStub.hides
  eventsMod.Emit('MERCHANT_SHOW')
  check('a vendor does not re-open or re-close what the player already opened',
    windowFramesStub.hides - hides, 0)
  eventsMod.Emit('MERCHANT_CLOSED')
  check('closing the vendor leaves the player windows open', #pipeline.Model(), 5)
  check('and nothing was hidden on the way out', windowFramesStub.hides - hides, 0)
end

testInteractionLeavesPlayerWindowsAlone()

-- The bank, including the ordering measured on issue #9: a BANKFRAME_CLOSED lands immediately
-- before the BANKFRAME_OPENED that opens it.
local function testBankOpensOurBags()
  local db = addon.modules['DB']
  db.SetWindowsOpen(false)
  pipeline.Refresh('38-bank-start')
  blizzardOpensBags()
  eventsMod.Emit('BANKFRAME_CLOSED')
  check('the stray BANKFRAME_CLOSED before an opening opens nothing', #pipeline.Model(), 0)
  eventsMod.Emit('BANKFRAME_OPENED')
  check('the bank opens our windows, backpack mirrors included', #pipeline.Model(), 10)
  check('and hides Blizzard bag window', combined.shown, false)
  eventsMod.Emit('BANKFRAME_CLOSED')
  check('closing the bank hides the windows it opened', windowFramesStub.hides, 2)
  pipeline.Refresh('38-after-bank')
  check('and no refresh brings them back', #pipeline.Model(), 0)
end

testBankOpensOurBags()

-- Hard rule 2: Blizzard's container frames are Blizzard's to hide during a combat lockdown. Ours
-- still open — the render half is already deferred by core/init.lua.
local function testNoHidingInCombat()
  local db = addon.modules['DB']
  db.SetWindowsOpen(false)
  pipeline.Refresh('38-combat-start')
  blizzardOpensBags()
  _G.InCombatLockdown = function() return true end
  eventsMod.Emit('BANKFRAME_OPENED')
  check('a bank opened in combat still opens our windows', #pipeline.Model(), 10)
  check('and leaves Blizzard bag window shown', combined.shown, true)
  blizzardOpensBags()
  check('the OpenAllBags hook hides nothing during lockdown either', combined.shown, true)
  _G.InCombatLockdown = function() return false end
  eventsMod.Emit('BANKFRAME_CLOSED')
end

testNoHidingInCombat()

-- Issue #47: the bank half of the window set. Every preset backpack window has a bank twin with the
-- same sections and the same category bindings, and the twins exist only while the bank is open:
-- harvest drops containers 6..14 on BANKFRAME_CLOSED, so a bank window after that frames nothing
-- (AC-13).
local function countKind(windows, kind)
  local n = 0
  for _, window in ipairs(windows) do
    if window.kind == kind then n = n + 1 end
  end
  return n
end

--- A saved window config's section list as `categories,categories,...` — the copy half of #47,
--- read off the profile rather than off a model that has already dropped the empty sections.
local function configBinds(windows, name)
  for _, window in ipairs(windows) do
    if window.name == name then
      local out = {}
      for _, section in ipairs(window.sections or {}) do
        out[#out + 1] = table.concat(section.categories, '+')
      end
      return table.concat(out, ',')
    end
  end
  return 'no such window'
end

--- How many of a window's drawn items came out of a bank container (index 6 and up).
local function bankItemsIn(window)
  local n = 0
  for _, section in ipairs(window.sections) do
    for _, item in ipairs(section.items) do
      if item.bagID >= 6 then n = n + 1 end
    end
  end
  return n
end

local function testBankWindows()
  local db = addon.modules['DB']
  db.SetWindowsOpen(true)
  pipeline.Refresh('47-bank-closed')

  check('the preset carries a bank twin for every backpack window',
    countKind(db.Windows(), 'bank') .. '/' .. countKind(db.Windows(), 'backpack'), '5/5')
  check('a closed bank harvests no bank container', containerAt(6), nil)
  check('and the model holds the five backpack windows only', #pipeline.Model(), 5)

  eventsMod.Emit('BANKFRAME_OPENED')
  check('the bank open puts the 48-slot grid in the harvest', containerAt(6) and containerAt(6).slots, 48)
  check('and the bank bag slots with it',
    tostring(containerAt(7) and containerAt(7).kind or 'none') .. '/'
      .. tostring(containerAt(14) or 'none'),
    'bank/none')
  local models = pipeline.Model()
  check('and the five bank twins in the model', #models, 10)

  local bank = windowIn(models, 'Bank')
  check('the mirror of the default backpack is a bank window', bank.kind, 'bank')
  -- The copy is a config fact: same sections, same bindings, same order. Which of them get drawn is
  -- a content fact, and the bank holds different content.
  check('it copies the default backpack sections and bindings',
    configBinds(db.Windows(), 'Bank'), configBinds(db.Windows(), 'Backpack'))
  check('the bank Tradeskills window copies the backpack one',
    configBinds(db.Windows(), 'Bank Tradeskills'), configBinds(db.Windows(), 'Tradeskills'))
  check('and draws only the sections the bank has content for', binds(bank), 'Junk,__catchall')

  check('bank junk lands in the bank window', placeIn(models, 1007), 'Bank/Junk')
  check('a bank weapon falls to the bank window catch-all', placeIn(models, 1009), 'Bank/Everything else')
  check('bank ore lands in the bank Tradeskills window', placeIn(models, 1008), 'Bank Tradeskills/Ore')
  check('a bank herb lands in the bank Herbs section', placeIn(models, 1010), 'Bank Tradeskills/Herbs')
  check('no backpack window leaks a bank item',
    bankItemsIn(windowIn(models, 'Backpack')) + bankItemsIn(windowIn(models, 'Tradeskills')), 0)
  check('opening the bank leaves the backpack windows the size they were',
    windowIn(models, 'Backpack').height, TITLE + 3 * (18 + CELL) + 3 * 6 + CELL + 8 + MONEY)

  -- The bag-level chrome (#42, #36) stays on the backpack side: a coin row on a bank window reads
  -- as a second purse, and the free-slot count is the player's bags, not the bank's.
  local carriers = {}
  for _, window in ipairs(models) do
    if window.showMoney then carriers[#carriers + 1] = window.name end
  end
  check('exactly one window carries the money bar, and no bank window does',
    table.concat(carriers, ','), 'Backpack')
  check('a bank window carries no bag-set count', bank.emptySlots, nil)
  check('the bag-set count still covers only the player bags',
    windowIn(models, 'Backpack').emptySlots, 21)
  check('and its cell still points at a slot in the player bags',
    harvest.FirstFreeSlot().bagID .. ':' .. harvest.FirstFreeSlot().slot, '0:12')
  check('a bank window is sized without the money band', bank.height, TITLE + 2 * (18 + CELL) + 2 * 6 + 8)

  -- Issue #44's count on the bank side: a section counts the bag of its family **on its own side**,
  -- so the two herb bags never add up into one number.
  local bankHerbs = sectionIn(windowIn(models, 'Bank Tradeskills'), 'Herbs')
  local backpackHerbs = sectionIn(windowIn(models, 'Tradeskills'), 'Herbs')
  check('the bank herb bag feeds the bank side', harvest.FreeSlotsForFamily(32, 'bank'), 9)
  check('the equipped herb bag feeds the backpack side alone',
    harvest.FreeSlotsForFamily(32, 'backpack'), 5)
  check('the bank Herbs section carries its own count', bankHerbs.emptySlots, 9)
  check('the backpack Herbs section carries 5, not the 14 both bags together make',
    backpackHerbs.emptySlots, 5)
  check('the bank cell points in the bank bag, not the equipped one',
    bankHerbs.emptySlot.bagID .. ':' .. bankHerbs.emptySlot.slot, '8:2')
  check('the backpack cell still points in the equipped bag',
    backpackHerbs.emptySlot.bagID .. ':' .. backpackHerbs.emptySlot.slot, '2:2')

  -- #43 in the bank: a bank window with nothing in it still draws, at its chrome floor.
  check('an empty bank window collapses to its chrome',
    windowIn(models, 'Bank Consumables').height, 95)

  eventsMod.Emit('BANKFRAME_CLOSED')
  check('closing the bank drops the bank containers', containerAt(6), nil)
  check('and every bank window leaves the model', #pipeline.Model(), 5)
  check('the backpack windows are back where they were',
    windowIn(pipeline.Model(), 'Backpack').emptySlots, 21)
end

testBankWindows()

for _, failure in ipairs(failures) do
  print('FAIL ' .. failure)
end
print(string.format('selftest: %d checks, %d failures', checks, #failures))
os.exit(#failures == 0 and 0 or 1)
