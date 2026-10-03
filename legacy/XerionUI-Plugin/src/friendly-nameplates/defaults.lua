local addonName, XerionUIFeatures = ...
local LSM = XerionUIFeatures.LSM

local moduleName = "FriendlyNameplates"
local FriendlyNameplates = XerionUIFeatures:GetModule(moduleName)

function FriendlyNameplates:GetDefaults()
    return {
        enabled = false,
        font = {
            fontFamily = "GothamNarrowBlack",
            fontSize = 14,
            fontOutline = "OUTLINESLUG",
        },
    }
end