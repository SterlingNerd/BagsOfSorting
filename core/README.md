# core

Infrastructure only: no inventory logic, no frames that display items.

| File | What it is |
|---|---|
| `boot.lua` | module registry without AceAddon (`addon:NewModule`), addon name/version |
| `log.lua` | diagnostics gated by `settings.debug` (NFR-6) |
| `client.lua` | the only file that knows what Forever can do (FR-2); `client.get/has`, and `Probe()` for the `/bos` capability dump |
| `constants.lua` | container arithmetic derived from client constants, plus layout and chunking numbers |
| `locale.lua` | one `L` table, key falls back to itself (NFR-5) |
| `events.lua` | one owned frame + dispatch table; also carries our internal `BOS_*` events and `Bucket` coalescing |
| `context.lua` | a refresh's identity: generation (stale work is dropped), phase timings for `/bos perf` |
| `async.lua` | chunked work across frames with a per-frame budget (FR-102); stops ticking when idle |
| `pool.lua` | object pools with double-free detection (FR-42) |
| `db.lua` | SavedVariables, schema version + `Migrate()`, the Default profile seed (the M1 layout as data) |
| `init.lua` | load/listen/enable wiring, combat deferral, `/bos` |
