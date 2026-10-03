local addonName, XerionUIFeatures = ...

local moduleName = "KeystoneLister"
local KeystoneLister = XerionUIFeatures:GetModule(moduleName)

function KeystoneLister:GetDefaults()
    return {
        enabled = false,
        mouseover = false,
        mouseoverAlpha = 1,
        mouseoverFadeAlpha = 0,
        showTooltips = true,

        itemLevel = 0,
        requiredRating = 0,
        playstyle = 0,

        paddingX = 10,
        paddingY = 3,
        buttonColor = {r = 0, g = 0, b = 0, a = 0.5},
        textColor = {r = 1, g = 1, b = 1, a = 1},
        point = {point = "CENTER", x = 0, y = 0},

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
