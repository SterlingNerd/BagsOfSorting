-- SavedVariables + our own profile store (docs/04). No library.
--
-- Rule of the schema: config is persisted, derived state is not. The only derived thing we
-- write is the item cache (FR-109), and it lives in its own table.
--
-- shortcut: only the shared Default profile is read in the prototype; FR-91 per-character
-- overrides (Default + differences) arrive with the profiles UI at M5. The `profiles` table
-- shape is already the final one, so that is a reader change, not a schema change.

local _, addon = ...

---@class DB: BoSModule
local db = addon:NewModule('DB')

local log = addon:GetModule('Log')
local constants = addon:GetModule('Constants')

local BAG = constants.BAG_FAMILY

db.CURRENT_VERSION = 3

---@class BoSSettings
-- Only settings something actually reads are present (FR-80: a setting with no UI home is
-- not added). The rest of docs/04 §settings arrives with the pane that edits it.
local DEFAULT_SETTINGS = {
  sorting = {
    item = 'nameThenQuality',   -- FR-46: nameThenQuality | qualityThenName | ilvl | expansion
  },
  debug = false,
}

--- One tradeskill category: `type = "Trade Goods"` and one of these `subtype` strings. They all
--- share priority 15 because each accepts a disjoint set of subtypes, so no item can reach a
--- second one. `type` is pinned on purpose — 'Cloth' and 'Leather' are Armor subtypes too, and
--- without it a cloth shirt sorts as tailoring material.
---
--- `bagFamily` (issue #44) is the specialty bag the category pairs with for its own free-slot
--- count: the Herbs section counts the herb bag's empty slots. It is left off where the client has
--- no bag of that trade to count — Cloth and Cooking have a subtype each and no bag of their own.
local function tradeskill(subtypes, bagFamily)
  local anySubtype = { op = 'any', children = {} }
  for _, subtype in ipairs(subtypes) do
    anySubtype.children[#anySubtype.children + 1] = { field = 'subtype', cmp = '=', value = subtype }
  end
  return {
    priority = 15, kind = 'rules', enabled = true, duplicate = false,
    bagFamily = bagFamily,
    rules = { op = 'all', children = { { field = 'type', cmp = '=', value = 'Trade Goods' }, anySubtype } },
  }
end

--- The M1/M2 layout, written as data so the schema is exercised from day one (docs/06 M1).
--- Array order in `windows` IS screen order, bottom-most first (issue #28 decision 4).
local DEFAULT_PROFILE = {
  windows = {
    {
      id = 'w1',
      name = 'Backpack',
      kind = 'backpack',
      priority = 1,
      openWithAll = true,
      columns = 5,
      compact = false,
      scale = 1.0,
      sections = {
        { id = 's1', name = 'Junk', categories = { 'Junk' } },
        { id = 's2', name = 'Armor', categories = { 'Armor' } },
        { id = 's3', name = 'Everything else', categories = { '__catchall' } },
      },
    },
    {
      id = 'w2',
      name = 'Quests',
      kind = 'backpack',
      priority = 2,
      openWithAll = true,
      columns = 5,
      compact = false,
      scale = 1.0,
      sections = {
        { id = 's4', name = 'Quest Items', categories = { 'Quest Items' } },
      },
    },
    -- Issue #41: Consumables and Tradeskills go between Quests and Tools. Array order IS screen
    -- order, so they are inserted here rather than appended and re-sorted. Window ids stay put.
    {
      id = 'w4',
      name = 'Consumables',
      kind = 'backpack',
      priority = 3,
      openWithAll = true,
      columns = 5,
      compact = false,
      scale = 1.0,
      sections = {
        { id = 's6', name = 'Consumables', categories = { 'Consumables' } },
      },
    },
    {
      id = 'w5',
      name = 'Tradeskills',
      kind = 'backpack',
      priority = 4,
      openWithAll = true,
      columns = 5,
      compact = false,
      scale = 1.0,
      -- One section per tradeskill (FR-11). flow.Layout drops the sections with nothing in them,
      -- so a character carrying only herbs gets one header here, not seven.
      sections = {
        { id = 's7', name = 'Herbs', categories = { 'Tradeskills.Herbs' } },
        { id = 's8', name = 'Ore', categories = { 'Tradeskills.Ore' } },
        { id = 's9', name = 'Leather', categories = { 'Tradeskills.Leather' } },
        { id = 's10', name = 'Cloth', categories = { 'Tradeskills.Cloth' } },
        { id = 's12', name = 'Elements', categories = { 'Tradeskills.Elements' } },
        { id = 's13', name = 'Engineering', categories = { 'Tradeskills.Parts' } },
        { id = 's14', name = 'Cooking', categories = { 'Tradeskills.Cooking' } },
      },
    },
    {
      id = 'w3',
      name = 'Tools',
      kind = 'backpack',
      priority = 5,
      openWithAll = true,
      columns = 5,
      compact = false,
      scale = 1.0,
      sections = {
        { id = 's5', name = 'Tools', categories = { 'Tools' } },
      },
    },
    -- Issue #47: the bank half, a copy of the five windows above with `kind = "bank"` — same
    -- sections, same bindings, same order. They only reach the screen while the bank is open
    -- (FR-13, AC-13; data/pipeline.lua is the gate).
    -- shortcut: a literal copy rather than a copy command. `window.copy` (FR-10b) and linked windows
    -- (FR-10c) are what make a user's own windows copy and stay in step; until then a bank window
    -- diverges by hand.
    {
      id = 'w6',
      name = 'Bank',
      kind = 'bank',
      priority = 6,
      openWithAll = true,
      columns = 5,
      compact = false,
      scale = 1.0,
      sections = {
        { id = 's16', name = 'Junk', categories = { 'Junk' } },
        { id = 's17', name = 'Armor', categories = { 'Armor' } },
        { id = 's18', name = 'Everything else', categories = { '__catchall' } },
      },
    },
    {
      id = 'w7',
      name = 'Bank Quests',
      kind = 'bank',
      priority = 7,
      openWithAll = true,
      columns = 5,
      compact = false,
      scale = 1.0,
      sections = {
        { id = 's19', name = 'Quest Items', categories = { 'Quest Items' } },
      },
    },
    {
      id = 'w8',
      name = 'Bank Consumables',
      kind = 'bank',
      priority = 8,
      openWithAll = true,
      columns = 5,
      compact = false,
      scale = 1.0,
      sections = {
        { id = 's20', name = 'Consumables', categories = { 'Consumables' } },
      },
    },
    {
      id = 'w9',
      name = 'Bank Tradeskills',
      kind = 'bank',
      priority = 9,
      openWithAll = true,
      columns = 5,
      compact = false,
      scale = 1.0,
      sections = {
        { id = 's21', name = 'Herbs', categories = { 'Tradeskills.Herbs' } },
        { id = 's22', name = 'Ore', categories = { 'Tradeskills.Ore' } },
        { id = 's23', name = 'Leather', categories = { 'Tradeskills.Leather' } },
        { id = 's24', name = 'Cloth', categories = { 'Tradeskills.Cloth' } },
        { id = 's25', name = 'Elements', categories = { 'Tradeskills.Elements' } },
        { id = 's26', name = 'Engineering', categories = { 'Tradeskills.Parts' } },
        { id = 's27', name = 'Cooking', categories = { 'Tradeskills.Cooking' } },
      },
    },
    {
      id = 'w10',
      name = 'Bank Tools',
      kind = 'bank',
      priority = 10,
      openWithAll = true,
      columns = 5,
      compact = false,
      scale = 1.0,
      sections = {
        { id = 's28', name = 'Tools', categories = { 'Tools' } },
      },
    },
  },
  categories = {
    -- Priority is the ladder the classifier walks, ascending (docs/04 §Precedence 1). A quest item
    -- must never fall to a generic rule, and a curated manual list beats a generic rule too.
    ['Quest Items'] = {
      priority = 5,
      kind = 'rules',
      enabled = true,
      duplicate = false,
      -- The same flag the tooltip's red "Quest item" line comes from: the harvest reads it from
      -- C_Container.GetContainerItemQuestInfo, not from the tooltip.
      rules = { op = 'all', children = { { field = 'isQuestItem', cmp = '=', value = true } } },
    },
    ['Tools'] = {
      priority = 8,
      kind = 'manual',
      enabled = true,
      duplicate = false,
      itemIDs = { [2901] = true, [6948] = true },   -- Mining Pick, Hearthstone
    },
    ['Junk'] = {
      priority = 10,
      kind = 'rules',
      enabled = true,
      duplicate = false,
      rules = { op = 'all', children = { { field = 'quality', cmp = '=', value = 0 } } },
    },
    -- Issue #41's priority rule: Consumables outranks every tradeskill category, so a potion
    -- crafted from herbs lands with the potions and not with the herbs. The class name is the
    -- client's own — measured 2026-10-20 off the persisted item cache, where Minor Healing Potion
    -- (118) reads type "Consumable" / subtype "Potions", Refreshing Spring Water (159) "Food &
    -- Drink" and Linen Bandage (1251) "Bandages". One rule over the whole class covers all three
    -- plus the subtypes this character carries nothing of (flasks, elixirs, scrolls).
    ['Consumables'] = {
      priority = 12,
      kind = 'rules',
      enabled = true,
      duplicate = false,
      rules = { op = 'all', children = { { field = 'type', cmp = '=', value = 'Consumable' } } },
    },
    -- Every subtype here is measured. `/bos test 41` (2026-10-20, build 1.60.1 70450) dumped the
    -- client's own tables: Trade Goods has subclasses Parts, Cloth, Leather, Metal & Stone, Cooking,
    -- Herb, Elemental, Other and Enchanting; Consumable has Potions, Elixirs, Flasks, Draughts,
    -- Scrolls, Food & Drink, Bandages, Explosives, Devices, Permanent and Other — so the one
    -- `type = "Consumable"` rule above covers every consumable the issue names.
    --
    -- No Gems category: subclass 4 (Jewelcrafting) is **absent** from this client's Trade Goods
    -- table and class 3 is `Jewelry(OBSOLETE)`, so there is nothing to match. Where gems actually
    -- live is `/bos test owners`'s to say the moment one is in a bag.
    --
    -- No Alchemy or Inscription category either. Alchemy reagents *are* the Herb and Elemental
    -- subtypes here, and Inscription has no subclass at all — "Alchemy" exists only as a **Recipe**
    -- subtype (class 9), which is the book, not the reagents.
    ['Tradeskills.Herbs'] = tradeskill({ 'Herb' }, BAG.Herb),
    ['Tradeskills.Ore'] = tradeskill({ 'Metal & Stone' }, BAG.Mining),
    ['Tradeskills.Leather'] = tradeskill({ 'Leather' }, BAG.Leatherworking),
    ['Tradeskills.Cloth'] = tradeskill({ 'Cloth' }),
    ['Tradeskills.Elements'] = tradeskill({ 'Elemental', 'Enchanting' }, BAG.Enchanting),
    ['Tradeskills.Parts'] = tradeskill({ 'Parts' }, BAG.Engineering),
    ['Tradeskills.Cooking'] = tradeskill({ 'Cooking' }),
    ['Armor'] = {
      priority = 20,
      kind = 'rules',
      enabled = true,
      duplicate = false,
      rules = { op = 'all', children = { { field = 'type', cmp = '=', value = 'Armor' } } },
    },
    -- FR-16: the catch-all is a real category, not a special-cased code path.
    ['__catchall'] = {
      priority = 999,
      kind = 'rules',
      enabled = true,
      duplicate = false,
      rules = { op = 'all', children = { { field = 'none', cmp = '=', value = true } } },
    },
  },
  settings = DEFAULT_SETTINGS,
}

local function deepCopy(value)
  if type(value) ~= 'table' then return value end
  local copy = {}
  for k, v in pairs(value) do copy[k] = deepCopy(v) end
  return copy
end

--- Migrations are numbered, additive, pure functions over the profile table (docs/04). A preset
--- field added to the schema is backfilled here: a profile written before it existed would leave
--- the feature that reads it silently off for anyone already playing.
local MIGRATIONS = {
  -- Issue #44: the tradeskill presets pair with a specialty bag.
  [2] = function(profile)
    local presetFamilies = {
      ['Tradeskills.Herbs'] = BAG.Herb,
      ['Tradeskills.Ore'] = BAG.Mining,
      ['Tradeskills.Leather'] = BAG.Leatherworking,
      ['Tradeskills.Elements'] = BAG.Enchanting,
      ['Tradeskills.Parts'] = BAG.Engineering,
    }
    for name, family in pairs(presetFamilies) do
      local category = profile.categories and profile.categories[name]
      if category and category.bagFamily == nil then category.bagFamily = family end
    end
  end,

  -- Issue #47: a profile written before the bank windows existed gets the preset bank half. The
  -- guard is what keeps a deliberate deletion from coming back: migrations run once per profile.
  -- shortcut: the preset is copied in rather than derived from the profile's own windows, so a
  -- profile whose backpack windows are not the preset gets preset twins. FR-10b's `window.copy`
  -- (M5 configure mode) is the thing that copies a user's own windows.
  [3] = function(profile)
    profile.windows = profile.windows or {}
    for _, window in ipairs(profile.windows) do
      if window.kind == 'bank' then return end
    end
    for _, preset in ipairs(DEFAULT_PROFILE.windows) do
      if preset.kind == 'bank' then
        profile.windows[#profile.windows + 1] = deepCopy(preset)
      end
    end
  end,
}

function db.Migrate()
  while db.sv.version < db.CURRENT_VERSION do
    local next = db.sv.version + 1
    local migrate = MIGRATIONS[next]
    if not migrate then
      log.Error('no migration for schema version ' .. next .. ', leaving data as-is')
      return
    end
    for _, profile in pairs(db.sv.profiles) do
      migrate(profile)
    end
    db.sv.version = next
  end
end

function db.Initialize()
  BagsOfSortingDB = BagsOfSortingDB or {}
  db.sv = BagsOfSortingDB
  -- A file we created ourselves is already at the current schema; only a file from an older
  -- build of the addon needs migrations run against it.
  db.sv.version = db.sv.version or db.CURRENT_VERSION
  db.sv.global = db.sv.global or {}
  db.sv.profiles = db.sv.profiles or {}
  db.sv.itemCache = db.sv.itemCache or {}

  if not db.sv.profiles.Default then
    db.sv.profiles.Default = deepCopy(DEFAULT_PROFILE)
  end
  db.Migrate()

  local settings = db.Settings()
  for key, value in pairs(DEFAULT_SETTINGS) do
    if settings[key] == nil then settings[key] = deepCopy(value) end
  end
  log.SetDebug(settings.debug)
end

---@return any
function db.Profile()
  return db.sv.profiles.Default
end

---@return BoSSettings
function db.Settings()
  local profile = db.Profile()
  profile.settings = profile.settings or deepCopy(DEFAULT_SETTINGS)
  return profile.settings
end

---@return table<string, any>
function db.Categories()
  return db.Profile().categories
end

---@return any[]
function db.Windows()
  return db.Profile().windows
end

---@return table<number, any>
function db.ItemCache()
  return db.sv.itemCache
end

--- Open or close every window. A closed window is out of the model, so no refresh reopens it;
--- the window's own X writes the same `hidden` flag (FR-41).
---@param open boolean
function db.SetWindowsOpen(open)
  for _, window in ipairs(db.Windows()) do
    -- `open and nil or true` is always true, which is what this avoids: clear the flag or set
    -- it, explicitly.
    if open then
      window.hidden = nil
    else
      window.hidden = true
    end
  end
end

--- `category.setEnabled` (docs/05 §Commands): the model half of "disable this category". A disabled
--- category stops owning items (classify.Ordered skips it) and keeps its data, so re-enabling it
--- puts them back. The category editor row that calls this is M3; until then this is the only way
--- to flip one, and it is what the headless harness exercises.
---@param name string
---@param enabled boolean
---@return boolean changed
function db.SetCategoryEnabled(name, enabled)
  local cat = db.Categories()[name]
  if not cat then return false end
  if (cat.enabled ~= false) == (enabled ~= false) then return false end
  cat.enabled = enabled
  db.NotifyModelChanged()
  return true
end

--- A dragged window keeps its saved point, and that point is the only thing that overrides the
--- layout rule (FR-41). The placement tests need the default placement, so this hands the windows
--- back to it. It clears nothing else: `hidden`, sections and scale stay as they are.
---@return number cleared
function db.ClearPositions()
  local cleared = 0
  for _, window in ipairs(db.Windows()) do
    if window.position then
      window.position = nil
      cleared = cleared + 1
    end
  end
  return cleared
end

--- The layout model changed: ask the pipeline to re-run (FR-26's entry point).
function db.NotifyModelChanged()
  addon:GetModule('Events').Emit('BOS_MODEL_CHANGED')
end

return db
