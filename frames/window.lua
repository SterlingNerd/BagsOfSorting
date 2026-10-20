-- Phase 8, windows. The shell is the client's own bag window template
-- (ContainerFrameTemplate inherits PortraitFrameFlatTemplate on this client), so our windows
-- look like the game's bags and a skinning addon treats them the same way (FR-49).
--
-- Default position comes from the client's bag bar (FR-41): a fresh install lands where the
-- player's bags already are. A dragged window stores its own point and keeps it.

local _, addon = ...

---@class WindowFrames: BoSModule
local windows = addon:NewModule('WindowFrames')

local sectionFrames = addon:GetModule('SectionFrames')
local anchors = addon:GetModule('Anchors')
local log = addon:GetModule('Log')

---@class BoSWindowFrame
---@field frame Frame
---@field sections BoSSectionFrame[]
---@field config any  -- the profile window this frame mirrors, for position persistence

---@type table<string, BoSWindowFrame>
local byId = {}

--- Sections whose release a combat lockdown made us defer.
local pendingRelease = {}

--- The frame our stack hangs from. Camelot's bags bar sits bottom-left and lays its buttons out
--- leftward from the backpack button (MainMenuBarBagButtons.xml: direction = Enum.BagsDirection.Left).
--- We anchor **above the bar**, not on it: BOTTOMLEFT-on-BOTTOMLEFT put the window over the player's
--- bags and the micro bar.
local function anchorFrame()
  return (_G.BagsBar and _G.BagsBar:IsShown() and _G.BagsBar)
    or _G.MainMenuBarBackpackButton
end

--- Place the whole model in one pass (FR-41, issue #28). The allowance is measured off the frame we
--- actually anchor to — Blizzard's CONTAINER_OFFSET_Y = 85 is an offset for its own bottom-right start,
--- not a number that transfers.
---@param models BoSWindowModel[]
function windows.Layout(models)
  local anchor = anchorFrame()
  -- shortcut: heights are compared unscaled while each window applies its own scale. Whether a fit
  -- scale and a per-window scale coexist is #18's product decision.
  anchors.Place(models, GetScreenHeight(), anchor and anchor:GetTop() or 0)
end

local function defaultAnchor(frame, model)
  local anchor = anchorFrame()
  if anchor then
    frame:SetPoint('BOTTOMLEFT', anchor, 'TOPLEFT', model.x or 0, model.y or 0)
  else
    -- shortcut: no bag bar found (UI addon removed it), fall back to a fixed screen spot.
    frame:SetPoint('BOTTOMLEFT', UIParent, 'BOTTOMLEFT', 20 + (model.x or 0), 20 + (model.y or 0))
  end
end

--- A window the player dragged keeps its saved point, and still consumes its slot in the column —
--- excluding dragged windows would make the layout depend on which windows happen to be dragged.
local function restorePosition(frame, model)
  frame:ClearAllPoints()
  local saved = model.config.position
  if saved and saved.point then
    frame:SetPoint(saved.point, UIParent, saved.relativePoint or saved.point, saved.x, saved.y)
  else
    defaultAnchor(frame, model)
  end
end

---@param config any
---@return BoSWindowFrame
local function create(config)
  local frame = CreateFrame('Frame', 'BagsOfSortingWindow' .. config.id, UIParent, 'PortraitFrameFlatTemplate')
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag('LeftButton')
  frame:SetClampedToScreen(true)
  frame:SetFrameStrata('MEDIUM')
  frame:SetScale(config.scale or 1)

  -- The stock X, through the template's own close callback (UIPanelCloseButton_OnClick ->
  -- HideUIPanel). Closing is persisted on the window config, otherwise the next BAG_UPDATE
  -- re-renders it straight back onto the screen. /bos show or the compartment entry reopens it.
  frame.onCloseCallback = function()
    config.hidden = true
    log.Debug('closed window', config.id)
    return true
  end

  frame:SetScript('OnDragStart', frame.StartMoving)
  frame:SetScript('OnDragStop', function(self)
    self:StopMovingOrSizing()
    local point, _, relativePoint, x, y = self:GetPoint()
    self.config.position = { point = point, relativePoint = relativePoint, x = x, y = y }
    log.Debug('saved position for window', self.config.id)
  end)

  local wf = { frame = frame, sections = {}, config = config }
  frame.config = config
  byId[config.id] = wf
  return wf
end

---@param wf BoSWindowFrame
local function releaseSections(wf)
  for i = #wf.sections, 1, -1 do
    sectionFrames.Release(wf.sections[i])
    wf.sections[i] = nil
  end
end

---@param wf BoSWindowFrame
local function hide(wf)
  -- Hiding our own frame is allowed in combat. Releasing pooled ItemButtons is not: reset() calls
  -- SetItemLocation, the client blocks it during lockdown, and the blocked call aborted the hide
  -- before frame:Hide() could run (checklist test 8). Defer the release to regen.
  if InCombatLockdown() then
    pendingRelease[wf] = true
  else
    releaseSections(wf)
  end
  wf.frame:Hide()
end

--- Draw one window from the layout model. Frames are reused across refreshes; only the
--- buttons and section blocks move (AC-42).
---@param model BoSWindowModel
function windows.Render(model)
  local wf = byId[model.id] or create(model.config)
  wf.config = model.config

  local frame = wf.frame
  frame.TitleContainer.TitleText:SetText(model.name)
  frame:SetScale(model.scale or 1)
  frame:SetSize(model.width, model.height)

  for i = #wf.sections + 1, #model.sections do
    wf.sections[i] = sectionFrames.Acquire()
  end
  for i = #model.sections + 1, #wf.sections do
    sectionFrames.Release(wf.sections[i])
    wf.sections[i] = nil
  end

  for i, sectionModel in ipairs(model.sections) do
    sectionFrames.Render(wf.sections[i], sectionModel, frame, sectionModel.offsetY)
  end

  restorePosition(frame, model)
  frame:Show()
  return wf
end

--- Hide windows the model no longer contains (deleted windows, bank windows when closed).
---@param visible table<string, boolean>
function windows.Prune(visible)
  for id, wf in pairs(byId) do
    if not visible[id] then hide(wf) end
  end
end

function windows.HideAll()
  for _, wf in pairs(byId) do hide(wf) end
end

--- Release what a combat lockdown made us defer (agents.md hard rule 3).
function windows.FlushReleases()
  for wf in pairs(pendingRelease) do
    releaseSections(wf)
    pendingRelease[wf] = nil
  end
end

--- Show windows that already have their buttons painted, without touching the buttons.
function windows.ShowPainted()
  for _, wf in pairs(byId) do
    if #wf.sections > 0 and not wf.config.hidden then wf.frame:Show() end
  end
end

---@return number
function windows.Count()
  local n = 0
  for _, wf in pairs(byId) do
    if wf.frame:IsShown() then n = n + 1 end
  end
  return n
end

return windows
