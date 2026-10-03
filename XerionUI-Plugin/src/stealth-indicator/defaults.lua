local addonName, XerionUIFeatures = ...
local LSM = XerionUIFeatures.LSM

local moduleName = "StealthIndicator"
local StealthIndicator = XerionUIFeatures:GetModule(moduleName)

function StealthIndicator:GetDefaults()
    return {
        enabled = false,
        displayText = "+Stealth",
        color = {r = 1, g = 1, b = 1, a = 1},
        point = {point = "CENTER", x = 0, y = 25},

        font = {
            fontFamily = "GothamNarrowBlack",
            fontSize = 14,
            fontOutline = "OUTLINE",
            fontShadowColor = {r = 0, g = 0, b = 0, a = 1},
            fontShadowXOffset = 1,
            fontShadowYOffset = -1,
            frameStrata = XerionUIFeatures.FrameStrataSettings.BACKGROUND,
            frameLevel = 1,
            justifyH = XerionUIFeatures.JustifyHSettings.CENTER,
        }
    }
end