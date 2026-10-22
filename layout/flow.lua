-- Phase 7: pack section blocks into a window's column budget and size the window to its
-- content (FR-40).
--
-- shortcut: sections stack vertically, left-aligned, one per row. River packing (several
-- sections sharing a row) is M2's layout work with its own sizing measurements (docs/06 M2,
-- AC-40); this function's output shape is already what M2 fills in.

local _, addon = ...

---@class Flow: BoSModule
local flow = addon:NewModule('Flow')

local constants = addon:GetModule('Constants')

local CELL = constants.BUTTON_SIZE + constants.BUTTON_GAP
local SECTION_GAP = 6

---@class BoSSectionModel
---@field id string
---@field name string
---@field categories string[]
---@field items BoSItem[]
---@field cols number
---@field rows number
---@field width number
---@field height number
---@field offsetY number
---@field emptySlots number?   -- free slots in this section's own tradeskill bag (issue #44)
---@field emptySlot BoSFreeSlot?  -- a real empty slot in that bag
---@field emptyOffsetY number?    -- where flow put the cell inside the block

---@class BoSWindowModel
---@field id string
---@field name string
---@field kind string
---@field columns number
---@field scale number
---@field config any
---@field sections BoSSectionModel[]
---@field emptySlots number?   -- free slots in the player's bags, on the window that shows them
---@field emptySlot BoSFreeSlot?  -- the real empty slot the indicator points at
---@field emptyOffsetY number?    -- the cell flow reserved for it
---@field showMoney boolean?      -- this window carries the money bar (issue #42: one window does)
---@field width number
---@field height number

--- Empty sections are skipped: a header for a block with nothing in it is noise, and the
--- catch-all still appears whenever it has items (AC-16).
---@param window BoSWindowModel
---@return BoSWindowModel
function flow.Layout(window)
  local maxColumns = window.columns or 5
  local contentHeight = 0
  local widest = 0

  for _, section in ipairs(window.sections) do
    local count = #section.items
    if count > 0 then
      section.cols = math.min(maxColumns, count)
      section.rows = math.ceil(count / section.cols)
      section.width = section.cols * CELL
      section.height = constants.SECTION_TITLE_HEIGHT + section.rows * CELL
      section.offsetY = contentHeight
      -- Issue #44: a section's own free-slot cell is one more row at the bottom of its block, so
      -- the block it belongs to is what grows, not the window around it.
      section.emptyOffsetY = nil
      if (section.emptySlots or 0) > 0 then
        section.emptyOffsetY = section.height
        section.height = section.height + CELL
      end
      contentHeight = contentHeight + section.height + SECTION_GAP
      widest = math.max(widest, section.width)
    end
  end

  -- Issue #36: the free-slot indicator is one more cell at the end of the column.
  window.emptyOffsetY = nil
  if (window.emptySlots or 0) > 0 then
    window.emptyOffsetY = contentHeight
    contentHeight = contentHeight + CELL
  end

  window.width = math.max(widest, maxColumns * CELL) + constants.WINDOW_PADDING * 2
  -- Issue #43: with nothing in it a window is its title band and nothing more — no blank cell, no body,
  -- no grid. The floor under it is the chrome, not a body cell: the art `HeldBagLayout` draws is 95 px
  -- end to end and the client cannot shrink its bottom corners below 72 px at all. The window still
  -- exists and still takes its slot in the column (#28 decision 2).
  window.height = math.max(constants.WINDOW_CHROME_HEIGHT,
    constants.WINDOW_TITLE_HEIGHT + contentHeight
      + constants.WINDOW_PADDING + (window.showMoney and constants.MONEY_BAR_SPACE or 0))
  return window
end

return flow
