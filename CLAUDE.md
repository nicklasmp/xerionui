# XerionUI — project notes

World of Warcraft: Midnight (12.x) addon, Lua 5.1. Two addons: `XerionUI/` (core, loads at login) and `XerionUI_Options/` (load on demand). `legacy/` is the old v1.20 — reference only, never edit or load it.

Read `docs/ARCHITECTURE.md` before changing code; `docs/PORTERING.md` tracks which legacy features are ported.

## Rules
- Every style setting (font, border, glow, bar, background, icon crop, sound/TTS, position) uses the shared blocks (`XUI.Templates`), the style engine (`XUI.Style`), the widgets (`XUI.Widgets`) and the options groups (`O.Groups`: `G.Font`, `G.Border`, `G.Glow`, `G.Icon`, `G.Bar`, `G.Background`, `G.Alert`, `G.Position`). Never hand-roll these per module.
- Modules: `XUI:NewModule` + `OnEnable` (events) + `OnRefresh` (drawing, honours `IsRunning()`/`IsPreview()`). Use the module's own `RegisterEvent`/`RegisterUnitEvent`/`After`/`NewTicker`/`SecureHook` so everything dies with the module. No idle `OnUpdate`.
- Midnight secret values: test `XUI.IsSecret(v)` before comparing; use `XUI.Readable` / `XUI.Probe`; wrap scans in one `pcall`.
- Global frame names start with `XUI_`. No accidental globals (`npm run lint` checks).
- Legacy code under `legacy/` derived from KiraUI-Plugin is All Rights Reserved (personal use only); ItruliaQoL is MIT (credit it); never copy EllesmereUI code.
- Code, comments and commits in English; talk to Nicklas in Danish.

## Verify
`cd tools && npm test` must print `ALL OK`; `npm run shots` renders the options pages to `tools/harness/out/` for a visual check. In-game testing with BugSack is still required — the harness is a mock.
