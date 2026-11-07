-- Section blocks: a title plus the grid of item buttons its categories produced (FR-11).
-- Sections are pooled too, so a 20-section window does not allocate 20 frames per refresh.

local _, addon = ...

---@class SectionFrames: BoSModule
local sectionFrames = addon:NewModule('SectionFrames')

local constants = addon:GetModule('Constants')
local pool = addon:GetModule('Pool')
local itemFrames = addon:GetModule('ItemFrames')
local dropdown = addon:GetModule('Dropdown')
local pipeline = addon:GetModule('Pipeline')
local db = addon:GetModule('DB')
local editModals = addon:GetModule('EditModals')

local CELL = constants.BUTTON_SIZE + constants.BUTTON_GAP

---@class BoSSectionFrame
---@field frame Frame
---@field title FontString
---@field items BoSItemEntry[]
---@field empty BoSItemEntry?  -- the section's own free-slot cell (issue #44)

local function create()
  local frame = CreateFrame('Frame')
  -- Lua-created frames take mouse input by default, and a section covers the whole window body:
  -- left as-is it swallows every press, so the window could not be dragged at all. The item
  -- buttons are children and keep their own input.
  frame:EnableMouse(false)
  frame:SetFrameLevel(1)
  local title = frame:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
  title:SetPoint('TOPLEFT', 0, 0)
  title:SetJustifyH('LEFT')
  title:SetWordWrap(true)
  -- Transparent button over the title area to catch right-clicks (FontStrings can't receive mouse events)
  local titleButton = CreateFrame('Button', nil, frame)
  titleButton:SetPoint('TOPLEFT', 0, 0)
  titleButton:SetSize(1, constants.SECTION_TITLE_HEIGHT) -- height fixed, width set in Render
  titleButton:EnableMouse(true)
  titleButton:SetFrameLevel(frame:GetFrameLevel() + 2)
  titleButton:SetScript('OnMouseDown', function(self, button)
    if button == 'RightButton' then
      local sectionFrame = self:GetParent()
      local sectionModel = sectionFrame._model
      local windowConfig = sectionFrame._windowConfig
      if sectionModel and windowConfig then
        ShowSectionMenu(self, sectionModel, windowConfig)
      end
    end
  end)
  return { frame = frame, title = title, titleButton = titleButton, items = {} }
end

local function clearItems(section)
  for i = #section.items, 1, -1 do
    itemFrames.Release(section.items[i])
    section.items[i] = nil
  end
  if section.empty then
    itemFrames.Release(section.empty)
    section.empty = nil
    section.frame.EmptySlot = nil
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
---@param windowConfig any
function sectionFrames.Render(section, model, parent, offsetY, windowConfig)
  clearItems(section)

  -- Guard: offsetY can be nil if flow.Layout hasn't run or section was added late
  offsetY = offsetY or 0
  -- Defensive defaults if flow.Layout didn't set them (e.g. section added after layout)
  model.width = model.width or (windowConfig.columns or 5) * (constants.BUTTON_SIZE + constants.BUTTON_GAP)
  model.height = model.height or constants.SECTION_TITLE_HEIGHT
  model.cols = model.cols or (windowConfig.columns or 5)
  model.rows = model.rows or 0

  -- Store references for the right-click handler
  section.frame._model = model
  section.frame._windowConfig = windowConfig

  section.frame:SetParent(parent)
  section.frame:SetFrameLevel(parent:GetFrameLevel() + 1)
  section.frame:ClearAllPoints()
  section.frame:SetPoint('TOPLEFT', parent, 'TOPLEFT',
    constants.WINDOW_PADDING, -(constants.WINDOW_TITLE_HEIGHT + offsetY))
  section.frame:SetSize(model.width, model.height)
  section.frame:Show()

  section.title:SetText(model.name)
  section.title:SetWidth(model.width)
  section.titleButton:SetWidth(model.width)

  -- Collapsed section: only show header, no items
  if model.collapsed then
    section.frame:SetHeight(constants.SECTION_TITLE_HEIGHT)
    return section
  end

  for i, item in ipairs(model.items) do
    local entry = itemFrames.Acquire()
    section.items[#section.items + 1] = entry
    itemFrames.Paint(entry, item, section.frame)

    local col = (i - 1) % model.cols
    local row = math.floor((i - 1) / model.cols)
    entry.parent:ClearAllPoints()
    entry.parent:SetPoint('TOPLEFT', section.frame, 'TOPLEFT', col * CELL, -(constants.SECTION_TITLE_HEIGHT + row * CELL))
  end

  -- The section's own free-slot cell (issue #44): the same empty slot the window-level indicator
  -- draws (#36), placed after this block's last row and pointing at a real free slot in the bag
  -- this section's category pairs with. It sits on the section frame the way the window's indicator
  -- sits on the window shell, so /bos test reads the drawn state, not the model's claim about it.
  if model.emptyOffsetY then
    section.empty = itemFrames.Acquire()
    itemFrames.PaintEmpty(section.empty, model.emptySlot, model.emptySlots, section.frame)
    section.empty.parent:ClearAllPoints()
    section.empty.parent:SetPoint('TOPLEFT', section.frame, 'TOPLEFT', 0, -model.emptyOffsetY)
    section.frame.EmptySlot = section.empty.button
  end

  return section
end

-- Show the section header context menu
function ShowSectionMenu(anchorFrame, model, windowConfig)
  local isCollapsed = model.collapsed or false
  local entries = {
    {
      text = isCollapsed and 'Uncompress' or 'Compress',
      value = 'toggle_collapse',
      func = function()
        -- Find the section config in the window and toggle collapsed
        for _, sectionConfig in ipairs(windowConfig.sections or {}) do
          if sectionConfig.id == model.id then
            sectionConfig.collapsed = not isCollapsed
            break
          end
        end
        db.NotifyModelChanged()
        pipeline.Refresh('section-toggle')
      end,
      notCheckable = true,
    },
    { text = ' ', isTitle = true, notCheckable = true },
    {
      text = 'Edit Section…',
      value = 'edit_section',
      func = function()
        OpenSectionEditModal(model, windowConfig)
      end,
      notCheckable = true,
    },
    {
      text = 'Add Section Below',
      value = 'add_section',
      func = function()
        AddSectionBelow(model, windowConfig)
      end,
      notCheckable = true,
    },
  }
  dropdown.Show(anchorFrame, entries)
end

-- Open edit modal for section
function OpenSectionEditModal(model, windowConfig)
  editModals.OpenSectionEdit(model, windowConfig)
end

-- Add a new section below the current one
function AddSectionBelow(model, windowConfig)
  editModals.AddSectionBelow(model, windowConfig)
end

return sectionFrames
