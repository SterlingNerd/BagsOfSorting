# layout

`flow.lua` packs section blocks into a window's column budget and sizes the window to its
content (FR-40). A window that carries a free-slot count gets one more cell at the end of its
column, and `emptyOffsetY` is where the frames layer draws it (issue #36). A tradeskill section with
a count of its own gets that cell inside its own block instead, one row below its last item row
(issue #44). A section with no items at all is skipped — except the one whose tradeskill bag still
has free slots, which is drawn with the cell as its only row and the window's column budget as its
width.

A window with nothing in it draws no body — no blank cell, no grid — and its height is floored at
`constants.WINDOW_CHROME_HEIGHT`, the 95 px the client's own bag chrome measures end to end (issue #43).
It still exists and still takes its slot in the column (#28 decision 2), and it grows the moment a
category gives it an item.

`anchors.lua` places the windows themselves (FR-41, `docs/07` Q24): a stack that grows upward from
the client's own bag window and wraps to a new column on the left when the next window will not fit,
with the cap measured as `screenHeight − allowance` at layout time. It is a port of Blizzard's
`UpdateContainerFrameAnchors` loop, never a call to it — see the file header for why.

shortcut: sections stack vertically, one per row. River packing (several sections sharing a
row) and the measurement-based title sizing are M2 (AC-40 and the ~20-section stress case,
issue #5). The output shape — `cols/rows/width/height/offsetY` per section — is already what M2
fills in.
