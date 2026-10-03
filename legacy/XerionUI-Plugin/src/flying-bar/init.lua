local addonName, XerionUIFeatures = ...
local LEM = XerionUIFeatures.LEM
local LSM = XerionUIFeatures.LSM
local E = XerionUIFeatures.E
local moduleName = "FlyingBar"

local FlyingBar = XerionUIFeatures:NewModule(moduleName)
FlyingBar.vigorSpellId = 372610
FlyingBar.secondWindSpellId = 425782
FlyingBar.whirlingSurgeSpellId = 361584

function FlyingBar:CreateTextureBorder(frame)
    frame:SetClipsChildren(true)
    local border = frame:CreateTexture(nil, "OVERLAY")
    PixelUtil.SetWidth(border, 1)
    border:SetPoint('TOP', frame)
    border:SetPoint('BOTTOM', frame)
    if frame:GetStatusBarTexture() then
        PixelUtil.SetPoint(border, 'RIGHT', frame:GetStatusBarTexture(), 'RIGHT', 0, 0)
    end
    border:SetColorTexture(0, 0, 0, 1)

    function border:UpdatePosition()
        border:ClearAllPoints()
        border:SetPoint('TOP', frame)
        border:SetPoint('BOTTOM', frame)
        PixelUtil.SetPoint(border, 'RIGHT', frame:GetStatusBarTexture(), 'RIGHT', 0, 0)
    end

    return border
end

local function OnUpdate(self)
    local isGliding, _, forwardSpeed = C_PlayerInfo.GetGlidingInfo()

    if isGliding then
        self.speed:SetValue(forwardSpeed / BASE_MOVEMENT_SPEED * 100 + 0.5, Enum.StatusBarInterpolation.ExponentialEaseOut)
    else
        self.speed:SetValue(0, Enum.StatusBarInterpolation.ExponentialEaseOut)
    end
end

function OnEvent(self)
    local canGlide = XerionUIFeatures:CanGlide()
    self:SetAlphaFromBoolean(canGlide, 1, 0)

    if canGlide then
        self:SetScript("OnUpdate", OnUpdate)
    else
        self:SetScript("OnUpdate", nil)
        return
    end

    local vigorCharges = C_Spell.GetSpellCharges(FlyingBar.vigorSpellId)
    local secondWindCharges = C_Spell.GetSpellCharges(FlyingBar.secondWindSpellId)

    local vigorDuration = C_Spell.GetSpellChargeDuration(FlyingBar.vigorSpellId)
    local secondWindDuration = C_Spell.GetSpellChargeDuration(FlyingBar.secondWindSpellId)

    local whilringSurgeCd = C_Spell.GetSpellCooldown(FlyingBar.whirlingSurgeSpellId)

    if whilringSurgeCd.isEnabled and whilringSurgeCd.duration and whilringSurgeCd.duration then
        self.surge.cd:SetCooldown(whilringSurgeCd.startTime, whilringSurgeCd.duration)
    end

    for i, bar in ipairs(self.vigor) do
        if vigorCharges.currentCharges >= i then
            bar:SetMinMaxValues(0, 1)
            bar:SetValue(1, Enum.StatusBarInterpolation.ExponentialEaseOut)
        elseif vigorDuration and i == vigorCharges.currentCharges + 1 then
            bar:SetTimerDuration(vigorDuration, Enum.StatusBarInterpolation.ExponentialEaseOut)
        else
            bar:SetMinMaxValues(0, 1)
            bar:SetValue(0, Enum.StatusBarInterpolation.ExponentialEaseOut)
        end
	end

    for i, bar in ipairs(self.secondWind) do
        if secondWindCharges.currentCharges >= i then
            bar:SetMinMaxValues(0, 1)
            bar:SetValue(1, Enum.StatusBarInterpolation.ExponentialEaseOut)
        elseif secondWindDuration and i == secondWindCharges.currentCharges + 1 then
            bar:SetTimerDuration(secondWindDuration, Enum.StatusBarInterpolation.ExponentialEaseOut)
        else
            bar:SetMinMaxValues(0, 1)
            bar:SetValue(0, Enum.StatusBarInterpolation.ExponentialEaseOut)
        end
	end
end


