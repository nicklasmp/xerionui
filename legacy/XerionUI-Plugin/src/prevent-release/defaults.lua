local addonName, XerionUIFeatures = ...
local LSM = XerionUIFeatures.LSM

local moduleName = "PreventRelease"
local PreventRelease = XerionUIFeatures:GetModule(moduleName)

function PreventRelease:GetDefaults()
    return {
        enabled = false,
        raidOnly = false,
    }
end