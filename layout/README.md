# layout

`flow.lua` packs section blocks into a window's column budget and sizes the window to its
content (FR-40). A window that carries a free-slot count gets one more cell at the end of its
column, and `emptyOffsetY` is where the frames layer draws it (issue #36).

A window with nothing in it is its title band and nothing more (issue #43): no blank cell, no body, no
grid. It still exists and still takes its slot in the column (#28 decision 2), and it grows back the
moment a category gives it an item.

`anchors.lua` places the windows themselves (FR-41, `docs/07` Q24): a stack that grows upward from
the client's own bag window and wraps to a new column on the left when the next window will not fit,
with the cap measured as `screenHeight − allowance` at layout time. It is a port of Blizzard's
`UpdateContainerFrameAnchors` loop, never a call to it — see the file header for why.

shortcut: sections stack vertically, one per row. River packing (several sections sharing a
row) and the measurement-based title sizing are M2 (AC-40 and the ~20-section stress case,
issue #5). The output shape — `cols/rows/width/height/offsetY` per section — is already what M2
fills in.
