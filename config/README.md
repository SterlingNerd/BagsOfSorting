# config

The parts of the config layer that are not the editor. The editor itself lives on the bags
(`docs/05`); this directory holds the things that have no physical counterpart there.

| File | What it is |
|---|---|
| `keybinds.lua` | `BINDING_HEADER_*` / `BINDING_NAME_*` text and the global `Bindings.xml` calls, so our bindings appear in the client's own Key Bindings panel (FR-64) |
| `settingspanel.lua` | Options → AddOns entry built with the client's settings API — no AceConfig, no settings window of our own (FR-88) |

`Bindings.xml` lives in the addon root, not here: the client loads it by path and it must not be
listed in the TOC.

`commands`, `undo`, `configuremode`, `categoryeditor`, `itemlisteditor`, `importexport`, `presets`
and `help` are M3/M4 (docs/06) and do not exist yet.
