local addonName, XerionUIFeatures = ...
local moduleName = "FocusInterruptIndicator"
local LSM = XerionUIFeatures.LSM
local LEM = XerionUIFeatures.LEM
local E = XerionUIFeatures.E

local FocusInterruptIndicator = XerionUIFeatures:NewModule(moduleName)

local function OnEvent(self, event, unit, ...)
    self.active = false

    if XerionUIFeatures.testMode then
        self:SetAlpha(1)
        self.text:Show()
        self.text:SetAlpha(1)
        return
    end

    if event == "PLAYER_SPECIALIZATION_CHANGED" or event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        self:CacheInterruptId()
        return
    end

    if unit and UnitCanAttack("player", unit) then
        if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START" or event == "PLAYER_FOCUS_CHANGED" then
            self:UpdateFocusInterruptIndicator(true)
        end
    end
end

local function OnUpdate(self)
    if XerionUIFeatures.testMode then
        self:SetAlpha(1)
        self.text:Show()
        self.text:SetAlpha(1)
        return
    end

    if not self.active then
        self:SetAlpha(1)
        self.text:Hide()
        self.text:SetAlpha(0)
        return
    end

    if self.interruptId then
        self.text:Show()
        self.text:SetAlphaFromBoolean(C_Spell.GetSpellCooldownDuration(self.interruptId):IsZero())
        self:SetAlphaFromBoolean(self.notInterruptible, 0, 1)
    end
end

function FocusInterruptIndicator:GenerateFrame(frameName, parent)
    local frame = CreateFrame("frame", frameName, parent or UIParent)
    PixelUtil.SetPoint(frame, "CENTER", parent or UIParent, "CENTER", 0, 150)
    PixelUtil.SetSize(frame, 28, 28)
    frame.active = false
    frame.interruptId = nil
    frame.notInterruptible = nil;

    frame.text = frame:CreateFontString(nil, "OVERLAY")
    frame.text:SetPoint("CENTER")
    frame.text:SetFont(LSM:Fetch("font", "GothamNarrowBlack"), 28, "OUTLINE")
    frame.text:SetTextColor(1, 1, 1)
    frame.text:SetJustifyH("CENTER")
    frame.text:SetText("INTERRUPT")
    frame.text:Hide()

    function frame:UpdateFocusInterruptIndicator(active)
        self.active = active

        if not self.active then
            return
        end

        local name, _, _, _, _, _, notInterruptible = UnitChannelInfo("focus")
        if not name then
            name, _, _, _, _, _, _, notInterruptible = UnitCastingInfo("focus")
        end

        if not name then
            self.active = false
            return
        end

        self.notInterruptible = notInterruptible;

        if FocusInterruptIndicator.db.playSound and FocusInterruptIndicator.db.sound then
            PlaySoundFile(LSM:Fetch("sound", FocusInterruptIndicator.db.sound), "Master")
        elseif FocusInterruptIndicator.db.playTTS and FocusInterruptIndicator.db.TTS then
            C_VoiceChat.SpeakText(FocusInterruptIndicator.db.TTSVoice, FocusInterruptIndicator.db.TTS, 1, FocusInterruptIndicator.db.TTSVolume, true)
        end
    end

    function frame:CacheInterruptId()
        self.interruptId = XerionUIFeatures:GetInterruptSpell()
    end

    function frame:UpdateStyles()
        if not E then
            self:ClearAllPoints()
            PixelUtil.SetPoint(self, FocusInterruptIndicator.db.point.point, self:GetParent() or UIParent, FocusInterruptIndicator.db.point.point, FocusInterruptIndicator.db.point.x, FocusInterruptIndicator.db.point.y)
        end

        self:SetFrameStrata(FocusInterruptIndicator.db.font.frameStrata or "BACKGROUND")
        self:SetFrameLevel(FocusInterruptIndicator.db.font.frameLevel or 1)
        self.text:ClearAllPoints()
        self.text:SetPoint(FocusInterruptIndicator.db.font.justifyH or "CENTER")
        self.text:SetJustifyH(FocusInterruptIndicator.db.font.justifyH or "CENTER")
        self.text:SetText(FocusInterruptIndicator.db.displayText)
        self.text:SetTextColor(FocusInterruptIndicator.db.color.r, FocusInterruptIndicator.db.color.g, FocusInterruptIndicator.db.color.b, FocusInterruptIndicator.db.color.a)
        if FocusInterruptIndicator.db.font.fontOutline ~= "OUTLINESLUG" then
            self.text:SetShadowColor(FocusInterruptIndicator.db.font.fontShadowColor.r, FocusInterruptIndicator.db.font.fontShadowColor.g, FocusInterruptIndicator.db.font.fontShadowColor.b, FocusInterruptIndicator.db.font.fontShadowColor.a)
            self.text:SetShadowOffset(FocusInterruptIndicator.db.font.fontShadowXOffset, FocusInterruptIndicator.db.font.fontShadowYOffset)
        else
            self.text:SetShadowColor(0, 0, 0, 0)
            self.text:SetShadowOffset(0, 0)
        end
        self.text:SetFont(LSM:Fetch("font", FocusInterruptIndicator.db.font.fontFamily), FocusInterruptIndicator.db.font.fontSize, FocusInterruptIndicator.db.font.fontOutline)

        if not self:HasAnySecretAspect() and not self.text:HasAnySecretAspect() then
            PixelUtil.SetSize(self, self.text:GetStringWidth(), self.text:GetStringHeight())
        end
    end

    return frame
end

function FocusInterruptIndicator:EnsureFrame()
    if self.frame then
        return self.frame
    end

    local frame = self:GenerateFrame(addonName .. moduleName)
    self.frame = frame

    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    frame:RegisterEvent("PLAYER_FOCUS_CHANGED")
    frame:RegisterUnitEvent("UNIT_SPELLCAST_START", "focus")
    frame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "focus")
    frame:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "focus")
    frame:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "focus")
    frame:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "focus")
    frame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "focus")

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

function FocusInterruptIndicator:OnInitialize()
    local profile = XerionUIFeatures.db.profile
    profile.FocusInterruptIndicator = profile.FocusInterruptIndicator or self:GetDefaults()
    self.db = profile.FocusInterruptIndicator

    -- Migration
    self.db.TTSVoice = self.db.TTSVoice or self:GetDefaults().TTSVoice
end

function FocusInterruptIndicator:RefreshConfig()
    local profile = XerionUIFeatures.db.profile
    profile.FocusInterruptIndicator = profile.FocusInterruptIndicator or self:GetDefaults()
    self.db = profile.FocusInterruptIndicator

    if self.db.enabled then
        local frame = self:EnsureFrame()

        frame:UpdateStyles()
        frame:CacheInterruptId()
        frame:SetScript("OnEvent", OnEvent)
        frame:SetScript("OnUpdate", OnUpdate)
        OnEvent(frame)
    elseif self.frame then
        self.frame:SetScript("OnEvent", nil)
        self.frame:SetScript("OnUpdate", nil)
        self.frame.text:Hide()
    end
end

function FocusInterruptIndicator:ApplyFontSettings(font)
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

function FocusInterruptIndicator:OnEnable()
    self:RefreshConfig()
end

function FocusInterruptIndicator:ToggleTestMode()
    if not self.db.enabled or not self.frame then
        return
    end

    OnEvent(self.frame)
end

function FocusInterruptIndicator:RegisterOptions(parentOptions)
    parentOptions.args[moduleName] = self:GetOptions(function()
        if self.frame then
            self.frame:UpdateStyles()
        end

        XerionUIFeatures:RefreshPreview(self)
    end);
end
