local addonName, XerionUIFeatures = ...
local moduleName = "PetMissingIndicator"

local LSM = XerionUIFeatures.LSM
local LEM = XerionUIFeatures.LEM
local E = XerionUIFeatures.E

local PetMissingIndicator = XerionUIFeatures:NewModule(moduleName)

local function OnEvent(self, event, ...)
    local petSpec = XerionUIFeatures:IsPetSpec()
    local conditionsWherePetIsntShown = IsMounted() or UnitInVehicle("player") or UnitIsDeadOrGhost("player")

    if XerionUIFeatures.testMode then
        self.text:Show()
        return
    end

    if not petSpec or conditionsWherePetIsntShown then
        self.text:Hide()
    else
        if UnitExists("pet") then
            self.text:Hide()
        else
            self.text:Show()
        end
    end
end

function PetMissingIndicator:GenerateFrame(name, parent)
    local frame = CreateFrame("frame", name, parent or UIParent)
    PixelUtil.SetPoint(frame, "CENTER", frame:GetParent() or UIParent, "CENTER", 0, 300)
    PixelUtil.SetSize(frame, 28, 28)

    frame.text = frame:CreateFontString(nil, "OVERLAY")
    frame.text:SetPoint("CENTER")
    frame.text:SetFont(LSM:Fetch("font", "GothamNarrowBlack"), 28, "OUTLINE")
    frame.text:SetText("**Pet missing!**")
    frame.text:SetTextColor(1, 1, 1)
    frame.text:SetJustifyH("CENTER")
    frame.text:Hide()

    function frame:IsPetPassive()
        if not UnitExists("pet") then
            return false
        end

        if not UnitAffectingCombat("player") then
            return false
        end

        local petTarget = UnitExists("pettarget")

        if not petTarget then
            return true
        end

        return false
    end

    function frame:UpdateStyles()
        if not E then
            self:ClearAllPoints()
            PixelUtil.SetPoint(self, PetMissingIndicator.db.point.point, self:GetParent() or UIParent, PetMissingIndicator.db.point.point, PetMissingIndicator.db.point.x, PetMissingIndicator.db.point.y)
        end

        self:SetFrameStrata(PetMissingIndicator.db.font.frameStrata or "BACKGROUND")
        self:SetFrameLevel(PetMissingIndicator.db.font.frameLevel or 1)
        self.text:ClearAllPoints()
        self.text:SetPoint(PetMissingIndicator.db.font.justifyH or "CENTER")
        self.text:SetJustifyH(PetMissingIndicator.db.font.justifyH or "CENTER")
        self.text:SetText(PetMissingIndicator.db.displayText)
        self.text:SetTextColor(PetMissingIndicator.db.color.r, PetMissingIndicator.db.color.g, PetMissingIndicator.db.color.b, PetMissingIndicator.db.color.a)
        if PetMissingIndicator.db.font.fontOutline ~= "OUTLINESLUG" then
            self.text:SetShadowColor(PetMissingIndicator.db.font.fontShadowColor.r, PetMissingIndicator.db.font.fontShadowColor.g, PetMissingIndicator.db.font.fontShadowColor.b, PetMissingIndicator.db.font.fontShadowColor.a)
            self.text:SetShadowOffset(PetMissingIndicator.db.font.fontShadowXOffset, PetMissingIndicator.db.font.fontShadowYOffset)
        else
            self.text:SetShadowColor(0, 0, 0, 0)
            self.text:SetShadowOffset(0, 0)
        end
        self.text:SetFont(LSM:Fetch("font", PetMissingIndicator.db.font.fontFamily), PetMissingIndicator.db.font.fontSize, PetMissingIndicator.db.font.fontOutline)
        PixelUtil.SetSize(self, self.text:GetStringWidth(), self.text:GetStringHeight())
    end

    return frame
end

function PetMissingIndicator:EnsureFrame()
    if self.frame then
        return self.frame
    end

    local frame = self:GenerateFrame(addonName .. moduleName)
    self.frame = frame

    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    frame:RegisterEvent("PLAYER_TALENT_UPDATE")
    frame:RegisterEvent("TRAIT_CONFIG_UPDATED")
    frame:RegisterEvent("UNIT_PET")
    frame:RegisterEvent("PET_BAR_UPDATE")
    frame:RegisterEvent("PET_BAR_UPDATE_COOLDOWN")
    frame:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
    frame:RegisterUnitEvent("UNIT_ENTERED_VEHICLE", "player")
    frame:RegisterUnitEvent("UNIT_EXITED_VEHICLE", "player")
    frame:RegisterEvent("PLAYER_DEAD")
    frame:RegisterEvent("PLAYER_ALIVE")

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

function PetMissingIndicator:OnInitialize()
    local profile = XerionUIFeatures.db.profile
    profile.PetMissingIndicator = profile.PetMissingIndicator or self:GetDefaults()
    self.db = profile.PetMissingIndicator
end

function PetMissingIndicator:RefreshConfig()
    local profile = XerionUIFeatures.db.profile
    profile.PetMissingIndicator = profile.PetMissingIndicator or self:GetDefaults()
    self.db = profile.PetMissingIndicator

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

function PetMissingIndicator:ApplyFontSettings(font)
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

function PetMissingIndicator:OnEnable()
    self:RefreshConfig()
end

function PetMissingIndicator:ToggleTestMode()
    if not self.db.enabled or not self.frame then
        return
    end

    OnEvent(self.frame)
end

function PetMissingIndicator:RegisterOptions(parentOptions)
    parentOptions.args[moduleName] = self:GetOptions(function()
        if self.frame then
            self.frame:UpdateStyles()
        end

        XerionUIFeatures:RefreshPreview(self)
    end)
end
