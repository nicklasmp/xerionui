local addonName, XerionUIFeatures = ...
local LSM = XerionUIFeatures.LSM

local moduleName = "FocusTargetMarker"
local FocusTargetMarker = XerionUIFeatures:GetModule(moduleName)

function FocusTargetMarker:GetDefaults()
    return {
        enabled = true,
        announce = not XerionUIFeatures.isForever,
        marker = 5,
    }
end