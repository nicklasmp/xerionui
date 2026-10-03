# XerionUI architecture

Two addons:

| Folder | Loads | Purpose |
|---|---|---|
| `XerionUI/` | at login | Core framework, style engine, movers, feature modules |
| `XerionUI_Options/` | on demand (`/xui`) | The settings window; costs nothing until opened |

Everything public hangs off one global table, `XerionUI` (`XUI` inside the code).

## Core (`XerionUI/Core`)

Load order matters; each file builds on the ones above it.

| File | Provides |
|---|---|
| `Init.lua` | `XUI` table, printing, secret-value helpers (`IsSecret`, `Readable`, `Probe`), `SafeCall`, table/path/colour helpers, `Coalesce`, the internal message bus (`XUI:On/Off/Fire`), addon-load and player-info helpers |
| `Database.lua` | `XUI.DB`: saved variables, profiles, defaults (inflate on activate, strip on logout), import/export |
| `Media.lua` | `XUI.Media`: LibSharedMedia lookups with caching and fallbacks, sorted lists |
| `Style.lua` | `XUI.Style`: resolves style blocks and applies fonts, borders, backgrounds, bars, icon crops and glows |
| `Audio.lua` | `XUI.Audio`: sound / text-to-speech alert blocks |
| `Modules.lua` | `XUI:NewModule`, the module lifecycle, load conditions, bootstrap |
| `Widgets.lua` | `XUI.Widgets` (text, icon, bar display components) and `XUI.Templates` (default setting blocks) |
| `Movers.lua` | `XUI.Movers`, our unlock mode, `XUI:SetUnlocked` |
| `Commands.lua` | `/xui`, options loading, Blizzard settings entry, addon compartment |

`Integrations/EllesmereUI.lua` registers our movers with EllesmereUI's unlock mode when it is installed.

### Messages (`XUI:On(message, owner, fn)`)

| Message | When |
|---|---|
| `Initialized` | database ready (ADDON_LOADED) |
| `LoggedIn` | modules evaluated (PLAYER_LOGIN) |
| `ProfileChanged` | profile switched, copied, reset or imported |
| `StyleChanged` | a global style value changed |
| `MediaChanged` | LibSharedMedia registered something (coalesced) |
| `ModuleStateChanged` (module) | a module was enabled/disabled |
| `PreviewChanged` (module) | a module preview toggled |
| `UnlockModeChanged` (active) | unlock preview on/off |
| `MoverRegistered` (entry) | a module registered a movable frame |

## Saved variables

```
XerionUIDB = {
  version, global = { accent, panel, unlock, loginMessage },
  profileKeys = { ["Name - Realm"] = "Default" },
  profiles = { Default = { general = {}, style = {...}, modules = { [key] = {...} } } },
}
XerionUICharDB = {}   -- per character, unused so far
```

Defaults are **filled into the active profile** when it is activated and **stripped on logout / profile switch**, so the file only stores what was changed, and a changed default reaches everyone who never touched it. Tables with a `[1]` entry (lists) and empty tables are atomic: a default list is copied whole when missing and never merged index by index. A value whose type does not match its default is replaced (protects against damaged imports).

## Modules

```lua
local XUI = select(2, ...).XUI
local T = XUI.Templates

local M = XUI:NewModule("MyFeature", {
    name = "My Feature",
    desc = "One sentence for the options header.",
    category = "general",           -- general | combat | group | class | tweaks
    icon = 136243,                  -- texture fileID for the sidebar
    order = 30,
    classes = { "DEATHKNIGHT" },    -- optional; other classes never see the module
    specs = { 250 },                -- optional; checked on spec change
    requires = "EllesmereUI",       -- optional addon dependency
    defaults = {
        text = T.Font(18, { color = { 1, 1, 1, 1 } }),
        icon = T.Icon(40),
        border = T.Border(),
        glow = T.Glow(true),
        alert = T.Alert("TTS", { text = "Something happened" }),
        position = T.Position(0, 150),
    },
})

function M:CanLoad()                -- optional extra condition
    return XUI.IsSpellKnown(12345), "Requires Some Talent."
end

local display
local function Display()
    if display then return display end
    display = XUI.Widgets:CreateIcon("XUI_MyFeature")
    display:Hide()
    XUI.Movers:Register(display, M, "position")
    return display
end

function M:OnEnable()               -- start listening
    Display()                       -- so the mover exists before the first trigger
    self:RegisterUnitEvent("UNIT_AURA", "player", "Update")
end

function M:Update()
    -- read game state (secret-safe!), store it, then:
    self:Refresh()
end

function M:OnRefresh()              -- draw from db + state; called on every relevant change
    if not (display or self:IsPreview()) then return end
    local d, db = Display(), self.db
    XUI.Movers:Apply(d)
    d:ApplyLayout(db.icon, db.border)
    local visible = self:IsPreview() or (self:IsRunning() and somethingIsTrue)
    d:SetGlow(db.glow, visible)
    d:SetShown(visible)
end
```

Lifecycle rules:

- A module **runs** while `db.enabled` is true and `CanRun()` holds. `OnEnable` registers events; when it stops, the framework drops every event, cancels every `self:After` / `self:NewTicker` timer and mutes every `self:SecureHook` before calling `OnDisable` — most modules need no `OnDisable`.
- `OnRefresh` draws. It is called after enable/disable, setting changes (coalesced), style/media/profile changes and preview toggles. It decides visibility from `IsRunning()` and `IsPreview()` — a module can be previewed from the options even when it is not running.
- Disabled modules create no frames and register no events.
- Use `self:RegisterUnitEvent` for unit events; never listen to every unit when you need one.
- No `OnUpdate` while idle. Tickers only while something is shown, and cancel them when it hides.
- Global frame names are prefixed `XUI_`.

