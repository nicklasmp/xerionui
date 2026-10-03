local addonName, XerionUIFeatures = ...
local LSM = XerionUIFeatures.LSM

local moduleName = "CombatAlert"
local CombatAlert = XerionUIFeatures:GetModule(moduleName)

function CombatAlert:GetDefaults()
    return {
        enabled = true,
        combatStartsText = "+Combat",
        combatStartsColor = {r = 0.9803922176361084, g = 1, b = 0, a = 1},
        combatEndsText = "-Combat",
        combatEndsColor = {r = 0.5333333611488342, g = 1, b = 0, a = 1},
        point = {point = "CENTER", x = 0, y = 0},

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