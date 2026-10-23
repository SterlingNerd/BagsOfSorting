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
local moneyFrames = addon:GetModule('MoneyFrames')
local itemFrames = addon:GetModule('ItemFrames')
local constants = addon:GetModule('Constants')
local log = addon:GetModule('Log')

---@class BoSWindowFrame
---@field frame Frame
---@field sections BoSSectionFrame[]
---@field empty BoSItemEntry?  -- the free-slot indicator, on the window the model gave the count to
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

--- The client's own bag chrome (issue #34). `ContainerFrame_OnLoad` applies exactly these to the same
--- template our shell inherits: the small portrait ring (`HeldBagLayout`'s
--- `ui-frame-portraitmetal-cornertopleftsmall`, not the full-size `UI-Frame-PortraitMetal-CornerTopLeft`
--- the plain template picks), a 36x36 icon at (-4, +1), and the title band starting at x=35 so the
--- name clears the portrait instead of sitting under it.
local BAG_PORTRAIT = 'Interface/Icons/Inv_misc_bag_08'  -- what ContainerFrameCombinedBags draws

-- The bank windows' corner icon (issue #47): the icon the client itself reports for the bank's own
-- tab. `C_Bank.FetchPurchasedBankTabData` answers `Tab 1, icon 134400` on this client (docs/07 Q10,
-- `/bos test dump` 2026-10-18), so the corner is the same chest the bank's Page 1 tab draws.
local BANK_PORTRAIT = 134400

-- The bank windows' blue tint (issue #47). The panel background is the client's own panel colour
-- pushed toward blue — red and green scaled down, blue lifted — so a bank window keeps the darkness
-- every other panel has and differs only in hue. The border art (the held-bag ring is its top-left
-- corner piece) takes a multiplier instead: Blizzard's metal is already bright, and the panel colour
-- would only dim it. The blue is a look, not a measurement — `/bos test 47` is the look check.
local BANK_BG_BLUE = 0.16
local BANK_BORDER = { 0.60, 0.75, 1.0 }

--- Everything a window draws sits on this level (issue #34). The shell had no level of its own, so its
--- whole subtree sat at the bottom of the band: Blizzard's action bar (`MainActionBar` frameLevel 50,
--- its EndCaps 100) and bag bar (`BagsBar` 52) drew over our panel background and money bar, Blizzard's
--- own bag buttons (`ContainerFrameItemButtonTemplate` frameLevel 10) tied with ours, and our border
--- art (`NineSlice` 500) drew over theirs. 300 clears every one of those numbers and stays under the
--- template's own chrome — portrait 400, border 500, title and close 510 — so the order inside a window
--- is Blizzard's own: background, content, portrait, border, title.
local CONTENT_BASE = 300

