local addonName, XerionUIFeatures = ...
local LSM = XerionUIFeatures.LSM

local moduleName = "FocusInterruptIndicator"
local FocusInterruptIndicator = XerionUIFeatures:GetModule(moduleName)

function FocusInterruptIndicator:GetDefaults()
    return {
        enabled = true,
        point = { point = "CENTER", x = 0, y = 150 },
        color = {r = 1, g = 1, b = 1, a = 1},
        displayText = "INTERRUPT",

        playSound = false,
        sound = "Kick",
        playTTS = false,
        TTS = "",
        TTSVolume = 50,
        TTSVoice = 0,

        font = {
            fontFamily = "GothamNarrowBlack",
            fontSize = 28,
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