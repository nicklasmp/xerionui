local addonName, XerionUIFeatures = ...

local moduleName = "DefensiveIndicator"
local DefensiveIndicator = XerionUIFeatures:GetModule(moduleName)

local function defaultTrackedAuras()
    local defaults = {}

    for spellId, tracked in pairs(DefensiveIndicator.defensiveAurasBySpell) do
        defaults[spellId] = tracked
    end

    return defaults
end

function DefensiveIndicator:GetDefaults()
    return {
        enabled = false,
        display = DefensiveIndicator.displayCircle,
        size = 46,
        barWidth = 160,
        barHeight = 14,
        barTexture = "Skullflower2",
        ringTexture = [[Interface\AddOns\XerionUI-Plugin\Media\textures\ItruliaCircleMedium.tga]],
        colors = {
            MASSIVE = {r = 0.925, g = 0.353, b = 0.353, a = 1},
            MAJOR = {r = 0.451, g = 0.741, b = 0.522, a = 1},
            MINOR = {r = 0.400, g = 0.616, b = 0.855, a = 1},
            EXTERNAL = {r = 0.949, g = 0.769, b = 0.318, a = 1},
        },
        backgroundColor = {r = 0, g = 0, b = 0, a = 0.6},
        showName = true,
        showDuration = true,
        textColor = {r = 1, g = 1, b = 1, a = 1},
        textOffset = {x = 0, y = 0},
        precision = 0,
        updateInterval = 0.1,
        point = {point = "CENTER", x = 0, y = -140},
        trackedAuras = defaultTrackedAuras(),

        font = {
            fontFamily = "GothamNarrowBlack",
            fontSize = 12,
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
