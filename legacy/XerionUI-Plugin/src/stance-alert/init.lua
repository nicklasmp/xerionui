local addonName, XerionUIFeatures = ...
local moduleName = "StanceAlert"

local LSM = XerionUIFeatures.LSM
local LEM = XerionUIFeatures.LEM
local E = XerionUIFeatures.E

local StanceAlert = XerionUIFeatures:NewModule(moduleName)

local defensiveStances = {[71] = true, [386208] = true}

local catFormId = 1
local bearFormId = 5
local moonkinFormId = 31

StanceAlert.DruidForms = {
    [102] = {form = moonkinFormId, spell = 24858},
    [103] = {form = catFormId, spell = 768},
    [104] = {form = bearFormId, spell = 5487},
}


StanceAlert.StanceCheckers = {
    WARRIOR = function()
        if 1 >= GetNumShapeshiftForms() then
            return false
        end

        local active = XerionUIFeatures:GetActiveStanceSpell()

        return active ~= nil and defensiveStances[active] == true
    end,

    DRUID = function(specID)
        local expected = StanceAlert.DruidForms[specID]

        if not expected then
            return false
        end

        if not UnitAffectingCombat("player") then
            return false
        end

        if expected.spell and not XerionUIFeatures:IsSpellKnown(expected.spell) then
            return false
        end

        return GetShapeshiftFormID() ~= expected.form
    end,
}

function StanceAlert:IsWrongStance()
    local checker = StanceAlert.StanceCheckers[XerionUIFeatures.playerClass]

    if not checker then
        return false
    end

    if IsMounted() or UnitInVehicle("player") or UnitIsDeadOrGhost("player") then
        return false
    end

    local specId = select(1, GetSpecializationInfo(GetSpecialization()))

    return checker(specId)
end

local function OnEvent(self)
    if XerionUIFeatures.testMode then
        self.text:Show()

        return
    end

    if StanceAlert:IsWrongStance() then
        self.text:Show()
    else
        self.text:Hide()
    end
end

function StanceAlert:GenerateFrame(name, parent)
    local frame = CreateFrame("frame", name, parent or UIParent)
    PixelUtil.SetPoint(frame, "CENTER", frame:GetParent() or UIParent, "CENTER", 0, 50)
    PixelUtil.SetSize(frame, 28, 28)

    frame.text = frame:CreateFontString(nil, "OVERLAY")
    frame.text:SetPoint("CENTER")
    frame.text:SetFont(LSM:Fetch("font", "GothamNarrowBlack"), 14, "OUTLINE")
    frame.text:SetTextColor(1, 1, 1)
    frame.text:SetJustifyH("CENTER")
    frame.text:Hide()

    function frame:UpdateStyles()
        if not E then
            self:ClearAllPoints()
            PixelUtil.SetPoint(self, StanceAlert.db.point.point, self:GetParent() or UIParent, StanceAlert.db.point.point, StanceAlert.db.point.x, StanceAlert.db.point.y)
        end

        self:SetFrameStrata(StanceAlert.db.font.frameStrata or "BACKGROUND")
        self:SetFrameLevel(StanceAlert.db.font.frameLevel or 1)
        self.text:ClearAllPoints()
        self.text:SetPoint(StanceAlert.db.font.justifyH or "CENTER")
        self.text:SetJustifyH(StanceAlert.db.font.justifyH or "CENTER")
        self.text:SetText(StanceAlert.db.displayText)
        self.text:SetTextColor(StanceAlert.db.color.r, StanceAlert.db.color.g, StanceAlert.db.color.b, StanceAlert.db.color.a)

        if StanceAlert.db.font.fontOutline ~= "OUTLINESLUG" then
            self.text:SetShadowColor(StanceAlert.db.font.fontShadowColor.r, StanceAlert.db.font.fontShadowColor.g, StanceAlert.db.font.fontShadowColor.b, StanceAlert.db.font.fontShadowColor.a)
            self.text:SetShadowOffset(StanceAlert.db.font.fontShadowXOffset, StanceAlert.db.font.fontShadowYOffset)
        else
            self.text:SetShadowColor(0, 0, 0, 0)
            self.text:SetShadowOffset(0, 0)
        end
        self.text:SetFont(LSM:Fetch("font", StanceAlert.db.font.fontFamily), StanceAlert.db.font.fontSize, StanceAlert.db.font.fontOutline)

        PixelUtil.SetSize(self, self.text:GetStringWidth(), self.text:GetStringHeight())
    end

    return frame
end

function StanceAlert:EnsureFrame()
    if self.frame then
        return self.frame
    end

    local frame = self:GenerateFrame(addonName .. moduleName)
    self.frame = frame

    if StanceAlert.StanceCheckers[XerionUIFeatures.playerClass] then
        frame:RegisterEvent("PLAYER_ENTERING_WORLD")
        frame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
        frame:RegisterEvent("PLAYER_TALENT_UPDATE")
        frame:RegisterEvent("TRAIT_CONFIG_UPDATED")
        frame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
        frame:RegisterEvent("UPDATE_SHAPESHIFT_FORMS")
        frame:RegisterEvent("PLAYER_REGEN_ENABLED")
        frame:RegisterEvent("PLAYER_REGEN_DISABLED")
        frame:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
        frame:RegisterUnitEvent("UNIT_ENTERED_VEHICLE", "player")
        frame:RegisterUnitEvent("UNIT_EXITED_VEHICLE", "player")
    end

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

function StanceAlert:OnInitialize()
    local profile = XerionUIFeatures.db.profile
    profile.StanceAlert = profile.StanceAlert or self:GetDefaults()
    self.db = profile.StanceAlert
end

function StanceAlert:RefreshConfig()
    local profile = XerionUIFeatures.db.profile
    profile.StanceAlert = profile.StanceAlert or self:GetDefaults()
    self.db = profile.StanceAlert

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

function StanceAlert:ApplyFontSettings(font)
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

function StanceAlert:OnEnable()
    self:RefreshConfig()
end

function StanceAlert:ToggleTestMode()
    if not self.db.enabled or not self.frame then
        return
    end

    OnEvent(self.frame)
end

function StanceAlert:RegisterOptions(parentOptions)
    parentOptions.args[moduleName] = self:GetOptions(function()
        if self.frame then
            self.frame:UpdateStyles()
        end

        XerionUIFeatures:RefreshPreview(self)
    end)
end
