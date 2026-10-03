local addonName, XerionUIFeatures = ...
local LSM = XerionUIFeatures.LSM

local moduleName = "DeathAlert"
local DeathAlert = XerionUIFeatures:GetModule(moduleName)

function DeathAlert:GetDefaults()
    return {
        enabled = true,
        whitelist = nil,
        blacklist = nil,
        displayText = "died",
        color = {r = 1, g = 1, b = 1, a = 1},
        messageDuration = 2,
        point = {point = "CENTER", x = 0, y = 200},

        playSound = false,
        sound = "Exit",
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
        },

        byRole = {
            display = {
                DAMAGER = {
                    enabled = true
                },
                HEALER = {
                    enabled = true
                },
                TANK = {
                    enabled = true
                },
            },
            sound = {
                DAMAGER = {
                    enabled = true,
                    sound = nil
                },
                HEALER = {
                    enabled = true,
                    sound = nil
                },
                TANK = {
                    enabled = true,
                    sound = nil
                },
            },
            tts = {
                DAMAGER = {
                    enabled = true,
                    tts = nil
                },
                HEALER = {
                    enabled = true,
                    tts = nil
                },
                TANK = {
                    enabled = true,
                    tts = nil
                },
            }
        },
    }
end