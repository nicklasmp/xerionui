local addonName, XerionUIFeatures = ...
local moduleName = "StealthIndicator"

local LSM = XerionUIFeatures.LSM
local LEM = XerionUIFeatures.LEM
local E = XerionUIFeatures.E

local StealthIndicator = XerionUIFeatures:NewModule(moduleName)

local function OnEvent(self, ...)
    if XerionUIFeatures.testMode then
        self.text:Show()
        return
    end

    if IsStealthed() then
        self.text:Show()
    else
        self.text:Hide()
    end
end

function StealthIndicator:GenerateFrame(name, parent)
    local frame = CreateFrame("frame", name, parent or UIParent)
    PixelUtil.SetPoint(frame, "CENTER", frame:GetParent() or UIParent, "CENTER", 0, 50)
    PixelUtil.SetSize(frame, 28, 28)

    frame.text = frame:CreateFontString(nil, "OVERLAY")
    frame.text:SetPoint("CENTER")
    frame.text:SetFont(LSM:Fetch("font", "GothamNarrowBlack"), 14, "OUTLINE")
    frame.text:SetTextColor(1, 1, 1)
    frame.text:SetJustifyH("CENTER")

    function frame:UpdateStyles()
        if not E then
            self:ClearAllPoints()
            PixelUtil.SetPoint(self, StealthIndicator.db.point.point, self:GetParent() or UIParent, StealthIndicator.db.point.point, StealthIndicator.db.point.x, StealthIndicator.db.point.y)
        end

        self:SetFrameStrata(StealthIndicator.db.font.frameStrata or "BACKGROUND")
        self:SetFrameLevel(StealthIndicator.db.font.frameLevel or 1)
        self.text:ClearAllPoints()
        self.text:SetPoint(StealthIndicator.db.font.justifyH or "CENTER")
        self.text:SetJustifyH(StealthIndicator.db.font.justifyH or "CENTER")
        self.text:SetText(StealthIndicator.db.displayText)
        self.text:SetTextColor(StealthIndicator.db.color.r, StealthIndicator.db.color.g, StealthIndicator.db.color.b, StealthIndicator.db.color.a)

        if StealthIndicator.db.font.fontOutline ~= "OUTLINESLUG" then
            self.text:SetShadowColor(StealthIndicator.db.font.fontShadowColor.r, StealthIndicator.db.font.fontShadowColor.g, StealthIndicator.db.font.fontShadowColor.b, StealthIndicator.db.font.fontShadowColor.a)
            self.text:SetShadowOffset(StealthIndicator.db.font.fontShadowXOffset, StealthIndicator.db.font.fontShadowYOffset)
        else
            self.text:SetShadowColor(0, 0, 0, 0)
            self.text:SetShadowOffset(0, 0)
        end
        self.text:SetFont(LSM:Fetch("font", StealthIndicator.db.font.fontFamily), StealthIndicator.db.font.fontSize, StealthIndicator.db.font.fontOutline)

        PixelUtil.SetSize(self, self.text:GetStringWidth(), self.text:GetStringHeight())
    end

    return frame
end

function StealthIndicator:EnsureFrame()
    if self.frame then
        return self.frame
    end

    local frame = self:GenerateFrame(addonName .. moduleName)
    self.frame = frame

    frame:RegisterEvent("UPDATE_STEALTH")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")

    if E then
        E:CreateMover(frame, frame:GetName() .. "Mover", moduleName, nil,
            nil,
            nil,
            "ALL,ITRULIA",
            function()
                return self.db.enabled
            end,
            addonName .. "," .. moduleName
        )
    elseif XerionUIFeatures.EUI then
        XerionUIFeatures:CreateEUIMover(self, frame, moduleName)
    else
        LEM:AddFrame(frame, function(_, layoutName, point, x, y)
            self.db.point = {point = point, x = x, y = y}
        end, self:GetDefaults().point)
    end

    return frame
end

function StealthIndicator:OnInitialize()
    local profile = XerionUIFeatures.db.profile
    profile.StealthIndicator = profile.StealthIndicator or self:GetDefaults()
    self.db = profile.StealthIndicator
end

function StealthIndicator:RefreshConfig()
    local profile = XerionUIFeatures.db.profile
    profile.StealthIndicator = profile.StealthIndicator or self:GetDefaults()
    self.db = profile.StealthIndicator

    if self.db.enabled then
        local frame = self:EnsureFrame()

        frame:UpdateStyles()
        frame:SetScript("OnEvent", OnEvent)
        OnEvent(frame)
    elseif self.frame then
        self.frame:SetScript("OnEvent", nil)
        self.frame:SetScript("OnUpdate", nil)
        self.frame.text:Hide()
    end
end

function StealthIndicator:ApplyFontSettings(font)
    self.db.font.fontFamily = font.fontFamily
    self.db.font.fontOutline = font.fontOutline
    self.db.font.fontShadowColor = font.fontShadowColor
    self.db.font.fontShadowXOffset = font.fontShadowXOffset
    self.db.font.fontShadowYOffset = font.fontShadowYOffset
    self.db.font.justifyH = font.justifyH

    if self.frame then
        self.frame:UpdateStyles()
    end
end

function StealthIndicator:OnEnable()
    self:RefreshConfig()
end

function StealthIndicator:ToggleTestMode()
    if not self.db.enabled or not self.frame then
        return
    end

    OnEvent(self.frame)
end

function StealthIndicator:RegisterOptions(parentOptions)
    parentOptions.args[moduleName] = self:GetOptions(function()
        if self.frame then
            self.frame:UpdateStyles()
        end

        XerionUIFeatures:RefreshPreview(self)
    end)
end
