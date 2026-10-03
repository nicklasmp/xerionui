local addonName, namespace = ...

local XerionUIFeatures = LibStub("AceAddon-3.0"):GetAddon(addonName)
local CDMSlash = XerionUIFeatures:NewModule("CDMSlash")

local InCombatLockdown = InCombatLockdown
local CooldownViewerSettings = _G.CooldownViewerSettings

local frame  = CreateFrame("frame", addonName .. "CDMSlash")
frame:EnableKeyboard(true)
frame:SetPropagateKeyboardInput(true)

function frame:toggleCDM()
	if InCombatLockdown() or not CooldownViewerSettings then 
        return 
    end

	if not CooldownViewerSettings:IsShown() then
		CooldownViewerSettings:Show()
	else
		CooldownViewerSettings:Hide()
	end
end

function CDMSlash:OnEnable() 
    SLASH_CDMSC2 = "/cdm"

    function SlashCmdList.CDMSC(msg, editbox)
        frame:toggleCDM()
    end
end
