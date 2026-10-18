-- WoW globals we actually touch. Keep this list as short as the code is:
-- if a name is not used by the addon, it does not belong here.
std = "lua51"
max_line_length = false

exclude_files = {
    "libs",
}

ignore = {
    "11/SLASH_.*",              -- slash command name globals
    "1/[A-Z][A-Z][A-Z0-9_]+",   -- FrameXML constants (NUM_BAG_SLOTS, KEYRING_CONTAINER, ...)
    "212/self",                 -- module methods follow the addon:NewModule(name) convention
}

globals = {
    "BagsOfSortingDB",
    "WOW_PROJECT_ID",
    "WOW_PROJECT_CAMELOT",
    "WOW_PROJECT_MAINLINE",
    "NUM_BAG_SLOTS",
    "NUM_REAGENTBAG_SLOTS",
    "NUM_TOTAL_EQUIPPED_BAG_SLOTS",
    "ITEM_INVENTORY_BANK_BAG_OFFSET",
    "NUM_CHARACTER_BANK_SLOTS",
    "KEYRING_CONTAINER",
    "ITEM_QUALITY_COLORS",

    "CreateFrame",
    "UIParent",
    "GameTooltip",
    "Enum",
    "C_Container",
    "C_Item",
    "C_Timer",
    "C_CurrencyInfo",
    "C_GameRules",
    "C_AddOns",
    "C_Warbank",
    "Settings",
    "ItemLocation",
    "ItemButtonUtil",
    "ContainerFrameSettingsManager",
    "ContainerFrameCombinedBags",
    "GetBinding",
    "BINDING_HEADER_BAGSOF_SORTING",
    "BINDING_NAME_BAGSOF_SORTING_TOGGLE",
    "IconDataProviderMixin",
    "EditModeManagerFrame",
    "IsUsingCombinedBags",
    "C_Bank",

    "GetTime",
    "GetBuildInfo",
    "GetCoinTextureString",
    "BlizzSortBags",
    "UnitName",
    "GetRealmName",
    "InCombatLockdown",
    "IsLoggedIn",
    "IsAddOnLoaded",
    "SetItemButtonTexture",
    "SetItemButtonQuality",
    "SetItemButtonCount",
    "ClearItemButtonOverlay",

    "SlashCmdList",
    "BagsOfSorting_OnAddonCompartmentClick",
    "BagsOfSorting_Toggle",
}
