# frames

The only modules that touch frames. They read the layout model and never write config (NFR-4).

| File | What it is |
|---|---|
| `item.lua` | pooled `ItemButton`s built from `ContainerFrameItemButtonTemplate`; each button's wrapper frame carries the real container index so Blizzard's own click/drag/tooltip/stack-split handlers do the work (FR-60) |
| `section.lua` | pooled section blocks: title + grid |
| `window.lua` | window shells built from `PortraitFrameFlatTemplate` (the client's own bag window), anchored off the bag bar by default, drag + saved position |

Not here yet: header handles, chips, menus, inspector, money, empty slots, bag bar, move mode —
all M2/M4.
