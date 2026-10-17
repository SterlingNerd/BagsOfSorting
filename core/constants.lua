-- Container arithmetic and layout constants, derived from the client's own constants.
--
-- agents.md: never enumerate Enum.BagIndex to find containers. On Forever the enum has no
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
constants.WINDOW_TITLE_HEIGHT = 26

-- docs/03: chunk phases 2-4 across frames above this many items.
constants.ASYNC_ITEM_THRESHOLD = 60
constants.ASYNC_ITEMS_PER_FRAME = 40

-- docs/04: the item cache is bounded (FR-97).
constants.MAX_ITEM_CACHE = 4000

-- docs/04 §Rule tree.
constants.MAX_RULE_DEPTH = 2

return constants
