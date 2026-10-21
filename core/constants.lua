-- Container arithmetic and layout constants, derived from the client's own constants.
--
-- wow-forever-api skill (references/containers-and-bags.md): never enumerate Enum.BagIndex to find
-- containers. On Forever the enum has no
-- BankBag_* values while Camelot's BankFrame computes bank-bag indices arithmetically, and
-- those land on the same numbers as CharacterBankTab_1..8. The container list data/harvest
-- iterates is discovered by probing (issue #9), never hardcoded.

local _, addon = ...

---@class Constants: BoSModule
local constants = addon:NewModule('Constants')

constants.BACKPACK = 0
constants.KEYRING = KEYRING_CONTAINER
constants.NUM_BAG_SLOTS = NUM_BAG_SLOTS or 4
constants.NUM_REAGENTBAG_SLOTS = NUM_REAGENTBAG_SLOTS or 1
constants.NUM_TOTAL_EQUIPPED_BAG_SLOTS = NUM_TOTAL_EQUIPPED_BAG_SLOTS
  or (constants.NUM_BAG_SLOTS + constants.NUM_REAGENTBAG_SLOTS)
constants.REAGENTBAG_INDEX = constants.BACKPACK + constants.NUM_BAG_SLOTS + 1
constants.ITEM_INVENTORY_BANK_BAG_OFFSET = ITEM_INVENTORY_BANK_BAG_OFFSET
constants.NUM_CHARACTER_BANK_SLOTS = NUM_CHARACTER_BANK_SLOTS

-- Keys /bos prints so the client facts land in one place (docs/06 M0, issue #2).
constants.ProbeKeys = {
  'NUM_BAG_SLOTS', 'NUM_REAGENTBAG_SLOTS', 'NUM_TOTAL_EQUIPPED_BAG_SLOTS',
  'REAGENTBAG_INDEX', 'ITEM_INVENTORY_BANK_BAG_OFFSET', 'NUM_CHARACTER_BANK_SLOTS', 'KEYRING',
}

-- ItemButton / ContainerFrameItemButtonTemplate are 37x37 (ContainerFrame.xml).
constants.BUTTON_SIZE = 37
constants.BUTTON_GAP = 1
constants.SECTION_TITLE_HEIGHT = 18
constants.WINDOW_PADDING = 8
-- The band between the window's top edge and its first section. It has to clear the portrait: the
-- client's bag portrait is 36 px at (-4, +1), so its bottom edge sits 35 px below the top edge, and
-- content starting any higher draws section titles underneath it (issue #34). Blizzard's own bag
-- window budgets 48 px for its titlebar and attic (`ContainerFrameMixin:GetPaddingHeight`).
constants.WINDOW_TITLE_HEIGHT = 40

-- The money bar is SmallMoneyFrameTemplate: 13 px tall, inset 8 px from the window's bottom edge,
-- with a 17 px coin-box border and Blizzard's own 4 px clearance above it (ContainerFrame.xml,
-- ContainerFrame.lua:UpdateCurrencyFrames). Its top edge therefore lands 21 px off the bottom edge
-- and the window's own padding covers 8 of that, so 17 px more is what the last row needs.
constants.MONEY_BAR_SPACE = 17

-- The bag chrome `HeldBagLayout` draws is 95 px end to end: the portrait ring renders 95x94 with its top
-- 16 px above a window's top edge and its bottom 79 px below it (`/bos test 43`, 2026-10-21). A window
-- shorter than this is shorter than its own frame art, and below 72 the client's corner crop fails
-- outright — it would have to remove more than the whole corner, and a corner it cannot shrink renders
-- at its full 512 px atlas. It is the floor a window's height is measured against.
constants.WINDOW_CHROME_HEIGHT = 95

-- docs/03: chunk phases 2-4 across frames above this many items.
constants.ASYNC_ITEM_THRESHOLD = 60
constants.ASYNC_ITEMS_PER_FRAME = 40

-- docs/04: the item cache is bounded (FR-97).
constants.MAX_ITEM_CACHE = 4000

-- docs/04 §Rule tree.
constants.MAX_RULE_DEPTH = 2

return constants