### Midnight secret values

In restricted content many API returns are secret: they can be passed back into the API but not compared, indexed or used in arithmetic. Rules:

- Read combat data through `XUI.Readable(v, fallback)`, `XUI.Probe(fn, ...)` or test `XUI.IsSecret(v)` **before** comparing (`IsSecret(x) or x == nil`, not the other way round).
- Wrap whole scans in one `pcall` rather than a closure per item.
- When a value is secret, treat it as unknown and prefer showing nothing over guessing.

## Style system

A module element stores small **style blocks**; `XUI.Style:Resolve(kind, block)` merges them over the global style (`XUI.DB.style[kind]`):

- `useGlobal ~= false` → only the element's **local fields** come from the block; everything else follows the Global Style page.
- `useGlobal == false` → every field in the block wins; missing fields still fall back to global.

| Kind | Global fields | Local fields (always per element) |
|---|---|---|
| `font` | face, outline, slug, shadow, shadowColor, shadowX/Y | size, color, justify |
| `border` | style (NONE/SOLID/DOUBLE/LSM border), size (px), color | enabled |
| `glow` | type (PIXEL/AUTOCAST/BUTTON/PROC), color, lines, frequency, length, thickness, particles, scale, offset | enabled |
| `background` | texture, color | enabled |
| `bar` | texture, bgColor | width, height, color |
| `icon` | zoom (crop %) | width, height, size |

Apply functions: `Style:ApplyFont(fs, block, size)`, `Style:Border(frame):Apply(block)`, `Style:Background(frame)` + `ApplyBackground`, `Style:ApplyBar(bar, block)`, `Style:IconTexCoord(tex, w, h, zoom)`, `Style:ShowGlow / HideGlow / SetGlow`. They are idempotent and cheap to call on every refresh (fonts and glows skip work when nothing changed).

Borders are drawn **inside** the frame in physical pixels; content is inset by `border:GetInset()`. Drop shadows come from shared FontObjects (runtime `SetShadowOffset` does not draw on 12.x). `slug` adds Midnight's crisp `SLUG` outline flag.

Prefer the widgets in `Widgets.lua` over hand-built frames: `CreateText`, `CreateIcon` (art, optional cooldown, border, glow, timer/count texts) and `CreateBar` (status bar, border, optional icon, name/time texts). They already apply the style blocks the options groups edit.

## Movers

`XUI.Movers:Register(frame, module, "position")` once, `XUI.Movers:Apply(frame)` in `OnRefresh`. Positions are `CENTER`/`CENTER` offsets from UIParent, which is also EllesmereUI's format. `/xui unlock` opens EllesmereUI's unlock mode when it is installed (General → Unlock mode), otherwise ours (drag, arrow-key nudge, Shift = 10, right-click resets, optional grid snap). Both turn on previews for every enabled module.

## Options (`XerionUI_Options`)

| File | Provides |
|---|---|
| `Theme.lua` | palette, panel font, drawing helpers, buttons |
| `Controls.lua` | toggle, slider, dropdown, color, input, button, description, heading, spacer, custom |
| `Dropdown.lua` | the shared dropdown list (filter box, media previews, sound play buttons) |
| `Page.lua` | contexts, cards, grid layout, scroll |
| `Groups.lua` | the shared option groups (see below) |
| `Panel.lua` | window, sidebar + search, page header (enable / preview / reset) |
| `Pages/*.lua` | Global Style, General, Profiles |
| `Modules/*.lua` | one builder per module, grouped by category |

A module's options are a list of cards built from descriptors:

```lua
O:RegisterModuleOptions("MyFeature", function(ctx, m, G)
    return {
        O.Card("Behaviour", {
            { type = "toggle", label = "Only in instances", path = "instancesOnly" },
            { type = "slider", label = "Threshold", path = "threshold", min = 1, max = 10, step = 1 },
        }),
        O.Card("Icon", G.Icon("icon", { square = true })),
        O.Card("Border", G.Border("border")),
        O.Card("Glow", G.Glow("glow")),
        O.Card("Text", G.Font("text", { color = true })),
        O.Card("Alert", G.Alert("alert")),
        O.Card("Position", G.Position("position")),
    }
end)
```

**Always use the groups** for style settings — that is what keeps every module's border, glow, font and texture options identical: `G.Font`, `G.Border`, `G.Glow`, `G.Icon`, `G.Bar`, `G.Background`, `G.Alert`, `G.Position`. The Global Style page is built from the same groups with `{ global = true }`.

Descriptor fields: `type`, `label`, `tip`, `path` (dotted, relative to the module db), `get(ctx)` / `set(ctx, v)` overrides, `min/max/step` (slider), `values` or `media` (dropdown), `hasAlpha` (color), `multiline` (input), `onClick` (button), `width = "full"` / `span`, `hidden(ctx)`, `disabled(ctx)`. Controls in a row share its bottom edge.

## Testing

```
cd tools && npm install
npm test          # loads both addons in a mocked client and drives every control
npm run shots     # renders each options page to tools/harness/out/*.html
npm run lint      # Lua 5.1 syntax + accidental global writes
npm run media     # regenerates the UI textures in XerionUI/Media
```

The harness (fengari, Lua 5.3) mocks the WoW API closely enough to load the TOCs, fire ADDON_LOADED / PLAYER_LOGIN / combat / aura events, open every options page, change every control, run profiles, previews and unlock mode, and fail on any Lua error. It is not the game: always test in the client too, with BugSack enabled.
