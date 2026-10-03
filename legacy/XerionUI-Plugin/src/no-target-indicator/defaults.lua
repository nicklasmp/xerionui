local addonName, XerionUIFeatures = ...
local LSM = XerionUIFeatures.LSM

local moduleName = "NoTargetIndicator"
local NoTargetIndicator = XerionUIFeatures:GetModule(moduleName)

function NoTargetIndicator:GetDefaults()
    return {
        enabled = false,
        displayText = "No target",
        color = {r = 0.769, g = 0.118, b = 0.227, a = 1},
        point = {point = "CENTER", x = 0, y = 25},
        friendlyisValidTarget = false,

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