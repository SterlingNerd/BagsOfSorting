-- Dropdown utility using EasyMenu (simple, reliable, no template initialization needed).
-- EasyMenu creates menus dynamically from entry tables.

local _, addon = ...

---@class Dropdown: BoSModule
local dropdown = addon:NewModule('Dropdown')

---@class DropdownEntry
---@field text string
---@field value any?
---@field checked boolean|function?
---@field func function?
---@field isTitle boolean?
---@field hasArrow boolean?
---@field menuList DropdownEntry[]?
---@field disabled boolean?
---@field notCheckable boolean?
---@field keepShownOnClick boolean?

---@type Frame?
local dropdownFrame

--- Ensure the dropdown frame exists (lazy init).
local function ensureFrame()
  if dropdownFrame then return dropdownFrame end

  dropdownFrame = CreateFrame('Frame', 'BagsOfSortingDropdown', UIParent, 'UIDropDownMenuTemplate')
  dropdownFrame:SetFrameStrata('TOOLTIP')
  dropdownFrame:SetClampedToScreen(true)
  return dropdownFrame
end

--- Show a dropdown menu anchored to a frame.
---@param anchorFrame Frame  -- frame to anchor to (for positioning)
---@param entries DropdownEntry[]
---@param onSelect fun(value: any, entry: DropdownEntry)?  -- optional callback
function dropdown.Show(anchorFrame, entries, onSelect)
  ensureFrame()

  -- Convert our entry format to EasyMenu format
  local menuList = {}
  for _, entry in ipairs(entries) do
    local info = {}
    info.text = entry.text
    info.value = entry.value
    info.checked = type(entry.checked) == 'function' and entry.checked() or entry.checked
    info.func = entry.func
    info.isTitle = entry.isTitle
    info.hasArrow = entry.hasArrow
    info.menuList = entry.menuList
    info.disabled = entry.disabled
    info.notCheckable = entry.notCheckable or (entry.func and not entry.checked)
    info.keepShownOnClick = entry.keepShownOnClick

    if entry.func and onSelect then
      local originalFunc = entry.func
      info.func = function(self, ...)
        originalFunc(self, ...)
        onSelect(entry.value, entry)
        if CloseDropDownMenus then CloseDropDownMenus() end
      end
    elseif onSelect and not entry.hasArrow then
      info.func = function(self)
        onSelect(entry.value, entry)
        if CloseDropDownMenus then CloseDropDownMenus() end
      end
    end

    if entry.hasArrow and entry.menuList then
      info.func = nil -- submenu handles its own func
    end

    menuList[#menuList + 1] = info
  end

  -- EasyMenu handles positioning and display
  if EasyMenu then
    EasyMenu(menuList, dropdownFrame, anchorFrame, 0, 0, 'MENU')
  elseif ToggleDropDownMenu then
    -- Fallback to standard dropdown if EasyMenu not available
    -- This requires UIDropDownMenu_Initialize to have been called
    dropdownFrame.menuList = menuList
    UIDropDownMenu_Initialize(dropdownFrame, function(self, level)
      for _, info in ipairs(menuList) do
        UIDropDownMenu_AddButton(info, level)
      end
    end, 'MENU')
    ToggleDropDownMenu(1, nil, dropdownFrame, anchorFrame, 0, 0)
  end
end

--- Close any open dropdown.
function dropdown.Close()
  if CloseDropDownMenus then CloseDropDownMenus() end
end

return dropdown