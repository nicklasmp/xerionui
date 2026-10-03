local addonName, XerionUIFeatures = ...
local moduleName = "DeathAlert"

local LSM = XerionUIFeatures.LSM
local LEM = XerionUIFeatures.LEM
local E = XerionUIFeatures.E

local DeathAlert = XerionUIFeatures:NewModule(moduleName)

local function OnEvent(self, event, deadGUID, ...)
    if XerionUIFeatures.testMode then
        local name = UnitName("player")
        local _, class = UnitClass("player")

        local color = C_ClassColor.GetClassColor(class);
        local displayText = CreateColor(
            DeathAlert.db.color.r,
            DeathAlert.db.color.g,
            DeathAlert.db.color.b,
            DeathAlert.db.color.a
        ):WrapTextInColorCode(DeathAlert.db.displayText)
        local nameText = color:WrapTextInColorCode(name)

        self.text:SetText(nameText .. " " .. displayText)
        self.text:SetAlpha(1)

        return self:UpdateStyles()
    end

    if event == "UNIT_DIED" then
        local unitId = XerionUIFeatures:UnitTokenFromGUID(deadGUID)

        if not unitId or not UnitIsDead(unitId) then
            -- well hunters in your party feign deathing is causing the event to fire without actually dying
            return
        end

        if UnitInParty(unitId) or UnitInRaid(unitId) or unitId == "player" then
            local showText = true;
            local sound = DeathAlert.db.sound;
            local playSound = DeathAlert.db.playSound and sound;
            local tts = DeathAlert.db.TTS;
            local playTTS = DeathAlert.db.playTTS and tts;

            local name = UnitName(unitId)

            if canaccessvalue(name) then
                if DeathAlert.db.whitelist and DeathAlert.db.whitelist ~= "" then
                    local allowedNames = XerionUIFeatures:SplitAndTrim(DeathAlert.db.whitelist)
                    local found = false

                    for _, v in ipairs(allowedNames) do
                        if v == name then
                            found = true
                            break
                        end
                    end

                    if not found then
                        return
                    end
                elseif DeathAlert.db.blacklist and DeathAlert.db.blacklist ~= "" then
                    local blockedNames = XerionUIFeatures:SplitAndTrim(DeathAlert.db.blacklist)
                    local found = false

                    for _, v in ipairs(blockedNames) do
                        if v == name then
                            found = true
                            break
                        end
                    end

                    if found then
                        return
                    end
                end
            end

            -- Only do role based configuration inside a raid
            if XerionUIFeatures:InRaid() then
                local role = UnitGroupRolesAssigned(unitId)

                if role == "NONE" then
                    role = "DAMAGER"
                end

                showText = DeathAlert.db.byRole.display[role].enabled
                sound = DeathAlert.db.byRole.sound[role].sound or sound
                playSound = playSound and DeathAlert.db.byRole.sound[role].enabled and sound
                tts = DeathAlert.db.byRole.sound[role].tts or tts
                playTTS = playTTS and DeathAlert.db.byRole.tts[role].enabled and tts
            end

            if showText then
                local name = UnitName(unitId)
                local _, class = UnitClass(unitId)
                local classColor = C_ClassColor.GetClassColor(class)

                local displayText = CreateColor(
                    DeathAlert.db.color.r,
                    DeathAlert.db.color.g,
                    DeathAlert.db.color.b,
                    DeathAlert.db.color.a
                ):WrapTextInColorCode(DeathAlert.db.displayText)
                local nameText = classColor:WrapTextInColorCode(name)

                self.text:SetText(nameText .. " " .. displayText)
                self.text:SetAlpha(1)
                self.text.anim:Stop()
                self.text.anim:Play()
            end

            if not self.lastSoundPlayedAt or (GetTime() - self.lastSoundPlayedAt) > 2 then
                if playSound then
                    self.lastSoundPlayedAt = GetTime()
                    PlaySoundFile(LSM:Fetch("sound", sound), "Master")
                elseif playTTS then
                    self.lastSoundPlayedAt = GetTime()
                    C_VoiceChat.SpeakText(DeathAlert.db.TTSVoice, tts, 1, DeathAlert.db.TTSVolume, true)
                end
            end
        else
            self.text:SetText("")
        end
    else
        self.text:SetText("")
    end

    self:UpdateStyles()
