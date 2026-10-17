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
local log = addon:GetModule('Log')

---@class BoSWindowFrame
---@field frame Frame
---@field sections BoSSectionFrame[]
---@field config any  -- the profile window this frame mirrors, for position persistence

---@type table<string, BoSWindowFrame>
local byId = {}

--- Windows stack upward from the bag bar in layout order until the player drags one.
local function defaultAnchor(frame, index)
  local anchor = _G.MainMenuBarBackpackButton or _G.BagsBar
  if anchor then
    frame:SetPoint('BOTTOMLEFT', anchor, 'BOTTOMLEFT', 0, (index - 1) * 40)
  else
    -- shortcut: no bag bar found (UI addon removed it), fall back to a fixed screen spot.
    frame:SetPoint('BOTTOMLEFT', UIParent, 'BOTTOMLEFT', 20, 20 + (index - 1) * 40)
  end
end

local function restorePosition(frame, config, index)
  frame:ClearAllPoints()
  local saved = config.position
  if saved and saved.point then
    frame:SetPoint(saved.point, UIParent, saved.relativePoint or saved.point, saved.x, saved.y)
  else
    defaultAnchor(frame, index)
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

  -- Closing a window is a model edit and the command layer is M3 (docs/06). Until then the
  -- stock close button would be a half-feature, so it is hidden rather than wired.
  if frame.CloseButton then frame.CloseButton:Hide() end

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
  releaseSections(wf)
  wf.frame:Hide()
end

--- Draw one window from the layout model. Frames are reused across refreshes; only the
--- buttons and section blocks move (AC-42).
---@param model BoSWindowModel
---@param index number
function windows.Render(model, index)
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

  restorePosition(frame, model.config, index)
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

---@return number
function windows.Count()
  local n = 0
  for _, wf in pairs(byId) do
    if wf.frame:IsShown() then n = n + 1 end
  end
  return n
end

return windows
