-- The only file that knows what the client can do (FR-2). Everything else asks
-- client.get('itemButtonType') or client.has('reagentBank').
--
-- Pattern copied from agents.md §Detection pattern; capability values are resolved once
-- at load, and a false capability means the table that would drive the feature is never
-- built (docs/03 §Client capability layer) rather than a branch at every call site.

local _, addon = ...

---@class Client: BoSModule
local client = addon:NewModule('Client')

local isCamelot = WOW_PROJECT_CAMELOT ~= nil and WOW_PROJECT_ID == WOW_PROJECT_CAMELOT
local isMainline = WOW_PROJECT_MAINLINE ~= nil and WOW_PROJECT_ID == WOW_PROJECT_MAINLINE

local function has(t, key)
  return t and t[key] ~= nil
end

---@class BoSCapabilities
local caps = {
  isForever = isCamelot,
  isRetailLike = isMainline or isCamelot,
  hasWarbank = false,             -- Forever ships no warbank (agents.md)
  hasReagentBank = false,         -- no REAGENT_BANK_TAB on this client
  hasBlizzSort = false,           -- no BlizzSortBags: new-item handling is ours (FR-47)
  hasContainerQuestInfo = has(C_Container, 'GetContainerItemQuestInfo'),
  hasModernMoney = isCamelot,     -- atlas coin textures
  hasAsyncItemFetch = has(C_Item, 'RequestLoadItemDataByID'),
  hasSearchMatcher = has(ItemButtonUtil, 'GetItemContextMatchResultForItem'),
  hasSearchMatcherContainer = has(ItemButtonUtil, 'GetItemContextMatchResultForContainer'),
  hasIconPicker = IconDataProviderMixin ~= nil,
  hasEditMode = EditModeManagerFrame ~= nil,
  hasSettingsAPI = has(Settings, 'RegisterAddOnCategory'),
  hasWowStyle1Dropdown = WowStyle1DropdownTemplate ~= nil,
  hasClassicDropdown = UIDropDownMenuTemplate ~= nil,
  -- The bag window shell we build from (docs/07 Q16: the client's own bag visuals).
  hasBagWindowTemplate = PortraitFrameFlatTemplate ~= nil,
  hasItemButtonTemplate = ContainerFrameItemButtonTemplate ~= nil,
  itemButtonType = 'ItemButton',
}

---@param key string
---@return any
function client.get(key)
  return caps[key]
end

---@param key string
---@return boolean
function client.has(key)
  return caps[key] == true
end

--- Facts that need a player to exist. Called at PLAYER_LOGIN, printed by `/bos`
--- (docs/06 M0: this dump is the Forever fact verification tool).
---@return string[]
function client.Probe()
  local lines = {}
  local function line(fmt, ...)
    lines[#lines + 1] = string.format(fmt, ...)
  end

  line('project=%s camelot=%s build=%s', tostring(WOW_PROJECT_ID), tostring(isCamelot), select(4, GetBuildInfo()))
  local scriptsDisabled = C_GameRules and Enum.GameRule and Enum.GameRule.UserScriptsDisabled
    and C_GameRules.IsGameRuleActive(Enum.GameRule.UserScriptsDisabled)
  line('scriptsAllowed=%s', tostring(not scriptsDisabled))

  for _, key in ipairs({
    'itemButtonType', 'hasWarbank', 'hasReagentBank', 'hasBlizzSort', 'hasContainerQuestInfo',
    'hasModernMoney', 'hasAsyncItemFetch', 'hasSearchMatcher', 'hasSearchMatcherContainer',
    'hasIconPicker', 'hasEditMode', 'hasSettingsAPI', 'hasWowStyle1Dropdown', 'hasClassicDropdown',
    'hasBagWindowTemplate', 'hasItemButtonTemplate',
  }) do
    line('%s=%s', key, tostring(caps[key]))
  end

  local constants = addon:GetModule('Constants')
  for _, key in ipairs(constants.ProbeKeys) do
    line('%s=%s', key, tostring(constants[key]))
  end

  line('combinedBags=%s', tostring(IsUsingCombinedBags and IsUsingCombinedBags()))

  if KEYRING_CONTAINER ~= nil then
    line('keyring index=%s slots=%s', tostring(KEYRING_CONTAINER),
      tostring(C_Container and C_Container.GetContainerNumSlots and select(2, pcall(C_Container.GetContainerNumSlots, KEYRING_CONTAINER)) or 'ERR'))
  else
    line('keyring=absent')
  end

  if C_Bank and C_Bank.FetchNumPurchasedBankTabs and Enum.BankType then
    local ok, tabs = pcall(C_Bank.FetchNumPurchasedBankTabs, Enum.BankType.Character)
    line('purchasedBankTabs=%s', ok and tostring(tabs) or 'ERR')
  end
  if C_Bank and C_Bank.ShouldUsePlayerBagsInBank then
    local ok, v = pcall(C_Bank.ShouldUsePlayerBagsInBank)
    line('shouldUsePlayerBagsInBank=%s', ok and tostring(v) or 'ERR')
  end

  return lines
end

return client
