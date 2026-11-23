# Simple category editor — spec (M3 slice, step 1)

A small, deliberately limited step toward the full M3 category editor
(`docs/06-milestones.md` M3). It exposes the `itemIDs` list on manual
categories through two UI entry points:

1. A **Category Editor dialog** opened from the bag-window context menu
   that lists every category and lets you edit its item ID list.
2. **Item menu options** (Ctrl+right-click an item): Add to Category /
   Remove from Category / Exclude from category (disabled).

No nested rule logic, no `any`/`all`/`none`/`EXCEPT`, no drag-and-drop,
no configure mode, no undo for this step. Each edit commits immediately.

---

## Data model (no change)

Categories live in `db.Profile().categories` (`db.Categories()`), keyed by
name. Manual categories already carry an `itemIDs` set:

```lua
['Tools'] = {
  kind = 'manual', enabled = true, duplicate = false,
  itemIDs = { [2901] = true, [6948] = true },   -- Mining Pick, Hearthstone
},
```

This spec only mutates `category.itemIDs[ itemID ] = true/false`. Rule-based
categories (`kind = 'rules'`, e.g. Junk, Consumables) are listed but their
item list is read-only here — they are owned by rules, not by a manual ID
list. (Decide later whether to even show them; showing them read-only is
safe and informative.)

Two helpers to add to `core/db.lua`:

```lua
function db.AddItemToCategory(categoryName, itemID)
  local cat = db.Categories()[categoryName]
  if not cat or cat.kind ~= 'manual' then return false end
  cat.itemIDs = cat.itemIDs or {}
  if cat.itemIDs[itemID] then return false end
  cat.itemIDs[itemID] = true
  db.NotifyModelChanged()
  pipeline.Refresh('category-editor')  -- see wiring note below
  return true
end

function db.RemoveItemFromCategory(categoryName, itemID)
  local cat = db.Categories()[categoryName]
  if not cat or not cat.itemIDs then return false end
  if not cat.itemIDs[itemID] then return false end
  cat.itemIDs[itemID] = nil
  db.NotifyModelChanged()
  pipeline.Refresh('category-editor')
  return true
end
```

`pipeline` is the module that re-runs the classify/harvest/paint pipeline
(`addon:GetModule('Pipeline')`, used by `editModals` via
`pipeline.Refresh('section-edit')`). `db` does not currently require
`pipeline`; pass the refresh reason in from the caller instead of requiring
Pipeline inside DB to avoid a circular require (DB → Pipeline → ?).

---

## UI 1 — Category Editor dialog

**Access:** window title context menu (`ShowWindowMenu` in
`frames/window.lua`) gains an entry:

```
Edit Categories…   (notCheckable)
```

Opening it creates/reuses a `BasicFrameTemplateWithInset` DIALOG frame
(centered, movable, like `editModals.OpenSectionEdit`).

**Contents:**

- Title: `Edit Categories`.
- A scrollable list, one row per category (enabled, non-`Unmatched Items`
  categories, matching `getCategoryList()` in `frames/editmodals.lua`).
- Each row shows:
  - category name (label)
  - its item IDs as a comma/space-separated list (or “(none)”)
  - a small **Remove** button next to each listed ID (removes that ID)
- Below the list: an **Item ID** input box + **Add** button. Typing a
  number and clicking Add appends it to the *currently selected* category.
  A dropdown above the input selects which category is being edited
  (simpler than per-row add boxes; one active category at a time).
- Footer: **Close** button (hides the dialog; no Cancel semantics — edits
  commit immediately as they are made).

**Behavior:**

- Selecting a category in the dropdown populates the input/rows for that
  category.
- Add: parse the input as a number; if the category is rule-based, refuse
  (print a chat message, keep dialog open); otherwise call
  `db.AddItemToCategory(name, id)` and refresh the row list.
- Remove per-ID: call `db.RemoveItemFromCategory(name, id)`.
- After any successful mutation: `db.NotifyModelChanged()` +
  `pipeline.Refresh('category-editor')` so the bags repaint with the new
  ownership immediately.

**Commit model:** immediate. No Apply/Cancel, no draft, no undo in this
step — consistent with “structural edits commit the moment they are made”
(`docs/02-requirements.md` FR-75) but without the staging machinery yet.

---

## UI 2 — Item menu options

In `ShowItemMenu` (`frames/item.lua`), after the existing disabled
placeholders (`Move to section…`, `Ignore this item`, `Clear ignore`),
add:

```
Add to Category   ▸  <submenu: one entry per manual category>
Remove from Category   ▸  <submenu: one entry per category that owns this itemID>
Exclude from category   (disabled, grayed)
```

- **Add to Category** submenu lists every enabled manual category not
  already owning the itemID. Clicking one calls
  `db.AddItemToCategory(category, item.itemID)` then
  `db.NotifyModelChanged()` + `pipeline.Refresh('add-to-category')`.
  If the item is already in the category, that category is omitted from the
  submenu (or shown disabled).
- **Remove from Category** submenu lists every category whose
  `itemIDs[item.itemID]` is true. Clicking one calls
  `db.RemoveItemFromCategory(category, item.itemID)` + notify + refresh.
- **Exclude from category** is a single disabled entry
  (`disabled = true`) with no submenu. It exists only to reserve the menu
  slot and communicate intent. Enabling it requires “not itemid” / negative
  logic in the rule grammar, which is explicitly out of scope here.

The dropdown module (`frames/dropdown.lua`) supports `hasArrow` +
`menuList` submenus and `disabled`, so no new dropdown machinery is needed.

---

## Out of scope (explicitly deferred to full M3)

- `any`/`all`/`none`/`EXCEPT` rule trees, rule chips, the `EXCEPT` row.
- Draft staging with Apply/Cancel, undo/redo, `⚠` competitor markers.
- The live item list (“items matching this category”) preview pane.
- Drag-and-drop assignment, configure mode, section handles.
- “Exclude from category” becoming functional (needs negative logic).
- Persisting across sessions beyond the existing profile save (categories
  are already part of the profile).

---

## Acceptance criteria (checklist)

- [ ] Window title context menu has “Edit Categories…” opening a dialog.
- [ ] Dialog lists categories and shows each one’s item IDs.
- [ ] Adding an item ID to a manual category updates `category.itemIDs`
      and repaints the bags immediately.
- [ ] Removing an item ID removes it from the category and repaints.
- [ ] Item menu has Add to Category / Remove from Category submenus that
      add/remove the clicked item’s itemID.
- [ ] Item menu has “Exclude from category” present but disabled.
- [ ] Rule-based categories cannot be edited here (refused, message shown).

---

## Wiring note

`ShowWindowMenu` already receives `windowConfig` and calls
`editModals`/`pipeline` indirectly. The category editor can live in
`frames/editmodals.lua` as `editModals.OpenCategoryEditor()` (reusing the
dialog conventions there) or a new `frames/categoryeditor.lua` module —
whichever keeps the diff smallest. It needs `db` and a way to trigger
`pipeline.Refresh`; pass the refresh reason in from the caller rather than
requiring Pipeline from DB.
