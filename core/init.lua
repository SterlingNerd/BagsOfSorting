-- Wiring: what loads, what listens, and the slash command that doubles as the Forever fact
-- verification tool (docs/06 M0).

local _, addon = ...

---@class Init: BoSModule
local init = addon:NewModule('Init')

local log = addon:GetModule('Log')
local events = addon:GetModule('Events')
local client = addon:GetModule('Client')
local context = addon:GetModule('Context')
local db = addon:GetModule('DB')
local harvest = addon:GetModule('Harvest')
local enrich = addon:GetModule('Enrich')
local pipeline = addon:GetModule('Pipeline')
local windows = addon:GetModule('WindowFrames')
local options = addon:GetModule('AddonOptions')
local itemFrames = addon:GetModule('ItemFrames')
local pool = addon:GetModule('Pool')
local diag = addon:GetModule('Diag')
local keybinds = addon:GetModule('Keybinds')

init.started = false

local function printLines(lines)
  for _, line in ipairs(lines) do print(line) end
end

---@param models BoSWindowModel[]
---@param shown table<string, boolean>
---@param ctx BoSContext
local function render(models, shown, ctx)
  if InCombatLockdown() then
    -- Painting is what the client blocks during lockdown (SetItemLocation on a secure ItemButton),
    -- so a window keeps whatever it last showed and re-renders on regen (docs/07 Q23).
    windows.ShowPainted()
    log.Debug('combat lockdown: render deferred to regen')
    return
  end
  for index, model in ipairs(models) do
    windows.Render(model, index)
  end
  windows.Prune(shown)
  context.MarkPhase(ctx, 'render')
  context.Finish(ctx)
  -- Bench refreshes are a synthetic loop (probe 13 runs 1000 of them); logging each one buries the
  -- chat capture in identical lines.
  if ctx.reason ~= 'bench' then log.Debug(context.Format(ctx)) end
end

events.On('BOS_REFRESH_DONE', render)

local function listen()
  -- A loot burst is one refresh, not twenty (docs/03 §The pipeline).
  events.Bucket('BAG_UPDATE', 0.2, function() pipeline.Refresh('bag-update') end)
  events.On('BAG_CONTAINER_UPDATE', function()
    harvest.Invalidate()
    pipeline.Refresh('container')
  end)
  events.On('PLAYER_EQUIPMENT_CHANGED', function()
    harvest.Invalidate()
    pipeline.Refresh('equipment')
  end)
  -- Tier-3 answers re-classify through the same bucketed path (FR-26's entry point).
  events.Bucket('BOS_ITEM_DATA', 0.3, function() pipeline.Refresh('item-data') end)
  events.On('ITEM_DATA_LOAD_RESULT', function(itemID, success)
    if enrich.OnItemDataLoaded(itemID, success) then
      events.Emit('BOS_ITEM_DATA')
    end
  end)
  events.On('BOS_MODEL_CHANGED', function() pipeline.Refresh('model') end)
  -- Everything a lockdown deferred lands here (docs/07 Q23).
  events.On('PLAYER_REGEN_ENABLED', function()
    windows.FlushReleases()
    pipeline.Refresh('regen')
  end)
end

function init.Start()
  if init.started then return end
  init.started = true

  -- Insurance for the one measured case where the client drops our binding: it re-applies our
  -- copy only when the client holds none (issue #13).
  keybinds.Restore()
  harvest.Discover()
  -- Pre-warm the button pool from the real inventory so a combat loot event does not have to
  -- create a secure button (agents.md hard rule 3).
  itemFrames.Warm(math.min(200, #harvest.Items() + 20))

  listen()
  pipeline.Refresh('login')
end

--- Plain-frame deferral, never an AceEvent-mediated one (agents.md §Debugging).
function init.Enable()
  if InCombatLockdown() then
    log.Debug('combat lockdown, deferring enable until PLAYER_REGEN_ENABLED')
    local f = CreateFrame('Frame')
    f:RegisterEvent('PLAYER_REGEN_ENABLED')
    f:SetScript('OnEvent', function(self)
      self:UnregisterAllEvents()
      init.Enable()
    end)
    return
  end
  init.Start()
end

---@return boolean
function init.IsShowing()
  return windows.Count() > 0
end

function init.Show()
  db.SetWindowsOpen(true)
  if InCombatLockdown() then
    -- Bags must be reachable in combat; only the painting is blocked (docs/07 Q23).
    windows.ShowPainted()
    log.Debug('combat lockdown: showing the last painted windows until regen')
  else
    pipeline.Refresh('show')
  end
end

function init.Toggle()
  if init.IsShowing() then
    db.SetWindowsOpen(false)
    windows.HideAll()
  else
    init.Show()
  end
end

local HELP = {
  '/bos               client capability dump + harvested containers',
  '/bos perf          last refresh timings, pool and item-cache stats',
  '/bos test          pending manual tests, then the helper names',
  '/bos test <id>     the run sheet for one test (the id is the issue it answers)',
  '/bos test <id><l>  run one captured step of that test, e.g. /bos test 15b',
  '/bos test <name>   a helper on its own: dump · log · flags · keybind · newitem · clock · expansion',
  '/bos find <id>     which container index holds that item',
  '/bos refresh       re-run the pipeline',
  '/bos show|hide     show or hide the sorting windows',
  '/bos debug         toggle debug logging',
}

---@param input string?
function init.Slash(input)
  local cmd = ((input or ''):match('^(%S+)') or ''):lower()

  if cmd == 'perf' then
    local ctx = pipeline.Last()
    print(ctx and context.Format(ctx) or 'no refresh has run yet')
    print(pool.Stats())
    print(enrich.Stats())
  elseif cmd == 'test' then
    diag.Command((input or ''):match('^%s*test%s*(.*)$'))
  elseif cmd == 'find' then
    diag.Find(tonumber((input or ''):match('(%d+)')))
  elseif cmd == 'refresh' then
    pipeline.Refresh('slash')
  elseif cmd == 'show' then
    init.Show()
  elseif cmd == 'hide' then
    db.SetWindowsOpen(false)
    windows.HideAll()
  elseif cmd == 'debug' then
    local settings = db.Settings()
    settings.debug = not settings.debug
    log.SetDebug(settings.debug)
    print('debug ' .. tostring(settings.debug))
  elseif cmd == 'help' then
    printLines(HELP)
  else
    print(string.format('%s %s', addon.title, addon.version))
    printLines(client.Probe())
    print('containers:')
    printLines(harvest.Summary())
  end
end

SLASH_BAGSOFsorting1 = '/bos'
SlashCmdList['BAGSOFsorting'] = init.Slash

events.On('ADDON_LOADED', function(loaded)
  if loaded ~= addon.name then return end
  db.Initialize()
  options.Register()
end)

events.On('PLAYER_LOGIN', init.Enable)

return init
