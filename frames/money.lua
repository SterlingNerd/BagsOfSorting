-- The window money bar (FR-48, issue #32). It is the client's own backpack money bar: the same
-- `ContainerMoneyFrameTemplate` a Blizzard bag window carries, so the coin textures, the coin-box
-- border, the PLAYER_MONEY refresh and the click-to-pickup behaviour all stay Blizzard's.
-- Money only — backpack currencies and the rest of the currency list are a later story.
-- Which window gets a bar is decided in data/pipeline.lua (issue #42: the first backpack window in
-- screen order, the same rule as the free-slot count) and called from frames/window.lua.

local _, addon = ...

---@class MoneyFrames: BoSModule
local moneyFrames = addon:NewModule('MoneyFrames')

local constants = addon:GetModule('Constants')

--- Attach a money bar to a window shell. It stretches across the window's bottom edge the way
--- `ContainerFrameTokenWatcherMixin:UpdateCurrencyFrames` does, so the coins stay right-aligned and
--- the coin-box border fills the width at any window size. The template's own OnLoad registers
--- PLAYER_MONEY and friends and its OnShow paints, so there is nothing for us to refresh.
---@param frame Frame
---@return Frame
function moneyFrames.Attach(frame)
  local bar = CreateFrame('Frame', nil, frame, 'ContainerMoneyFrameTemplate')
  bar:SetPoint('BOTTOMLEFT', frame, 'BOTTOMLEFT', constants.WINDOW_PADDING, constants.WINDOW_PADDING)
  bar:SetPoint('BOTTOMRIGHT', frame, 'BOTTOMRIGHT', -constants.WINDOW_PADDING, constants.WINDOW_PADDING)
  -- A Lua-created frame takes mouse input, and this one spans the window's whole bottom edge: left
  -- as-is it swallows the drag that starts there (the same fix frames/section.lua makes). The coin
  -- buttons are children and keep their own input.
  bar:EnableMouse(false)
  -- Same stack as the sections (issue #34): one level above the shell, so the coins clear the panel
  -- background and Blizzard's own bag buttons instead of tying with either.
  bar:SetFrameLevel(frame:GetFrameLevel() + 1)
  return bar
end

return moneyFrames
