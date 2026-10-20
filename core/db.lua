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

db.CURRENT_VERSION = 1

---@class BoSSettings
-- Only settings something actually reads are present (FR-80: a setting with no UI home is
-- not added). The rest of docs/04 §settings arrives with the pane that edits it.
local DEFAULT_SETTINGS = {
  sorting = {
    item = 'nameThenQuality',   -- FR-46: nameThenQuality | qualityThenName | ilvl | expansion
  },
  debug = false,
}

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
    {
      id = 'w3',
      name = 'Tools',
      kind = 'backpack',
      priority = 3,
      openWithAll = true,
      columns = 5,
      compact = false,
      scale = 1.0,
      sections = {
        { id = 's5', name = 'Tools', categories = { 'Tools' } },
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

--- Migrations are numbered, additive, pure functions over the profile table (docs/04). There are
--- none: while one user owns every deployed file the schema changes breakingly and the game-side
--- file is deleted out-of-band. Migrations return at M3 (docs/04 §Migration).
local MIGRATIONS = {}

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
