local addonName, XerionUIFeatures = ...
local moduleName = "HealerManaIndicator"

local LSM = XerionUIFeatures.LSM
local LEM = XerionUIFeatures.LEM
local E = XerionUIFeatures.E

local HealerManaIndicator = XerionUIFeatures:NewModule(moduleName)

local lineSpacing = 4

local function IsGroupUnit(unit)
    return unit == "player"
        or (unit ~= nil and (strmatch(unit, "^party%d+$") ~= nil or strmatch(unit, "^raid%d+$") ~= nil))
end

local function OnEvent(self, event, unit, powerType)
    if XerionUIFeatures.testMode then
        self:ClearTexts()
        self:UpdateManaText(1, "player", 69)
        self:UpdateManaText(2, "player", 50)
        self:UpdateStyles()

        return
    end

    -- power events fire for every unit in the world, so only refresh the text of
    -- the healer that actually changed and never touch anchors or fonts here
    if event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER" or event == "UNIT_DISPLAYPOWER" then
        if event ~= "UNIT_DISPLAYPOWER" and powerType ~= "MANA" then
            return
        end

        self:UpdateManaValue(unit)

        return
    end

    self:UpdateManaTexts()
    self:UpdateStyles()
end

function HealerManaIndicator:GenerateFrame(frameName, parent)
    local frame = CreateFrame("frame", frameName, parent or UIParent)
    PixelUtil.SetPoint(frame, "CENTER", frame:GetParent() or UIParent, "CENTER", 0, 50)
    PixelUtil.SetSize(frame, 150, 28)

    frame.texts = {}
    frame.healers = {}

    function frame:IsHealer(unit)
        return UnitExists(unit)
            and UnitIsConnected(unit)
            and (
                UnitGroupRolesAssigned(unit) == "HEALER"
                or UnitName(unit) == "Shambun"
            )
    end

    function frame:UpdateTextStyle(text)
        if not text then
            return
        end

        if not text:HasAnySecretAspect() then
            text:SetJustifyH(HealerManaIndicator.db.font.justifyH or "LEFT")
            if HealerManaIndicator.db.font.fontOutline ~= "OUTLINESLUG" then
                text:SetShadowColor(HealerManaIndicator.db.font.fontShadowColor.r, HealerManaIndicator.db.font.fontShadowColor.g, HealerManaIndicator.db.font.fontShadowColor.b, HealerManaIndicator.db.font.fontShadowColor.a)
                text:SetShadowOffset(HealerManaIndicator.db.font.fontShadowXOffset, HealerManaIndicator.db.font.fontShadowYOffset)
            else
                text:SetShadowColor(0, 0, 0, 0)
                text:SetShadowOffset(0, 0)
            end
            text:SetFont(LSM:Fetch("font", HealerManaIndicator.db.font.fontFamily), HealerManaIndicator.db.font.fontSize, HealerManaIndicator.db.font.fontOutline)
            text:SetTextColor(HealerManaIndicator.db.color.r, HealerManaIndicator.db.color.g, HealerManaIndicator.db.color.b, HealerManaIndicator.db.color.a)
        end
    end

    -- The stack starts at the edge it grows away from, so the lines always stay
    -- inside the frame: the movers (EllesmereUI, ElvUI, LibEditMode) and the config
    -- preview are all drawn from this frame's rect, and a stack hanging outside it
    -- puts the mover box somewhere the text isn't.
    function frame:AnchorText(index)
        local text = self.texts[index]

        if not text then
            return
        end

        local point = "LEFT"
        if HealerManaIndicator.db.font.justifyH == "CENTER" then
            point = ""
        elseif HealerManaIndicator.db.font.justifyH == "RIGHT" then
            point = "RIGHT"
        end

        text:ClearAllPoints()

        if index == 1 then
            local anchor = HealerManaIndicator.db.growUpwards and "BOTTOM" or "TOP"

            PixelUtil.SetPoint(text, anchor .. point, self, anchor .. point, 0, 0)
        elseif HealerManaIndicator.db.growUpwards then
            PixelUtil.SetPoint(text, "BOTTOM" .. point, self.texts[index - 1], "TOP" .. point, 0, lineSpacing)
        else
            PixelUtil.SetPoint(text, "TOP" .. point, self.texts[index - 1], "BOTTOM" .. point, 0, -lineSpacing)
        end
    end

    -- Sized from the lines that are actually showing, so the frame is the block of
    -- text and nothing else.
    function frame:UpdateSize()
        local lines, width, hasSecret = 0, 0, false

        for _, text in ipairs(self.texts) do
            if text:IsShown() then
                lines = lines + 1

                -- A live mana value can be a secret, and the string width is secret
                -- with it. HasAnySecretAspect misses text-content secrecy, so the
                -- measured value itself must be checked before any arithmetic, and
                -- some builds deny the measurement outright instead.
                if text:HasAnySecretAspect() then
                    hasSecret = true
                else
                    local measured, textWidth = pcall(text.GetStringWidth, text)
                    if measured and not issecretvalue(textWidth) and type(textWidth) == "number" then
                        width = math.max(width, textWidth)
                    else
                        hasSecret = true
                    end
                end
            end
        end

        if hasSecret or width <= 0 then
            width = self:GetWidth()
        end

        -- Nothing listed still leaves a line's worth of box, so the mover and the
        -- preview keep something to grab.
        local fontSize = HealerManaIndicator.db.font.fontSize
        local height = math.max(lines, 1) * fontSize + math.max(lines - 1, 0) * lineSpacing

        PixelUtil.SetSize(self, math.max(width, 1), height)
    end

    function frame:UpdateStyles()
        if not self:HasAnySecretAspect() then
            if not E then
                self:ClearAllPoints()
                PixelUtil.SetPoint(self, HealerManaIndicator.db.point.point, self:GetParent() or UIParent, HealerManaIndicator.db.point.point, HealerManaIndicator.db.point.x, HealerManaIndicator.db.point.y)
            end

            self:SetFrameStrata(HealerManaIndicator.db.font.frameStrata or "BACKGROUND")
            self:SetFrameLevel(HealerManaIndicator.db.font.frameLevel or 1)

            for index, text in ipairs(self.texts) do
                self:UpdateTextStyle(text)
                self:AnchorText(index)
            end

            self:UpdateSize()
        end
    end

    function frame:GetOrCreateText(index)
        if not self.texts[index] then
            local text = self:CreateFontString(nil, "OVERLAY")
            self:UpdateTextStyle(text)
            text:SetText(" ")
            text:Hide()

            self.texts[index] = text
            self:AnchorText(index)
        end

        return self.texts[index]
    end

    function frame:ClearTexts()
        wipe(self.healers)

        for _, text in ipairs(self.texts) do
            text:SetText(" ")
            text:Hide()
        end

        self:UpdateSize()
    end

    function frame:UpdateManaText(index, unit, overrideMana)
        local percent = overrideMana or UnitPowerPercent(unit, Enum.PowerType.Mana, true, CurveConstants.ScaleTo100)
        local name = UnitName(unit)
        local _, class = UnitClass(unit)
        local classColor = C_ClassColor.GetClassColor(class)
        local nameText = classColor:WrapTextInColorCode(name)

        local text = self:GetOrCreateText(index)
        text:SetText(string.format("%d%% - %s", percent, nameText))
        text:Show()

        self:UpdateSize()
    end

    function frame:IsActive()
        if XerionUIFeatures:InRaid() then
            return HealerManaIndicator.db.enableInRaids
        elseif XerionUIFeatures:InDungeon() then
            return HealerManaIndicator.db.enableInDungeons
        end

        return false
    end

    function frame:UpdateManaValue(unit)
        if not IsGroupUnit(unit) or #self.healers == 0 then
            return
        end

        for index, healer in ipairs(self.healers) do
            if UnitIsUnit(unit, healer) then
                self:UpdateManaText(index, healer)

                return
            end
        end
    end

    function frame:UpdateManaTexts()
        wipe(self.healers)

        if self:IsActive() then
            for _, unit in ipairs(XerionUIFeatures:GetGroupUnits()) do
                if self:IsHealer(unit) then
                    self.healers[#self.healers + 1] = unit
                end
            end
        end

        for index, unit in ipairs(self.healers) do
            self:UpdateManaText(index, unit)
        end

        for index = #self.healers + 1, #self.texts do
            local text = self.texts[index]
            text:SetText(" ")
            text:Hide()
        end

        self:UpdateSize()
    end

    return frame
end

function HealerManaIndicator:EnsureFrame()
    if self.frame then
        return self.frame
    end

    local frame = self:GenerateFrame(addonName .. moduleName)
    self.frame = frame

    frame:RegisterEvent("GROUP_ROSTER_UPDATE")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("UNIT_POWER_UPDATE")
    frame:RegisterEvent("UNIT_DISPLAYPOWER")
    frame:RegisterEvent("UNIT_MAXPOWER")

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

function HealerManaIndicator:OnInitialize()
    local profile = XerionUIFeatures.db.profile
    profile.HealerManaIndicator = profile.HealerManaIndicator or self:GetDefaults()
    self.db = profile.HealerManaIndicator
end

function HealerManaIndicator:RefreshConfig()
    local profile = XerionUIFeatures.db.profile
    profile.HealerManaIndicator = profile.HealerManaIndicator or self:GetDefaults()
    self.db = profile.HealerManaIndicator

    if self.db.enabled then
        local frame = self:EnsureFrame()

        frame:ClearTexts()
        frame:UpdateStyles()
        frame:SetScript("OnEvent", OnEvent)
        OnEvent(frame)
    elseif self.frame then
        self.frame:SetScript("OnEvent", nil)
        self.frame:SetScript("OnUpdate", nil)
        self.frame:ClearTexts()
    end
end

function HealerManaIndicator:ApplyFontSettings(font)
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

function HealerManaIndicator:OnEnable()
    self:RefreshConfig()
end

function HealerManaIndicator:ToggleTestMode()
    if not self.db.enabled or not self.frame then
        return
    end

    OnEvent(self.frame)
end


function HealerManaIndicator:RegisterOptions(parentOptions)
    parentOptions.args[moduleName] = self:GetOptions(function()
        if self.frame then
            OnEvent(self.frame)
        end

        XerionUIFeatures:RefreshPreview(self)
    end)
end
