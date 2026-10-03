local addonName, XerionUIFeatures = ...
local moduleName = "FriendlyNameplates"
local LSM = XerionUIFeatures.LSM

local FriendlyNameplates = XerionUIFeatures:NewModule(moduleName)

-- Let the UI frameworks handle this
if XerionUIFeatures.EUI or XerionUIFeatures.E then
    return
end

local function ApplyFont()
    local font = LSM:Fetch("font", FriendlyNameplates.db.font.fontFamily)

    _G.SystemFont_NamePlate:SetFont(font, FriendlyNameplates.db.font.fontSize, FriendlyNameplates.db.font.fontOutline)
    _G.SystemFont_NamePlate_Outlined:SetFont(font, FriendlyNameplates.db.font.fontSize, FriendlyNameplates.db.font.fontOutline)
end

local function OnEvent()
    ApplyFont()

    SetCVar("nameplateUseClassColorForFriendlyPlayerUnitNames", 1)
    SetCVar("UnitNameFriendlyPlayerName", 1)
    SetCVar("nameplateShowFriendlyPlayers", 1)
    SetCVar("nameplateShowOnlyNameForFriendlyPlayerUnits", 1)
end

function FriendlyNameplates:GenerateFrame(name, parent)
    return CreateFrame("frame", name, parent or UIParent)
end

function FriendlyNameplates:EnsureFrame()
    if self.frame then
        return self.frame
    end

    local frame = self:GenerateFrame(addonName .. moduleName)
    self.frame = frame

    frame:RegisterEvent("PLAYER_ENTERING_WORLD")

    return frame
end

function FriendlyNameplates:OnInitialize()
    local profile = XerionUIFeatures.db.profile
    profile.FriendlyNameplates = profile.FriendlyNameplates or self:GetDefaults()
    self.db = profile.FriendlyNameplates
end

function FriendlyNameplates:RefreshConfig()
    local profile = XerionUIFeatures.db.profile
    profile.FriendlyNameplates = profile.FriendlyNameplates or self:GetDefaults()
    self.db = profile.FriendlyNameplates

    if self.db.enabled then
        local frame = self:EnsureFrame()

        frame:SetScript("OnEvent", OnEvent)
        OnEvent(frame)
    elseif self.frame then
        self.frame:SetScript("OnEvent", nil)
    end
end

-- Only the font, so a late media registration doesn't re-apply the CVars.
function FriendlyNameplates:Restyle()
    if self.db and self.db.enabled and self.frame then
        ApplyFont()
    end
end

function FriendlyNameplates:OnEnable()
    self:RefreshConfig()
end

function FriendlyNameplates:RegisterOptions(parentOptions)
    parentOptions.args[moduleName] = self:GetOptions(function()
        if self.frame then
            OnEvent(self.frame)
        end
    end)
end
