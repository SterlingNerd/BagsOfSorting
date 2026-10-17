# layout

`flow.lua` packs section blocks into a window's column budget and sizes the window to its
content (FR-40).

shortcut: sections stack vertically, one per row. River packing (several sections sharing a
row) and the measurement-based title sizing are M2 (AC-40 and the ~20-section stress case,
issue #5). The output shape — `cols/rows/width/height/offsetY` per section — is already what M2
fills in.