end

function DeathAlert:GenerateFrame(name, parent)
    local frame = CreateFrame("frame", name, parent or UIParent)
    PixelUtil.SetPoint(frame, "CENTER", frame:GetParent() or UIParent, "CENTER", 0, 300)
    PixelUtil.SetSize(frame, 28, 28)
    frame.lastSoundPlayedAt = nil

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
    frame.alpha:SetStartDelay(4)

    function frame:UpdateStyles()
        if not E then
            self:ClearAllPoints()
            PixelUtil.SetPoint(self, DeathAlert.db.point.point, self:GetParent() or UIParent, DeathAlert.db.point.point, DeathAlert.db.point.x, DeathAlert.db.point.y)
        end

        self:SetFrameStrata(DeathAlert.db.font.frameStrata or "BACKGROUND")
        self:SetFrameLevel(DeathAlert.db.font.frameLevel or 1)
        self.text:ClearAllPoints()
        self.text:SetPoint(DeathAlert.db.font.justifyH or "CENTER")
        self.text:SetJustifyH(DeathAlert.db.font.justifyH or "CENTER")
        self.text:SetTextColor(DeathAlert.db.color.r, DeathAlert.db.color.g, DeathAlert.db.color.b, DeathAlert.db.color.a)
        if DeathAlert.db.font.fontOutline ~= "OUTLINESLUG" then
            self.text:SetShadowColor(DeathAlert.db.font.fontShadowColor.r, DeathAlert.db.font.fontShadowColor.g, DeathAlert.db.font.fontShadowColor.b, DeathAlert.db.font.fontShadowColor.a)
            self.text:SetShadowOffset(DeathAlert.db.font.fontShadowXOffset, DeathAlert.db.font.fontShadowYOffset)
        else
            self.text:SetShadowColor(0, 0, 0, 0)
            self.text:SetShadowOffset(0, 0)
        end
        self.text:SetFont(LSM:Fetch("font", DeathAlert.db.font.fontFamily), DeathAlert.db.font.fontSize, DeathAlert.db.font.fontOutline)
        self.alpha:SetStartDelay(DeathAlert.db.messageDuration)

        PixelUtil.SetSize(self, self.text:GetStringWidth(), self.text:GetStringHeight())
    end

    return frame
end

function DeathAlert:EnsureFrame()
    if self.frame then
        return self.frame
    end

    local frame = self:GenerateFrame(addonName .. moduleName)
    self.frame = frame

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

function DeathAlert:OnInitialize()
    local profile = XerionUIFeatures.db.profile
    profile.DeathAlert = profile.DeathAlert or self:GetDefaults()
    self.db = profile.DeathAlert

    -- Migration
    self.db.byRole = self.db.byRole or self:GetDefaults().byRole
    self.db.TTSVoice = self.db.TTSVoice or self:GetDefaults().TTSVoice
end

function DeathAlert:RefreshConfig()
    local profile = XerionUIFeatures.db.profile
    profile.DeathAlert = profile.DeathAlert or self:GetDefaults()
    self.db = profile.DeathAlert

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

function DeathAlert:ApplyFontSettings(font)
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

function DeathAlert:OnEnable()
    self:RefreshConfig()
end

function DeathAlert:ToggleTestMode()
    if not self.db.enabled or not self.frame then
        return
    end

    OnEvent(self.frame)
end

function DeathAlert:RegisterOptions(parentOptions)
    parentOptions.args[moduleName] = self:GetOptions(function()
        if self.frame then
            self.frame:UpdateStyles()
        end

        XerionUIFeatures:RefreshPreview(self)
    end)
end
