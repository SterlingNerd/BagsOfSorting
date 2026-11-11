-- WoW globals we actually touch. Keep this list as short as the code is:
-- if a name is not used by the addon, it does not belong here.
std = "lua51"
max_line_length = false

exclude_files = {
    "libs",
    ".deploy",
    ".luacheckrc",
    "tests",
}

ignore = {
    "11/SLASH_.*",              -- slash command name globals
    "1/[A-Z][A-Z][A-Z0-9_]+",   -- FrameXML constants (NUM_BAG_SLOTS, KEYRING_CONTAINER, ...)
    "212/self",                 -- module methods follow the addon:NewModule(name) convention
    "211",                      -- unused loop variable
    "212",                      -- unused argument
    "213",                      -- unused variable
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
    "C_NewItems",
    "Settings",
    "ItemLocation",
    "ItemButtonUtil",
    "ContainerFrameSettingsManager",
    "ContainerFrameCombinedBags",
    "OpenAllBags",
    "hooksecurefunc",
    "BankFrame",
    "GetBindingKey",
    "GetCurrentBindingSet",
    "SetBinding",
    "C_KeyBindings",
    "BINDING_HEADER_BAGSOF_SORTING",
    "BINDING_NAME_BAGSOF_SORTING_TOGGLE",
    "IconDataProviderMixin",
    "EditModeManagerFrame",
    "NineSliceUtil",
    "IsUsingCombinedBags",
    "C_Bank",
    "CreateColor",
    "PANEL_BACKGROUND_COLOR",

    "GetTime",
    "GetBuildInfo",
    "issecure",
    "GetCursorInfo",
    "GetCVar",
    "GetAddOnMemoryUsage",
    "GetScreenHeight",
    "GetScreenWidth",
    "GetCoinTextureString",
    "GetMoney",
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

    -- Dropdown/Menu APIs
    "CloseDropDownMenus",
    "EasyMenu",
    "ToggleDropDownMenu",
    "UIDropDownMenu_Initialize",
    "UIDropDownMenu_AddButton",
    "UIDropDownMenu_CreateInfo",
    "UIDropDownMenu_SetWidth",
    "UIDropDownMenu_SetSelectedValue",

    -- StaticPopup APIs
    "StaticPopup_Show",
    "StaticPopupDialogs",

    -- Input/key APIs
    "IsControlKeyDown",
    "GetInventoryItemLink",
    "GetInventoryItemID",

    -- Custom globals set by our frames
    "ShowItemMenu",
    "ShowSectionMenu",
    "OpenSectionEditModal",
    "AddSectionBelow",
    "ShowWindowMenu",
    "OpenWindowEditModal",
    "AddSectionToWindow",
    "C_EquipmentSet",
}
