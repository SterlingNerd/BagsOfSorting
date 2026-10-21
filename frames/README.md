# frames

The only modules that touch frames. They read the layout model and never write config (NFR-4).

| File | What it is |
|---|---|
| `item.lua` | pooled `ItemButton`s built from `ContainerFrameItemButtonTemplate`; each button's wrapper frame carries the real container index so Blizzard's own click/drag/tooltip/stack-split handlers do the work (FR-60). `PaintEmpty` draws the same button as an empty slot holding a free-slot count (issue #36) |
| `section.lua` | pooled section blocks: title + grid |
| `window.lua` | window shells built from `PortraitFrameFlatTemplate` (the client's own bag window), with the client's own bag chrome on them — small portrait ring, 36 px bag icon, panel background colour (issue #34) — anchored off the client's bag window by default, drag + saved position, and the free-slot indicator on the window the model gave the count to |
| `money.lua` | the window money bar: the client's own `ContainerMoneyFrameTemplate`, anchored across the window's bottom edge (FR-48). One window carries it — the default backpack window the model picks (issue #42). Money only — backpack currencies are a later story |

Not here yet: header handles, chips, menus, inspector, the **slots** half of FR-44 (every empty slot
drawn, `frames/emptyslot.lua`), bag bar, move mode — all M2/M4.

## Window stacking

One base level, derived not hardcoded, so nothing of Blizzard's interleaves with a window (issue #34).
`frames/window.lua` puts the shell and its panel background on `CONTENT_BASE` (300) and marks the shell
`toplevel`, which is what `ContainerFrameCombinedBags` itself carries. Everything else reads the level
of the frame it was drawn into: section 301, button wrapper 302, `ItemButton` 303, money bar 301. The
template's own chrome sits above all of it — portrait 400, border 500, title and close 510 — so the
order inside a window is Blizzard's: background, content, portrait, border, title. 300 is above
`MainActionBar` (50), its EndCaps (100), `BagsBar` (52) and Blizzard's `ContainerFrameItemButtonTemplate`
(10), which is the whole z-order complaint on that issue. Measured on the live client (`/bos test 34`,
2026-10-20): `UIParent` is itself MEDIUM at level 0 and none of these frames are strata-fixed, so levels
are the only lever. Where a window overlaps Blizzard's own bag window, **Blizzard's draws on top** — its
chrome carries the same 400/500/510 numbers and its window is `toplevel` — and that is the accepted
behaviour, not a bug to chase: the client's bags stay reachable (FR-51).


## The border art is 95 px tall, and the window is floored at it

Measured on the live client (`/bos test 43`, 2026-10-20 and 2026-10-21). `HeldBagLayout`'s top-left
corner — the portrait ring — renders **95x94**, its top 16 px above the window's top edge and its bottom
**79 px below it**, and the medallion's arm runs down the window's left side for all 79 of that. The
`LeftEdge` and `RightEdge` come back **95x0** on every window we render: the side borders are corner art,
not edges.

`windows.Render` calls `NineSliceUtil.UpdateCornerCropping` after every `SetSize` — the call
`ContainerFrameMixin:UpdateFrameSize` makes for the client's own bag windows (`ContainerFrame.lua:992`,
`NineSlice.lua:263`) — which leaves `height + 19 − 90` of bottom corner: 32 px on a 103-tall window, 39 on
110, 77 on 147, 100 on 171. Without that call every window draws its bottom corners at their full 512 px
atlas. The crop is capped at the corner's own atlas height (`NineSlice.lua:253`), so below 72 px there is
no valid bottom corner at all — the shrink needed exceeds the whole corner, and a corner the client cannot
shrink renders at full size.

So the height is floored instead of the art clipped: `constants.WINDOW_CHROME_HEIGHT = 95` is the art's own
extent, and `layout/flow.lua` measures every window against it. A window shorter than 95 px has its arm
hanging past its own bottom edge and into the window below — known, accepted, and open for the art edit
that would fix it (issue #43, issue #31).
