local addonName, XerionUIFeatures = ...

local moduleName = "RaidFrameManager"
local RaidFrameManager = XerionUIFeatures:GetModule(moduleName)

function RaidFrameManager:GetDefaults()
    return {
        enabled = false,
        onlyInGroup = true,
        onlyInRaid = true,
        mouseover = false,
        mouseoverAlpha = 1,
        mouseoverFadeAlpha = 0,
        showTooltips = false,
        orientation = "HORIZONTAL",
        paddingX = 10,
        paddingY = 3,
        spacing = 1,
        buttonColor = {r = 0, g = 0, b = 0, a = 0.5},
        textColor = {r = 1, g = 1, b = 1, a = 1},
        point = {point = "TOP", x = 0, y = -5},

        actions = {
            readyCheck = true,
            rolePoll = false,
        },

        pullTimers = {10, 15},
        cancelPull = true,

        font = {
            fontFamily = "GothamNarrowBlack",
            fontSize = 12,
            fontOutline = "OUTLINE",
            fontShadowColor = {r = 0, g = 0, b = 0, a = 1},
            fontShadowXOffset = 1,
            fontShadowYOffset = -1,
            frameStrata = XerionUIFeatures.FrameStrataSettings.MEDIUM,
            frameLevel = 1,
            justifyH = XerionUIFeatures.JustifyHSettings.CENTER,
        }
    }
end
