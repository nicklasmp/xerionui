local addonName, XerionUIFeatures = ...
local LSM = XerionUIFeatures.LSM

local moduleName = "MovementAlert"
local MovementAlert = XerionUIFeatures:GetModule(moduleName)

local function defaultTrackedSpells()
    local defaults = {}

    for specId, spellIds in pairs(MovementAlert.movementAbilitiesBySpec) do
        local spells = {}

        for _, spellId in ipairs(spellIds) do
            spells[spellId] = true
        end

        defaults[specId] = spells
    end

    return defaults
end

local function defaultTimeSpiralSpells()
    local defaults = {}

    for spellId, tracked in pairs(MovementAlert.timeSpiralAbilitiesBySpell) do
        defaults[spellId] = tracked
    end

    return defaults
end

function MovementAlert:GetDefaults()
    return {
        enabled = true,
        precision = 0,
        color = {r = 1, g = 1, b = 1, a = 1},
        updateInterval = 0.1,
        point = {point = "CENTER", x = 0, y = 50},
        trackedSpells = defaultTrackedSpells(),

        showTimeSpiral = true,
        timeSpiralSpells = defaultTimeSpiralSpells(),
        timeSpiralText = "Free Movement",
        timeSpiralColor = {r = 0.5333333611488342, g = 1, b = 0, a = 1},
        timeSpiralPlaySound = false,
        timeSpiralSound = nil,
        timeSpiralPlayTTS = false,
        timeSpiralTTS = "",
        timeSpiralTTSVolume = 50,
        timeSpiralTTSVoice = 0,

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