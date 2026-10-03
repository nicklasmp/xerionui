local addonName, XerionUIFeatures = ...

-- A compact execute control for AceConfig: a spell icon framed by a 1px border
-- with the macro name shown underneath. AceConfigDialog uses it via
-- `dialogControl = "ItruliaMacroIcon"` and drives it through SetImage /
-- SetImageSize / SetLabel / OnClick.
local AceGUI = LibStub("AceGUI-3.0")

local widgetType, widgetVersion = "ItruliaMacroIcon", 4

if (AceGUI:GetWidgetVersion(widgetType) or 0) >= widgetVersion then
    return
end

local borderSize = 1
local labelMargin = 3
local labelPadding = 6
local maxLabelWidth = 100

local function Control_OnEnter(frame)
    frame.obj:Fire("OnEnter")
end

local function Control_OnLeave(frame)
    frame.obj:Fire("OnLeave")
end

local function Control_OnClick(frame, button)
    frame.obj:Fire("OnClick", button)
    AceGUI:ClearFocus()
end

local methods = {
    ["OnAcquire"] = function(self)
        self.exists = nil -- widgets are pooled; clear stale state
        self:SetImageSize(36, 36)
        self:SetImage(nil)
        self:SetLabel()
        self:SetDisabled(false)
    end,

    ["SetLabel"] = function(self, text)
        if text and text ~= "" then
            self.label:SetText(text)
            self.label:Show()
        else
            self.label:SetText("")
            self.label:Hide()
        end

        self:UpdateLayout()
    end,

    ["SetImage"] = function(self, path, ...)
        local image = self.image
        image:SetTexture(path)

        if image:GetTexture() then
            local count = select("#", ...)
            if count == 4 or count == 8 then
                image:SetTexCoord(...)
            else
                image:SetTexCoord(0, 1, 0, 1)
            end
        end
    end,

    ["SetImageSize"] = function(self, width, height)
        self.imageW = width
        self.imageH = height
        PixelUtil.SetSize(self.image, width, height)
        PixelUtil.SetSize(self.border, width + borderSize * 2, height + borderSize * 2)
        self:UpdateLayout()
    end,

    -- Size the frame to the icon, widening for a longer name up to a cap. Names
    -- past the cap wrap onto extra lines (making the button taller) rather than
    -- truncating, so it still flows nicely in the options grid.
    ["UpdateLayout"] = function(self)
        local width = (self.imageW or 36) + borderSize * 2
        local height = (self.imageH or 36) + borderSize * 2

        if self.label:IsShown() then
            -- GetStringWidth is the unwrapped width; cap it, then constrain the
            -- label so GetStringHeight reflects the wrapped line count.
            local labelWidth = math.min(self.label:GetStringWidth(), maxLabelWidth)
            self.label:SetWidth(labelWidth)

            width = math.max(width, labelWidth + labelPadding)
            height = height + labelMargin + self.label:GetStringHeight()
        end

        PixelUtil.SetSize(self.frame, width, height)
    end,

    ["ApplyState"] = function(self)
        if self.disabled then
            self.frame:Disable()
            self.image:SetDesaturated(true)
            self.image:SetVertexColor(0.5, 0.5, 0.5)
            self.border:SetColorTexture(0.3, 0.3, 0.3, 1)
            self.label:SetTextColor(0.5, 0.5, 0.5)
            return
        end

        self.frame:Enable()

        -- Grey out (desaturate) the icon once its macro has been created.
        local exists = self.exists and self.exists()
        self.image:SetDesaturated(exists and true or false)
        self.image:SetVertexColor(1, 1, 1)
        self.border:SetColorTexture(0, 0, 0, 1)
        self.label:SetTextColor(1, 1, 1)
    end,

    ["SetDisabled"] = function(self, disabled)
        self.disabled = disabled
        self:ApplyState()
    end,

    -- AceConfigDialog forwards the option's `arg` here; we use it as an "exists"
    -- getter so the icon greys out when its macro already exists. Re-runs on each
    -- page rebuild (e.g. after a click creates the macro).
    ["SetCustomData"] = function(self, exists)
        self.exists = exists
        self:ApplyState()
    end,
}

local function Constructor()
    local frame = CreateFrame("Button", nil, UIParent)
    frame:Hide()
    frame:EnableMouse(true)
    frame:SetScript("OnEnter", Control_OnEnter)
    frame:SetScript("OnLeave", Control_OnLeave)
    frame:SetScript("OnClick", Control_OnClick)

    local border = frame:CreateTexture(nil, "BACKGROUND")
    border:SetColorTexture(0, 0, 0, 1)
    border:SetPoint("TOP")

    local image = frame:CreateTexture(nil, "ARTWORK")
    image:SetPoint("CENTER", border, "CENTER")

    local highlight = frame:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints(image)
    highlight:SetColorTexture(1, 1, 1, 0.25)
    highlight:SetBlendMode("ADD")

    local label = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    PixelUtil.SetPoint(label, "TOP", border, "BOTTOM", 0, -labelMargin)
    label:SetJustifyH("CENTER")
    label:SetWordWrap(true)

    local widget = {
        image = image,
        border = border,
        label = label,
        frame = frame,
        type = widgetType,
    }

    for method, func in pairs(methods) do
        widget[method] = func
    end

    widget.SetText = widget.SetLabel

    return AceGUI:RegisterAsWidget(widget)
end

AceGUI:RegisterWidgetType(widgetType, Constructor, widgetVersion)
