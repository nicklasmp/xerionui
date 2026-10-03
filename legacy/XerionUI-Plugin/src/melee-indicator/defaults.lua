local addonName, XerionUIFeatures = ...
local LSM = XerionUIFeatures.LSM

local moduleName = "MeleeIndicator"
local MeleeIndicator = XerionUIFeatures:GetModule(moduleName)

function MeleeIndicator:GetDefaults()
    return {
        enabled = true,
        displayText = "+",
        color = {r = 1, g = 0, b = 0, a = 1},
        updateInterval = 0.5,
        point = { point = "CENTER", x = 0, y = 0 },

        font = {
            fontFamily = "GothamNarrowBlack",
            fontSize = 28,
            fontOutline = "OUTLINE",
            fontShadowColor = {r = 0, g = 0, b = 0, a = 0},
            fontShadowXOffset = 1,
            fontShadowYOffset = -1,
            frameStrata = XerionUIFeatures.FrameStrataSettings.BACKGROUND,
            frameLevel = 1,
            justifyH = XerionUIFeatures.JustifyHSettings.CENTER,
        }
    }
end