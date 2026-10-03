local addonName, XerionUIFeatures = ...
local moduleName = "CombatAlert"

local LSM = XerionUIFeatures.LSM
local LEM = XerionUIFeatures.LEM
local E = XerionUIFeatures.E

local CombatAlert = XerionUIFeatures:NewModule(moduleName)

local function OnEvent(self, event, ...)
    if XerionUIFeatures.testMode then
        self.text:SetText(CombatAlert.db.combatStartsText)
        self.text:SetTextColor(CombatAlert.db.combatEndsColor.r, CombatAlert.db.combatEndsColor.g, CombatAlert.db.combatEndsColor.b, CombatAlert.db.combatEndsColor.a)
        self.text:SetAlpha(1)
        return self:UpdateStyles()
    else
        self.text:SetText("")
    end

    if event == "PLAYER_REGEN_ENABLED" then
        self.text:SetText(CombatAlert.db.combatEndsText)
        self.text:SetTextColor(CombatAlert.db.combatEndsColor.r, CombatAlert.db.combatEndsColor.g, CombatAlert.db.combatEndsColor.b, CombatAlert.db.combatEndsColor.a)
        self.text:SetAlpha(1)
        self.text.anim:Stop()
        self.text.anim:Play()
    elseif event == "PLAYER_REGEN_DISABLED" then
        self.text:SetText(CombatAlert.db.combatStartsText)
        self.text:SetTextColor(CombatAlert.db.combatStartsColor.r, CombatAlert.db.combatStartsColor.g, CombatAlert.db.combatStartsColor.b, CombatAlert.db.combatStartsColor.a)
        self.text:SetAlpha(1)
        self.text.anim:Stop()
        self.text.anim:Play()
    end

    self:UpdateStyles()
end

function CombatAlert:GenerateFrame(name, parent)
    local frame = CreateFrame("frame", name, parent or UIParent)
    PixelUtil.SetPoint(frame, "CENTER", frame:GetParent() or UIParent, "CENTER", 0, 0)
    PixelUtil.SetSize(frame, 28, 28)

    frame.text = frame:CreateFontString(nil, "OVERLAY")
    frame.text:SetPoint("CENTER")
    frame.text:SetFont(LSM:Fetch("font", "GothamNarrowBlack"), 28, "OUTLINE")
    frame.text:SetTextColor(1, 1, 1)
    frame.text:SetJustifyH("CENTER")

    frame.text.anim = frame.text:CreateAnimationGroup()
    frame.text.anim:SetScript("OnFinished", function()
        frame.text:SetText("")
    end)
    frame.alpha = frame.text.anim:CreateAnimation("Alpha")
    frame.alpha:SetFromAlpha(1)
    frame.alpha:SetToAlpha(0)
    frame.alpha:SetDuration(1)
    frame.alpha:SetStartDelay(1.5)

    function frame:UpdateStyles()
        if not E then
            self:ClearAllPoints()
            PixelUtil.SetPoint(self, CombatAlert.db.point.point, self:GetParent() or UIParent, CombatAlert.db.point.point, CombatAlert.db.point.x, CombatAlert.db.point.y)
        end

        self:SetFrameStrata(CombatAlert.db.font.frameStrata or "BACKGROUND")
        self:SetFrameLevel(CombatAlert.db.font.frameLevel or 1)
        self.text:ClearAllPoints()
        self.text:SetPoint(CombatAlert.db.font.justifyH or "CENTER")
        self.text:SetJustifyH(CombatAlert.db.font.justifyH or "CENTER")
        if CombatAlert.db.font.fontOutline ~= "OUTLINESLUG" then
            self.text:SetShadowColor(CombatAlert.db.font.fontShadowColor.r, CombatAlert.db.font.fontShadowColor.g, CombatAlert.db.font.fontShadowColor.b, CombatAlert.db.font.fontShadowColor.a)
            self.text:SetShadowOffset(CombatAlert.db.font.fontShadowXOffset, CombatAlert.db.font.fontShadowYOffset)
        else
            self.text:SetShadowColor(0, 0, 0, 0)
            self.text:SetShadowOffset(0, 0)
        end
        self.text:SetFont(LSM:Fetch("font", CombatAlert.db.font.fontFamily), CombatAlert.db.font.fontSize, CombatAlert.db.font.fontOutline)

        PixelUtil.SetSize(self, self.text:GetStringWidth(), self.text:GetStringHeight())
    end

    return frame
end

function CombatAlert:EnsureFrame()
    if self.frame then
        return self.frame
    end

    local frame = self:GenerateFrame(addonName .. moduleName)
    self.frame = frame

    frame:RegisterEvent("PLAYER_REGEN_DISABLED")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
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

function CombatAlert:OnInitialize()
    local profile = XerionUIFeatures.db.profile
    profile.CombatAlert = profile.CombatAlert or self:GetDefaults()
    self.db = profile.CombatAlert
end

function CombatAlert:RefreshConfig()
    local profile = XerionUIFeatures.db.profile
    profile.CombatAlert = profile.CombatAlert or self:GetDefaults()
    self.db = profile.CombatAlert

    if self.db.enabled then
        local frame = self:EnsureFrame()

        frame:UpdateStyles()
        frame:SetScript("OnEvent", OnEvent)
        OnEvent(frame)
    elseif self.frame then
        self.frame:SetScript("OnEvent", nil)
        self.frame:SetScript("OnUpdate", nil)
        self.frame.text.anim:Stop()
        self.frame.text:SetText("")
    end
end

function CombatAlert:ApplyFontSettings(font)
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

function CombatAlert:OnEnable()
    self:RefreshConfig()
end

function CombatAlert:ToggleTestMode()
    if not self.db.enabled or not self.frame then
        return
    end

    OnEvent(self.frame)
end

function CombatAlert:RegisterOptions(parentOptions)
    parentOptions.args[moduleName] = self:GetOptions(function()
        if self.frame then
            self.frame:UpdateStyles()
        end

        XerionUIFeatures:RefreshPreview(self)
    end);
end
