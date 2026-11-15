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

  sectionEditFrame = CreateFrame('Frame', 'BagsOfSortingSectionEdit', UIParent)

  -- Match the category editor: translucent dialog background + Dialog NineSlice border.
  local border = CreateFrame('Frame', nil, sectionEditFrame, 'DialogBorderTranslucentTemplate')
  border:SetAllPoints(sectionEditFrame)
  sectionEditFrame:SetSize(350, 450)
  sectionEditFrame:SetPoint('CENTER')
  sectionEditFrame:SetFrameStrata('DIALOG')
  sectionEditFrame:SetMovable(true)
  sectionEditFrame:EnableMouse(true)
  sectionEditFrame:RegisterForDrag('LeftButton')
  sectionEditFrame:SetScript('OnDragStart', sectionEditFrame.StartMoving)
  sectionEditFrame:SetScript('OnDragStop', sectionEditFrame.StopMovingOrSizing)
  sectionEditFrame.TitleText = sectionEditFrame:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
  sectionEditFrame.TitleText:SetPoint('TOP', 0, -14)
  sectionEditFrame.TitleText:SetText('Edit Section: ' .. model.name)

  local closeBtn = CreateFrame('Button', nil, sectionEditFrame, 'UIPanelCloseButton')
  closeBtn:SetPoint('TOPRIGHT', -10, 8)
  closeBtn:SetScript('OnClick', function()
    sectionEditFrame:Hide()
  end)

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
  catContainer:SetSize(290, 250)
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

  sectionEditFrame:Show()
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
--- Open the category editor dialog (issue #71). Lists every enabled, non-__catchall category;
--- rule-based categories are read-only, manual categories list their item IDs as clickable links
--- (with remove buttons) plus an inline Add input placed last in the row. Edits commit immediately
--- and repaint the bags. db must not require Pipeline (circular require risk), so the refresh
--- reason is passed in from here, the same way OpenSectionEdit passes 'section-edit'.
function editModals.OpenCategoryEditor()
  if categoryEditorFrame then
    categoryEditorFrame:Hide()
  end

  local sw, sh = GetScreenWidth(), GetScreenHeight()
  local width, height = math.floor(sw * 0.5), math.floor(sh * 0.5)

  categoryEditorFrame = CreateFrame('Frame', 'BagsOfSortingCategoryEditor', UIParent)
  categoryEditorFrame:SetSize(width, height)
  categoryEditorFrame:SetPoint('CENTER')
  categoryEditorFrame:SetFrameStrata('DIALOG')
  categoryEditorFrame:SetMovable(true)
  categoryEditorFrame:EnableMouse(true)
  categoryEditorFrame:RegisterForDrag('LeftButton')
  categoryEditorFrame:SetScript('OnDragStart', categoryEditorFrame.StartMoving)
  categoryEditorFrame:SetScript('OnDragStop', categoryEditorFrame.StopMovingOrSizing)

  -- Match the HUD Edit Mode window: translucent dialog background + Dialog NineSlice border.
  local border = CreateFrame('Frame', nil, categoryEditorFrame, 'DialogBorderTranslucentTemplate')
  border:SetAllPoints(categoryEditorFrame)

  categoryEditorFrame.TitleText = categoryEditorFrame:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
  categoryEditorFrame.TitleText:SetPoint('TOP', 0, -14)
  categoryEditorFrame.TitleText:SetText('Edit Categories')

  categoryEditorFrame:Show()

  local closeBtn = CreateFrame('Button', nil, categoryEditorFrame, 'UIPanelCloseButton')
  closeBtn:SetPoint('TOPRIGHT', -10, 10)
  closeBtn:SetScript('OnClick', function()
    categoryEditorFrame:Hide()
  end)

  local scrollFrame = CreateFrame('ScrollFrame', nil, categoryEditorFrame, 'UIPanelScrollFrameTemplate')
  scrollFrame:SetPoint('TOPLEFT', 14, -42)
  scrollFrame:SetPoint('BOTTOMRIGHT', -36, 70)

  local scrollChild = CreateFrame('Frame', nil, scrollFrame)
  scrollChild:SetSize(width - 56, 1)
  scrollFrame:SetScrollChild(scrollChild)

  local cats = db.Categories()
  local categoryList = getCategoryList()
  local rows = {}  -- categoryName -> row frame

  local nameWidth = 170
  local rowGap = 16
  local lineHeight = 22
  local idGap = 6
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
        row.nameLabel:SetPoint('TOPLEFT', 8, -7)
      end
      row.nameLabel:SetText(catName)

      -- Remove this whole category (X next to the name; manual categories only,
      -- __catchall is never listed). Removing confirms via a popup so a misclick
      -- cannot wipe a category and its items.
      if isManual then
        if not row.removeCatBtn then
          row.removeCatBtn = CreateFrame('Button', nil, row, 'UIPanelButtonTemplate')
          row.removeCatBtn:SetSize(16, 16)
          row.removeCatBtn:SetText('×')
        end
        local nameW = row.nameLabel:GetStringWidth()
        if nameW == 0 then nameW = textWidth(catName) end
        row.removeCatBtn:ClearAllPoints()
        row.removeCatBtn:SetPoint('TOPLEFT', 8 + nameW + 5, -6)
        row.removeCatBtn:SetScript('OnClick', function(self)
          StaticPopup_Show('BOS_CONFIRM_REMOVE_CATEGORY', catName, nil, catName)
        end)
        row.removeCatBtn:Show()
      elseif row.removeCatBtn then
        row.removeCatBtn:Hide()
      end

      -- Clear per-row dynamic children (id entries + add controls), keeping the name label
      for _, entry in ipairs(row.idEntries or {}) do
        entry.label:Hide()
        entry.remove:Hide()
      end
      if row.addEdit then row.addEdit:Hide() end
      if row.addBtn then row.addBtn:Hide() end
      if row.statusLabel then row.statusLabel:Hide() end
      if row.emptyLabel then row.emptyLabel:Hide() end
      if row.divider then row.divider:Hide() end

      -- Band 1: category name (top of row). Kept at a fixed offset so every row
      --   starts at the same visual height.
      local band1Y = 0
      local band1H = lineHeight        -- name label height

      -- Band 2: content below the name band. Rule-based shows a read-only label;
      --   manual shows item links (+Remove) then an inline Add input. All content
      --   flows downward from band2Y.
      local band2Y = band1Y + band1H + 8          -- 8px gap under the name band
      local contentBottom = band2Y                -- track the lowest content edge
      local x = idStartX                          -- running X cursor for items

      if not isManual then
        -- Rule-based / dynamic category: read-only status label
        if not row.statusLabel then
          row.statusLabel = row:CreateFontString(nil, 'OVERLAY', 'GameFontDisable')
        end
        row.statusLabel:SetPoint('TOPLEFT', idStartX, band2Y)
        row.statusLabel:SetText('(rule-based — read-only)')
        row.statusLabel:Show()
        contentBottom = math.max(contentBottom, band2Y + lineHeight)
      else
        -- Manual category: list item IDs as clickable links horizontally,
        --   wrapping when needed, then an inline Add input below.
        local idEntries = row.idEntries or {}
        row.idEntries = idEntries
        local ids = {}
        if cat.itemIDs then
          for id in pairs(cat.itemIDs) do ids[#ids + 1] = id end
        end
        table.sort(ids)

        local lineY = band2Y
        for i, id in ipairs(ids) do
          local itemID = id  -- capture per-iteration so tooltips and removals keep the right item
          local link = itemLinkFor(itemID)

          local entry = idEntries[i]
          if not entry then
            local lbl = row:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
            lbl:SetJustifyH('LEFT')
            local remove = CreateFrame('Button', nil, row, 'UIPanelButtonTemplate')
            remove:SetSize(18, 16)
            remove:SetText('×')
            entry = { label = lbl, remove = remove }
            idEntries[i] = entry
          end
          entry.label:SetText(link)
          entry.label:Show()
          entry.label:ClearAllPoints()
          entry.label:SetPoint('TOPLEFT', x, lineY)

          local actualW = entry.label:GetStringWidth()
          if actualW == 0 then
            actualW = textWidth(link)
          end
          local entryWidth = actualW + 4 + 18 + idGap
          -- wrap if this item won't fit on the current line (and it's not the first)
          if x + entryWidth > maxRight and x > idStartX then
            x = idStartX
            lineY = lineY + lineHeight
            entry.label:SetPoint('TOPLEFT', x, lineY)
          end

          entry.remove:ClearAllPoints()
          entry.remove:SetPoint('TOPLEFT', x + actualW + 4, lineY)
          entry.remove.id = itemID
          entry.remove:SetScript('OnClick', function(self)
            db.RemoveItemFromCategory(catName, self.id)
            pipeline.Refresh('category-editor')
            refresh()
          end)
          entry.remove:Show()

          entry.label:SetScript('OnEnter', function(self)
            GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
            GameTooltip:SetItemByID(itemID)
            GameTooltip:Show()
          end)
          entry.label:SetScript('OnLeave', function(self)
            GameTooltip:Hide()
          end)

          contentBottom = math.max(contentBottom, lineY + lineHeight)
          x = x + entryWidth
        end

        if #ids == 0 then
          if not row.emptyLabel then
            row.emptyLabel = row:CreateFontString(nil, 'OVERLAY', 'GameFontDisable')
            row.emptyLabel:SetText('(none)')
          end
          row.emptyLabel:ClearAllPoints()
          row.emptyLabel:SetPoint('TOPLEFT', x, band2Y)
          row.emptyLabel:Show()
          contentBottom = math.max(contentBottom, band2Y + lineHeight)
        elseif row.emptyLabel then
          row.emptyLabel:Hide()
        end

        -- Add input + button on their own line below the items.
        lineY = lineY + lineHeight
        if not row.addEdit then
          row.addEdit = CreateFrame('EditBox', nil, row, 'InputBoxTemplate')
          row.addEdit:SetSize(80, 22)
          row.addEdit:SetAutoFocus(false)
          row.addEdit:SetScript('OnEnterPressed', function(self) self:ClearFocus() end)
        end
        row.addEdit:ClearAllPoints()
        row.addEdit:SetPoint('TOPLEFT', idStartX, lineY)
        row.addEdit:SetText('')
        row.addEdit:Show()
        contentBottom = math.max(contentBottom, lineY + 26)

        if not row.addBtn then
          row.addBtn = CreateFrame('Button', nil, row, 'UIPanelButtonTemplate')
          row.addBtn:SetSize(50, 22)
          row.addBtn:SetText('Add')
        end
        row.addBtn:ClearAllPoints()
        row.addBtn:SetPoint('TOPLEFT', idStartX + 86, lineY - 2)
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

      -- Band 3: divider rule between categories
      local dividerY = contentBottom + 10   -- 10px gap under content
      if not row.divider then
        row.divider = row:CreateTexture(nil, 'ARTWORK')
        row.divider:SetHeight(1)
        row.divider:SetColorTexture(0.5, 0.5, 0.5, 0.6)
      end
      row.divider:ClearAllPoints()
      row.divider:SetPoint('TOPLEFT', 8, dividerY)
      row.divider:SetPoint('TOPRIGHT', -8, dividerY)
      row.divider:Show()

      -- Row height: divider bottom + gap, with a floor so short rows are still
      --   tall enough to tap and read comfortably.
      local rowHeight = math.max(dividerY + 1 + 14, band1H + 16 + 44)
      row:SetSize(scrollW - 30, rowHeight)
      y = y - rowHeight
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
    scrollFrame:UpdateScrollChildRect()
  end

  StaticPopupDialogs['BOS_CONFIRM_REMOVE_CATEGORY'] = {
    text = 'Remove category "%s"? Items in it will fall to __catchall.',
    button1 = 'Remove',
    button2 = 'Cancel',
    OnAccept = function(self, data)
      if db.RemoveCategory(data) then
        pipeline.Refresh('category-editor')
        categoryList = getCategoryList()
        refresh()
      end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
  }

  refresh()

  -- Footer: add a brand-new category (below the scroll, left of Close)
  local footer = CreateFrame('Frame', nil, categoryEditorFrame)
  footer:SetSize(340, 38)
  footer:SetPoint('BOTTOMLEFT', 14, 16)

  local newCatLabel = footer:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
  newCatLabel:SetPoint('TOPLEFT', 2, -6)
  newCatLabel:SetText('New category:')

  local newCatName = CreateFrame('EditBox', nil, footer, 'InputBoxTemplate')
  newCatName:SetSize(110, 20)
  newCatName:SetPoint('TOPLEFT', 2, -24)
  newCatName:SetAutoFocus(false)

  local newCatBtn = CreateFrame('Button', nil, footer, 'UIPanelButtonTemplate')
  newCatBtn:SetSize(100, 22)
  newCatBtn:SetPoint('TOPLEFT', 126, -24)
  newCatBtn:SetText('Add Category')
  newCatBtn:SetScript('OnClick', function()
    local name = newCatName:GetText():trim()
    if not db.AddCategory(name, 'manual') then
      print('|cff00ff00BagsOfSorting|r: Could not add category "' .. tostring(name) .. '" (empty or duplicate)')
      return
    end
    newCatName:SetText('')
    pipeline.Refresh('category-editor')
    categoryList = getCategoryList()
    refresh()
  end)

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