local addonName, XerionUIFeatures = ...
local moduleName = "PotionAlert"

local LSM = XerionUIFeatures.LSM
local LEM = XerionUIFeatures.LEM
local E = XerionUIFeatures.E

local PotionAlert = XerionUIFeatures:NewModule(moduleName)

local potions = {
    -- TWW
    212263, -- Tempered Potion
    212264, -- Tempered Potion
    212265, -- Tempered Potion
    -- Midnight
    241292, -- Draught of Rampant Abandon
    241293, -- Draught of Rampant Abandon
    241308, -- Light's Potential
    241309, -- Light's Potential
}

local function OnEvent(self, event, ...)
    self.text:Hide()

    if event == "ENCOUNTER_START" then
        -- Makes it so at the start of a boss fight you wont be told it's off cd
        self.onCD = false
    end

    if XerionUIFeatures.testMode then
        self.text:Show()
        return
    end

    local potion
    for _, v in ipairs(self.potions) do
        local _, _, enabled = C_Container.GetItemCooldown(v)

        if enabled then
            potion = v
            break;
        end
    end

    if not potion then
        return
    end

    if
        (PotionAlert.db.enabledInDungeons and XerionUIFeatures:InMythicDungeon())
        or (PotionAlert.db.enabledInRaids and XerionUIFeatures:InRaid() and PlayerIsInCombat())
    then
        local start = C_Container.GetItemCooldown(potion)

        if start == 0 then
            if self.onCD then
                if PotionAlert.db.playSound and PotionAlert.db.sound then
                    PlaySoundFile(LSM:Fetch("sound", PotionAlert.db.sound), "Master")
                elseif PotionAlert.db.playTTS and PotionAlert.db.TTS then
                    C_VoiceChat.SpeakText(PotionAlert.db.TTSVoice, PotionAlert.db.TTS, 1, PotionAlert.db.TTSVolume, true)
                end
            end

            self.onCD = false
            self.text:Show()
        else
            self.onCD = true
        end
    end
end

function PotionAlert:GenerateFrame(name, parent)
    local frame = CreateFrame("frame", name, parent or UIParent)
    PixelUtil.SetPoint(frame, "CENTER", frame:GetParent() or UIParent, "CENTER", 0, 300)
    PixelUtil.SetSize(frame, 28, 28)

    frame.text = frame:CreateFontString(nil, "OVERLAY")
    frame.text:SetPoint("CENTER")
    frame.text:SetFont(LSM:Fetch("font", "GothamNarrowBlack"), 14, "OUTLINE")
    frame.text:SetTextColor(1, 1, 1, 1)
    frame.text:SetJustifyH("CENTER")
    frame.text:Hide();

    frame.onCD = false
    frame.potions = potions

    function frame:UpdateStyles()
        if not E then
            self:ClearAllPoints()
            PixelUtil.SetPoint(self, PotionAlert.db.point.point, self:GetParent() or UIParent, PotionAlert.db.point.point, PotionAlert.db.point.x, PotionAlert.db.point.y)
        end

        self:SetFrameStrata(PotionAlert.db.font.frameStrata or "BACKGROUND")
        self:SetFrameLevel(PotionAlert.db.font.frameLevel or 1)
        self.text:ClearAllPoints()
        self.text:SetPoint(PotionAlert.db.font.justifyH or "CENTER")
        self.text:SetJustifyH(PotionAlert.db.font.justifyH or "CENTER")
        self.text:SetText(PotionAlert.db.displayText)
        self.text:SetTextColor(PotionAlert.db.color.r, PotionAlert.db.color.g, PotionAlert.db.color.b, PotionAlert.db.color.a)
        if PotionAlert.db.font.fontOutline ~= "OUTLINESLUG" then
            self.text:SetShadowColor(PotionAlert.db.font.fontShadowColor.r, PotionAlert.db.font.fontShadowColor.g, PotionAlert.db.font.fontShadowColor.b, PotionAlert.db.font.fontShadowColor.a)
            self.text:SetShadowOffset(PotionAlert.db.font.fontShadowXOffset, PotionAlert.db.font.fontShadowYOffset)
        else
            self.text:SetShadowColor(0, 0, 0, 0)
            self.text:SetShadowOffset(0, 0)
        end
        self.text:SetFont(LSM:Fetch("font", PotionAlert.db.font.fontFamily), PotionAlert.db.font.fontSize, PotionAlert.db.font.fontOutline)
        PixelUtil.SetSize(self, math.max(self.text:GetStringWidth(), 28), math.max(self.text:GetStringHeight(), 28))
    end

    return frame
end

function PotionAlert:EnsureFrame()
    if self.frame then
        return self.frame
    end

    local frame = self:GenerateFrame(addonName .. moduleName)
    self.frame = frame

    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("BAG_UPDATE_COOLDOWN") -- doesn't fire often in dungeons/raids
    frame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    frame:RegisterEvent("PLAYER_REGEN_DISABLED")
    frame:RegisterEvent("ENCOUNTER_START")

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

function PotionAlert:OnInitialize()
    local profile = XerionUIFeatures.db.profile
    profile.PotionAlert = profile.PotionAlert or self:GetDefaults()
    self.db = profile.PotionAlert

    -- Migration
    self.db.TTSVoice = self.db.TTSVoice or self:GetDefaults().TTSVoice
end

function PotionAlert:RefreshConfig()
    local profile = XerionUIFeatures.db.profile
    profile.PotionAlert = profile.PotionAlert or self:GetDefaults()
    self.db = profile.PotionAlert

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

function PotionAlert:ApplyFontSettings(font)
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

function PotionAlert:OnEnable()
    self:RefreshConfig()
end

function PotionAlert:ToggleTestMode()
    if not self.db.enabled or not self.frame then
        return
    end

    OnEvent(self.frame)
end

function PotionAlert:RegisterOptions(parentOptions)
    parentOptions.args[moduleName] = self:GetOptions(function()
        if self.frame then
            self.frame:UpdateStyles()
            OnEvent(self.frame)
        end

        XerionUIFeatures:RefreshPreview(self)
    end)
end
