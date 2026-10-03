local addonName, XerionUIFeatures = ...
local moduleName = "NoTargetIndicator"

local LSM = XerionUIFeatures.LSM
local LEM = XerionUIFeatures.LEM
local E = XerionUIFeatures.E

local NoTargetIndicator = XerionUIFeatures:NewModule(moduleName)

local function OnEvent(self, ...)
    self.text:Hide()

    if XerionUIFeatures.testMode then
        self.text:Show()
        return
    end

    if not PlayerIsInCombat() then
        return
    end

    if UnitIsDeadOrGhost("target") then
        self.text:Show()
        return
    end

    if not UnitExists("target") then
        self.text:Show()
        return
    end

    if not UnitCanAttack("player", "target") and not NoTargetIndicator.db.friendlyisValidTarget then
        self.text:Show()
        return
    end
end

function NoTargetIndicator:GenerateFrame(name, parent)
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
            PixelUtil.SetPoint(self, NoTargetIndicator.db.point.point, self:GetParent() or UIParent, NoTargetIndicator.db.point.point, NoTargetIndicator.db.point.x, NoTargetIndicator.db.point.y)
        end

        self:SetFrameStrata(NoTargetIndicator.db.font.frameStrata or "BACKGROUND")
        self:SetFrameLevel(NoTargetIndicator.db.font.frameLevel or 1)
        self.text:ClearAllPoints()
        self.text:SetPoint(NoTargetIndicator.db.font.justifyH or "CENTER")
        self.text:SetJustifyH(NoTargetIndicator.db.font.justifyH or "CENTER")
        self.text:SetText(NoTargetIndicator.db.displayText)
        self.text:SetTextColor(NoTargetIndicator.db.color.r, NoTargetIndicator.db.color.g, NoTargetIndicator.db.color.b, NoTargetIndicator.db.color.a)
        if NoTargetIndicator.db.font.fontOutline ~= "OUTLINESLUG" then
            self.text:SetShadowColor(NoTargetIndicator.db.font.fontShadowColor.r, NoTargetIndicator.db.font.fontShadowColor.g, NoTargetIndicator.db.font.fontShadowColor.b, NoTargetIndicator.db.font.fontShadowColor.a)
            self.text:SetShadowOffset(NoTargetIndicator.db.font.fontShadowXOffset, NoTargetIndicator.db.font.fontShadowYOffset)
        else
            self.text:SetShadowColor(0, 0, 0, 0)
            self.text:SetShadowOffset(0, 0)
        end
        self.text:SetFont(LSM:Fetch("font", NoTargetIndicator.db.font.fontFamily), NoTargetIndicator.db.font.fontSize, NoTargetIndicator.db.font.fontOutline)

        PixelUtil.SetSize(self, self.text:GetStringWidth(), self.text:GetStringHeight())
    end

    return frame
end

function NoTargetIndicator:EnsureFrame()
    if self.frame then
        return self.frame
    end

    local frame = self:GenerateFrame(addonName .. moduleName)
    self.frame = frame

    frame:RegisterEvent("PLAYER_TARGET_CHANGED")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    frame:RegisterEvent("PLAYER_REGEN_DISABLED")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("UNIT_DIED")

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

function NoTargetIndicator:OnInitialize()
    local profile = XerionUIFeatures.db.profile
    profile.NoTargetIndicator = profile.NoTargetIndicator or self:GetDefaults()
    self.db = profile.NoTargetIndicator
end

function NoTargetIndicator:RefreshConfig()
    local profile = XerionUIFeatures.db.profile
    profile.NoTargetIndicator = profile.NoTargetIndicator or self:GetDefaults()
    self.db = profile.NoTargetIndicator

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

function NoTargetIndicator:ApplyFontSettings(font)
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

function NoTargetIndicator:OnEnable()
    self:RefreshConfig()
end

function NoTargetIndicator:ToggleTestMode()
    if not self.db.enabled or not self.frame then
        return
    end

    OnEvent(self.frame)
end

function NoTargetIndicator:RegisterOptions(parentOptions)
    parentOptions.args[moduleName] = self:GetOptions(function()
        if self.frame then
            self.frame:UpdateStyles()
        end

        XerionUIFeatures:RefreshPreview(self)
    end)
end
