local addonName, XerionUIFeatures = ...
local LSM = XerionUIFeatures.LSM

local moduleName = "MacroFactory"
local MacroFactory = XerionUIFeatures:GetModule(moduleName)

function MacroFactory:GetDefaults()
    return {
        enabled = true,
    }
end