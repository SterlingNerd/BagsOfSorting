-- FR-41 placement (docs/07 Q24, issue #28): windows stack upward from the bag bar in profile
-- order, and wrap to a new column on the left when the next window will not fit.
--
-- This is a **port** of Blizzard's `UpdateContainerFrameAnchors` loop
-- (`origin/forever` `Blizzard_UIPanels_Game/Mainline/ContainerFrame.lua:1378-1408`), not a call to
-- it: that function iterates `ContainerFrameSettingsManager:GetBagsShown()` — Blizzard's own frame
-- list, and that manager is what agents.md hard rule 8 forbids — and its constants are `local` to
-- the file, so the numbers are copied rather than read.
--
-- Two divergences from Blizzard, both deliberate:
--   * It answers an overflowing column by shrinking container scale in 0.01 steps and restarting
--     (`GetContainerScale`, :1326). We do not rescale (#18); `frame:SetClampedToScreen(true)` in
--     frames/window.lua is what degrades an over-tall window.
--   * It stops wrapping left at `BankFrame:GetRight() - 25` while the bank is open. Bank windows are
--     M5, so there is no limit to honour yet.

local _, addon = ...

---@class Anchors: BoSModule
local anchors = addon:NewModule('Anchors')

-- Blizzard's own gaps, both `local` to ContainerFrame.lua: CONTAINER_SPACING = 8 between stacked
-- frames, and the -11 that starts a new column (:1398).
local GAP = 8
local COLUMN_GAP = 11

--- Pure math over the layout model: writes `x`/`y` next to the `width`/`height` flow.Layout wrote.
--- Call it **once per render pass over the whole model** — the column state carries between windows.
---@param models BoSWindowModel[]
---@param screenHeight number
---@param allowance number  -- the top of the frame we actually anchor to, measured, not a constant
---@return BoSWindowModel[]
function anchors.Place(models, screenHeight, allowance)
  local freeHeight = screenHeight - allowance
  local columnX, columnHeight, columnWidth = 0, 0, 0

  for _, window in ipairs(models) do
    -- `columnHeight > 0` is Blizzard's `framesInColumn == 1` rule: a single window taller than the
    -- cap keeps the first slot rather than opening a phantom empty column.
    if columnHeight > 0 and columnHeight + GAP + window.height > freeHeight then
      columnX = columnX - (columnWidth + COLUMN_GAP)
      columnHeight, columnWidth = 0, 0
    end
    window.x = columnX
    window.y = columnHeight > 0 and columnHeight + GAP or 0
    -- columnHeight is the top of the last window placed, gaps included: Blizzard's own loop
    -- subtracts only frame heights and then anchors with a spacing gap, which lets its stack creep
    -- past the free height by one gap per window.
    columnHeight = window.y + window.height
    columnWidth = math.max(columnWidth, window.width)
  end

  return models
end

return anchors
