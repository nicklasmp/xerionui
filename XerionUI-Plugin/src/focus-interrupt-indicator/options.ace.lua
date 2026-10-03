local addonName, XerionUIFeatures = ...
local LSM = XerionUIFeatures.LSM

local moduleName = "FocusInterruptIndicator"
local FocusInterruptIndicator = XerionUIFeatures:GetModule(moduleName)

function FocusInterruptIndicator:GetOptions(onChange)
    return {
        order = 2,
        type = "group",
        name = "Focus Interrupt",
        args = {
            preview = XerionUIFeatures:CreatePreviewOption(FocusInterruptIndicator),
            description = {
                type = "description",
                name = "Shows an alert when your focus casts an interruptable cast and you have your interrupt ready \n\n",
                width = "full",
                order = 1,
            },
            enable = {
                order = 2,
                type = "toggle",
                width = "full",
                name = "Enable",
                get = function() 
                    return FocusInterruptIndicator.db.enabled
                end,
                set = function(_, value)
                    FocusInterruptIndicator.db.enabled = value
                    FocusInterruptIndicator:RefreshConfig()
                end,
            },
            displaySettings = {
                type = "group",
                name = "",
                order = 4,
                inline = true,
                args = {
                    displayText = {
                        order = 2,
                        type = "input",
                        name = "Display text",
                        get = function()
                            return FocusInterruptIndicator.db.displayText
                        end,
                        set = function(_, value)
                            FocusInterruptIndicator.db.displayText = value
                            onChange()
                        end,
                    },
                    color = {
                        order = 2,
                        type = "color",
                        name = "Color",
                        width = 0.4,
                        hasAlpha = true, 
                        get = function()
                            local color = FocusInterruptIndicator.db.color
                            return color.r, color.g, color.b, color.a
                        end,
                        set = function(_, r, g, b, a)
                            FocusInterruptIndicator.db.color = {
                                r = r,
                                g = g,
                                b = b,
                                a = a,
                            }
                            onChange()
                        end,
                    },
                }
            },
            fontSettings = {
                type = "group",
                name = "",
                order = 5,
                inline = true,
                args = XerionUIFeatures:createFontOptions(function() return FocusInterruptIndicator.db.font end, function() 
                    onChange()
                end)
            },
            soundGroup = {
                type = "group",
                name = "",
                order = 6,
                inline = true,
                args = {
                    disclaimer = {
                        type = "description",
                        name = "Unfortunately due to API restrictions, this sound will play even when your interrupt is not available or the cast is not interruptible \n\n",
                        width = "full",
                        order = 1,
                    },
                    playSound = {
                        order = 2,
                        type = "toggle",
                        name = "Play sound",
                        get = function() 
                            return FocusInterruptIndicator.db.playSound
                        end,
                        set = function(_, value)
                            FocusInterruptIndicator.db.playSound = value
                        end,
                    },
                    sound = {
                        order = 3,
                        type = "select",
                        dialogControl = "LSM30_Sound",
                        name = "Sound",
                        values = LSM:HashTable("sound"),
                        get = function()
                            return FocusInterruptIndicator.db.sound
                        end,
                        set = function(_, value)
                            FocusInterruptIndicator.db.sound = value
                        end,
                        disabled = function()
                            return not FocusInterruptIndicator.db.playSound
                        end,
                    },
                }
            },
            ttsGroup = {
                type = "group",
                name = "",
                order = 7,
                inline = true,
                args = {
                    playTTS = {
                        order = 1,
                        type = "toggle",
                        name = "Play TTS",
                        get = function() 
                            return FocusInterruptIndicator.db.playTTS
                        end,
                        set = function(_, value)
                            FocusInterruptIndicator.db.playTTS = value
                        end,
                    },
                    TTS = {
                        order = 2,
                        type = "input",
                        name = "TTS Message",
                        get = function()
                            return FocusInterruptIndicator.db.TTS
                        end,
                        set = function(_, value)
                            FocusInterruptIndicator.db.TTS = value
                        end,
                        disabled = function()
                            return not FocusInterruptIndicator.db.playTTS
                        end,
                    },
                    ttsPreview = XerionUIFeatures:TTSPreviewButton(3,
                        function() return FocusInterruptIndicator.db.TTS end,
                        function() return FocusInterruptIndicator.db.TTSVolume end,
                        function() return FocusInterruptIndicator.db.TTSVoice end,
                        function() return not FocusInterruptIndicator.db.playTTS end
                    ),
                    TTSVolume = {
                        order = 4,
                        type = "range",
                        width = 0.75,
                        min = 0,
                        max = 100,
                        step = 1,
                        name = "TTS Volume",
                        get = function()
                            return FocusInterruptIndicator.db.TTSVolume
                        end,
                        set = function(_, value)
                            FocusInterruptIndicator.db.TTSVolume = value
                        end,
                        disabled = function()
                            return not FocusInterruptIndicator.db.playTTS
                        end,
                    },
                    TTSVoice = XerionUIFeatures:TTSVoiceOption(5,
                        function() return FocusInterruptIndicator.db.TTSVoice end,
                        function(_, value) FocusInterruptIndicator.db.TTSVoice = value end,
                        function() return not FocusInterruptIndicator.db.playTTS end
                    ),
                },
                disabled = function()
                    return FocusInterruptIndicator.db.playSound
                end,
            },
        }
    }
end