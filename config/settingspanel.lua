-- Options → AddOns entry (FR-88): the native home for the settings that genuinely need a window.
-- Forever ships the modern settings API (`Settings.RegisterVerticalLayoutCategory` +
-- `Settings.RegisterAddOnCategory`, Blizzard_Settings_Shared/Blizzard_Settings.lua), so there is
-- no AceConfig and no settings window of our own invention.
--
-- One setting exists today, so exactly one control exists today. The utility panes (profiles,
-- presets, import/export, find) arrive with the panes that own them (docs/06 M5/M6).

local _, addon = ...

local db = addon:GetModule('DB')
local log = addon:GetModule('Log')

---@class AddonOptions: BoSModule
local options = addon:NewModule('AddonOptions')

--- Called from core/init.lua after db.Initialize, because an addon setting writes straight into
--- the SavedVariables table and that table does not exist before ADDON_LOADED.
function options.Register()
  if not (Settings and Settings.RegisterVerticalLayoutCategory) then
    log.Debug('no settings API on this client, skipping the options panel entry')
    return
  end

  local category = Settings.RegisterVerticalLayoutCategory(addon.title)

  local debugSetting = Settings.RegisterAddOnSetting(category, 'BAGSOF_SORTING_DEBUG', 'debug',
    db.Settings(), Settings.VarType.Boolean, 'Debug logging', Settings.Default.False)
  debugSetting:SetValueChangedCallback(function(_, value)
    log.SetDebug(value)
  end)
  Settings.CreateCheckbox(category, debugSetting, 'Write refresh timings and pipeline detail to the chat log.')

  Settings.RegisterAddOnCategory(category)
  options.categoryID = category:GetID()
  log.Debug('registered options panel category', options.categoryID)
end

return options
