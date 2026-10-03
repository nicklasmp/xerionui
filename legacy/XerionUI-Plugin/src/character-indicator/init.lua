local addonName, XerionUIFeatures = ...
local moduleName = "CharacterIndicator"

local LSM = XerionUIFeatures.LSM
local LEM = XerionUIFeatures.LEM
local E = XerionUIFeatures.E

local CharacterIndicator = XerionUIFeatures:NewModule(moduleName)


local function OnEvent(self, ...)
    if XerionUIFeatures.testMode or PlayerIsInCombat() then
        self.text:Show()
    else
        self.text:Hide()
    end
end


function CharacterIndicator:GenerateFrame(name, parent)
    local frame = CreateFrame("frame", name, parent or UIParent)
    PixelUtil.SetPoint(frame, "CENTER", frame:GetParent() or UIParent, "CENTER", 0, 0)
    PixelUtil.SetSize(frame, 28, 28)

    frame.text = frame:CreateFontString(nil, "OVERLAY")
    frame.text:SetPoint("CENTER")
    frame.text:SetFont(LSM:Fetch("font", "GothamNarrowBlack"), 28, "OUTLINE")
    frame.text:SetText("+")
    frame.text:SetTextColor(1, 0, 0)
    frame.text:SetJustifyH("CENTER")
    frame.text:Hide()

    function frame:UpdateStyles()
        if not E then
            self:ClearAllPoints()
            PixelUtil.SetPoint(self, CharacterIndicator.db.point.point, self:GetParent() or UIParent, CharacterIndicator.db.point.point, CharacterIndicator.db.point.x, CharacterIndicator.db.point.y)
        end

        self:SetFrameStrata(CharacterIndicator.db.font.frameStrata or "BACKGROUND")
        self:SetFrameLevel(CharacterIndicator.db.font.frameLevel or 1)
        self.text:ClearAllPoints()
        self.text:SetPoint(CharacterIndicator.db.font.justifyH or "CENTER")
        self.text:SetJustifyH(CharacterIndicator.db.font.justifyH or "CENTER")
        self.text:SetTextColor(CharacterIndicator.db.color.r, CharacterIndicator.db.color.g, CharacterIndicator.db.color.b, CharacterIndicator.db.color.a)
        self.text:SetText(CharacterIndicator.db.displayText)
        if CharacterIndicator.db.font.fontOutline ~= "OUTLINESLUG" then
            self.text:SetShadowColor(CharacterIndicator.db.font.fontShadowColor.r, CharacterIndicator.db.font.fontShadowColor.g, CharacterIndicator.db.font.fontShadowColor.b, CharacterIndicator.db.font.fontShadowColor.a)
            self.text:SetShadowOffset(CharacterIndicator.db.font.fontShadowXOffset, CharacterIndicator.db.font.fontShadowYOffset)
        else
            self.text:SetShadowColor(0, 0, 0, 0)
            self.text:SetShadowOffset(0, 0)
        end
        self.text:SetFont(LSM:Fetch("font", CharacterIndicator.db.font.fontFamily), CharacterIndicator.db.font.fontSize, CharacterIndicator.db.font.fontOutline)
        PixelUtil.SetSize(self, math.max(self.text:GetStringWidth(), 28), math.max(self.text:GetStringHeight(), 28))
    end

    return frame
end

function CharacterIndicator:EnsureFrame()
    if self.frame then
        return self.frame
    end

    local frame = self:GenerateFrame(addonName .. moduleName)
    self.frame = frame

    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    frame:RegisterEvent("PLAYER_REGEN_DISABLED")

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

function CharacterIndicator:OnInitialize()
    local profile = XerionUIFeatures.db.profile
    profile.CharacterIndicator = profile.CharacterIndicator or self:GetDefaults()
    self.db = profile.CharacterIndicator
end

function CharacterIndicator:RefreshConfig()
    local profile = XerionUIFeatures.db.profile
    profile.CharacterIndicator = profile.CharacterIndicator or self:GetDefaults()
    self.db = profile.CharacterIndicator

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

function CharacterIndicator:ApplyFontSettings(font)
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

function CharacterIndicator:OnEnable()
    self:RefreshConfig()
end

function CharacterIndicator:ToggleTestMode()
    if not self.db.enabled or not self.frame then
        return
    end

    OnEvent(self.frame)
end

function CharacterIndicator:RegisterOptions(parentOptions)
    parentOptions.args[moduleName] = self:GetOptions(function()
        if self.frame then
            self.frame:UpdateStyles()
        end

        XerionUIFeatures:RefreshPreview(self)
    end)
end
