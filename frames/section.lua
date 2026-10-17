-- Section blocks: a title plus the grid of item buttons its categories produced (FR-11).
-- Sections are pooled too, so a 20-section window does not allocate 20 frames per refresh.

local _, addon = ...

---@class SectionFrames: BoSModule
local sectionFrames = addon:NewModule('SectionFrames')

local constants = addon:GetModule('Constants')
local pool = addon:GetModule('Pool')
local itemFrames = addon:GetModule('ItemFrames')

local CELL = constants.BUTTON_SIZE + constants.BUTTON_GAP

---@class BoSSectionFrame
---@field frame Frame
---@field title FontString
---@field items BoSItemEntry[]

local function create()
  local frame = CreateFrame('Frame')
  frame:SetFrameLevel(1)
  local title = frame:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
  title:SetPoint('TOPLEFT', 0, 0)
  title:SetJustifyH('LEFT')
  return { frame = frame, title = title, items = {} }
end

local function clearItems(section)
  for i = #section.items, 1, -1 do
    itemFrames.Release(section.items[i])
    section.items[i] = nil
  end
end

local function reset(section)
  clearItems(section)
  section.frame:ClearAllPoints()
  section.frame:SetParent(nil)
  section.frame:Hide()
end

sectionFrames.pool = pool.Named('section', create, reset)

--- Release the buttons a section no longer needs, keeping the frame itself.
---@param section BoSSectionFrame
function sectionFrames.ClearItems(section)
  clearItems(section)
end

---@return BoSSectionFrame
function sectionFrames.Acquire()
  return sectionFrames.pool:Acquire()
end

---@param section BoSSectionFrame
function sectionFrames.Release(section)
  sectionFrames.pool:Release(section)
end

---@param section BoSSectionFrame
---@param model BoSSectionModel
---@param parent Frame
---@param offsetY number distance down from the window's content top
function sectionFrames.Render(section, model, parent, offsetY)
  clearItems(section)

  section.frame:SetParent(parent)
  section.frame:SetFrameLevel(parent:GetFrameLevel() + 1)
  section.frame:ClearAllPoints()
  section.frame:SetPoint('TOPLEFT', parent, 'TOPLEFT',
    constants.WINDOW_PADDING, -(constants.WINDOW_TITLE_HEIGHT + offsetY))
  section.frame:SetSize(model.width, model.height)
  section.frame:Show()

  section.title:SetText(model.name)
  section.title:SetWidth(model.width)

  for i, item in ipairs(model.items) do
    local entry = itemFrames.Acquire()
    section.items[#section.items + 1] = entry
    itemFrames.Paint(entry, item, section.frame)

    local col = (i - 1) % model.cols
    local row = math.floor((i - 1) / model.cols)
    entry.parent:ClearAllPoints()
    entry.parent:SetPoint('TOPLEFT', section.frame, 'TOPLEFT', col * CELL, -(constants.SECTION_TITLE_HEIGHT + row * CELL))
  end

  return section
end

return sectionFrames
