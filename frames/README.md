# frames

The only modules that touch frames. They read the layout model and never write config (NFR-4).

| File | What it is |
|---|---|
| `item.lua` | pooled `ItemButton`s built from `ContainerFrameItemButtonTemplate`; each button's wrapper frame carries the real container index so Blizzard's own click/drag/tooltip/stack-split handlers do the work (FR-60). `PaintEmpty` draws the same button as an empty slot holding a free-slot count (issue #36) |
| `section.lua` | pooled section blocks: title + grid |
| `window.lua` | window shells built from `PortraitFrameFlatTemplate` (the client's own bag window), anchored off the bag bar by default, drag + saved position, and the free-slot indicator on the window the model gave the count to |
| `money.lua` | the window money bar: the client's own `ContainerMoneyFrameTemplate`, anchored across the window's bottom edge (FR-48). Money only — backpack currencies are a later story |

Not here yet: header handles, chips, menus, inspector, the **slots** half of FR-44 (every empty slot
drawn, `frames/emptyslot.lua`), bag bar, move mode — all M2/M4.
