# layout

`flow.lua` packs section blocks into a window's column budget and sizes the window to its
content (FR-40).

`anchors.lua` places the windows themselves (FR-41, `docs/07` Q24): a stack that grows upward from
the bag bar and wraps to a new column on the left when the next window will not fit, with the cap
measured as `screenHeight − allowance` at layout time. It is a port of Blizzard's
`UpdateContainerFrameAnchors` loop, never a call to it — see the file header for why.

shortcut: sections stack vertically, one per row. River packing (several sections sharing a
row) and the measurement-based title sizing are M2 (AC-40 and the ~20-section stress case,
issue #5). The output shape — `cols/rows/width/height/offsetY` per section — is already what M2
fills in.
