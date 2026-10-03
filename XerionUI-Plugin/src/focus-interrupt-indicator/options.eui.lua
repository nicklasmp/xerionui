local addonName, XerionUIFeatures = ...

local moduleName = "FocusInterruptIndicator"
local FocusInterruptIndicator = XerionUIFeatures:GetModule(moduleName)

FocusInterruptIndicator.EUIPages = { "Display", "Sound Alert" }

function FocusInterruptIndicator:GetEUIOptions(pageName)
    local function apply() XerionUIFeatures:ApplyModuleStyles(moduleName) end

    if pageName == "Sound Alert" then
        return {
            name = "Focus Interrupt",
            rows = {
                {
                    header = "Sound",
                },
                {
                    text = "This sound plays even when your interrupt is unavailable or the cast is not interruptible (API limitation).",
                },
                {
                    type = "toggle",
                    label = "Play sound",
                    refresh = true,
                    get = function()
                        return FocusInterruptIndicator.db.playSound
                    end,
                    set = function(value)
                        FocusInterruptIndicator.db.playSound = value
                    end,
                },
                XerionUIFeatures:EUISoundRow({
                    disabled = function()
                        return not FocusInterruptIndicator.db.playSound
                    end,
                    get = function()
                        return FocusInterruptIndicator.db.sound
                    end,
                    set = function(value)
                        FocusInterruptIndicator.db.sound = value
                    end,
                }),
                {
                    header = "Text-to-Speech",
                },
                {
                    type = "toggle",
                    label = "Play TTS",
                    refresh = true,
                    disabled = function()
                        return FocusInterruptIndicator.db.playSound
                    end,
                    get = function()
                        return FocusInterruptIndicator.db.playTTS
                    end,
                    set = function(value)
                        FocusInterruptIndicator.db.playTTS = value
                    end,
                },
                XerionUIFeatures:EUITTSRow({
                    label = "TTS message",
                    disabled = function()
                        return FocusInterruptIndicator.db.playSound or not FocusInterruptIndicator.db.playTTS
                    end,
                    get = function()
                        return FocusInterruptIndicator.db.TTS
                    end,
                    set = function(value)
                        FocusInterruptIndicator.db.TTS = value
                    end,
                    volume = {
                        get = function() return FocusInterruptIndicator.db.TTSVolume end,
                        set = function(value) FocusInterruptIndicator.db.TTSVolume = value end,
                    },
                    voice = {
                        get = function() return FocusInterruptIndicator.db.TTSVoice end,
                        set = function(value) FocusInterruptIndicator.db.TTSVoice = value end,
                    },
                }),
            },
        }
    end

    local displayRow = {
        type = "color",
        label = "Display",
        hasAlpha = true,
        get = function()
            local color = FocusInterruptIndicator.db.color
            return color.r, color.g, color.b, color.a
        end,
        set = function(r, g, b, a)
            FocusInterruptIndicator.db.color = {
                r = r,
                g = g,
                b = b,
                a = a,
            }
            apply()
        end,
        cog = {
            title = "Alert Text",
            rows = {
                {
                    type = "input",
                    label = "Text",
                    width = 120,
                    get = function()
                        return FocusInterruptIndicator.db.displayText or ""
                    end,
                    set = function(value)
                        FocusInterruptIndicator.db.displayText = value
                        apply()
                    end,
                },
            },
        },
    }

    return {
        name = "Focus Interrupt",
        rows = XerionUIFeatures:EUIFontRows(function() return FocusInterruptIndicator.db.font end, apply, nil, { displayRow }),
    }
end
