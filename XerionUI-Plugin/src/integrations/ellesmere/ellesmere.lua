local addonName, XerionUIFeatures = ...

-- EllesmereUI integration.
--
-- Mirrors the ElvUI integration (see init.lua): when EllesmereUI is present we
-- surface the same settings inside its config window and register our movers
-- with its unlock mode.
--
-- EllesmereUI replaced Ace3 with its own widget framework, so we cannot hand it
-- an AceConfig options table the way we do for ElvUI. Each module hand-authors
-- its EllesmereUI settings as a list of rows in its own options.eui.lua
-- (Module:GetEUIOptions), which RenderEUIList turns into EllesmereUI widgets.
--
-- A module that draws something also gets a live preview of its own frame pinned
-- above the page, in EllesmereUI's content header -- see EUIPreviewHeaderBuilder.
--
-- The registration technique (loadstring trampoline to pass EllesmereUI's
-- caller whitelist, plus manual sidebar injection) follows NaowhUI_EUI, the
-- reference third-party companion addon.

-- Resolve a value that may be a plain value or an AceConfig callback.
local function resolve(v, ...)
    if type(v) == "function" then
        return v(...)
    end

    return v
end

-- Live-restyle a module's named frame -- the faithful equivalent of the
-- AceConfig `onChange` (frame:UpdateStyles), without RefreshConfig's heavier
-- side effects (e.g. resetting the combat timer on a colour change). Manual
-- options.eui.lua lists use this for appearance changes; the enable toggle
-- still calls the module's RefreshConfig to set up / tear down.
-- Never restyle a disabled module. The indicators' FontStrings are shown by
-- default and are only ever hidden from their OnEvent handler, which
-- RefreshConfig unwires while the module is off -- so they sit there visible but
-- empty. A single UpdateStyles fills the text in and it stays on screen for
-- good, which reads as the module having enabled itself even though db.enabled
-- is still false. EllesmereUI reaches this from every options row's apply() and
-- from ApplySavedPositions at login (which applies positions for every
-- registered element, hidden or not), so it only surfaces under EllesmereUI.
-- `== false` rather than `not`: a module without the field must still restyle.
function XerionUIFeatures:ApplyModuleStyles(moduleName)
    local module = self:GetModule(moduleName, true)

    -- Ahead of the disabled guard: the preview is a separate instance that never
    -- touches the screen, so it keeps tracking the settings while the module is off.
    -- Seeing what a module will look like before switching it on is the point of it.
    if module then
        self:RefreshPreview(module)
    end

    if module and module.db and module.db.enabled == false then
        return
    end

    local frame = _G[addonName .. moduleName]

    if frame and frame.UpdateStyles then
        frame:UpdateStyles()
    end
end

