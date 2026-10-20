-- Phase 8, windows. The shell is the client's own bag window template
-- (ContainerFrameTemplate inherits PortraitFrameFlatTemplate on this client), so our windows
-- look like the game's bags and a skinning addon treats them the same way (FR-49).
--
-- Default position comes from the client's own bag window (FR-41): the stack starts at its
-- bottom-right corner. A dragged window stores its own point and keeps it.

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

--- The client's own bag window, and the corner of it our stack starts from. Measured 2026-10-20
--- (issue #28): the bag **bar** is the wrong anchor. Camelot's bar is configurable — set to vertical
--- it puts `BagsBar:GetTop()` at 317, so the stack started 317 px up the screen, flush to the right
--- edge with no margin. Bottom-right to the client's bag window bottom-right follows the window
--- rather than a bar the player rearranged, but the client's own margin from the screen edge is not
--- enough on its own — see MARGIN below.
--- `ContainerFrameCombinedBags` is a frame, not `ContainerFrameSettingsManager`: hard rule 8 forbids
--- the manager, not reading a global frame's coordinates.
local function anchorFrame()
  local bag = _G.ContainerFrameCombinedBags
  if bag and bag:IsShown() then return bag, 'BOTTOMRIGHT', bag:GetBottom() end
  -- shortcut: no client bag window to copy (another addon hides it — FR-51). Sit above the backpack
  -- button instead, which is at least where the player's bags are.
  local button = _G.MainMenuBarBackpackButton
  if button then return button, 'TOPRIGHT', button:GetTop() end
end

--- Place the whole model in one pass (FR-41, issue #28). The allowance is measured off the corner we
--- actually start from — Blizzard's CONTAINER_OFFSET_Y = 85 is an offset for its own bottom-right
--- start, not a number that transfers.
---@param models BoSWindowModel[]
function windows.Layout(models)
  local _, _, allowance = anchorFrame()
  -- shortcut: heights are compared unscaled while each window applies its own scale. Whether a fit
  -- scale and a per-window scale coexist is #18's product decision.
  anchors.Place(models, GetScreenHeight(), allowance or 0)
end

--- A gap from the screen edge. Matching the client's corner alone leaves us as flush as its bags
--- are: Blizzard's own floor for that gap is `GetInitialContainerFrameOffsetX()` = right action bar
--- width + 10, and with no right action bars that is 10 px.
local MARGIN = 10

local function defaultAnchor(frame, model)
  local anchor, corner = anchorFrame()
  if anchor then
    frame:SetPoint('BOTTOMRIGHT', anchor, corner, (model.x or 0) - MARGIN, model.y or 0)
  else
    -- shortcut: no bag window and no backpack button (UI addon removed both), fixed screen spot.
    frame:SetPoint('BOTTOMRIGHT', UIParent, 'BOTTOMRIGHT', (model.x or 0) - MARGIN, 20 + (model.y or 0))
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
