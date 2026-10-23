-- What our windows do when the client opens one of its own interaction windows (issue #38).
--
-- A vendor and the bank both open Blizzard's bag window on top of ours: `MerchantFrame_OnShow`
-- calls the global `OpenAllBags(self, true)` (`origin/forever`
-- Blizzard_UIPanels_Game/Mainline/MerchantFrame.lua:149) and `BankFrameBaseMixin:OnShow` calls
-- `OpenAllBags(self)` (`Mainline/BankFrameTemplates.lua:99`). Both close them again on hide
-- (`MerchantFrame.lua:163`, `BankFrameTemplates.lua:104`), so the client already treats "an
-- interaction window is open" as "the bags are open".
--
-- The rule is the narrow one: **while one of those windows is open and our windows are shown,
-- Blizzard's bag windows stay closed and ours are open.** Measured on the live client 2026-10-22
-- (`/bos test 38`): a vendor and the bank both land on `our windows shown 5` with
-- `ContainerFrameCombinedBags` closed, and closing either lands on ours closed. A deliberate open —
-- whatever key the player has bound to `OPENALLBAGS` (on the test account that is CTRL-B; plain B is
-- ours) or a bag-bar click — goes through `ToggleAllBags`, not `OpenAllBags`
-- (`Blizzard_MainMenuBarBagButtons/Shared/MainMenuBarBagButtons.lua:74,168`), so it is left alone and
-- the player can still reach the real bags at any time (FR-51).
--
-- docs/07 Q4 option B: we never replace Blizzard's bag functions. `hooksecurefunc` observes the
-- call and never changes what it does.

local _, addon = ...

---@class Interactions: BoSModule
local interactions = addon:NewModule('Interactions')

local db = addon:GetModule('DB')
local events = addon:GetModule('Events')
local constants = addon:GetModule('Constants')
local log = addon:GetModule('Log')
local harvest = addon:GetModule('Harvest')
local pipeline = addon:GetModule('Pipeline')
local windows = addon:GetModule('WindowFrames')

-- True while Blizzard's bag windows must stay closed.
local suppressing = false
-- True when an interaction is what opened our windows, so closing it is what closes them. Windows
-- the player had already open are left where the player left them.
local openedForInteraction = false

--- Blizzard's own bag windows: the combined window, plus the individual container frames it uses
--- when the player has switched combined bags off. Reading and hiding a global frame is allowed;
--- calling `ContainerFrameSettingsManager` to find out which frames exist is not (hard rule 8), so
--- the list is the frame names FrameXML itself uses (`ContainerFrame.lua:141`).
local function hideBlizzardBags()
  if InCombatLockdown() then
    -- Hard rule 2: in combat Blizzard's container frames are Blizzard's to show and hide.
    log.Debug('combat lockdown: leaving Blizzard bag windows alone')
    return
  end

  local combined = _G.ContainerFrameCombinedBags
  if combined and combined:IsShown() then combined:Hide() end
  -- NUM_CONTAINER_FRAMES, not NUM_TOTAL_BAG_FRAMES: Blizzard numbers its container frames over the
  -- bag slots **plus the backpack plus the keyring** (`ContainerFrame.lua:8-11`) and iterates that
  -- same range itself (`:140`). Bounded at NUM_TOTAL_BAG_FRAMES = 5 the loop missed frame 6, and the
  -- live client showed the tradeskill bag window stay open at a vendor (issue #38, 2026-10-22).
  for i = 1, NUM_CONTAINER_FRAMES or (constants.NUM_TOTAL_EQUIPPED_BAG_SLOTS + 2) do
    local frame = _G['ContainerFrame' .. i]
    if frame and frame:IsShown() then frame:Hide() end
  end
end

--- Our windows are open when the model has a window the player has not closed. This is the same
--- flag `pipeline.Assign` filters on, so the answer cannot disagree with what is rendered.
---@return boolean
local function windowsOpen()
  for _, window in ipairs(db.Windows()) do
    if not window.hidden then return true end
  end
  return false
end

local function onOpen()
  local opening = not windowsOpen()
  if opening then db.SetWindowsOpen(true) end
  if not windowsOpen() then return end  -- a profile with no windows: leave Blizzard's bags alone
  -- shortcut: an interaction opens our windows whenever none are open, so a player who chose
  -- `/bos hide` gets them back at the next vendor. The answer is FR-51's vanilla/sorting toggle, not
  -- a second flag (issue #38).

  -- Hide before the caller refreshes. The stack anchors off Blizzard's bag window while it is shown,
  -- so a refresh placed before the hide lays the windows out against one corner and the next one
  -- against another.
  suppressing = true
  hideBlizzardBags()
  if opening then openedForInteraction = true end
end

local function onClose(reason)
  suppressing = false
  if not openedForInteraction then return end
  openedForInteraction = false
  -- The same pair `/bos hide` and the keybind use: the flag keeps the next refresh from reopening
  -- them, the hide takes them off screen now.
  db.SetWindowsOpen(false)
  windows.HideAll()
  log.Debug('interaction closed: ' .. reason)
end

events.On('MERCHANT_SHOW', function()
  onOpen()
  pipeline.Refresh('merchant')
end)
events.On('MERCHANT_CLOSED', function() onClose('merchant') end)

-- The bank is the one interaction that also changes the container set (issue #47): containers 6..14
-- exist only while it is open, so every open/close pair re-runs the pipeline whether or not the bank
-- is what opened our windows. That refresh is what takes the bank windows back off the screen (AC-13).
events.On('BANKFRAME_OPENED', function()
  harvest.SetBankOpen(true)
  onOpen()
  pipeline.Refresh('bank-open')
end)
events.On('BANKFRAME_CLOSED', function()
  harvest.SetBankOpen(false)
  onClose('bank')
  pipeline.Refresh('bank-close')
end)

-- Blizzard opens its bags from inside the frame's own OnShow, which lands after the open event we
-- react to, so the suppression is re-applied on the way out of Blizzard's call.
-- shortcut: `OpenAllBags` is the only path the client's vendor and bank take. If another Blizzard
-- panel opens bags by a different route, widen this to `OpenAllBagsInternal`'s EventRegistry
-- callback (`ContainerFrame.lua:2090`).
if type(OpenAllBags) == 'function' then
  hooksecurefunc('OpenAllBags', function()
    if suppressing then hideBlizzardBags() end
  end)
end

---@return boolean
function interactions.Suppressing()
  return suppressing
end

return interactions
