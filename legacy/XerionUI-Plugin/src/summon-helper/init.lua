local addonName, XerionUIFeatures = ...
local moduleName = "SummonHelper"

local LSM = XerionUIFeatures.LSM
local LEM = XerionUIFeatures.LEM
local LGF = XerionUIFeatures.LGF
local LCG = LibStub("LibCustomGlow-1.0")
local E = XerionUIFeatures.E

local SummonHelper = XerionUIFeatures:NewModule(moduleName)

SummonHelper.styleBorder = "BORDER"
SummonHelper.stylePixel = "PIXEL"

local ritualOfSummoning = 698
local reminderThrottle = 300

local chatEvents = {
    CHAT_MSG_SAY = true,
    CHAT_MSG_PARTY = true,
    CHAT_MSG_PARTY_LEADER = true,
    CHAT_MSG_RAID = true,
    CHAT_MSG_RAID_LEADER = true,
    CHAT_MSG_INSTANCE_CHAT = true,
    CHAT_MSG_INSTANCE_CHAT_LEADER = true,
}

function SummonHelper:GetPhrases()
    if not self.phrases then
        local phrases = {}

        for _, phrase in ipairs(XerionUIFeatures:SplitAndTrim(self.db.phrases or "")) do
            if phrase ~= "" then
                phrases[#phrases + 1] = phrase:lower()
            end
        end

        self.phrases = phrases
    end

    return self.phrases
end

function SummonHelper:MatchesPhrase(message)
    message = message:lower()

    for _, phrase in ipairs(self:GetPhrases()) do
        if message:find(phrase, 1, true) then
            return true
        end
    end

    return false
end

local highlightPool = {}
local function acquireHighlight()
    local highlight = table.remove(highlightPool)

    if highlight then
        return highlight
    end

    highlight = CreateFrame("frame", nil, UIParent, "BackdropTemplate")
    highlight:EnableMouse(false)

    return highlight
end

local glowStarters = {
    PIXEL = function(highlight)
        local pixel = SummonHelper.db.pixel
        local thickness = PixelUtil.GetNearestPixelSize(pixel.thickness, highlight:GetEffectiveScale(), 1)
        LCG.PixelGlow_Start(
            highlight, 
            {pixel.color.r, pixel.color.g, pixel.color.b, 1},
            pixel.lines, 1 / pixel.speed, 
            nil, 
            thickness
        )
    end,
    AUTOCAST = function(highlight)
        LCG.AutoCastGlow_Start(highlight)
    end,
}

local glowStoppers = {
    PIXEL = function(highlight)
        LCG.PixelGlow_Stop(highlight)
    end,
    AUTOCAST = function(highlight)
        LCG.AutoCastGlow_Stop(highlight)
    end,
}

local function stopGlow(highlight)
    if not highlight.glowing then
        return
    end

    glowStoppers[highlight.glowing](highlight)
    highlight.glowing = nil
end

function SummonHelper:StyleHighlight(highlight)
    local starter = glowStarters[self.db.style]

    stopGlow(highlight)

    if starter then
        highlight:SetBackdrop(nil)

        starter(highlight)
        highlight.glowing = self.db.style

        return
    end

    local border = self.db.border
    local edgeSize = PixelUtil.GetNearestPixelSize(border.thickness, highlight:GetEffectiveScale(), 1)

    highlight:SetBackdrop({edgeFile = [[Interface\Buttons\WHITE8x8]], edgeSize = edgeSize})
    highlight:SetBackdropBorderColor(border.color.r, border.color.g, border.color.b, border.color.a)
end

function SummonHelper:AnchorHighlight(highlight, frame)
    local spacing = self.db.spacing or 0

    highlight.anchor = frame

    highlight:SetParent(frame)
    highlight:ClearAllPoints()
    PixelUtil.SetPoint(highlight, "TOPLEFT", frame, "TOPLEFT", -spacing, spacing)
    PixelUtil.SetPoint(highlight, "BOTTOMRIGHT", frame, "BOTTOMRIGHT", spacing, -spacing)
    highlight:SetFrameLevel(frame:GetFrameLevel() + 8)
end

function SummonHelper:Highlight(unit)
    local guid = UnitGUID(unit)

    if not guid then
        return
    end

    local frame = LGF.GetUnitFrame(unit)

    if not frame then
        return
    end

    local highlight = self.active[guid] or acquireHighlight()
    self.active[guid] = highlight

    if highlight.timer then
        highlight.timer:Cancel()
    end

    self:AnchorHighlight(highlight, frame)
    self:StyleHighlight(highlight)

    highlight:Show()

    highlight.timer = C_Timer.NewTimer(self.db.duration, function()
        self:ReleaseHighlight(guid)
    end)
end

function SummonHelper:ReleaseHighlight(guid)
    local highlight = self.active[guid]

    if not highlight then
        return
    end

    self.active[guid] = nil

    if highlight.timer then
        highlight.timer:Cancel()
        highlight.timer = nil
    end

    stopGlow(highlight)
    highlight:Hide()
    highlight:SetParent(UIParent)
    highlight:ClearAllPoints()
    highlight.anchor = nil

    highlightPool[#highlightPool + 1] = highlight
end

function SummonHelper:ReleaseAllHighlights()
    for guid in pairs(self.active or {}) do
        self:ReleaseHighlight(guid)
    end
end

function SummonHelper:RestyleHighlights()
    for _, highlight in pairs(self.active or {}) do
        if highlight.anchor then
            self:AnchorHighlight(highlight, highlight.anchor)
        end

        self:StyleHighlight(highlight)
    end
end

function SummonHelper:RefreshHighlightAnchors()
    for guid, highlight in pairs(self.active or {}) do
        local unit = XerionUIFeatures:UnitTokenFromGUID(guid)
        local frame = unit and LGF.GetUnitFrame(unit)

        if not frame then
            self:ReleaseHighlight(guid)
        elseif frame ~= highlight.anchor then
            self:AnchorHighlight(highlight, frame)
            self:StyleHighlight(highlight)
        end
    end
end

function SummonHelper:ReleaseSummoned()
    if not (C_IncomingSummon and C_IncomingSummon.HasIncomingSummon) then
        return
    end

    for guid in pairs(self.active or {}) do
        local unit = XerionUIFeatures:UnitTokenFromGUID(guid)

        if unit and C_IncomingSummon.HasIncomingSummon(unit) then
            self:ReleaseHighlight(guid)
        end
    end
end

function SummonHelper:IsRitualReady()
    if XerionUIFeatures.playerClass ~= "WARLOCK" or not XerionUIFeatures:IsSpellKnown(ritualOfSummoning) then
        return false
    end

    local cdInfo = C_Spell.GetSpellCooldown(ritualOfSummoning)

    if not cdInfo then
        return false
    end

    return cdInfo.timeUntilEndOfStartRecovery == 0 or cdInfo.isOnGCD == true
end

function SummonHelper:MaybeShowStoneReminder()
    if not self.db.stoneReminder or not self.frame then
        return
    end

    local now = GetTime()

    if self.lastReminderAt and now - self.lastReminderAt < reminderThrottle then
        return
    end

    if not self:IsRitualReady() then
        return
    end

    self.lastReminderAt = now
    self.frame:ShowMessage()
end

function SummonHelper:GenerateFrame(name, parent)
    local frame = CreateFrame("frame", name, parent or UIParent)
    PixelUtil.SetPoint(frame, "CENTER", frame:GetParent() or UIParent, "CENTER", 0, 150)
    PixelUtil.SetSize(frame, 28, 28)

    frame.text = frame:CreateFontString(nil, "OVERLAY")
    frame.text:SetPoint("CENTER")
    frame.text:SetFont(LSM:Fetch("font", "GothamNarrowBlack"), 18, "OUTLINE")
    frame.text:SetJustifyH("CENTER")
    frame.text:Hide()

    frame.text.anim = frame.text:CreateAnimationGroup()
    frame.text.anim:SetScript("OnFinished", function()
        frame.text:Hide()
    end)

    frame.fade = frame.text.anim:CreateAnimation("Alpha")
    frame.fade:SetFromAlpha(1)
    frame.fade:SetToAlpha(0)
    frame.fade:SetDuration(1)
    frame.fade:SetStartDelay(20)

    function frame:ShowMessage()
        self.text:SetText(SummonHelper.db.messageText)
        self.text:SetAlpha(1)
        self.text:Show()

        -- The frame sizes itself from the text, so a text change has to restyle.
        self:UpdateStyles()

        self.text.anim:Stop()
        self.text.anim:Play()
    end

    function frame:HideMessage()
        self.text.anim:Stop()
        self.text:Hide()
    end

    function frame:ShowSample()
        self.text.anim:Stop()
        self.text:SetText(SummonHelper.db.messageText)
        self.text:SetAlpha(1)
        self.text:Show()
        self:UpdateStyles()
    end

    function frame:UpdateStyles()
        local font = SummonHelper.db.font

        if not E then
            self:ClearAllPoints()
            PixelUtil.SetPoint(self, SummonHelper.db.point.point, self:GetParent() or UIParent, SummonHelper.db.point.point, SummonHelper.db.point.x, SummonHelper.db.point.y)
        end

        self:SetFrameStrata(font.frameStrata or "BACKGROUND")
        self:SetFrameLevel(font.frameLevel or 1)

        self.text:SetJustifyH(font.justifyH or "CENTER")
        self.text:SetTextColor(SummonHelper.db.textColor.r, SummonHelper.db.textColor.g, SummonHelper.db.textColor.b, SummonHelper.db.textColor.a)

        if font.fontOutline ~= "OUTLINESLUG" then
            self.text:SetShadowColor(font.fontShadowColor.r, font.fontShadowColor.g, font.fontShadowColor.b, font.fontShadowColor.a)
            self.text:SetShadowOffset(font.fontShadowXOffset, font.fontShadowYOffset)
        else
            self.text:SetShadowColor(0, 0, 0, 0)
            self.text:SetShadowOffset(0, 0)
        end

        self.text:SetFont(LSM:Fetch("font", font.fontFamily), font.fontSize, font.fontOutline)
        self.fade:SetStartDelay(SummonHelper.db.duration)

        PixelUtil.SetSize(self, math.max(self.text:GetStringWidth(), 28), math.max(self.text:GetStringHeight(), 28))

        SummonHelper:RestyleHighlights()
    end

    return frame
end

local function OnEvent(self, event, ...)
    if chatEvents[event] then
        if XerionUIFeatures:IsChatLocked() then
            return
        end

        local message = ...
        local guid = select(12, ...)

        if not guid or not SummonHelper:MatchesPhrase(message) then
            return
        end

        local unit = XerionUIFeatures:UnitTokenFromGUID(guid)

        if not unit then
            return
        end

        SummonHelper:Highlight(unit)

        if guid ~= UnitGUID("player") then
            SummonHelper:MaybeShowStoneReminder()
        end

        return
    end

    if event == "PLAYER_REGEN_DISABLED" then
        SummonHelper:ReleaseAllHighlights()
        self:HideMessage()

        return
    end

    if event == "INCOMING_SUMMON_CHANGED" then
        SummonHelper:ReleaseSummoned()

        return
    end

    if event == "GROUP_ROSTER_UPDATE" then
        SummonHelper:RefreshHighlightAnchors()

        return
    end

    if XerionUIFeatures.testMode then
        SummonHelper:Highlight("player")
        self:ShowSample()

        return
    end

    SummonHelper:ReleaseAllHighlights()
    self:HideMessage()
end

function SummonHelper:EnsureFrame()
    if self.frame then
        return self.frame
    end

    local frame = self:GenerateFrame(addonName .. moduleName)
    self.frame = frame

    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("PLAYER_REGEN_DISABLED")
    frame:RegisterEvent("INCOMING_SUMMON_CHANGED")
    frame:RegisterEvent("GROUP_ROSTER_UPDATE")

    for event in pairs(chatEvents) do
        frame:RegisterEvent(event)
    end

    LGF.RegisterCallback(self, "GETFRAME_REFRESH", function()
        self:RefreshHighlightAnchors()
    end)

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

function SummonHelper:OnInitialize()
    local profile = XerionUIFeatures.db.profile
    profile[moduleName] = profile[moduleName] or self:GetDefaults()
    self.db = profile[moduleName]

    self.active = {}
end

function SummonHelper:RefreshConfig()
    local profile = XerionUIFeatures.db.profile
    profile[moduleName] = profile[moduleName] or self:GetDefaults()
    self.db = profile[moduleName]

    local defaults = self:GetDefaults()
    self.db.spacing = self.db.spacing or defaults.spacing
    self.db.border = self.db.border or defaults.border
    self.db.pixel = self.db.pixel or defaults.pixel

    self.phrases = nil

    if self.db.enabled then
        local frame = self:EnsureFrame()

        frame:UpdateStyles()
        frame:SetScript("OnEvent", OnEvent)

        OnEvent(frame)
    elseif self.frame then
        self.frame:SetScript("OnEvent", nil)
        self.frame:HideMessage()
        self:ReleaseAllHighlights()
    end
end

function SummonHelper:ApplyFontSettings(font)
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

function SummonHelper:OnEnable()
    self:RefreshConfig()
end

function SummonHelper:UpdateVisibility()
    if not self.db.enabled or not self.frame then
        return
    end

    OnEvent(self.frame)
end

function SummonHelper:ToggleTestMode()
    self:UpdateVisibility()
end

function SummonHelper:RegisterOptions(parentOptions)
    parentOptions.args[moduleName] = self:GetOptions(function()
        if self.frame then
            self.frame:UpdateStyles()
        end

        XerionUIFeatures:RefreshPreview(self)
    end)
end
