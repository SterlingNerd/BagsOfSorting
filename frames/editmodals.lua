-- Edit modals for section and window configuration.

local _, addon = ...

---@class EditModals: BoSModule
local editModals = addon:NewModule('EditModals')

local db = addon:GetModule('DB')
local pipeline = addon:GetModule('Pipeline')

---@type Frame?
local sectionEditFrame
---@type Frame?
local windowEditFrame
---@type Frame?
local categoryEditorFrame

-- Categories available for multi-select (populated dynamically)
local function getCategoryList()
  local cats = db.Categories()
  local list = {}
  for name, cat in pairs(cats) do
    if name ~= '__catchall' and cat.enabled ~= false then
      list[#list + 1] = name
    end
  end
  table.sort(list)
  return list
end

-- Create a simple checkbox for category selection
local function createCategoryCheckbox(parent, categoryName, yOffset, onChange)
  local cb = CreateFrame('CheckButton', nil, parent, 'InterfaceOptionsCheckButtonTemplate')
  cb:SetPoint('TOPLEFT', 10, yOffset)
  cb.Text:SetText(categoryName)
  cb:SetScript('OnClick', function(self)
    onChange(categoryName, self:GetChecked())
  end)
  return cb
end

--- Open the section edit modal.
---@param model BoSSectionModel
---@param windowConfig any
function editModals.OpenSectionEdit(model, windowConfig)
  if sectionEditFrame then
    sectionEditFrame:Hide()
  end

  sectionEditFrame = CreateFrame('Frame', 'BagsOfSortingSectionEdit', UIParent, 'BasicFrameTemplateWithInset')
  sectionEditFrame:SetSize(350, 450)
  sectionEditFrame:SetPoint('CENTER')
  sectionEditFrame:SetFrameStrata('DIALOG')
  sectionEditFrame:SetMovable(true)
  sectionEditFrame:EnableMouse(true)
  sectionEditFrame:RegisterForDrag('LeftButton')
  sectionEditFrame:SetScript('OnDragStart', sectionEditFrame.StartMoving)
  sectionEditFrame:SetScript('OnDragStop', sectionEditFrame.StopMovingOrSizing)
  sectionEditFrame.TitleText:SetText('Edit Section: ' .. model.name)

  -- Name edit box
  local nameLabel = sectionEditFrame:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
  nameLabel:SetPoint('TOPLEFT', 15, -35)
  nameLabel:SetText('Section Name:')

  local nameEdit = CreateFrame('EditBox', nil, sectionEditFrame, 'InputBoxTemplate')
  nameEdit:SetSize(300, 25)
  nameEdit:SetPoint('TOPLEFT', nameLabel, 'BOTTOMLEFT', 0, -5)
  nameEdit:SetText(model.name)
  nameEdit:SetAutoFocus(false)
  nameEdit:SetScript('OnEnterPressed', function(self) self:ClearFocus() end)

  -- Categories multi-select
  local catLabel = sectionEditFrame:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
  catLabel:SetPoint('TOPLEFT', nameEdit, 'BOTTOMLEFT', 0, -15)
  catLabel:SetText('Categories (multi-select):')

  local catContainer = CreateFrame('Frame', nil, sectionEditFrame)
  catContainer:SetSize(320, 250)
  catContainer:SetPoint('TOPLEFT', catLabel, 'BOTTOMLEFT', 0, -5)

  -- Scroll frame for categories
  local scrollFrame = CreateFrame('ScrollFrame', nil, catContainer, 'UIPanelScrollFrameTemplate')
  scrollFrame:SetAllPoints(catContainer)

  local scrollChild = CreateFrame('Frame', nil, scrollFrame)
  scrollChild:SetSize(300, 1)
  scrollFrame:SetScrollChild(scrollChild)

  -- Track selected categories
  local selectedCategories = {}
  for _, cat in ipairs(model.categories) do
    selectedCategories[cat] = true
  end

  local categoryList = getCategoryList()
  for i, catName in ipairs(categoryList) do
    local cb = createCategoryCheckbox(scrollChild, catName, -(i - 1) * 25, function(name, checked)
      selectedCategories[name] = checked or nil
    end)
    cb:SetChecked(selectedCategories[catName] or false)
  end
  scrollChild:SetHeight(#categoryList * 25 + 10)

  -- Buttons
  local deleteBtn = CreateFrame('Button', nil, sectionEditFrame, 'UIPanelButtonTemplate')
  deleteBtn:SetSize(100, 25)
  deleteBtn:SetPoint('BOTTOMLEFT', 15, 15)
  deleteBtn:SetText('Delete')
  deleteBtn:SetScript('OnClick', function()
    StaticPopup_Show('BOS_CONFIRM_DELETE_SECTION', model.name, nil, { model = model, windowConfig = windowConfig })
  end)

  local cancelBtn = CreateFrame('Button', nil, sectionEditFrame, 'UIPanelButtonTemplate')
  cancelBtn:SetSize(100, 25)
  cancelBtn:SetPoint('BOTTOMRIGHT', -15, 15)
  cancelBtn:SetText('Cancel')
  cancelBtn:SetScript('OnClick', function()
    sectionEditFrame:Hide()
  end)

  local saveBtn = CreateFrame('Button', nil, sectionEditFrame, 'UIPanelButtonTemplate')
  saveBtn:SetSize(100, 25)
  saveBtn:SetPoint('RIGHT', cancelBtn, 'LEFT', -10, 0)
  saveBtn:SetText('Save')
  saveBtn:SetScript('OnClick', function()
    -- Find and update the section config
    local newName = nameEdit:GetText():trim()
    if newName == '' then
      print('|cff00ff00BagsOfSorting|r: Section name cannot be empty')
      return
    end

    local newCategories = {}
    for name, _ in pairs(selectedCategories) do
      newCategories[#newCategories + 1] = name
    end
    if #newCategories == 0 then
      print('|cff00ff00BagsOfSorting|r: Section must have at least one category')
      return
    end

    for _, sectionConfig in ipairs(windowConfig.sections or {}) do
      if sectionConfig.id == model.id then
        sectionConfig.name = newName
        sectionConfig.categories = newCategories
        break
      end
    end

    db.NotifyModelChanged()
    pipeline.Refresh('section-edit')
    sectionEditFrame:Hide()
  end)
end

--- Open the window edit modal.
---@param windowConfig any
function editModals.OpenWindowEdit(windowConfig)
  if windowEditFrame then
    windowEditFrame:Hide()
  end

  windowEditFrame = CreateFrame('Frame', 'BagsOfSortingWindowEdit', UIParent, 'BasicFrameTemplateWithInset')
  windowEditFrame:SetSize(350, 380)
  windowEditFrame:SetPoint('CENTER')
  windowEditFrame:SetFrameStrata('DIALOG')
  windowEditFrame:SetMovable(true)
  windowEditFrame:EnableMouse(true)
  windowEditFrame:RegisterForDrag('LeftButton')
  windowEditFrame:SetScript('OnDragStart', windowEditFrame.StartMoving)
  windowEditFrame:SetScript('OnDragStop', windowEditFrame.StopMovingOrSizing)
  windowEditFrame.TitleText:SetText('Edit Window: ' .. windowConfig.name)

  -- Name edit box
  local nameLabel = windowEditFrame:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
  nameLabel:SetPoint('TOPLEFT', 15, -35)
  nameLabel:SetText('Window Name:')

  local nameEdit = CreateFrame('EditBox', nil, windowEditFrame, 'InputBoxTemplate')
  nameEdit:SetSize(300, 25)
  nameEdit:SetPoint('TOPLEFT', nameLabel, 'BOTTOMLEFT', 0, -5)
  nameEdit:SetText(windowConfig.name)
  nameEdit:SetAutoFocus(false)
  nameEdit:SetScript('OnEnterPressed', function(self) self:ClearFocus() end)

  -- Scale slider
  local scaleLabel = windowEditFrame:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
  scaleLabel:SetPoint('TOPLEFT', nameEdit, 'BOTTOMLEFT', 0, -15)
  scaleLabel:SetText('Scale: ' .. (windowConfig.scale or 1.0))

  local scaleSlider = CreateFrame('Slider', nil, windowEditFrame, 'OptionsSliderTemplate')
  scaleSlider:SetSize(300, 20)
  scaleSlider:SetPoint('TOPLEFT', scaleLabel, 'BOTTOMLEFT', 0, -5)
  scaleSlider:SetMinMaxValues(0.5, 2.0)
  scaleSlider:SetValueStep(0.05)
  scaleSlider:SetValue(windowConfig.scale or 1.0)
  scaleSlider:SetScript('OnValueChanged', function(self, value)
    scaleLabel:SetText('Scale: ' .. string.format('%.2f', value))
    self.value = value
  end)

  -- Columns dropdown
  local colsLabel = windowEditFrame:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
  colsLabel:SetPoint('TOPLEFT', scaleSlider, 'BOTTOMLEFT', 0, -15)
  colsLabel:SetText('Columns:')

  local colsDropdown = CreateFrame('Frame', 'BagsOfSortingWindowColsDropdown', windowEditFrame, 'UIDropDownMenuTemplate')
  colsDropdown:SetPoint('TOPLEFT', colsLabel, 'BOTTOMLEFT', -15, -5)
  UIDropDownMenu_SetWidth(colsDropdown, 150)
  UIDropDownMenu_Initialize(colsDropdown, function(self, level)
    for i = 4, 12 do
      local info = UIDropDownMenu_CreateInfo()
      info.text = tostring(i)
      info.value = i
      info.func = function(btn)
        UIDropDownMenu_SetSelectedValue(colsDropdown, btn.value)
        colsDropdown.selectedValue = btn.value
      end
      info.checked = (i == (windowConfig.columns or 5))
      UIDropDownMenu_AddButton(info, level)
    end
  end)
  UIDropDownMenu_SetSelectedValue(colsDropdown, windowConfig.columns or 5)
  colsDropdown.selectedValue = windowConfig.columns or 5

  -- Compact checkbox
  local compactCheck = CreateFrame('CheckButton', nil, windowEditFrame, 'InterfaceOptionsCheckButtonTemplate')
  compactCheck:SetPoint('TOPLEFT', colsDropdown, 'BOTTOMLEFT', 15, -10)
  compactCheck.Text:SetText('Compact mode')
  compactCheck:SetChecked(windowConfig.compact or false)

  -- Buttons
  local cancelBtn = CreateFrame('Button', nil, windowEditFrame, 'UIPanelButtonTemplate')
  cancelBtn:SetSize(100, 25)
  cancelBtn:SetPoint('BOTTOMRIGHT', -15, 15)
  cancelBtn:SetText('Cancel')
  cancelBtn:SetScript('OnClick', function()
    windowEditFrame:Hide()
  end)

  local saveBtn = CreateFrame('Button', nil, windowEditFrame, 'UIPanelButtonTemplate')
  saveBtn:SetSize(100, 25)
  saveBtn:SetPoint('RIGHT', cancelBtn, 'LEFT', -10, 0)
  saveBtn:SetText('Save')
  saveBtn:SetScript('OnClick', function()
    local newName = nameEdit:GetText():trim()
    if newName == '' then
      print('|cff00ff00BagsOfSorting|r: Window name cannot be empty')
      return
    end

    windowConfig.name = newName
    windowConfig.scale = scaleSlider.value or (windowConfig.scale or 1.0)
    windowConfig.columns = colsDropdown.selectedValue or (windowConfig.columns or 5)
    windowConfig.compact = compactCheck:GetChecked() or false

    db.NotifyModelChanged()
    pipeline.Refresh('window-edit')
    windowEditFrame:Hide()
  end)
end

--- Open the category editor dialog (issue #71). Lists every enabled, non-__catchall category and
--- lets the player edit each manual category's itemIDs. Edits commit immediately and repaint the
--- bags. db must not require Pipeline (circular require risk), so the refresh reason is passed in
--- from here, the same way OpenSectionEdit passes 'section-edit'.
function editModals.OpenCategoryEditor()
  if categoryEditorFrame then
    categoryEditorFrame:Hide()
  end

  categoryEditorFrame = CreateFrame('Frame', 'BagsOfSortingCategoryEditor', UIParent, 'BasicFrameTemplateWithInset')
  categoryEditorFrame:SetSize(440, 520)
  categoryEditorFrame:SetPoint('CENTER')
  categoryEditorFrame:SetFrameStrata('DIALOG')
  categoryEditorFrame:SetMovable(true)
  categoryEditorFrame:EnableMouse(true)
  categoryEditorFrame:RegisterForDrag('LeftButton')
  categoryEditorFrame:SetScript('OnDragStart', categoryEditorFrame.StartMoving)
  categoryEditorFrame:SetScript('OnDragStop', categoryEditorFrame.StopMovingOrSizing)
  categoryEditorFrame.TitleText:SetText('Edit Categories')

  local cats = db.Categories()
  local categoryList = getCategoryList()
  local selected = categoryList[1]
  local refreshList

  -- Category selector: which category's itemIDs are shown and edited below
  local catLabel = categoryEditorFrame:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
  catLabel:SetPoint('TOPLEFT', 15, -35)
  catLabel:SetText('Category:')

  local catDropdown = CreateFrame('Frame', 'BagsOfSortingCategoryEditorCatDropdown', categoryEditorFrame, 'UIDropDownMenuTemplate')
  catDropdown:SetPoint('TOPLEFT', catLabel, 'BOTTOMLEFT', -15, -5)
  UIDropDownMenu_SetWidth(catDropdown, 300)
  UIDropDownMenu_SetSelectedValue(catDropdown, selected)
  UIDropDownMenu_Initialize(catDropdown, function(self, level)
    for _, name in ipairs(categoryList) do
      local info = UIDropDownMenu_CreateInfo()
      info.text = name
      info.value = name
      info.func = function(btn)
        selected = btn.value
        UIDropDownMenu_SetSelectedValue(catDropdown, selected)
        refreshList()
      end
      info.checked = (name == selected)
      UIDropDownMenu_AddButton(info, level)
    end
  end)

  -- Scrollable list of the selected category's item IDs, each with a Remove button
  local listLabel = categoryEditorFrame:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
  listLabel:SetPoint('TOPLEFT', catDropdown, 'BOTTOMLEFT', 15, -12)
  listLabel:SetText('Item IDs:')

  local listContainer = CreateFrame('Frame', nil, categoryEditorFrame)
  listContainer:SetSize(400, 220)
  listContainer:SetPoint('TOPLEFT', listLabel, 'BOTTOMLEFT', 0, -5)

  local scrollFrame = CreateFrame('ScrollFrame', nil, listContainer, 'UIPanelScrollFrameTemplate')
  scrollFrame:SetAllPoints(listContainer)

  local scrollChild = CreateFrame('Frame', nil, scrollFrame)
  scrollChild:SetSize(380, 1)
  scrollFrame:SetScrollChild(scrollChild)

  local rows = {}

  refreshList = function()
    for _, r in ipairs(rows) do
      r.id:Hide()
      if r.remove then r.remove:Hide() end
    end
    local cat = cats[selected]
    local ids = {}
    if cat and cat.itemIDs then
      for id in pairs(cat.itemIDs) do ids[#ids + 1] = id end
    end
    table.sort(ids)
    local n = #ids
    if n == 0 then n = 1 end
    for i = 1, n do
      local r = rows[i]
      if not r then
        local idText = scrollChild:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
        idText:SetPoint('TOPLEFT', 10, -(i - 1) * 20)
        local remove = CreateFrame('Button', nil, scrollChild, 'UIPanelButtonTemplate')
        remove:SetSize(70, 18)
        remove:SetPoint('TOPLEFT', 110, -(i - 1) * 20 - 2)
        remove:SetText('Remove')
        remove:Hide()
        r = { id = idText, remove = remove }
        rows[i] = r
      end
      r.id:Show()
      if #ids == 0 then
        r.id:SetText('(none)')
        r.remove:Hide()
      else
        local id = ids[i]
        r.remove.itemID = id
        r.id:SetText(tostring(id))
        r.remove:SetScript('OnClick', function(self)
          db.RemoveItemFromCategory(selected, self.itemID)
          pipeline.Refresh('category-editor')
          refreshList()
        end)
        r.remove:Show()
      end
    end
    scrollChild:SetHeight(math.max(#ids, 1) * 20 + 10)
  end

  -- Item ID input + Add: appends to the selected manual category
  local addLabel = categoryEditorFrame:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
  addLabel:SetPoint('TOPLEFT', listContainer, 'BOTTOMLEFT', 0, -12)
  addLabel:SetText('Item ID:')

  local idEdit = CreateFrame('EditBox', nil, categoryEditorFrame, 'InputBoxTemplate')
  idEdit:SetSize(120, 25)
  idEdit:SetPoint('TOPLEFT', addLabel, 'BOTTOMLEFT', 0, -5)
  idEdit:SetAutoFocus(false)
  idEdit:SetScript('OnEnterPressed', function(self) self:ClearFocus() end)

  local addBtn = CreateFrame('Button', nil, categoryEditorFrame, 'UIPanelButtonTemplate')
  addBtn:SetSize(70, 25)
  addBtn:SetPoint('LEFT', idEdit, 'RIGHT', 10, 0)
  addBtn:SetText('Add')
  addBtn:SetScript('OnClick', function()
    local text = idEdit:GetText():trim()
    local num = tonumber(text)
    if not num or num <= 0 then
      print('|cff00ff00BagsOfSorting|r: Item ID must be a number')
      return
    end
    if not db.AddItemToCategory(selected, num) then
      print('|cff00ff00BagsOfSorting|r: Cannot add to ' .. tostring(selected) .. ' (rule-based categories cannot be edited here)')
      return
    end
    pipeline.Refresh('category-editor')
    refreshList()
    idEdit:SetText('')
  end)

  -- Close: hides the dialog. Edits commit immediately, there is no Cancel.
  local closeBtn = CreateFrame('Button', nil, categoryEditorFrame, 'UIPanelButtonTemplate')
  closeBtn:SetSize(100, 25)
  closeBtn:SetPoint('BOTTOMRIGHT', -15, 15)
  closeBtn:SetText('Close')
  closeBtn:SetScript('OnClick', function()
    categoryEditorFrame:Hide()
  end)
end

--- Add a new section below the given one.
---@param model BoSSectionModel
---@param windowConfig any
function editModals.AddSectionBelow(model, windowConfig)
  local newSection = {
    id = 's' .. (math.random(10000, 99999)),
    name = 'New Section',
    categories = { '__catchall' },
    collapsed = false,
  }

  -- Find insertion index
  local insertIdx = #windowConfig.sections + 1
  for i, sectionConfig in ipairs(windowConfig.sections) do
    if sectionConfig.id == model.id then
      insertIdx = i + 1
      break
    end
  end

  table.insert(windowConfig.sections, insertIdx, newSection)
  db.NotifyModelChanged()
  pipeline.Refresh('add-section')
end

--- Add a new section to the end of the window.
---@param windowConfig any
function editModals.AddSectionToWindow(windowConfig)
  local newSection = {
    id = 's' .. (math.random(10000, 99999)),
    name = 'New Section',
    categories = { '__catchall' },
    collapsed = false,
  }

  table.insert(windowConfig.sections, newSection)
  db.NotifyModelChanged()
  pipeline.Refresh('add-section')
end

if StaticPopupDialogs then
  StaticPopupDialogs['BOS_CONFIRM_DELETE_SECTION'] = {
    text = 'Delete section "%s"? This cannot be undone.',
    button1 = 'Delete',
    button2 = 'Cancel',
    OnAccept = function(self, data)
      local model, windowConfig = data.model, data.windowConfig
      for i, sectionConfig in ipairs(windowConfig.sections or {}) do
        if sectionConfig.id == model.id then
          table.remove(windowConfig.sections, i)
          break
        end
      end
      db.NotifyModelChanged()
      pipeline.Refresh('delete-section')
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
  }
end

return editModals