-- The only file that knows what the client can do (FR-2). Everything else asks
-- client.get('itemButtonType') or client.has('reagentBank').
--
-- Pattern copied from the wow-forever-api skill (references/client-identity.md); capability values are
-- resolved once
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
  hasWarbank = C_Warbank ~= nil,
  hasReagentBank = has(Enum, 'BagIndex') and Enum.BagIndex.ReagentBag ~= nil,
  hasBlizzSort = BlizzSortBags ~= nil,
  hasContainerQuestInfo = has(C_Container, 'GetContainerItemQuestInfo'),
  hasModernMoney = GetCoinTextureString ~= nil,
  hasAsyncItemFetch = has(C_Item, 'RequestLoadItemDataByID'),
  hasSearchMatcher = has(ItemButtonUtil, 'GetItemContextMatchResultForItem'),
  hasSearchMatcherContainer = has(ItemButtonUtil, 'GetItemContextMatchResultForContainer'),
  hasIconPicker = IconDataProviderMixin ~= nil,
  hasEditMode = EditModeManagerFrame ~= nil,
  hasSettingsAPI = has(Settings, 'RegisterAddOnCategory'),
  itemButtonType = 'ItemButton',
}

-- Asserted from `wow-ui-source` instead of measured on the running client. The dump marks these,
-- so an assumption is never read as a measurement.
local ASSUMED = { itemButtonType = true }

-- Frame templates (`ContainerFrameItemButtonTemplate`, `WowStyle1DropdownTemplate`, ...) are not
-- probed here: they resolve through the frame-tree registry, not globals, so `X ~= nil` is always
-- false whether or not the client ships them. The addon building its own frames is the test.

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
    'hasIconPicker', 'hasEditMode', 'hasSettingsAPI',
  }) do
    line('%s=%s%s', key, tostring(caps[key]), ASSUMED[key] and ' (assumed)' or '')
  end

  local constants = addon:GetModule('Constants')
  for _, key in ipairs(constants.ProbeKeys) do
    line('%s=%s', key, tostring(constants[key]))
  end

  -- `IsUsingCombinedBags` is not a global on this client; it is a method on Blizzard's own
  -- ContainerFrameSettingsManager, which agents.md hard rule 8 says we must not call from addon
  -- code (it builds and stores state). Presence only, never a call.
  line('combinedBagsManager=%s', tostring(ContainerFrameSettingsManager ~= nil))

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
