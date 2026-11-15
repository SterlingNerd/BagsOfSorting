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

--- Open the category editor dialog (issue #71). HUD Edit Mode style: a translucent dialog that
--- lists every enabled, non-__catchall category in a grid. Each row is one category:
--- rule-based (dynamic) categories show a read-only label; manual categories list their item IDs
--- horizontally, each with a remove button, plus an inline Add input. Edits commit immediately
--- and repaint the bags. db must not require Pipeline (circular require risk), so the refresh
--- reason is passed in from here, the same way OpenSectionEdit passes 'section-edit'.
function editModals.OpenCategoryEditor()
  if categoryEditorFrame then
    categoryEditorFrame:Hide()
  end

  local sw, sh = GetScreenWidth(), GetScreenHeight()
  local width, height = math.floor(sw * 0.75), math.floor(sh * 0.75)

  categoryEditorFrame = CreateFrame('Frame', 'BagsOfSortingCategoryEditor', UIParent, 'BasicFrameTemplateWithInset')
  categoryEditorFrame:SetSize(width, height)
  categoryEditorFrame:SetPoint('CENTER')
  categoryEditorFrame:SetFrameStrata('DIALOG')
  categoryEditorFrame:SetMovable(true)
  categoryEditorFrame:EnableMouse(true)
  categoryEditorFrame:RegisterForDrag('LeftButton')
  categoryEditorFrame:SetScript('OnDragStart', categoryEditorFrame.StartMoving)
  categoryEditorFrame:SetScript('OnDragStop', categoryEditorFrame.StopMovingOrSizing)
  categoryEditorFrame.TitleText:SetText('Edit Categories')

  local closeBtn = CreateFrame('Button', nil, categoryEditorFrame, 'UIPanelCloseButton')
  closeBtn:SetPoint('TOPRIGHT', -6, 6)

  local scrollFrame = CreateFrame('ScrollFrame', nil, categoryEditorFrame, 'UIPanelScrollFrameTemplate')
  scrollFrame:SetPoint('TOPLEFT', 18, -44)
  scrollFrame:SetPoint('BOTTOMRIGHT', -18, 76)

  local scrollChild = CreateFrame('Frame', nil, scrollFrame)
  scrollChild:SetSize(width - 36, 1)
  scrollFrame:SetScrollChild(scrollChild)

  local cats = db.Categories()
  local categoryList = getCategoryList()
  local rows = {}  -- categoryName -> row frame

  local nameWidth = 170
  local rowGap = 10
  local lineHeight = 22
  local idGap = 10
  local idStartX = 8 + nameWidth + 14

  --- Resolve an itemID to a clickable item link, falling back to a raw link if uncached.
  local function itemLinkFor(itemID)
    local _, link = GetItemInfo(itemID)
    if link then return link end
    return string.format('|Hitem:%d:::::::::::::::::::|h[#%d]|h', itemID, itemID)
  end

  --- Estimated display width of text at GameFontHighlight size (markup stripped).
  local function textWidth(text)
    local visible = text:gsub('|c%x*', ''):gsub('|r', ''):gsub('|H.-|h', ''):gsub('|h', '')
    return #visible * 7.5 + 8
  end

  --- Build / refresh every category row. Reuses row frames so repeated refreshes do not leak frames.
  local function refresh()
    local y = -8
    local scrollW = scrollChild:GetWidth()
    local maxRight = scrollW - 14
    for _, catName in ipairs(categoryList) do
      local cat = cats[catName]
      local isManual = cat.kind == 'manual'

      local row = rows[catName]
      if not row then
        row = CreateFrame('Frame', nil, scrollChild)
        rows[catName] = row
      end
      row:ClearAllPoints()
      row:SetPoint('TOPLEFT', 0, y)
      row:Show()

      -- Category name label (created once per row)
      if not row.nameLabel then
        row.nameLabel = row:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
        row.nameLabel:SetWidth(nameWidth)
        row.nameLabel:SetJustifyH('LEFT')
        row.nameLabel:SetPoint('TOPLEFT', 8, -6)
      end
      row.nameLabel:SetText(catName)

      -- Clear per-row dynamic children (id entries + add controls), keeping the name label
      for _, entry in ipairs(row.idEntries or {}) do
        entry.label:Hide()
        entry.remove:Hide()
      end
      if row.addEdit then row.addEdit:Hide() end
      if row.addBtn then row.addBtn:Hide() end
      if row.statusLabel then row.statusLabel:Hide() end
      if row.emptyLabel then row.emptyLabel:Hide() end

      local rowBottom = -6  -- lowest content edge in this row (relative to row top)
      if not isManual then
        -- Rule-based / dynamic category: read-only label
        if not row.statusLabel then
          row.statusLabel = row:CreateFontString(nil, 'OVERLAY', 'GameFontDisable')
        end
        row.statusLabel:SetPoint('TOPLEFT', idStartX, -6)
        row.statusLabel:SetText('(rule-based — read-only)')
        row.statusLabel:Show()
        rowBottom = -6 + lineHeight
      else
        -- Manual category: list item IDs as links horizontally, wrapping when they run out of room
        local idEntries = row.idEntries or {}
        row.idEntries = idEntries
        local ids = {}
        if cat.itemIDs then
          for id in pairs(cat.itemIDs) do ids[#ids + 1] = id end
        end
        table.sort(ids)

        local x = idStartX
        local lineY = -6
        for i, id in ipairs(ids) do
          local link = itemLinkFor(id)
          local labelW = textWidth(link)
          local entryWidth = labelW + 4 + 20 + idGap
          -- wrap if this item won't fit on the current line (and it's not the first)
          if x + entryWidth > maxRight and x > idStartX then
            x = idStartX
            lineY = lineY + lineHeight
          end
          local entry = idEntries[i]
          if not entry then
            local label = row:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
            label:SetJustifyH('LEFT')
            local remove = CreateFrame('Button', nil, row, 'UIPanelButtonTemplate')
            remove:SetSize(20, 18)
            remove:SetText('×')
            entry = { label = label, remove = remove }
            idEntries[i] = entry
          end
          entry.label:SetText(link)
          entry.label:SetWidth(labelW)
          entry.label:ClearAllPoints()
          entry.label:SetPoint('TOPLEFT', x, lineY - 2)
          entry.label:Show()
          entry.remove:ClearAllPoints()
          entry.remove:SetPoint('TOPLEFT', x + labelW + 4, lineY - 2)
          entry.remove.id = id
          entry.remove:SetScript('OnClick', function(self)
            db.RemoveItemFromCategory(catName, self.id)
            pipeline.Refresh('category-editor')
            refresh()
          end)
          entry.remove:Show()
          rowBottom = math.max(rowBottom, lineY + lineHeight)
          x = x + labelW + 4 + 20 + idGap
        end

        if #ids == 0 then
          if not row.emptyLabel then
            row.emptyLabel = row:CreateFontString(nil, 'OVERLAY', 'GameFontDisable')
            row.emptyLabel:SetText('(none)')
          end
          row.emptyLabel:ClearAllPoints()
          row.emptyLabel:SetPoint('TOPLEFT', x, -6)
          row.emptyLabel:Show()
          rowBottom = math.max(rowBottom, -6 + lineHeight)
          x = x + 50
        elseif row.emptyLabel then
          row.emptyLabel:Hide()
        end

        -- Inline Add input + Add button, placed after items on this line if room, else a new line
        if not row.addEdit then
          row.addEdit = CreateFrame('EditBox', nil, row, 'InputBoxTemplate')
          row.addEdit:SetSize(80, 22)
          row.addEdit:SetAutoFocus(false)
          row.addEdit:SetScript('OnEnterPressed', function(self) self:ClearFocus() end)
        end
        local addEditW, addBtnW = 80, 54
        if x + addEditW + addBtnW + idGap > maxRight and x > idStartX then
          x = idStartX
          lineY = lineY + lineHeight
        end
        row.addEdit:ClearAllPoints()
        row.addEdit:SetPoint('TOPLEFT', x, lineY - 2)
        row.addEdit:SetText('')
        row.addEdit:Show()
        rowBottom = math.max(rowBottom, lineY + lineHeight)

        if not row.addBtn then
          row.addBtn = CreateFrame('Button', nil, row, 'UIPanelButtonTemplate')
          row.addBtn:SetSize(54, 22)
          row.addBtn:SetText('Add')
        end
        row.addBtn:ClearAllPoints()
        row.addBtn:SetPoint('TOPLEFT', x + addEditW + 6, lineY - 2)
        row.addBtn:SetScript('OnClick', function()
          local text = row.addEdit:GetText():trim()
          local num = tonumber(text)
          if not num or num <= 0 then
            print('|cff00ff00BagsOfSorting|r: Item ID must be a number')
            return
          end
          if not db.AddItemToCategory(catName, num) then
            print('|cff00ff00BagsOfSorting|r: Cannot add to ' .. catName .. ' (rule-based categories cannot be edited here)')
            return
          end
          pipeline.Refresh('category-editor')
          refresh()
          row.addEdit:SetText('')
        end)
        row.addBtn:Show()
      end

      y = y - (rowBottom + 6 + rowGap)
    end

    -- Hide any leftover rows (categories removed)
    for _, row in pairs(rows) do
      local shown = false
      for _, catName in ipairs(categoryList) do
        if rows[catName] == row then shown = true break end
      end
      if not shown then row:Hide() end
    end

    scrollChild:SetHeight(math.max(-y + 10, 1))
    scrollChild:SetWidth(width - 36)
  end

  refresh()

  -- Close: hides the dialog. Edits commit immediately, there is no Cancel.
  local doneBtn = CreateFrame('Button', nil, categoryEditorFrame, 'UIPanelButtonTemplate')
  doneBtn:SetSize(100, 26)
  doneBtn:SetPoint('BOTTOMRIGHT', -16, 16)
  doneBtn:SetText('Close')
  doneBtn:SetScript('OnClick', function()
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