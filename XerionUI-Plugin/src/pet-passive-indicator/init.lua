local addonName, XerionUIFeatures = ...
local moduleName = "PetPassiveIndicator"

local LSM = XerionUIFeatures.LSM
local LEM = XerionUIFeatures.LEM
local E = XerionUIFeatures.E

local PetPassiveIndicator = XerionUIFeatures:NewModule(moduleName)

local function OnEvent(self, event, ...)
    if XerionUIFeatures.testMode then
        self.text:Show()
        return
    end

    if self:IsPetPassive() then
        self.text:Show()
    else
        self.text:Hide()
    end
end

function PetPassiveIndicator:GenerateFrame(frameName, parent)
    local frame = CreateFrame("frame", frameName, parent or UIParent)
    PixelUtil.SetPoint(frame, "CENTER", frame:GetParent() or UIParent, "CENTER", 0, 300)
    PixelUtil.SetSize(frame, 28, 28)

    frame.text = frame:CreateFontString(nil, "OVERLAY")
    frame.text:SetPoint("CENTER")
    frame.text:SetFont(LSM:Fetch("font", "GothamNarrowBlack"), 28, "OUTLINE")
    frame.text:SetText("**Pet passive!**")
    frame.text:SetTextColor(1, 1, 1)
    frame.text:SetJustifyH("CENTER")
    frame.text:Hide()

    function frame:IsPetPassive()
        -- Pet bar might be active while mounted
        if not UnitExists("pet") or not PetHasActionBar() or IsMounted() then
            return false
        end

        for slot = 1, NUM_PET_ACTION_SLOTS or 10 do
            local name, _, token, active = GetPetActionInfo(slot)

            if name == "PET_MODE_PASSIVE" and token and active then
                return true
            end
        end

        return false
    end

    function frame:UpdateStyles()
        if not E then
            self:ClearAllPoints()
            PixelUtil.SetPoint(self, PetPassiveIndicator.db.point.point, self:GetParent() or UIParent, PetPassiveIndicator.db.point.point, PetPassiveIndicator.db.point.x, PetPassiveIndicator.db.point.y)
        end

        self:SetFrameStrata(PetPassiveIndicator.db.font.frameStrata or "BACKGROUND")
        self:SetFrameLevel(PetPassiveIndicator.db.font.frameLevel or 1)
        self.text:ClearAllPoints()
        self.text:SetPoint(PetPassiveIndicator.db.font.justifyH or "CENTER")
        self.text:SetJustifyH(PetPassiveIndicator.db.font.justifyH or "CENTER")
        self.text:SetText(PetPassiveIndicator.db.displayText)
        self.text:SetTextColor(PetPassiveIndicator.db.color.r, PetPassiveIndicator.db.color.g, PetPassiveIndicator.db.color.b, PetPassiveIndicator.db.color.a)
        if PetPassiveIndicator.db.font.fontOutline ~= "OUTLINESLUG" then
            self.text:SetShadowColor(PetPassiveIndicator.db.font.fontShadowColor.r, PetPassiveIndicator.db.font.fontShadowColor.g, PetPassiveIndicator.db.font.fontShadowColor.b, PetPassiveIndicator.db.font.fontShadowColor.a)
            self.text:SetShadowOffset(PetPassiveIndicator.db.font.fontShadowXOffset, PetPassiveIndicator.db.font.fontShadowYOffset)
        else
            self.text:SetShadowColor(0, 0, 0, 0)
            self.text:SetShadowOffset(0, 0)
        end
        self.text:SetFont(LSM:Fetch("font", PetPassiveIndicator.db.font.fontFamily), PetPassiveIndicator.db.font.fontSize, PetPassiveIndicator.db.font.fontOutline)

        PixelUtil.SetSize(self, self.text:GetStringWidth(), self.text:GetStringHeight())
    end

    return frame
end

function PetPassiveIndicator:EnsureFrame()
    if self.frame then
        return self.frame
    end

    local frame = self:GenerateFrame(addonName .. moduleName)
    self.frame = frame

    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("UNIT_PET")
    frame:RegisterEvent("PLAYER_DEAD")
    frame:RegisterEvent("PLAYER_ALIVE")
    frame:RegisterEvent("PET_BAR_UPDATE")
    frame:RegisterEvent("PET_BAR_UPDATE_COOLDOWN")
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

function PetPassiveIndicator:OnInitialize()
    local profile = XerionUIFeatures.db.profile
    profile.PetPassiveIndicator = profile.PetPassiveIndicator or self:GetDefaults()
    self.db = profile.PetPassiveIndicator
end

function PetPassiveIndicator:RefreshConfig()
    local profile = XerionUIFeatures.db.profile
    profile.PetPassiveIndicator = profile.PetPassiveIndicator or self:GetDefaults()
    self.db = profile.PetPassiveIndicator

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

function PetPassiveIndicator:ApplyFontSettings(font)
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

function PetPassiveIndicator:OnEnable()
    self:RefreshConfig()
end

function PetPassiveIndicator:ToggleTestMode()
    if not self.db.enabled or not self.frame then
        return
    end

    OnEvent(self.frame)
end

function PetPassiveIndicator:RegisterOptions(parentOptions)
    parentOptions.args[moduleName] = self:GetOptions(function()
        if self.frame then
            self.frame:UpdateStyles()
        end

        XerionUIFeatures:RefreshPreview(self)
    end)
end