---@param frame Frame
---@param kind string  -- 'backpack' | 'bank' (issue #47)
local function bagChrome(frame, kind)
  -- The template's own OnLoad already drew the full-size ring from its `layoutType` KeyValue, so the
  -- field and the art both have to change.
  frame.layoutType = 'HeldBagLayout'
  frame:SetBorder('HeldBagLayout')
  frame:SetPortraitTextureSizeAndOffset(36, -4, 1)
  frame:SetTitleOffsets(35)
  -- Camelot's `ContainerFrame_UpdatePortraitPosition`: the template's CircleMask is cut for the
  -- 62x62 portrait, so on the 36 one it has to sit flush or it clips the icon.
  local portrait = frame.PortraitContainer.portrait
  local mask = frame.PortraitContainer.CircleMask
  mask:ClearAllPoints()
  mask:SetPoint('TOPLEFT', portrait, 'TOPLEFT', 0, 0)
  mask:SetPoint('BOTTOMRIGHT', portrait, 'BOTTOMRIGHT', 0, 0)
  frame:SetPortraitToAsset(kind == 'bank' and BANK_PORTRAIT or BAG_PORTRAIT)
  -- Shell and background share the base level; content sits above it (frames/section.lua) and the
  -- template's chrome already sits above that. `toplevel` is what Blizzard's own bag window carries
  -- (`ContainerFrame.xml:308`) and what BetterBags' backpack window carries on this client.
  frame:SetFrameLevel(CONTENT_BASE)
  frame:SetToplevel(true)
  frame.Bg:SetFrameLevel(CONTENT_BASE)
  -- The flat panel's TopSection and BottomEdge carry no texture of their own; Blizzard's held-bag
  -- windows hand them PANEL_BACKGROUND_COLOR in `ContainerFrameMixin:UpdateBackground`. Whether the
  -- template's own XML colour is enough for us is what `/bos test 34` reads — issue #34's "too
  -- transparent" is reported against the client's own bag window in the same capture.
  if kind == 'bank' then
    local r, g, b, a = 0.11, 0.10, 0.09, 1
    if PANEL_BACKGROUND_COLOR then r, g, b, a = PANEL_BACKGROUND_COLOR:GetRGBA() end
    frame:SetBackgroundColor(CreateColor(r * 0.55, g * 0.8, math.min(1, b + BANK_BG_BLUE), a))
    frame.NineSlice:SetBorderColor(BANK_BORDER[1], BANK_BORDER[2], BANK_BORDER[3])
  else
    frame:SetBackgroundColor()
  end
end

---@param config any
---@return BoSWindowFrame
local function create(config)
  local frame = CreateFrame('Frame', 'BagsOfSortingWindow' .. config.id, UIParent, 'PortraitFrameFlatTemplate')
  bagChrome(frame, config.kind)
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
--- Release the frames this window holds (buttons only: the shells stay pooled in byId).
---@param wf BoSWindowFrame
local function releaseSections(wf)
  if wf.empty then
    itemFrames.Release(wf.empty)
    wf.empty = nil
    wf.frame.EmptySlot = nil
  end
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

--- The free-slot indicator (issue #36): one slot at the end of the window's column, holding the
--- number of slots the player's bags still have open. Only the window the model gave the count to
--- draws one, and a window that lost the count gives its button back to the pool.
---@param wf BoSWindowFrame
---@param model BoSWindowModel
local function renderEmptySlot(wf, model)
  if not model.emptyOffsetY then
    if wf.empty then
      itemFrames.Release(wf.empty)
      wf.empty = nil
      wf.frame.EmptySlot = nil
    end
    return
  end

  wf.empty = wf.empty or itemFrames.Acquire()
  itemFrames.PaintEmpty(wf.empty, model.emptySlot, model.emptySlots, wf.frame)
  wf.empty.parent:ClearAllPoints()
  wf.empty.parent:SetPoint('TOPLEFT', wf.frame, 'TOPLEFT',
    constants.WINDOW_PADDING, -(constants.WINDOW_TITLE_HEIGHT + model.emptyOffsetY))
  -- The button on the shell is what `/bos test freeslots` reads, the same way the money bar is
  -- frame.MoneyFrame: the capture needs the drawn state, not the model's claim about it.
  wf.frame.EmptySlot = wf.empty.button
end

--- The money bar (issue #42): only the window the model gave it to draws one. The bar is a child of
--- the shell, so it hides with the window and scales with it (FR-48); a window that lost the bar to
--- another one keeps the frame and hides it rather than rebuilding it on every refresh.
---@param wf BoSWindowFrame
---@param model BoSWindowModel
local function renderMoney(wf, model)
  local frame = wf.frame
  if model.showMoney then
    frame.MoneyFrame = frame.MoneyFrame or moneyFrames.Attach(frame)
    frame.MoneyFrame:Show()
  elseif frame.MoneyFrame then
    frame.MoneyFrame:Hide()
  end
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
  -- Issue #31/#43: the client's own answer to a window shorter than its border art — the same call
  -- `ContainerFrameMixin:UpdateFrameSize` makes (`ContainerFrame.lua:992`). Without it every window we
  -- render draws its bottom corners at their full 512 px atlas. Measured 2026-10-20/21 (`/bos test 43`):
  -- the ring renders 95x94 and reaches 79 px below a window's top edge, the LeftEdge/RightEdge come back
  -- 95x0 on every window, and the crop leaves `height + 19 − 90` of bottom corner — 32 px on a 103-tall
  -- window, 100 on a 171-tall one. The crop is capped at the corner's own atlas height (`NineSlice.lua:253`)
  -- and a corner it cannot shrink renders at full size, which is why `constants.WINDOW_CHROME_HEIGHT` is
  -- the floor `layout/flow.lua` measures the height against rather than a shorter window with clipped art.
  NineSliceUtil.UpdateCornerCropping(frame, model.height)

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

  renderEmptySlot(wf, model)
  renderMoney(wf, model)

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