function FlyingBar:GenerateFrame(name, parent)
    local frame = CreateFrame("frame", name, parent or UIParent)
    frame:SetAlpha(0)
    frame:SetPoint("CENTER")

    frame.surge = CreateFrame("frame", "$parent_WhirlingSurge", frame)
    frame.surge:SetPoint("TOPLEFT")
    frame.surge:SetPoint("BOTTOMLEFT")

    frame.surge.icon = frame.surge:CreateTexture(nil, 'ARTWORK')
    frame.surge.icon:SetAllPoints()
    frame.surge.icon:SetTexture(C_Spell.GetSpellTexture(FlyingBar.whirlingSurgeSpellId))
    frame.surge.icon:SetTexCoord(.08, .92, .08, .92)

    frame.surge.cd = CreateFrame('Cooldown', nil, frame.surge, 'CooldownFrameTemplate')
    frame.surge.cd:SetAllPoints()
    frame.surge.cd:SetHideCountdownNumbers(true)

    frame.surge.border = XerionUIFeatures:CreateBorder(frame.surge)

    frame.vigor = CreateFrame("StatusBar", "$parent_Vigor", frame)
    PixelUtil.SetPoint(frame.vigor, "TOPLEFT", frame.surge, "TOPRIGHT", 1, 0)
    frame.vigor:SetPoint("TOPRIGHT")

    for index = 1, C_Spell.GetSpellCharges(FlyingBar.vigorSpellId).maxCharges do
        local bar = CreateFrame("StatusBar", "$parent_" .. index, frame.vigor)
        bar:SetMinMaxValues(0, 100)
        bar:SetPoint("TOP")
        bar:SetPoint("BOTTOM")
        bar.border = XerionUIFeatures:CreateBorder(bar)
        bar.bg = XerionUIFeatures:CreateBackground(bar)
        bar.textureBorder = FlyingBar:CreateTextureBorder(bar)

        if index == 1 then
            PixelUtil.SetPoint(bar, 'LEFT', frame.vigor, 'LEFT', 0, 0)
        else
            bar:SetPoint('LEFT', frame.vigor[index - 1], 'RIGHT', 1, 0)
        end

        frame.vigor[index] = bar
    end

    frame.speed = CreateFrame("StatusBar", "$parent_Speed", frame)
    PixelUtil.SetPoint(frame.speed, "TOPLEFT", frame.vigor, "BOTTOMLEFT", 0, -1)
    PixelUtil.SetPoint(frame.speed, "TOPRIGHT", frame.vigor, "BOTTOMRIGHT", 0, -1)
    frame.speed:SetMinMaxValues(0, 1440)
    frame.speed.border = XerionUIFeatures:CreateBorder(frame.speed)
    frame.speed.bg = XerionUIFeatures:CreateBackground(frame.speed)
    frame.speed.textureBorder = FlyingBar:CreateTextureBorder(frame.speed)
    frame.speed.tick = frame.speed:CreateTexture(nil, "OVERLAY")
    PixelUtil.SetWidth(frame.speed.tick, 1)
    frame.speed.tick:SetColorTexture(0, 0, 0, 1)
    frame.speed.tick:SetSnapToPixelGrid(true)
    frame.speed.tick:SetTexelSnappingBias(0)

    function frame.speed.tick:UpdatePosition()
        local owner = self:GetParent();
        local width = owner:GetWidth();
        local pixelPerPower = width / select(2, owner:GetMinMaxValues())

        self:ClearAllPoints()
        self:SetPoint('TOP', owner)
        self:SetPoint('BOTTOM', owner)
        PixelUtil.SetPoint(self, 'LEFT', owner, 'LEFT', pixelPerPower * (select(2, owner:GetMinMaxValues()) / 2) - math.ceil(self:GetWidth() / 2), 0)
    end

    frame.secondWind = CreateFrame("StatusBar", "$parent_SecondWind", frame)
    PixelUtil.SetPoint(frame.secondWind, "TOPLEFT", frame.speed, "BOTTOMLEFT", 0, -1)
    PixelUtil.SetPoint(frame.secondWind, "TOPRIGHT", frame.speed, "BOTTOMRIGHT", 0, -1)

    for index = 1, C_Spell.GetSpellCharges(FlyingBar.secondWindSpellId).maxCharges do
        local bar = CreateFrame("StatusBar", "$parent_" .. index, frame.secondWind)
        bar:SetMinMaxValues(0, 100)
        bar:SetPoint("TOP")
        bar:SetPoint("BOTTOM")
        bar.border = XerionUIFeatures:CreateBorder(bar)
        bar.bg = XerionUIFeatures:CreateBackground(bar)
        bar.textureBorder = FlyingBar:CreateTextureBorder(bar)

        if index == 1 then
            PixelUtil.SetPoint(bar, 'LEFT', frame.secondWind, 'LEFT', 0, 0)
        else
            bar:SetPoint('LEFT', frame.secondWind[index - 1], 'RIGHT', 1, 0)
        end

        frame.secondWind[index] = bar
    end

    function frame:UpdateStyles()
        if not E then
            self:ClearAllPoints()
            PixelUtil.SetPoint(self, FlyingBar.db.point.point, self:GetParent() or UIParent, FlyingBar.db.point.point, FlyingBar.db.point.x, FlyingBar.db.point.y)
        end

        PixelUtil.SetSize(
            self,
            FlyingBar.db.width,
            FlyingBar.db.vigor.height + FlyingBar.db.speed.height + FlyingBar.db.secondWind.height + 2
        )
        self:SetFrameStrata(FlyingBar.db.frameStrata or "BACKGROUND")
        self:SetFrameLevel(FlyingBar.db.frameLevel or 1)

        self.surge:SetWidth(FlyingBar.db.vigor.height + FlyingBar.db.speed.height + FlyingBar.db.secondWind.height + 2)
        self.secondWind:SetHeight(FlyingBar.db.secondWind.height)
        self.speed:SetHeight(FlyingBar.db.speed.height)
        self.vigor:SetHeight(FlyingBar.db.vigor.height)

        self.speed:SetStatusBarTexture(LSM:Fetch("statusbar", FlyingBar.db.speed.statusbarTexture))
        self.speed:SetStatusBarColor(FlyingBar.db.speed.color.r, FlyingBar.db.speed.color.g, FlyingBar.db.speed.color.b, FlyingBar.db.speed.color.a)
        self.speed.tick:UpdatePosition()
        self.speed.textureBorder:UpdatePosition()

        local frameWidth = self.speed:GetWidth()

        local pixel = PixelUtil.GetNearestPixelSize(1, self:GetEffectiveScale(), 1)

        local vigorUsable = frameWidth - pixel * (#self.vigor - 1)
        local vigorWidth = math.floor(vigorUsable / #self.vigor / pixel) * pixel
        local vigorSpare = math.floor((vigorUsable - vigorWidth * #self.vigor) / pixel + 0.5)

        for index, bar in ipairs(self.vigor) do
            bar:SetWidth(vigorWidth + (index <= vigorSpare and pixel or 0))

            if index > 1 then
                bar:SetPoint('LEFT', self.vigor[index - 1], 'RIGHT', pixel, 0)
            end

            bar:SetStatusBarTexture(LSM:Fetch("statusbar", FlyingBar.db.vigor.statusbarTexture))
            bar:SetStatusBarColor(FlyingBar.db.vigor.color.r, FlyingBar.db.vigor.color.g, FlyingBar.db.vigor.color.b, FlyingBar.db.vigor.color.a)
            bar.textureBorder:UpdatePosition()
        end

        local secondWindUsable = frameWidth - pixel * (#self.secondWind - 1)
        local secondWindWidth = math.floor(secondWindUsable / #self.secondWind / pixel) * pixel
        local secondWindSpare = math.floor((secondWindUsable - secondWindWidth * #self.secondWind) / pixel + 0.5)

        for index, bar in ipairs(self.secondWind) do
            bar:SetWidth(secondWindWidth + (index <= secondWindSpare and pixel or 0))

            if index > 1 then
                bar:SetPoint('LEFT', self.secondWind[index - 1], 'RIGHT', pixel, 0)
            end

            bar:SetStatusBarTexture(LSM:Fetch("statusbar", FlyingBar.db.secondWind.statusbarTexture))
            bar:SetStatusBarColor(FlyingBar.db.secondWind.color.r, FlyingBar.db.secondWind.color.g, FlyingBar.db.secondWind.color.b, FlyingBar.db.secondWind.color.a)
            bar.textureBorder:UpdatePosition()
        end
    end

    return frame
end

function FlyingBar:EnsureFrame()
    if self.frame then
        return self.frame
    end

    local frame = self:GenerateFrame(addonName .. moduleName)
    self.frame = frame

    frame:RegisterEvent('SPELL_UPDATE_COOLDOWN')
    frame:RegisterEvent('SPELL_UPDATE_CHARGES')
    frame:RegisterEvent('PLAYER_ENTERING_WORLD')
    frame:RegisterEvent("PLAYER_CAN_GLIDE_CHANGED")
    frame:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
    frame:RegisterUnitEvent("UNIT_ENTERED_VEHICLE", "player")
    frame:RegisterUnitEvent("UNIT_EXITED_VEHICLE", "player")

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

function FlyingBar:OnInitialize()
    local profile = XerionUIFeatures.db.profile
    profile[moduleName] = profile[moduleName] or self:GetDefaults()
    self.db = profile[moduleName]

    if not self.db.point then
        self.db.point = self:GetDefaults().point
    end
end

function FlyingBar:RefreshConfig()
    local profile = XerionUIFeatures.db.profile
    profile[moduleName] = profile[moduleName] or self:GetDefaults()
    self.db = profile[moduleName]

    if self.db.enabled then
        local frame = self:EnsureFrame()

        frame:Show()
        frame:UpdateStyles()
        frame:SetScript("OnEvent", OnEvent)
        OnEvent(frame)
    elseif self.frame then
        self.frame:SetScript("OnEvent", nil)
        self.frame:SetScript("OnUpdate", nil)
        self.frame:Hide()
    end
end

function FlyingBar:OnEnable()
    self:RefreshConfig()
end

function FlyingBar:RegisterOptions(parentOptions)
    parentOptions.args[moduleName] = self:GetOptions(function()
        if self.frame then
            self.frame:UpdateStyles()
        end

        XerionUIFeatures:RefreshPreview(self)
    end)
end