-- AceConfig selects sort by display text by default (no `sorting` given); mirror
-- that so dropdown order matches the other hosts.
local function selectOrder(values)
    local order = {}

    for k in pairs(values) do
        order[#order + 1] = k
    end

    table.sort(order, function(a, b)
        return tostring(values[a]) < tostring(values[b])
    end)

    return order
end

-- `refresh = true` on a row re-renders the page after its edit, so controls it
-- gates (their `disabled`/values depend on this one) update immediately.
--
-- `rebuild = true` is for the edits that change the row *set* itself -- adding
-- or removing a pull timer, say. EllesmereUI's plain RefreshPage takes a fast
-- path that only re-reads DB values through the widgets already on the page, so
-- rows that should appear or disappear never do; only a forced refresh tears the
-- page down and calls GetEUIOptions again.
--
-- Used for the page's own rows and for cog popup rows alike: a setting behind a
-- cogwheel gates page rows just as often as a page row does (RaidFrameManager's
-- "Only in a raid", which disables the "Only in a group" toggle it hangs off).
local function wrapPageRefresh(fn, refresh, rebuild)
    if not (refresh or rebuild) or not fn then
        return fn
    end

    return function(...)
        fn(...)

        local EUI = XerionUIFeatures.EUI

        if EUI and EUI.RefreshPage then
            EUI:RefreshPage(rebuild and true or nil)
        end
    end
end

-- Translates one of our row specs into BuildCogPopup's own vocabulary, which
-- names a few fields differently (dropdown/colorpicker/button, `action`,
-- `inputWidth`).
local function cogPopupRow(item)
    if item.type == "execute" then
        return {
            type = "button",
            label = item.label,
            action = wrapPageRefresh(item.func, item.refresh, item.rebuild),
        }
    end

    local vals = item.values
    local itemType = item.type

    if itemType == "select" then
        itemType = "dropdown"
    elseif itemType == "color" then
        itemType = "colorpicker"
    end

    -- Same nil guard as halfConfig's slider branch above: EllesmereUI's slider
    -- does arithmetic on the value, so a field a profile happens to lack (added
    -- after that profile was created, or never seeded at all) must not reach it
    -- as nil. Cog rows go through this translation instead of halfConfig, so they
    -- need their own copy of the same fallback.
    local get = item.get

    if itemType == "slider" then
        get = function()
            local v = item.get and item.get()

            if v == nil then
                return item.min or 0
            end

            return v
        end
    end

    return {
        type = itemType,
        label = item.label,
        tooltip = item.tooltip,
        hasAlpha = item.hasAlpha,
        min = item.min,
        max = item.max,
        step = item.step,
        values = vals,
        order = vals and (item.order or selectOrder(vals)) or nil,
        disabled = item.disabled,
        disabledTooltip = item.disabledTooltip,
        rawTooltip = item.rawTooltip,
        inputWidth = item.width,
        get = get,
        set = wrapPageRefresh(item.set, item.refresh, item.rebuild),
    }
end

-- EllesmereUI's cog popup dims a disabled colour row's swatch but, unlike its
-- other row types, leaves the label at full alpha -- so a greyed-out colour still
-- reads as active next to the rows above it. Dim it ourselves, finding the label
-- by its text the way EllesmereUI's own BuildCursorAnchorRow does. `colorRows` is
-- the popup's colour rows that have a `disabled`.
local labelAlpha, labelAlphaDisabled = 0.6, 0.25

local function dimDisabledCogLabels(popup, colorRows)
    local EUI = XerionUIFeatures.EUI

    for _, row in ipairs(colorRows) do
        if not row._cogLabel then
            local text = (EUI.L and EUI.L(row.label)) or row.label

            for i = 1, popup:GetNumRegions() do
                local reg = select(i, popup:GetRegions())

                if reg and reg.GetText and reg:GetText() == text then
                    row._cogLabel = reg
                    break
                end
            end
        end

        if row._cogLabel then
            row._cogLabel:SetAlpha(row.disabled() and labelAlphaDisabled or labelAlpha)
        end
    end
end

-- Inline cogwheel on a settings row: a small cog left of the row's control that
-- opens a popup with secondary settings, the way EllesmereUI keeps offsets and
-- other detail settings off the page instead of spending a full row on each.
-- `cog` is { title = "Popup Title", rows = { <row>, ... }, icon = <texture?> },
-- its rows using the same specs as the page itself.
--
-- A cog may also carry `disabled` (a function) and `disabledTooltip` (a full
-- sentence, shown verbatim), for settings that only mean anything while the row
-- they hang off is on -- there is no point opening a popup whose every row would
-- be greyed out. The cog dims, stops opening, and explains itself on hover.
local cogAlpha, cogAlphaHover, cogAlphaDisabled = 0.4, 0.7, 0.15

local function attachEUICog(region, cog)
    local EUI = XerionUIFeatures.EUI

    if not region or not cog or not cog.rows or #cog.rows == 0 then
        return
    end

    if not (EUI and EUI.BuildCogPopup) then
        return
    end

    local rows = {}
    local colorRows = {}

    for i, row in ipairs(cog.rows) do
        rows[i] = cogPopupRow(row)

        if row.type == "color" and row.disabled then
            colorRows[#colorRows + 1] = row
        end
    end

    local _, cogShow = EUI.BuildCogPopup({ title = cog.title, rows = rows })

    -- The popup is built on first open, so its labels can only be dimmed from
    -- there. Chain into its own refresh as well, so an edit inside the popup that
    -- flips a colour row's `disabled` keeps the label in step.
    local function show(anchorBtn)
        cogShow(anchorBtn)

        local popup = cogShow._popupFrame

        if not popup or #colorRows == 0 then
            return
        end

        if not popup.itruliaQoLDimHooked then
            popup.itruliaQoLDimHooked = true

            local refresh = popup._refresh
            popup._refresh = function(...)
                refresh(...)
                dimDisabledCogLabels(popup, colorRows)
            end
        end

        dimDisabledCogLabels(popup, colorRows)
    end

    -- Chain off `_lastInline` so several inline extras on one row stack leftwards,
    -- which is the convention EllesmereUI's own pages follow.
    local anchor = region._lastInline or region._control

    local btn = CreateFrame("Button", nil, region)
    PixelUtil.SetSize(btn, 26, 26)

    if anchor then
        PixelUtil.SetPoint(btn, "RIGHT", anchor, "LEFT", -8, 0)
    else
        PixelUtil.SetPoint(btn, "RIGHT", region, "RIGHT", -20, 0)
    end

    region._lastInline = btn
    btn:SetFrameLevel(region:GetFrameLevel() + 5)

    local tex = btn:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints()
    tex:SetTexture(cog.icon or EUI.COGS_ICON)

    local function disabled()
        return cog.disabled and cog.disabled() and true or false
    end

    -- Through EllesmereUI's widget refresh list, so a page row that gates this cog
    -- (its `refresh = true` edit re-reads every widget) dims it in the same pass.
    local function updateState()
        btn:SetAlpha(disabled() and cogAlphaDisabled or cogAlpha)
    end

    if cog.disabled and EUI.RegisterWidgetRefresh then
        EUI.RegisterWidgetRefresh(updateState)
    end

    updateState()

    -- EllesmereUI's own tooltip rather than GameTooltip, so it carries the panel's
    -- styling and rides its scale slider the way every other disabled control does.
    btn:SetScript("OnEnter", function(self)
        if disabled() then
            if cog.disabledTooltip and EUI.ShowWidgetTooltip then
                EUI.ShowWidgetTooltip(self, cog.disabledTooltip)
            end

            return
        end

        self:SetAlpha(cogAlphaHover)
    end)
    btn:SetScript("OnLeave", function()
        if EUI.HideWidgetTooltip then
            EUI.HideWidgetTooltip()
        end

        updateState()
    end)
    btn:SetScript("OnClick", function(self)
        if disabled() then
            return
        end

        show(self)
    end)
end

-- A checkbox dropdown, EllesmereUI's own widget for a setting that is a set rather
-- than one value: the closed control summarises the checked entries ("None", "All",
-- or the names), the open menu is a list of checkboxes. `items` are its entries,
-- { key =, label =, icon = <texture?> } plus { isHeader = true, label = } to group
-- them, and `get`/`set` take the key.
--
-- The control hangs off the row's left region, right-aligned, the way EllesmereUI's
-- own pages place theirs. Nothing is built during a hidden search prebuild: those
-- pages are thrown away, and the widget registers a refresh closure that would
-- outlive them.
local function attachEUIMultiSelect(region, item)
    local EUI = XerionUIFeatures.EUI

    if not region or not item.items or #item.items == 0 then
        return
    end

    if not (EUI and EUI.BuildVisOptsCBDropdown) or EUI._prebuilding then
        return
    end

    local PP = EUI.PanelPP or EUI.PP

    local dropdown, refresh = EUI.BuildVisOptsCBDropdown(
        region,
        item.width or 210,
        region:GetFrameLevel() + 2,
        item.items,
        item.get,
        wrapPageRefresh(item.set, item.refresh, item.rebuild),
        nil,
        item.maxVisible or 10,
        item.searchable and true or false
    )

    PP.Point(dropdown, "RIGHT", region, "RIGHT", -20, 0)
    region._control = dropdown

    if refresh and EUI.RegisterWidgetRefresh then
        EUI.RegisterWidgetRefresh(refresh)
    end

    if not item.disabled then
        return
    end

    -- The widget has no disabled state of its own, so it gets the one EllesmereUI's
    -- own halves apply: the control dims and stops taking clicks.
    local function updateState()
        local off = item.disabled() and true or false

        dropdown:SetAlpha(off and 0.3 or 1)
        dropdown:EnableMouse(not off)
    end

    if EUI.RegisterWidgetRefresh then
        EUI.RegisterWidgetRefresh(updateState)
    end

    updateState()
end

-- Manual settings list (options.eui.lua).
--
-- A module can hand-author its EllesmereUI settings by defining
-- Module:GetEUIOptions() in its own options.eui.lua, returning
--   { name = "Display Name", rows = { <row>, <row>, ... } }
-- Rows use clean get/set closures (no AceConfig `(info, value)` wrapper):
--
--   { header = "Section" }                                    -- section title
--   { spacer = 12 }                                           -- vertical gap
--   { text   = "Some help text" }                             -- plain label row
--   { rows   = { ... }, header = "optional" }                 -- nested sub-list
--   { pair   = { <row>, <row> } }                             -- two controls, half width each
--   { type = "empty" }                                        -- a blank half in a pair
--   { type = "toggle",  label=, tooltip=, disabled=, get=, set= }
--   { type = "slider",  label=, min=, max=, step=, disabled=, get=, set= }
--   { type = "select",  label=, values=, order=, disabled=, get=, set= }
--   { type = "multiselect", label=, items=, get=, set= }    -- checkbox dropdown
--   { type = "color",   label=, hasAlpha=, get=, set= }       -- get -> r,g,b,a ; set(r,g,b,a)
--   { type = "input",   label=, width=, disabled=, get=, set= }
--   { type = "execute", label=, disabled=, func= }
--   { type = "icons",   items = { { icon=, label=, tooltip=, onClick=, desaturated= }, ... } }
--
-- Any control row may also carry
--   cog = { title = "Popup Title", rows = { <row>, ... } }
-- to put secondary settings behind a cogwheel next to its control instead of on
-- rows of their own (see attachEUICog).
--
-- `disabled` is a function returning a bool. `disabledTooltip` explains why (a
-- requirement noun that EllesmereUI wraps into "This option requires X to be
-- enabled", or a full sentence of your own with `rawTooltip = true`). `get`/`set`
-- read/write the module db directly and call the module's own apply (e.g.
-- self:RefreshConfig()).
function XerionUIFeatures:RenderEUIList(widgets, parent, y, rows)
    local _, h

    -- Translate one row spec into a DualRow half config. EllesmereUI's DualRow takes
    -- a left and a right config, so the same translation serves a full-width row
    -- (left only) and a `pair` (both halves) -- see the `pair` branch below.
    -- Returns nil for the specs that are not controls (headers, spacers, grids).
    local function halfConfig(item)
        if not item then
            return nil
        end

        if item.text and not item.type then
            return { text = item.text }
        end

        -- A blank half, so an odd control still gets half the row rather than
        -- stretching its control across the full width.
        if item.type == "empty" then
            return { type = "spacer" }
        end

        -- The checkbox dropdown is not one of EllesmereUI's DualRow types: the half is
        -- the label alone and the control is hung off its region afterwards, by
        -- attachRowControls below.
        if item.type == "multiselect" then
            return {
                type = "label",
                text = item.label,
                tooltip = item.tooltip,
                disabled = item.disabled,
                disabledTooltip = item.disabledTooltip,
                rawTooltip = item.rawTooltip,
            }
        end

        if item.type == "toggle" then
            return {
                type = "toggle",
                text = item.label,
                tooltip = item.tooltip,
                disabled = item.disabled,
                disabledTooltip = item.disabledTooltip,
                rawTooltip = item.rawTooltip,
                getValue = item.get,
                setValue = wrapPageRefresh(item.set, item.refresh, item.rebuild),
            }
        end

        if item.type == "slider" then
            -- EllesmereUI's slider does arithmetic on the value, so it must never
            -- be nil. Existing profiles can lack a field added after they were
            -- created (module defaults only seed brand-new profiles), so fall
            -- back to the slider min.
            local getV = item.get

            return {
                type = "slider",
                text = item.label,
                tooltip = item.tooltip,
                min = item.min,
                max = item.max,
                step = item.step,
                disabled = item.disabled,
                disabledTooltip = item.disabledTooltip,
                rawTooltip = item.rawTooltip,
                getValue = function()
                    local v = getV and getV()

                    if v == nil then
                        return item.min or 0
                    end

                    return v
                end,
                setValue = item.set,
            }
        end

        if item.type == "select" then
            local vals = item.values or {}

            return {
                type = "dropdown",
                text = item.label,
                tooltip = item.tooltip,
                values = vals,
                order = item.order or selectOrder(vals),
                disabled = item.disabled,
                disabledTooltip = item.disabledTooltip,
                rawTooltip = item.rawTooltip,
                getValue = item.get,
                setValue = wrapPageRefresh(item.set, item.refresh, item.rebuild),
            }
        end

        if item.type == "color" then
            return {
                type = "colorpicker",
                text = item.label,
                hasAlpha = item.hasAlpha,
                getValue = item.get,
                setValue = item.set,
            }
        end

        if item.type == "input" then
            return {
                type = "input",
                text = item.label,
                tooltip = item.tooltip,
                inputWidth = item.width or 180,
                disabled = item.disabled,
                disabledTooltip = item.disabledTooltip,
                rawTooltip = item.rawTooltip,
                getValue = item.get,
                setValue = wrapPageRefresh(item.set, item.refresh, item.rebuild),
            }
        end

        if item.type == "execute" then
            return {
                type = "button",
                text = item.label,
                disabled = item.disabled,
                disabledTooltip = item.disabledTooltip,
                rawTooltip = item.rawTooltip,
                onClick = wrapPageRefresh(item.func, item.refresh, item.rebuild),
            }
        end

        return nil
    end

    -- Everything a half needs on top of its DualRow config: the checkbox dropdown,
    -- which EllesmereUI has no DualRow type for, and the cogwheel. In that order, so
    -- the cog chains off the dropdown and lands left of it rather than under it.
    local function attachRowControls(region, item)
        if not (region and item) then
            return
        end

        if item.type == "multiselect" then
            attachEUIMultiSelect(region, item)
        end

        attachEUICog(region, item.cog)
    end

    local row

    for _, item in ipairs(rows) do
        if item.pair then
            -- Two controls sharing one row, each getting half the width.
            row, h = widgets:DualRow(parent, y, halfConfig(item.pair[1]), halfConfig(item.pair[2]))
            attachRowControls(row._leftRegion, item.pair[1])
            attachRowControls(row._rightRegion, item.pair[2])
            y = y - h
        elseif item.rows then
            if item.header then
                _, h = widgets:SectionHeader(parent, item.header, y)
                y = y - h
            end

            y = self:RenderEUIList(widgets, parent, y, item.rows)
        elseif item.header then
            _, h = widgets:SectionHeader(parent, item.header, y)
            y = y - h
        elseif item.spacer then
            _, h = widgets:Spacer(parent, y, item.spacer)
            y = y - h
        elseif item.type == "icons" then
            _, h = self:RenderEUIIconGrid(parent, y, item.items or {})
            y = y - h
        else
            -- Anything else is a single control on its own full-width row.
            local cfg = halfConfig(item)

            if cfg then
                row, h = widgets:DualRow(parent, y, cfg)
                attachRowControls(row._leftRegion, item)
                y = y - h
            end
        end
    end

    return y
end

-- Renders a grid of clickable spell-icon buttons (a 1px-bordered icon with a
-- label underneath and an accent hover border), matching EllesmereUI's own macro
-- page. Used by the "icons" row type. Each item:
--   { icon = <texture>, label = <string>, tooltip = <string?>,
--     onClick = function() ... end, desaturated = function() return <bool> end? }
-- Returns (frame, height) so it slots into RenderEUIList's `y = y - h` loop.
function XerionUIFeatures:RenderEUIIconGrid(parent, y, items)
    local EUI = self.EUI
    local PP = EUI.PanelPP or EUI.PP
    local pad = EUI.CONTENT_PAD or 0
    local fontPath = (EUI.GetFontPath and EUI.GetFontPath()) or STANDARD_TEXT_FONT

    local iconSize = 36
    local cellWidth = 84 -- horizontal stride per icon (icon + gap + label room)
    local rowHeight = 60 -- vertical stride per row (icon + label + gap)
    local topInset = 8

    local availW = parent:GetWidth() - pad * 2
    local perRow = math.max(1, math.floor(availW / cellWidth))
    local count = #items
    local rows = math.ceil(count / perRow)
    local height = topInset + rows * rowHeight

    local frame = CreateFrame("frame", nil, parent)
    PP.Size(frame, availW, height)
    PP.Point(frame, "TOPLEFT", parent, "TOPLEFT", pad, y)

    for i, item in ipairs(items) do
        local idx = i - 1
        local row = math.floor(idx / perRow)
        local col = idx % perRow
        -- Centre the (possibly partial) last row within the available width.
        local inThisRow = math.min(perRow, count - row * perRow)
        local startX = (availW - inThisRow * cellWidth) / 2
        local cx = startX + col * cellWidth + cellWidth / 2
        local cy = -topInset - row * rowHeight

        local btn = CreateFrame("Button", nil, frame)
        PP.Size(btn, iconSize, iconSize)
        PixelUtil.SetPoint(btn, "TOP", frame, "TOPLEFT", cx, cy)

        local tex = btn:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints()
        tex:SetTexture(item.icon)
        tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        local bdr = CreateFrame("frame", nil, btn)
        bdr:SetAllPoints()
        bdr:SetFrameLevel(btn:GetFrameLevel() + 1)
        PP.CreateBorder(bdr, 0, 0, 0, 1, 1)

        local hoverBdr = CreateFrame("frame", nil, btn)
        PixelUtil.SetPoint(hoverBdr, "TOPLEFT", btn, "TOPLEFT", -1, 1)
        PixelUtil.SetPoint(hoverBdr, "BOTTOMRIGHT", btn, "BOTTOMRIGHT", 1, -1)
        hoverBdr:SetFrameLevel(btn:GetFrameLevel() + 2)
        local ar, ag, ab = EUI.GetAccentColor()
        PP.CreateBorder(hoverBdr, ar, ag, ab, 1, 2)
        hoverBdr:Hide()

        local label = frame:CreateFontString(nil, "OVERLAY")
        label:SetFont(fontPath, 12, "")
        label:SetTextColor(1, 1, 1, 0.9)
        PixelUtil.SetPoint(label, "TOP", btn, "BOTTOM", 0, -3)
        label:SetWidth(cellWidth - 10)
        label:SetWordWrap(false)
        label:SetJustifyH("CENTER")
        label:SetText((item.label or ""):gsub("\n", " "))

        local function refreshState()
            if item.desaturated then
                tex:SetDesaturated(item.desaturated() and true or false)
            end
        end
        refreshState()

        btn:SetScript("OnEnter", function(self2)
            hoverBdr:Show()
            GameTooltip:SetOwner(self2, "ANCHOR_RIGHT")
            GameTooltip:SetText(item.label or "", 1, 1, 1, 1, true)
            if item.tooltip then
                GameTooltip:AddLine(item.tooltip, 1, 1, 1, true)
            end
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function()
            hoverBdr:Hide()
            GameTooltip:Hide()
        end)
        btn:SetScript("OnClick", function()
            if item.onClick then
                item.onClick()
            end
            refreshState()
        end)
    end

    return frame, height
end

-- Live preview of the module's own frame, in EllesmereUI's content header -- the
-- non-scrolling strip between the tab bar and the page, which is where EllesmereUI
-- puts its own previews (see the resource bars / action bars options).
--
-- A module page gets one by returning this builder from the registration's
-- `getHeaderBuilder`; EllesmereUI runs it on each cold page build and passes the
-- header frame and its width, expecting the used height back. Pages that return nil
-- get no header at all, so modules that draw nothing cost nothing.
--
-- Lifecycle, and why nothing here has to free anything: when the page is left,
-- EllesmereUI either stashes the header's children (page cached) or orphans them with
-- SetParent(nil) (page cleared). Either way `display` goes with it and the preview
-- inside it stops drawing. On the way back, a cached page fires onPageCacheRestore
-- (RestoreEUIPreview below) and a cleared one rebuilds cold through this builder.
local previewHeaderHeight = 120

-- `pageName` is passed through to PreparePreview, so a module split across tabs can
-- preview the state each tab configures. Its display is remembered per page: a tabbed
-- module has one header per tab, each cached separately by EllesmereUI.
function XerionUIFeatures:EUIPreviewHeaderBuilder(module, pageName)
    if not self:HasPreview(module) then
        return nil
    end

    return function(hdr, hdrW)
        -- Clipped so an oversized preview (a long alert text, a wide bar) stays in the
        -- header strip instead of drawing over the page below it.
        local display = CreateFrame("frame", nil, hdr)
        PixelUtil.SetSize(display, hdrW, previewHeaderHeight)
        PixelUtil.SetPoint(display, "CENTER", hdr, "CENTER", 0, 0)
        display:SetClipsChildren(true)

        if not XerionUIFeatures:ShowPreview(module, display, pageName) then
            return 0
        end

        module.euiPreviewDisplays = module.euiPreviewDisplays or {}
        module.euiPreviewDisplays[pageName or true] = display

        return previewHeaderHeight
    end
end

-- The builder for one page of a sidebar entry, or nil when that page previews nothing.
function XerionUIFeatures:EUIPageHeaderBuilder(entry, pageName)
    local module = entry.previewFor and entry.previewFor(pageName)

    return module and self:EUIPreviewHeaderBuilder(module, pageName) or nil
end

-- Re-attach after EllesmereUI restores a cached page: the header's frames come back
-- from its stash rather than through the builder, so the preview has to be re-hung
-- and redrawn against the settings as they stand now.
function XerionUIFeatures:RestoreEUIPreview(module, pageName)
    local displays = module.euiPreviewDisplays
    local display = displays and displays[pageName or true]

    -- No parent means EllesmereUI orphaned this header instead of caching it; the page
    -- is about to be built cold, and the builder will make a fresh display.
    if display and display:GetParent() then
        self:ShowPreview(module, display, pageName)
    end
end

-- Prominent "still being built" banner, shown on the General page only (see
-- `betaNotice` in addEntry): it is about the integration as a whole, so a copy
-- above every module's settings would just be a row they scroll past. Returns
-- (frame, height) so it slots into the same `y = y - h` flow as everything else.
function XerionUIFeatures:RenderEUIBetaNotice(parent, y)
    local EUI = self.EUI
    local PP = EUI.PanelPP or EUI.PP
    local pad = EUI.CONTENT_PAD or 0
    local fontPath = (EUI.GetFontPath and EUI.GetFontPath()) or STANDARD_TEXT_FONT

    local padX, padY = 12, 10
    local availW = parent:GetWidth() - pad * 2

    local frame = CreateFrame("frame", nil, parent)
    PP.Point(frame, "TOPLEFT", parent, "TOPLEFT", pad, y)
    PP.Size(frame, availW, 1) -- provisional; resized once the text has wrapped

    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.85, 0.55, 0.1, 0.12)

    local title = frame:CreateFontString(nil, "OVERLAY")
    title:SetFont(fontPath, 16, "OUTLINE")
    title:SetTextColor(1, 0.75, 0.2, 1)
    PixelUtil.SetPoint(title, "TOPLEFT", frame, "TOPLEFT", padX, -padY)
    title:SetText("BETA")

    local body = frame:CreateFontString(nil, "OVERLAY")
    body:SetFont(fontPath, 12, "")
    body:SetTextColor(1, 1, 1, 0.8)
    PixelUtil.SetPoint(body, "TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    body:SetWidth(availW - padX * 2)
    body:SetJustifyH("LEFT")
    body:SetWordWrap(true)
    body:SetText("The EllesmereUI integration is still being built. The ElvUI and standalone config panels are the complete ones for now (although uglier).")

    -- Where to take a problem. Amber rather than the body's white, because this is
    -- the line that saves the EllesmereUI Discord a support request that is not
    -- theirs to answer.
    local support = frame:CreateFontString(nil, "OVERLAY")
    support:SetFont(fontPath, 12, "")
    support:SetTextColor(1, 0.85, 0.5, 0.9)
    PixelUtil.SetPoint(support, "TOPLEFT", body, "BOTTOMLEFT", 0, -8)
    support:SetWidth(availW - padX * 2)
    support:SetJustifyH("LEFT")
    support:SetWordWrap(true)
    support:SetText(XerionUIFeatures.displayName .. " is an unofficial module and not part of EllesmereUI. Please do not ask about it in the EllesmereUI Discord. Contact the XerionUI maintainer directly instead.")

    -- Straight to the complete panel, styled like EllesmereUI's own "Unlock Mode"
    -- footer link: accent text that brightens on hover. The EllesmereUI panel is
    -- closed first -- AceConfigDialog would otherwise open behind it -- and the
    -- open is deferred a frame so it does not run inside the panel's own hide.
    local ar, ag, ab = EUI.GetAccentColor()

    local linkText = frame:CreateFontString(nil, "OVERLAY")
    linkText:SetFont(fontPath, 12, "")
    linkText:SetTextColor(ar, ag, ab, 0.9)
    PixelUtil.SetPoint(linkText, "TOPLEFT", support, "BOTTOMLEFT", 0, -8)
    linkText:SetText("Open the standalone config >")

    local link = CreateFrame("Button", nil, frame)
    PixelUtil.SetPoint(link, "TOPLEFT", linkText, "TOPLEFT", -2, 2)
    PixelUtil.SetPoint(link, "BOTTOMRIGHT", linkText, "BOTTOMRIGHT", 2, -2)
    link:SetFrameLevel(frame:GetFrameLevel() + 5)
    link:SetScript("OnEnter", function()
        linkText:SetTextColor(ar + (1 - ar) * 0.25, ag + (1 - ag) * 0.25, ab + (1 - ab) * 0.25, 1)
    end)
    link:SetScript("OnLeave", function()
        linkText:SetTextColor(ar, ag, ab, 0.9)
    end)
    link:SetScript("OnClick", function()
        C_Timer.After(0, function()
            XerionUIFeatures.CD:Open(addonName)
        end)
    end)

    local height = padY + title:GetStringHeight() + 6 + body:GetStringHeight()
        + 8 + support:GetStringHeight() + 8 + linkText:GetStringHeight() + padY + 8
    PP.Size(frame, availW, height)
    PP.CreateBorder(frame, 0.95, 0.65, 0.15, 1, 1)

    return frame, height
end

-- Font family dropdown data in EllesmereUI's native format: the label is the
-- font NAME and each item previews in its own font (values[name] = { text, font }),
-- instead of showing the raw file path. Keyed by LSM font name, so it stays
-- compatible with the stored fontFamily and LSM:Fetch.
function XerionUIFeatures:EUIFontValues()
    local vals, order = {}, {}

    for name, path in pairs(self.LSM:HashTable("font")) do
        vals[name] = { text = name, font = path }
        order[#order + 1] = name
    end

    table.sort(order)

    return vals, order
end

-- A single EllesmereUI-native "Font" dropdown row (name label + per-font preview).
-- `getFont` returns the font settings table rather than being it, for the reason
-- given on EUIFontRows below.
function XerionUIFeatures:EUIFontFamilyRow(getFont, apply)
    local vals, order = self:EUIFontValues()

    return {
        type = "select",
        label = "Font",
        values = vals,
        order = order,
        get = function()
            return getFont().fontFamily
        end,
        set = function(v)
            getFont().fontFamily = v

            if apply then
                apply()
            end
        end,
    }
end

-- Statusbar texture dropdown data in EllesmereUI's native format: the label is
-- the texture NAME and each row previews the texture behind it (via the
-- dropdown's `_menuOpts.background` hook, the same way EllesmereUI's own bar
-- texture pickers do), instead of showing the raw file path. Keyed by LSM name,
-- so it stays compatible with the stored value and LSM:Fetch.
function XerionUIFeatures:EUIStatusbarValues()
    local LSM = self.LSM
    local vals, order = {}, {}

    for name in pairs(LSM:HashTable("statusbar")) do
        vals[name] = name
        order[#order + 1] = name
    end

    table.sort(order)

    vals._menuOpts = {
        itemHeight = 28,
        background = function(key)
            return LSM:Fetch("statusbar", key)
        end,
    }

    return vals, order
end

-- A single EllesmereUI-native "Statusbar texture" dropdown row (name label +
-- per-texture preview). `row` is the usual select spec minus values/order:
--   { label?, tooltip?, disabled?, refresh?, get, set, none? }
-- `get`/`set` read/write the LSM texture name. With `none` set, a "None" entry
-- (a string overrides the label) is pinned above the textures and maps to nil:
-- `get` may return nil and `set` receives nil when it is picked, so "no texture
-- stored" round-trips without the caller knowing the sentinel key.
function XerionUIFeatures:EUIStatusbarRow(row)
    local vals, order = self:EUIStatusbarValues()
    local get, set = row.get, row.set

    if row.none then
        local noneKey = "__none__"
        vals[noneKey] = type(row.none) == "string" and row.none or "None"
        table.insert(order, 1, noneKey)

        -- LSM:Fetch falls back to the default statusbar texture for unknown
        -- keys, which would preview a texture behind the "None" entry.
        local background = vals._menuOpts.background
        vals._menuOpts.background = function(key)
            if key == noneKey then
                return nil
            end

            return background(key)
        end

        get = function()
            return row.get() or noneKey
        end
        set = function(value)
            if value == noneKey then
                row.set(nil)
            else
                row.set(value)
            end
        end
    end

    return {
        type = "select",
        label = row.label or "Statusbar texture",
        tooltip = row.tooltip,
        values = vals,
        order = order,
        disabled = row.disabled,
        refresh = row.refresh,
        get = get,
        set = set,
    }
end

-- Sound dropdown data in EllesmereUI's native format: the label is the sound
-- NAME and each row gets a click-to-preview speaker icon (via the dropdown's
-- `_menuOpts.icon*` hooks, the same way EllesmereUI's own sound pickers do),
-- instead of showing the raw file path. Keyed by LSM sound name, so it stays
-- compatible with the stored value and LSM:Fetch.
function XerionUIFeatures:EUISoundValues()
    local LSM = self.LSM
    local vals, order = {}, {}

    for name in pairs(LSM:HashTable("sound")) do
        vals[name] = name
        order[#order + 1] = name
    end

    table.sort(order)

    vals._menuOpts = {
        itemHeight = 26,
        maxTextWidthPct = 0.8,
        searchable = true,
        iconAtlas = function()
            return "common-icon-sound"
        end,
        iconPressedAtlas = function()
            return "common-icon-sound-pressed"
        end,
        iconOnClick = function(key)
            local path = LSM:Fetch("sound", key)

            if path then
                PlaySoundFile(path, "Master")
            end
        end,
        iconTooltip = function()
            return "Preview Sound"
        end,
    }

    return vals, order
end

-- A single EllesmereUI-native "Sound" dropdown row (name label + click-to-preview
-- speaker icon). Same `row` spec as EUIStatusbarRow; `get`/`set` read/write the
-- LSM sound name.
function XerionUIFeatures:EUISoundRow(row)
    local vals, order = self:EUISoundValues()

    return {
        type = "select",
        label = row.label or "Sound",
        tooltip = row.tooltip,
        values = vals,
        order = order,
        disabled = row.disabled,
        refresh = row.refresh,
        get = row.get,
        set = row.set,
    }
end

-- A TTS message input row with Voice, Volume and a click-to-preview button
-- behind its cogwheel, the EUI equivalent of the ace TTS voice select + volume
-- slider + preview button. `row` is the usual input spec (`label?`, `tooltip?`,
-- `disabled?`, `get`, `set`) plus `volume` (`{ get, set, min?, max?, step? }`)
-- for the TTS volume and `voice` (`{ get, set }`) for the TTS voice.
function XerionUIFeatures:EUITTSRow(row)
    local volume = row.volume or {}
    local voice = row.voice

    local cogRows = {}

    if voice then
        local values, order = self:GetTTSVoiceOptions()

        cogRows[#cogRows + 1] = {
            type = "select",
            label = "Voice",
            values = values,
            order = order,
            get = voice.get,
            set = voice.set,
        }
    end

    cogRows[#cogRows + 1] = {
        type = "slider",
        label = "Volume",
        min = volume.min or 0,
        max = volume.max or 100,
        step = volume.step or 1,
        get = volume.get,
        set = volume.set,
    }

    cogRows[#cogRows + 1] = {
        type = "execute",
        label = "Preview",
        disabled = function()
            local message = row.get()

            return not message or message == ""
        end,
        func = function()
            local message = row.get()

            if message and message ~= "" then
                C_VoiceChat.SpeakText(voice and voice.get and voice.get() or 0, message, 1, volume.get and volume.get() or 100, true)
            end
        end,
    }

    return {
        type = "input",
        label = row.label or "TTS Message",
        tooltip = row.tooltip,
        disabled = row.disabled,
        get = row.get,
        set = row.set,
        cog = {
            title = "Text-to-Speech",
            disabled = row.disabled,
            disabledTooltip = row.disabledTooltip or "TTS",
            rows = cogRows,
        },
    }
end

-- Shared font-settings rows for the manual list, mirroring createFontOptions.
-- `apply` runs after each change (e.g. the module's RefreshConfig). `exclude` is
-- an optional set of row keys to skip:
--   size, font, outline, justify, shadowX, shadowY, shadowColor, strata, level
--
-- The block is the three dropdowns -- Font, Outline, Frame Strata -- two to a row,
-- with everything else on their cogwheels: size and justify on Font's, the shadow
-- settings on Outline's, the frame level on Frame Strata's, the way EllesmereUI
-- keeps a picker's detail settings next to it rather than below it. `exclude`
-- still keys every setting individually, and a cog row falls back to a row of its
-- own when its host is the one excluded.
--
-- `lead` is an optional list of rows to put in front of the dropdowns, joining the
-- same two-to-a-row flow rather than sitting above it -- for a module whose own
-- text settings (a colour, say) belong with the font ones.
--
-- `getFont` returns the font settings table, rather than being that table. The table
-- a module edits is not the same one forever -- switching profiles points the module
-- at the new profile's, and so does resetting a module or copying one over from
-- another profile -- and a row holding the old one would read and write a table
-- nothing else points at any more. These rows are rebuilt on every page draw, so it
-- matters less here than in createFontOptions, but the two keep the same contract.
function XerionUIFeatures:EUIFontRows(getFont, apply, exclude, lead)
    exclude = exclude or {}

    -- A slug outline draws its own backdrop, so the shadow settings do nothing.
    -- They stay on the Outline cog, greyed out with that explanation, rather than
    -- the cog itself coming and going as the outline changes.
    local function slug()
        return getFont().fontOutline == "OUTLINESLUG"
    end

    local slugTip = "A slug outline draws its own backdrop, so a text shadow has no effect."

    local rows = {}
    local function add(key, row)
        if exclude[key] then
            return
        end

        rows[#rows + 1] = row
    end

    -- The cog spec for `specs` ({ key, row } pairs), dropping excluded rows and
    -- returning nil when nothing is left to put behind the cog.
    local function cogSpec(title, specs)
        local cogRows = {}

        for _, spec in ipairs(specs) do
            if not exclude[spec[1]] then
                cogRows[#cogRows + 1] = spec[2]
            end
        end

        if #cogRows == 0 then
            return nil
        end

        return { title = title, rows = cogRows }
    end

    local sizeRow = {
        type = "slider",
        label = "Size",
        min = 1,
        max = 68,
        step = 1,
        get = function()
            return getFont().fontSize
        end,
        set = function(v)
            getFont().fontSize = v
            apply()
        end,
    }
    local justifyRow = {
        type = "select",
        label = "Justify",
        values = self.JustifyHSettings,
        get = function()
            return getFont().justifyH or "CENTER"
        end,
        set = function(v)
            getFont().justifyH = v
            apply()
        end,
    }
    local shadowXRow = {
        type = "slider",
        label = "Shadow X Offset",
        min = -5,
        max = 5,
        step = 1,
        disabled = slug,
        disabledTooltip = slugTip,
        rawTooltip = true,
        get = function()
            return getFont().fontShadowXOffset
        end,
        set = function(v)
            getFont().fontShadowXOffset = v
            apply()
        end,
    }
    local shadowYRow = {
        type = "slider",
        label = "Shadow Y Offset",
        min = -5,
        max = 5,
        step = 1,
        disabled = slug,
        disabledTooltip = slugTip,
        rawTooltip = true,
        get = function()
            return getFont().fontShadowYOffset
        end,
        set = function(v)
            getFont().fontShadowYOffset = v
            apply()
        end,
    }
    local shadowColorRow = {
        type = "color",
        label = "Shadow Color",
        hasAlpha = true,
        disabled = slug,
        disabledTooltip = slugTip,
        rawTooltip = true,
        get = function()
            local color = getFont().fontShadowColor
            return color.r, color.g, color.b, color.a
        end,
        set = function(r, g, b, a)
            getFont().fontShadowColor = { r = r, g = g, b = b, a = a }
            apply()
        end,
    }

    -- The dropdowns, paired up at the tail of this function; everything they host
    -- lives on their cogwheels. Any `lead` rows join the same flow, ahead of them.
    local pickers = {}

    for _, row in ipairs(lead or {}) do
        pickers[#pickers + 1] = row
    end

    -- Font: the family dropdown, with size and justify on its cogwheel.
    if exclude.font then
        add("size", sizeRow)
        add("justify", justifyRow)
    else
        local fontRow = self:EUIFontFamilyRow(getFont, apply)
        fontRow.cog = cogSpec("Font Settings", {
            { "size", sizeRow },
            { "justify", justifyRow },
        })

        pickers[#pickers + 1] = fontRow
    end

    -- Outline: the mode dropdown, with the shadow settings on its cogwheel.
    local shadowSpecs = {
        { "shadowX", shadowXRow },
        { "shadowY", shadowYRow },
        { "shadowColor", shadowColorRow },
    }

    if exclude.outline then
        for _, spec in ipairs(shadowSpecs) do
            add(spec[1], spec[2])
        end
    else
        local outlineRow = {
            type = "select",
            label = "Outline",
            values = self.OutlineSettings,
            get = function()
                return getFont().fontOutline or "NONE"
            end,
            set = function(v)
                getFont().fontOutline = (v ~= "NONE") and v or nil
                apply()
            end,
        }

        outlineRow.cog = cogSpec("Shadow Settings", shadowSpecs)

        pickers[#pickers + 1] = outlineRow
    end

    -- Frame Strata: the strata dropdown, with the level on its cogwheel.
    local levelRow = {
        type = "slider",
        label = "Frame Level",
        min = 1,
        max = 10,
        step = 1,
        get = function()
            return getFont().frameLevel or 1
        end,
        set = function(v)
            getFont().frameLevel = v
            apply()
        end,
    }

    if exclude.strata then
        add("level", levelRow)
    else
        local strataRow = {
            type = "select",
            label = "Frame Strata",
            values = self.FrameStrataSettings,
            get = function()
                return getFont().frameStrata or "BACKGROUND"
            end,
            set = function(v)
                getFont().frameStrata = v
                apply()
            end,
        }

        strataRow.cog = cogSpec("Frame Settings", { { "level", levelRow } })

        pickers[#pickers + 1] = strataRow
    end

    -- The pickers go first, two to a row, above whatever fell back to a row of its
    -- own. An odd one out keeps its half rather than stretching over the full row.
    local at = 1

    for i = 1, #pickers, 2 do
        local left, right = pickers[i], pickers[i + 1]

        table.insert(rows, at, { pair = { left, right or { type = "empty" } } })
        at = at + 1
    end

    return rows
end

-- Popups (profile names, confirmations, import/export strings)
local function popupEditBox(self)
    return self.editBox or self.EditBox or (self.GetEditBox and self:GetEditBox())
end

StaticPopupDialogs["ITRULIAQOL_EUI_INPUT"] = {
    text = "%s",
    button1 = ACCEPT,
    button2 = CANCEL,
    hasEditBox = true,
    maxLetters = 12000,
    editBoxWidth = 260,
    OnAccept = function(self)
        local data = self.data
        local eb = popupEditBox(self)

        if data and data.onAccept and eb then
            data.onAccept(eb:GetText())
        end
    end,
    OnShow = function(self)
        local data = self.data
        local eb = popupEditBox(self)

        if eb then
            eb:SetText((data and data.initial) or "")
            eb:HighlightText()
            eb:SetFocus()
        end
    end,
    EditBoxOnEnterPressed = function(self)
        StaticPopup_OnClick(self:GetParent(), 1)
    end,
    EditBoxOnEscapePressed = function(self)
        self:GetParent():Hide()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["ITRULIAQOL_EUI_CONFIRM"] = {
    text = "%s",
    button1 = YES,
    button2 = NO,
    OnAccept = function(self)
        local data = self.data

        if data and data.onAccept then
            data.onAccept()
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function ShowInputPopup(prompt, initial, onAccept)
    StaticPopup_Show("ITRULIAQOL_EUI_INPUT", prompt, nil, { initial = initial, onAccept = onAccept })
end

local function ShowConfirmPopup(prompt, onAccept)
    StaticPopup_Show("ITRULIAQOL_EUI_CONFIRM", prompt, nil, { onAccept = onAccept })
end

-- Keep our popups above the EllesmereUI panel.
hooksecurefunc("StaticPopup_Show", function(which)
    if which and which:find("^ITRULIAQOL_EUI_") then
        local frame = StaticPopup_FindVisible(which)

        if frame then
            frame:SetFrameStrata("TOOLTIP")
            frame:SetFrameLevel(1000)
        end
    end
end)

-- Sidebar layout
--
-- Every module gets its own row under a group header carrying the addon's
-- display name (XerionUIFeatures.displayName, "Itrulia QoL" on retail and "Itrulia
-- Forever" on WoW Forever), matching how EllesmereUI lists its own suite, so a
-- module is one click away instead of being buried on an arbitrary
-- Indicators/Alerts/Utility page. Each row owns a single page; the panel header
-- already names the module, so pages don't need distinct names beyond the two
-- on the Profiles row.
local groupKey   = "itrulia"
local groupLabel = XerionUIFeatures.displayName

-- The on-screen form of the name, in the addon's own colours (the same escape
-- sequence as `## Title` in the .toc, so it reads the way the addon does in the
-- AddOns list). Used for the two places EllesmereUI renders it as a FontString:
-- the sidebar group heading and the panel header above each of our pages.
--
-- Embedded |cff codes win over SetTextColor, which is the point for the sidebar
-- heading: EllesmereUI tints group labels with its accent colour (and re-applies
-- it from an accent callback), leaving our group indistinguishable from its
-- own groups.
--
-- Plain groupLabel stays the name wherever the string is not rendered text --
-- the unlock-mode group, which EllesmereUI also keys movers by, and the sidebar
-- search text, which is matched against the player's plain-text query.
local groupLabelColored = XerionUIFeatures.displayNameColored

local pageGeneral      = "General"
local pageDisplay      = "Display"
local pageSettings     = "Settings"
local pageProfiles     = "Profiles"
local pageImportExport = "Import / Export"

-- The single tab of a module that doesn't declare EUIPages. A module that draws
-- something calls that tab "Display", matching the first tab of the modules that
-- do declare pages; one that only listens for events (FocusTargetMarker,
-- PreventRelease) has no display to name, so its tab stays "Settings".
-- PreparePreview is the same draws-something flag the preview header keys off.
local function defaultPage(module)
    return module.PreparePreview and pageDisplay or pageSettings
end

-- Modules whose settings share one sidebar row instead of getting one each. Each
-- member becomes a tab on that row, and the row is emitted where its first member
-- would have appeared, so the surrounding order is untouched. The row needs its
-- own `description`: it is shown per row rather than per tab, so the members'
-- individual blurbs are not rendered anywhere.
local combinedRows = {
    {
        key = "PetIndicators",
        display = "Pet Indicators",
        members = { "PetMissingIndicator", "PetPassiveIndicator" },
        description = "Missing/Passive pet text indicators.",
    },
}

local combinedByModule = {}

for _, row in ipairs(combinedRows) do
    for _, key in ipairs(row.members) do
        combinedByModule[key] = row
    end
end

-- Top-level parentOptions.args keys that are not modules.
local reserved = {
    all = true, enable = true, description = true, profiles = true, importExport = true,
}

-- Addon-wide settings, from general/options.eui.lua.
function XerionUIFeatures:BuildEUIGeneralPage(parent, yOffset)
    local widgets = self.EUI.Widgets
    local y = yOffset
    local _, h

    _, h = widgets:Spacer(parent, y, 8)
    y = y - h
    _, h = widgets:SectionHeader(parent, "GENERAL", y)
    y = y - h

    local spec = self.GetGeneralEUIOptions and self:GetGeneralEUIOptions()

    if spec and spec.rows then
        y = self:RenderEUIList(widgets, parent, y, spec.rows)
    end

    return math.abs(y)
end

-- One module's settings, from its own options.eui.lua. No section header for the
-- module name -- it is already the panel title and the selected sidebar row.
--
-- `descriptionInHeader` drops the leading plain-text row: every module's list
-- opens with one describing the module, and when that text is the panel header
-- instead (see descriptionFor in RegisterEUI) printing it again wastes the top of
-- the page. Combined rows pass it too, so their tabs stay clean -- but note that
-- config.description is per row rather than per page, so a combined row's header
-- carries one shared blurb and the members' individual ones are not shown.
--
-- `pageName` is forwarded to GetEUIOptions so a module big enough to want tabs can
-- return just that page's rows. Such a module lists its tabs in a static
-- `EUIPages` field, which is read at registration -- a plain table rather than a
-- call, so building the sidebar does not mean invoking every module at login.
-- Modules without EUIPages ignore the argument and keep their single page.
function XerionUIFeatures:BuildEUIModulePage(module, parent, yOffset, descriptionInHeader, pageName)
    local widgets = self.EUI.Widgets
    local y = yOffset
    local _, h

    _, h = widgets:Spacer(parent, y, 8)
    y = y - h

    local spec = module.GetEUIOptions and module:GetEUIOptions(pageName)

    if not spec then
        _, h = widgets:DualRow(parent, y, { text = "This module has no EllesmereUI settings yet." })

        return math.abs(y - h)
    end

    local rows = spec.rows or {}
    local first = rows[1]

    if descriptionInHeader and first and first.text and not (first.type or first.rows or first.header) then
        local rest = {}

        for i = 2, #rows do
            rest[#rest + 1] = rows[i]
        end

        rows = rest
    end

    -- Modules whose only setting was the enable flag have nothing left to draw once
    -- that moved to the sidebar switch, so say so rather than showing a blank page.
    if #rows == 0 then
        _, h = widgets:DualRow(parent, y, { text = "Nothing to configure. Use the switch on the sidebar row to turn this on or off." })

        return math.abs(y - h)
    end

    y = self:RenderEUIList(widgets, parent, y, rows)

    return math.abs(y)
end

-- Profiles page (built directly against AceDB rather than translated)
function XerionUIFeatures:BuildEUIProfilesPage(parent, yOffset, addon)
    addon = addon or self

    local EUI = self.EUI
    local widgets = EUI.Widgets
    local db = addon.db
    local y = yOffset
    local _, h

    local function names()
        return db:GetProfiles()
    end

    local function currentValues()
        local vals = {}

        for _, name in ipairs(names()) do
            vals[name] = name
        end

        return vals
    end

    local function otherValues()
        local vals, cur = {}, db:GetCurrentProfile()

        for _, name in ipairs(names()) do
            if name ~= cur then
                vals[name] = name
            end
        end

        return vals
    end

    local function sortedKeys(tbl)
        local keys = {}

        for k in pairs(tbl) do
            keys[#keys + 1] = k
        end

        table.sort(keys)

        return keys
    end

    -- Forced: the profile dropdowns' `values`/`order` are baked in at build time
    -- (currentValues()/otherValues(), read once as of this call), not re-derived
    -- from a live getter the way a row's own value is. A plain RefreshPage only
    -- re-reads get/set through the widgets already on the page -- it cannot make a
    -- new, renamed, copied, or deleted profile show up in these lists. Only a
    -- forced refresh tears the page down and calls this builder again.
    local function refresh()
        if EUI.RefreshPage then
            EUI:RefreshPage(true)
        end
    end

    _, h = widgets:Spacer(parent, y, 8)
    y = y - h
    _, h = widgets:SectionHeader(parent, "PROFILES", y)
    y = y - h

    do
        local cv = currentValues()
        _, h = widgets:DualRow(parent, y, {
            type = "dropdown",
            text = "Current Profile",
            values = cv,
            order = sortedKeys(cv),
            getValue = function()
                return db:GetCurrentProfile()
            end,
            setValue = function(v)
                db:SetProfile(v)
                refresh()
            end,
        })
        y = y - h
    end

    _, h = widgets:DualRow(parent, y, {
        type = "button",
        text = "New Profile",
        onClick = function()
            ShowInputPopup("Enter a name for the new profile:", "", function(name)
                name = name and name:match("^%s*(.-)%s*$") or ""

                if name ~= "" then
                    db:SetProfile(name)
                    refresh()
                end
            end)
        end,
    })
    y = y - h

    do
        local ov = otherValues()
        _, h = widgets:DualRow(parent, y,
            {
                type = "dropdown",
                text = "Copy From",
                values = ov,
                order = sortedKeys(ov),
                getValue = function()
                    return addon._euiCopyFrom
                end,
                setValue = function(v)
                    addon._euiCopyFrom = v
                end,
            },
            {
                type = "button",
                text = "Copy",
                onClick = function()
                    local from = addon._euiCopyFrom

                    if from and from ~= db:GetCurrentProfile() then
                        db:CopyProfile(from)
                        addon:RefreshModules()
                        refresh()
                    end
                end,
            }
        )
        y = y - h
    end

    do
        local ov = otherValues()
        _, h = widgets:DualRow(parent, y,
            {
                type = "dropdown",
                text = "Delete Profile",
                values = ov,
                order = sortedKeys(ov),
                getValue = function()
                    return addon._euiDeleteSel
                end,
                setValue = function(v)
                    addon._euiDeleteSel = v
                end,
            },
            {
                type = "button",
                text = "Delete",
                onClick = function()
                    local target = addon._euiDeleteSel

                    if target and target ~= db:GetCurrentProfile() then
                        ShowConfirmPopup("Delete profile '" .. target .. "'? This cannot be undone.", function()
                            db:DeleteProfile(target)
                            addon._euiDeleteSel = nil
                            refresh()
                        end)
                    end
                end,
            }
        )
        y = y - h
    end

    _, h = widgets:DualRow(parent, y, {
        type = "button",
        text = "Reset Current Profile",
        onClick = function()
            ShowConfirmPopup("Reset the current profile to defaults?", function()
                db:ResetProfile()
                addon:RefreshModules()
                refresh()
            end)
        end,
    })
    y = y - h

    return math.abs(y)
end

-- Import / Export page
--
-- `addon` is whose profile is exported and imported, defaulting to XerionUIFeatures.
-- Each addon owns its own profile-string functions (the serialization is not
-- shared -- see the copies in ItruliaEUI's src/init.lua), so all this page needs
-- is the three methods below and a Print to report the outcome.
function XerionUIFeatures:BuildEUIImportExportPage(parent, yOffset, addon)
    addon = addon or self

    local EUI = self.EUI
    local widgets = EUI.Widgets
    local y = yOffset
    local _, h

    _, h = widgets:Spacer(parent, y, 8)
    y = y - h
    _, h = widgets:SectionHeader(parent, "IMPORT / EXPORT", y)
    y = y - h

    _, h = widgets:DualRow(parent, y, { text = "Share your current profile, or paste a string to load one." })
    y = y - h

    _, h = widgets:WideButton(parent, "Export Current Profile", y, function()
        ShowInputPopup("Copy your profile export string:", addon:ExportFeatureProfile(), nil)
    end)
    y = y - h

    _, h = widgets:WideButton(parent, "Import (Overwrite Current Profile)", y, function()
        ShowInputPopup("Paste a string to OVERWRITE the current profile:", "", function(str)
            if not str or str == "" then
                return
            end

            local ok, err = addon:ImportIntoCurrentProfile(str)

            if ok then
                addon:Print("|cff00ff00Profile imported.|r")

                if EUI.RefreshPage then
                    EUI:RefreshPage()
                end
            else
                addon:Print("|cffff0000Import failed:|r", err)
            end
        end)
    end)
    y = y - h

    _, h = widgets:WideButton(parent, "Import as New Profile", y, function()
        ShowInputPopup("Paste a string to import as a new profile:", "", function(str)
            if not str or str == "" then
                return
            end

            ShowInputPopup("Enter a name for the new profile:", "", function(name)
                name = name and name:match("^%s*(.-)%s*$") or ""

                if name == "" then
                    return
                end

                local ok, err = addon:ImportAsNewProfile(str, name)

                if ok then
                    addon:Print("|cff00ff00Profile created:|r", name)

                    if EUI.RefreshPage then
                        EUI:RefreshPage()
                    end
                else
                    addon:Print("|cffff0000Import failed:|r", err)
                end
            end)
        end)
    end)
    y = y - h

    return math.abs(y)
end

function XerionUIFeatures:CreateEUIMover(module, frame, moduleName)
    local EUI = self.EUI

    if not (EUI and EUI.RegisterUnlockElements and EUI.MakeUnlockElement) then
        return
    end

    EUI:RegisterUnlockElements({
        EUI.MakeUnlockElement({
            key = frame:GetName(),
            label = moduleName,
            group = groupLabel,
            order = 1,
            isHidden = function()
                return not module.db.enabled
            end,
            getFrame = function()
                return frame
            end,
            getSize = function()
                return frame:GetWidth(), frame:GetHeight()
            end,
            -- EllesmereUI hands back CENTER/CENTER coords; store them the same
            -- shape the LibEditMode callback uses so UpdateStyles can reapply.
            savePos = function(_, point, relPoint, x, y)
                module.db.point = { point = point, relPoint = relPoint, x = x, y = y }
            end,
            -- Must return CENTER/CENTER for EllesmereUI to accept the stored pos.
            loadPos = function()
                local point = module.db.point

                if not point or not point.x then
                    return nil
                end

                return { point = point.point, relPoint = point.relPoint or point.point, x = point.x, y = point.y }
            end,
            -- Both gated on enabled for the reason described on
            -- ApplyModuleStyles: EllesmereUI calls applyPos for every registered
            -- element at login regardless of isHidden, and restyling a disabled
            -- module is what puts it on screen.
            clearPos = function()
                module.db.point = module:GetDefaults().point

                if module.db.enabled ~= false and frame.UpdateStyles then
                    frame:UpdateStyles()
                end
            end,
            applyPos = function()
                if module.db.enabled ~= false and frame.UpdateStyles then
                    frame:UpdateStyles()
                end
            end,
        }),
    }, addonName)
end

-- Registration
--
-- EllesmereUI's config sidebar is built from a hardcoded roster; add our entry
-- to the extension hooks it reads (mirrors NaowhUI_EUI). Safe to call once at
-- login: the sidebar is built lazily on first panel open.
-- `entries` is the ordered list of { key = , display = } rows to show under our
-- group header. Each key is a synthetic folder name (never a real addon folder),
-- so it must be marked alwaysLoaded: EllesmereUI otherwise greys the row and
-- offers a power toggle for an addon that does not exist.
function XerionUIFeatures:InjectEUISidebar(entries)
    local EUI = self.EUI

    if not EUI then
        return
    end

    EUI._addonInfoByFolder = EUI._addonInfoByFolder or {}
    EUI._syncExempt = EUI._syncExempt or {}

    local members = {}

    for _, entry in ipairs(entries) do
        EUI._addonInfoByFolder[entry.key] = EUI._addonInfoByFolder[entry.key] or {
            folder = entry.key,
            display = entry.display,
            search_name = entry.display .. " " .. groupLabel .. " Itrulia",
            alwaysLoaded = true,
        }

        EUI._syncExempt[entry.key] = true
        members[#members + 1] = entry.key
    end

    EUI.ADDON_GROUPS = EUI.ADDON_GROUPS or {}

    -- Member order is authoritative for the sidebar, so on a repeat call replace
    -- the list rather than bailing -- otherwise a changed module set keeps the
    -- stale rows.
    for _, group in ipairs(EUI.ADDON_GROUPS) do
        if group.key == groupKey then
            group.members = members

            return
        end
    end

    -- Appended, not prepended: we are a companion rather than part of the suite,
    -- and this group is long enough that putting it first would push EllesmereUI's
    -- own addons down the list.
    table.insert(EUI.ADDON_GROUPS, {
        key = groupKey,
        label = groupLabelColored,
        members = members,
    })
end

-- "(Inofficial Module)" beside our sidebar group header, so the group reads as a
-- companion addon rather than part of the EllesmereUI suite.
--
-- EllesmereUI's group rows carry only their own accent-coloured label, so the note
-- is a second FontString anchored to it, smaller and grey. The row is built once
-- per CreateMainFrame (kept in _sidebarGroupButtons, keyed by group), so attaching
-- once is enough -- guarded by _itruliaNote, since this runs on every panel open.
--
-- `targetGroupKey` defaults to our own group so existing callers need not pass
-- it; the companion addons (ItruliaEUI) hand in theirs, since the note belongs on
-- every group we inject and the frame-level guard keeps them independent.
function XerionUIFeatures:AttachEUISidebarGroupNote(targetGroupKey)
    local EUI = self.EUI
    local headers = EUI and EUI._sidebarGroupButtons
    local header = headers and headers[targetGroupKey or groupKey]

    if not header or header._itruliaNote or not header._label then
        return
    end

    local note = header:CreateFontString(nil, "OVERLAY")
    note:SetFont((EUI.GetFontPath and EUI.GetFontPath()) or STANDARD_TEXT_FONT, 11, "")
    note:SetTextColor(1, 1, 1, 0.35)
    note:SetText("(Inofficial Module)")
    PixelUtil.SetPoint(note, "LEFT", header._label, "RIGHT", 6, -1)

    header._itruliaNote = note
end

-- Bring our sidebar group into view, for when the panel is opened at one of our
-- rows (`/itrulia`, `/itrulia eui`). The group is appended after EllesmereUI's own
-- suite (see InjectEUISidebar), so it starts below the fold -- the panel would open
-- with its content on our page but the sidebar scrolled to somebody else's rows.
--
-- The sidebar's smooth-scroll target and its thumb updater are both file-locals in
-- EllesmereUI, so the scroll is set directly and the thumb refreshed through the
-- OnScrollRangeChanged script that updater is installed as. Setting the offset
-- outright is safe here: the wheel handler only follows its own target while its
-- animation is running, and opening the panel never leaves it running.
--
-- Retried rather than deferred once, because how many frames it takes before the
-- sidebar can be measured depends on how the panel was reached. Opening it later in
-- a session only needs the one frame: the rows exist and are only repositioned. The
-- first open of a session builds the whole panel a frame after ShowModule was called
-- (EllesmereUI splits that work, see its _SplitFirstOpen), so on that path the rows
-- have only just been created when the first attempt runs -- GetTop() and the scroll
-- range are both still unset, and a single attempt would silently give up.
local sidebarScrollMargin = 6
local sidebarScrollAttempts = 20

function XerionUIFeatures:ScrollEUISidebarToGroup(moduleKey, targetGroupKey)
    local EUI = self.EUI

    if not EUI then
        return
    end

    local attempts = 0

    local function scroll()
        attempts = attempts + 1

        local sf = EUI._addonScrollFrame
        local child = EUI._addonScrollChild
        local headers = EUI._sidebarGroupButtons
        local header = headers and headers[targetGroupKey or groupKey]
        local childTop = child and child:GetTop()
        local headerTop = header and header:IsShown() and header:GetTop()
        local maxScroll = (sf and EUI.SafeScrollRange and EUI.SafeScrollRange(sf)) or 0

        -- Not measurable yet, or the sidebar search has filtered our group out. The
        -- first is worth waiting a frame for, the second never resolves, so both get
        -- the same bounded retry and whatever the player is searching for keeps the
        -- scroll position.
        if not (sf and childTop and headerTop) or maxScroll <= 0 then
            if attempts < sidebarScrollAttempts then
                C_Timer.After(0, scroll)
            end

            return
        end

        local target = childTop - headerTop - sidebarScrollMargin

        -- The group header at the top is only the starting point: the row the panel
        -- opened at can sit below the fold in a group this long, and a sidebar that
        -- does not show the selected row is worse than one scrolled a little further.
        local rows = EUI._sidebarButtons
        local row = moduleKey and rows and rows[moduleKey]
        local rowBottom = row and row:IsShown() and row:GetBottom()

        if rowBottom then
            local lowest = childTop - rowBottom - sf:GetHeight() + sidebarScrollMargin

            if lowest > target then
                target = lowest
            end
        end

        sf:SetVerticalScroll(math.max(0, math.min(maxScroll, target)))

        local refreshThumb = sf:GetScript("OnScrollRangeChanged")

        if refreshThumb then
            refreshThumb(sf)
        end
    end

    C_Timer.After(0, scroll)
end

-- Per-module enable switch on the sidebar row itself, so a module can be turned on
-- or off without opening its page.
--
-- EllesmereUI has no API for this -- rows are built from _addonInfoByFolder and the
-- only right-edge controls it knows about are its own power / sync / download
-- icons -- so we attach ours to the row frame it exposes via _sidebarButtons. Three
-- things this has to work around:
--   * the row is a Button that selects the module on click, so ours sits several
--     frame levels above it to receive its own clicks;
--   * rows are created once per CreateMainFrame and only repositioned afterwards,
--     so attaching once per row is enough (guarded by row._itruliaEnable);
--   * EllesmereUI clamps the row label against btn._dlIcon, which exists (hidden)
--     on every row, so the right edge is already reserved and long display names
--     will not run under the switch.
--
-- A combined row switches every member at once: the switch reads as on when ANY of
-- them is on, and a click sets them all to the same state. The members still own
-- their own enabled flags, editable individually from their tabs.
function XerionUIFeatures:AttachEUISidebarSwitches(entries)
    local EUI = self.EUI
    local rows = EUI._sidebarButtons

    if not rows then
        return
    end

    for _, entry in ipairs(entries) do
        local members = entry.members
        local row = members and members[1] and rows[entry.key]

        if row and not row._itruliaEnable then
            local btn = CreateFrame("Button", nil, row)

            -- Same icon, size and slot EllesmereUI uses for its own power toggle.
            PixelUtil.SetSize(btn, 13, 13)
            PixelUtil.SetPoint(btn, "RIGHT", row, "RIGHT", -18, 0)
            btn:SetFrameLevel(row:GetFrameLevel() + 5)

            local tex = btn:CreateTexture(nil, "OVERLAY")
            tex:SetAllPoints()
            tex:SetTexture(EUI.ICONS_PATH .. "power.png")

            -- On when ANY member is on, so a combined row reads as enabled even if
            -- only one of its modules is.
            local function anyOn()
                for _, member in ipairs(members) do
                    if member.module.db and member.module.db.enabled then
                        return true
                    end
                end

                return false
            end

            -- Icon alpha plus the row label: a module that is off greys its name, the
            -- way EllesmereUI dims an addon that is not installed. Its NAV_* colours
            -- are file-locals, so the alphas are copied from EllesmereUI.lua's
            -- "Sidebar nav states" block -- all 1,1,1 with alpha 1 (selected), 0.6
            -- (enabled), 0.11 (disabled), 0.86 (hover enabled), 0.39 (hover disabled).
            --
            -- We cannot simply set row._loaded = false and let EllesmereUI paint it:
            -- the row's OnClick is gated on _loaded, so the row would stop opening and
            -- there would be no way back in to re-enable the module.
            local function paint(hovered)
                local on = anyOn()

                tex:SetVertexColor(1, 1, 1, on and 1 or 0.5)

                local label = row._label

                if not label then
                    return
                end

                if not on then
                    label:SetTextColor(1, 1, 1, hovered and 0.39 or 0.11)
                elseif hovered then
                    label:SetTextColor(1, 1, 1, 0.86)
                elseif EUI.GetActiveModule and EUI:GetActiveModule() == entry.key then
                    label:SetTextColor(1, 1, 1, 1)
                else
                    label:SetTextColor(1, 1, 1, 0.6)
                end
            end

            row._itruliaRepaint = paint

            -- EllesmereUI's own hover scripts recolour the label from _loaded, which
            -- is always true for our rows, so wrap them and restore our state after.
            local rowEnter, rowLeave = row:GetScript("OnEnter"), row:GetScript("OnLeave")

            row:SetScript("OnEnter", function(self2, ...)
                if rowEnter then
                    rowEnter(self2, ...)
                end

                paint(true)
            end)

            row:SetScript("OnLeave", function(self2, ...)
                if rowLeave then
                    rowLeave(self2, ...)
                end

                paint(false)
            end)

            paint()

            -- Wrapped, not passed directly: OnShow hands the frame to its handler,
            -- which would arrive as a truthy `hovered`.
            btn:SetScript("OnShow", function()
                paint()
            end)

            btn:SetScript("OnClick", function()
                -- Every member follows the row: on when any was off, off otherwise.
                local enable = not anyOn()

                for _, member in ipairs(members) do
                    if member.module.db then
                        member.module.db.enabled = enable

                        if member.module.RefreshConfig then
                            member.module:RefreshConfig()
                        end
                    end
                end

                paint()

                -- Keep the members' own Enable toggles in step if the page is open.
                if EUI.GetActiveModule and EUI:GetActiveModule() == entry.key and EUI.RefreshPage then
                    EUI:RefreshPage(true)
                end
            end)

            -- Hover previews the action, red to turn off and green to turn on,
            -- matching EllesmereUI's own power icon.
            btn:SetScript("OnEnter", function(self2)
                local on = anyOn()

                if on then
                    tex:SetVertexColor(0.824, 0.212, 0.212, 1)
                else
                    tex:SetVertexColor(0.212, 0.824, 0.325, 1)
                end

                if EUI.ShowWidgetTooltip then
                    EUI.ShowWidgetTooltip(self2,
                        (on and "Disable " or "Enable ") .. entry.display)
                end
            end)

            btn:SetScript("OnLeave", function()
                paint()

                if EUI.HideWidgetTooltip then
                    EUI.HideWidgetTooltip()
                end
            end)

            row._itruliaEnable = btn
        end
    end
end

-- Repaint every row we own. EllesmereUI recolours labels from its own state in
-- RefreshSidebarStates (on each panel open) and UpdateSidebarHighlight (on each
-- module switch), so the disabled grey has to be reapplied after both.
function XerionUIFeatures:RefreshEUISidebarRows(entries)
    local rows = self.EUI._sidebarButtons

    if not rows then
        return
    end

    for _, entry in ipairs(entries) do
        local row = rows[entry.key]

        if row and row._itruliaRepaint then
            row._itruliaRepaint()
        end
    end
end

-- RegisterModule whitelists callers by their "AddOns/<folder>/" path via
-- debugstack. From a loadstring chunk the caller reads as "[string ...]", so the
-- guard falls through. (Same approach as NaowhUI_EUI.) Compiled once and reused
-- for every row; it reads the pending registration back out of a global.
local euiRegisterChunk = loadstring([[
    local r = _G.__XerionUIFeatures_pendingReg
    if r and EllesmereUI and EllesmereUI.RegisterModule then
        EllesmereUI:RegisterModule(r.key, r.config)
    end
]], "XerionUIFeatures-register")

-- Never assume registration worked. RegisterModule returns silently when the
-- caller isn't whitelisted, so a clean pcall proves nothing -- check the registry
-- itself (_modules is EllesmereUI's read-only alias). Without this a rejected
-- registration is indistinguishable from a working one until you notice the
-- sidebar row selects nothing.
function XerionUIFeatures:RegisterEUIModule(key, config)
    local EUI = self.EUI
    local ok, err = false, nil

    _G.__XerionUIFeatures_pendingReg = { key = key, config = config }

    if euiRegisterChunk then
        ok, err = pcall(euiRegisterChunk)
    end

    _G.__XerionUIFeatures_pendingReg = nil

    if not ok then
        ok, err = pcall(EUI.RegisterModule, EUI, key, config)
    end

    if not (EUI._modules and EUI._modules[key]) then
        self:Print("|cffff0000EllesmereUI registration failed for|r", key,
            err or "caller rejected by EllesmereUI:RegisterModule")
    end
end

-- Build and register the EllesmereUI rows. Called from init.lua's
-- RegisterOptions with the fully-built AceConfig `parentOptions`.
-- The row a slash command reopens its group at, remembered for the session.
-- EllesmereUI keeps the tab within a module itself (_lastPagePerModule), so the row
-- is all we track. Per group, so the sibling addons that borrow this integration
-- (ItruliaUI, ItruliaEUI) each remember their own without seeing each other's.
local lastEUIModuleKeys = {}

function XerionUIFeatures:RememberEUIModule(folderName, targetGroupKey)
    lastEUIModuleKeys[targetGroupKey or groupKey] = folderName
end

function XerionUIFeatures:GetLastEUIModule(targetGroupKey)
    local EUI = self.EUI
    local registered = EUI and EUI._modules
    local remembered = lastEUIModuleKeys[targetGroupKey or groupKey]

    if remembered and registered and registered[remembered] then
        return remembered
    end

    return nil
end

function XerionUIFeatures:RegisterEUI(parentOptions)
    local EUI = self.EUI

    -- Never gate on EUI.Widgets here. EllesmereUI_Widgets.lua wraps its whole
    -- body in a deferred init, so EUI.Widgets only exists once EnsureLoaded()
    -- has run -- and whether that happened before we get here is a PLAYER_LOGIN
    -- handler-order race (EllesmereUI registers its EnsureLoaded frame at file
    -- scope, we arrive via AceAddon's frame), so it flips whenever the installed
    -- addon set changes and silently skips the entire integration. Widgets is
    -- only read from buildPage, which runs on panel open, long after
    -- EnsureLoaded. NaowhUI_EUI guards on RegisterModule alone for this reason.
    if not (EUI and EUI.RegisterModule) then
        return
    end

    if self._euiRegistered then
        return
    end

    self._euiRegistered = true

    -- One sidebar row per module, alphabetical by the name the row shows. The
    -- AceConfig `order` fields are ignored here on purpose: they group the
    -- standalone/ElvUI tree by theme, which reads as arbitrary in a flat sidebar
    -- long enough to need scrolling.
    local moduleKeys = {}

    for key, e in pairs(parentOptions.args) do
        if type(e) == "table" and e.type == "group" and not reserved[key] then
            moduleKeys[#moduleKeys + 1] = key
        end
    end

    local function displayFor(key)
        local grp = parentOptions.args[key]

        return tostring(resolve(grp and grp.name) or key)
    end

    -- A module sharing a combined row sorts under that row's name rather than its
    -- own, so the row lands in one predictable place instead of wherever its
    -- first member happens to fall.
    local function sidebarName(key)
        local combined = combinedByModule[key]

        return combined and combined.display or displayFor(key)
    end

    -- A module can opt out of the alphabetical run with EUISortLast, which parks it
    -- between the last module and Profiles. Misc uses it: a catch-all row reads as
    -- the end of the list, not as something filed under M.
    local function sortWeight(key)
        local combined = combinedByModule[key]

        if combined then
            return 0
        end

        local module = self:GetModule(key, true)

        return module and module.EUISortLast and 1 or 0
    end

    table.sort(moduleKeys, function(a, b)
        local wa, wb = sortWeight(a), sortWeight(b)

        if wa ~= wb then
            return wa < wb
        end

        local na, nb = sidebarName(a), sidebarName(b)

        -- Equal names means two members of one combined row. It is emitted once
        -- either way, so this only needs to be stable.
        if na == nb then
            return a < b
        end

        return na < nb
    end)

    local entries = {}

    -- Keys are namespaced so they can never collide with a real addon folder in
    -- EllesmereUI's roster. `build` takes (pageName, parent, y).
    -- `members` is the list of { key = , module = } this row fronts -- one entry for
    -- a normal module row, several for a combined one. It is what gives the row its
    -- enable switch (see AttachEUISidebarSwitches); rows without it (General,
    -- Profiles) get none.
    -- `previewFor` maps a page name to the module whose preview belongs in that page's
    -- content header -- one module for a normal row, the tab's own member for a
    -- combined one. Rows without it (General, Profiles) show no preview.
    local function addEntry(key, display, pages, build, description, members, previewFor)
        entries[#entries + 1] = {
            key = addonName .. "_" .. key,
            display = display,
            pages = pages,
            build = build,
            description = description,
            members = members,
            previewFor = previewFor,
            betaNotice = key == "General",
        }
    end

    -- Each module's own blurb, reused as the panel header description so it does
    -- not have to be repeated as the first row of the page. Read from the
    -- AceConfig tree rather than GetEUIOptions, which would mean calling into
    -- every module at login just to build the sidebar.
    local function descriptionFor(key)
        local grp = parentOptions.args[key]
        local desc = grp and grp.args and grp.args.description
        local text = desc and resolve(desc.name)

        if not text then
            return nil
        end

        -- The AceConfig strings pad themselves with trailing newlines for ElvUI's
        -- layout; the header does its own spacing.
        return (tostring(text):gsub("%s+$", ""))
    end

    addEntry("General", "General", { pageGeneral }, function(_, parent, y)
        return XerionUIFeatures:BuildEUIGeneralPage(parent, y)
    end, "Quality-of-life indicators, alerts and helpers. Move things with EllesmereUI's unlock mode.")

    local emittedCombined = {}

    for _, key in ipairs(moduleKeys) do
        local combined = combinedByModule[key]

        -- Skip modules with no hand-authored list -- they would get a sidebar row
        -- that opens an empty page. DungeonTeleports is the only one today.
        if combined then
            if not emittedCombined[combined.key] then
                emittedCombined[combined.key] = true

                local parts = {}

                for _, memberKey in ipairs(combined.members) do
                    local member = self:GetModule(memberKey, true)

                    if member and member.GetEUIOptions then
                        parts[#parts + 1] = {
                            key = memberKey,
                            module = member,
                            display = displayFor(memberKey),
                        }
                    end
                end

                if #parts > 0 then
                    -- One tab per member, labelled with its own name, so each keeps
                    -- a page to itself instead of sharing one long scroll.
                    local pages, moduleByPage = {}, {}

                    for _, part in ipairs(parts) do
                        pages[#pages + 1] = part.display
                        moduleByPage[part.display] = part.module
                    end

                    addEntry(combined.key, combined.display, pages,
                        function(pageName, parent, y)
                            local module = moduleByPage[pageName] or parts[1].module

                            return XerionUIFeatures:BuildEUIModulePage(module, parent, y, true)
                        end, combined.description, parts, function(pageName)
                            return moduleByPage[pageName]
                        end)
                end
            end
        else
            local module = self:GetModule(key, true)

            if module and module.GetEUIOptions then
                -- Modules with nothing to turn off opt out of the row's enable
                -- switch by setting EUINoEnableSwitch; no members means no switch.
                local members

                if not module.EUINoEnableSwitch then
                    members = { { key = key, module = module } }
                end

                addEntry(key, displayFor(key), module.EUIPages or { defaultPage(module) },
                    function(pageName, parent, y)
                        return XerionUIFeatures:BuildEUIModulePage(module, parent, y, true, pageName)
                    end, descriptionFor(key), members, function()
                        return module
                    end)
            end
        end
    end

    addEntry("Profiles", "Profiles", { pageProfiles, pageImportExport }, function(pageName, parent, y)
        if pageName == pageImportExport then
            return XerionUIFeatures:BuildEUIImportExportPage(parent, y)
        end

        return XerionUIFeatures:BuildEUIProfilesPage(parent, y)
    end)

    self:InjectEUISidebar(entries)

    -- Attach the row switches as soon as the panel opens rather than waiting for a
    -- page to be built. The rows only exist once CreateMainFrame has run, and that
    -- is reachable only from these three, each of which also runs
    -- RefreshSidebarStates before returning -- so a post-hook on them is the
    -- earliest point at which every row is present. Attaching is idempotent, so
    -- firing on every open (and on Toggle's close) costs nothing.
    local ours = {}

    for _, entry in ipairs(entries) do
        ours[entry.key] = true
    end

    if not self._euiSwitchHooked then
        self._euiSwitchHooked = true

        for _, name in ipairs({ "Show", "Toggle", "ShowModule" }) do
            if EUI[name] then
                hooksecurefunc(EUI, name, function()
                    XerionUIFeatures:AttachEUISidebarGroupNote()
                    XerionUIFeatures:AttachEUISidebarSwitches(entries)
                    XerionUIFeatures:RefreshEUISidebarRows(entries)
                end)
            end
        end

        -- SelectModule recolours the outgoing and incoming labels itself. It is also
        -- where the row `/itrulia` reopens is remembered from -- EllesmereUI keeps
        -- the tab per module itself, so the row is all we have to hold on to.
        if EUI.SelectModule then
            hooksecurefunc(EUI, "SelectModule", function(_, folderName)
                if ours[folderName] then
                    XerionUIFeatures:RememberEUIModule(folderName)
                end

                XerionUIFeatures:RefreshEUISidebarRows(entries)
            end)
        end
    end

    for _, entry in ipairs(entries) do
        local build = entry.build

        -- onReset wipes the whole profile, so it only belongs on the General row.
        -- EllesmereUI labels the footer button "Reset <row>", which on a module
        -- row would read as resetting that module alone.
        local onReset

        if entry.key == addonName .. "_General" then
            onReset = function()
                XerionUIFeatures.db:ResetProfile()
                XerionUIFeatures:RefreshModules()

                if EUI.RefreshPage then
                    EUI:RefreshPage()
                end
            end
        end

        self:RegisterEUIModule(entry.key, {
            title = groupLabelColored .. " - " .. entry.display,
            description = "|cffffbf33BETA:|r " .. (entry.description or ""),
            pages = entry.pages,
            buildPage = function(pageName, parent, yOffset)
                -- Filling the content header is the page's own job on a cold build;
                -- getHeaderBuilder below only hands the same builder back so
                -- EllesmereUI can re-run it after invalidating its header cache.
                --
                -- Not while prebuilding: EllesmereUI's global search runs buildPage
                -- against an off-screen wrapper to index it, and there is only ever
                -- one preview instance per module -- filling the header here would
                -- move it out of the page the player is actually looking at.
                local headerBuilder = not EUI._prebuilding
                    and XerionUIFeatures:EUIPageHeaderBuilder(entry, pageName)

                if headerBuilder and EUI.SetContentHeader then
                    EUI:SetContentHeader(headerBuilder)
                end

                local y = yOffset

                if entry.betaNotice then
                    local _, noticeH = XerionUIFeatures:RenderEUIBetaNotice(parent, y)
                    y = y - noticeH
                end

                return build(pageName, parent, y) or math.abs(y)
            end,
            getHeaderBuilder = function(pageName)
                return XerionUIFeatures:EUIPageHeaderBuilder(entry, pageName)
            end,
            onPageCacheRestore = function(pageName)
                local module = entry.previewFor and entry.previewFor(pageName)

                if module then
                    XerionUIFeatures:RestoreEUIPreview(module, pageName)
                end
            end,
            onReset = onReset,
        })
    end

    -- Test mode follows unlock mode (the EllesmereUI equivalent of hooking ElvUI's ToggleMovers).
    if EUI.RegisterUnlockModeListener then
        EUI:RegisterUnlockModeListener(addonName, function(active)
            XerionUIFeatures:ToggleTestMode(active and true or false)
        end)
    end
end
