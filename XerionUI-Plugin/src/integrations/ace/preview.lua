local addonName, XerionUIFeatures = ...

-- AceConfig host for the module previews (the shared core lives in src/preview.lua).
--
-- AceConfigDialog builds it from a `description` option via
-- `dialogControl = "ItruliaPreview"` and hands us the module through the option's
-- `arg` -- see XerionUIFeatures:CreatePreviewOption below.
local AceGUI = LibStub("AceGUI-3.0")

local widgetType, widgetVersion = "ItruliaPreview", 1

if (AceGUI:GetWidgetVersion(widgetType) or 0) >= widgetVersion then
    return
end

local defaultHeight = 120
local labelHeight = 15

local methods = {
    ["OnAcquire"] = function(self)
        self.module = nil -- widgets are pooled; clear stale state
        self.label:SetText("")
        self.frame:SetHeight(defaultHeight)
        self:SetDisabled(false)
    end,

    ["OnRelease"] = function(self)
        self:Detach()
    end,

    ["SetText"] = function(self, text)
        self.label:SetText(text or "")
    end,

    ["SetFontObject"] = function(self, font)
        self.label:SetFontObject(font or GameFontHighlightSmall)
    end,

    ["SetDisabled"] = function(self, disabled)
        self.disabled = disabled
    end,

    -- Called both on release and before attaching a different module, so a pooled
    -- widget never leaves a preview behind.
    ["Detach"] = function(self)
        local module = self.module
        if not module then
            return
        end

        self.module = nil
        XerionUIFeatures:HidePreview(module, self.display)
    end,

    -- AceConfigDialog forwards the option's `arg` here; we expect the table built by
    -- XerionUIFeatures:CreatePreviewOption.
    ["SetCustomData"] = function(self, data)
        self:Detach()

        local module = data and data.module
        if type(module) == "string" then
            module = XerionUIFeatures:GetModule(module, true)
        end

        if not module then
            return
        end

        if data.height then
            self.frame:SetHeight(data.height)
        end

        if XerionUIFeatures:ShowPreview(module, self.display, data.page) then
            self.module = module
        end
    end,
}

-- AceConfigDialog hands us the module -- and so triggers the first draw -- before the
-- widget is parented into the options window, so that draw sees the wrong strata and
-- scale, and measures a frame that has never been laid out. A module that sizes itself
-- from its own layout comes out empty: the flying bar derives its vigor and second
-- wind pip widths from the speed bar's width, which reads zero until a layout pass has
-- run. So re-pin now, and restyle from scratch once the panel has laid us out.
--
-- EllesmereUI needs none of this: its content header is already parented and sized
-- when it calls the builder.
local function Control_OnShow(frame)
    local widget = frame.obj

    if not widget.module then
        return
    end

    XerionUIFeatures:PinPreview(widget.module)

    C_Timer.After(0, function()
        -- Widgets are pooled, so re-read the module rather than capturing it: by now
        -- this one may be showing a different page's preview, and that is the one
        -- wanting the redraw.
        if widget.module then
            XerionUIFeatures:RefreshPreview(widget.module)
        end
    end)
end

local function Constructor()
    local frame = CreateFrame("frame", nil, UIParent, "BackdropTemplate")
    frame:Hide()
    frame:SetBackdrop({
        bgFile = [[Interface\Buttons\WHITE8x8]],
        edgeFile = [[Interface\Buttons\WHITE8x8]],
        edgeSize = 1,
    })
    frame:SetBackdropColor(0, 0, 0, 0.4)
    frame:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    frame:SetHeight(defaultHeight)
    frame:SetScript("OnShow", Control_OnShow)

    local label = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    PixelUtil.SetPoint(label, "TOPLEFT", label:GetParent() or UIParent, "TOPLEFT", 5, -3)
    label:SetJustifyH("LEFT")

    -- Clipped so an oversized preview (a long alert text, a wide bar) stays inside the
    -- box instead of drawing over the rest of the options page.
    local display = CreateFrame("frame", nil, frame)
    PixelUtil.SetPoint(display, "TOPLEFT", display:GetParent() or UIParent, "TOPLEFT", 1, -labelHeight)
    PixelUtil.SetPoint(display, "BOTTOMRIGHT", display:GetParent() or UIParent, "BOTTOMRIGHT", -1, 1)
    display:SetClipsChildren(true)

    local widget = {
        label = label,
        display = display,
        frame = frame,
        type = widgetType,
    }

    for method, func in pairs(methods) do
        widget[method] = func
    end

    return AceGUI:RegisterAsWidget(widget)
end

AceGUI:RegisterWidgetType(widgetType, Constructor, widgetVersion)

-- Option entry for the top of a module's AceConfig page.
--
-- `page` only matters for a module split across tabs (`childGroups = "tab"`). Put one
-- of these at the top of each tab's group naming that tab, and PreparePreview gets it
-- -- so a tab previews the state it configures. Switching tabs releases one widget and
-- acquires the other, which is what re-points the single preview instance.
function XerionUIFeatures:CreatePreviewOption(module, order, height, page)
    return {
        order = order or 0,
        type = "description",
        name = "Preview",
        width = "full",
        dialogControl = "ItruliaPreview",
        arg = {module = module, height = height, page = page},
    }
end
