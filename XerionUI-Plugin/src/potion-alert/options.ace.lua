local addonName, XerionUIFeatures = ...
local LSM = XerionUIFeatures.LSM

local moduleName = "PotionAlert"
local PotionAlert = XerionUIFeatures:GetModule(moduleName)

function PotionAlert:GetOptions(onChange)
    return {
        order = 2,
        type = "group",
        name = "Potion Alert",
        args = {
            preview = XerionUIFeatures:CreatePreviewOption(PotionAlert),
            description = {
                type = "description",
                name =  "Displays a text and plays a sound when your combat potion is off CD\n\n",
                width = "full",
                order = 1,
            },
            enableSettings = {
                type = "group",
                name = "",
                order = 2,
                inline = true,
                args = {
                    enable = {
                        order = 1,
                        type = "toggle",
                        width = 0.4,
                        name = "Enable",
                        get = function(info)
                            return PotionAlert.db.enabled
                        end,
                        set = function(info, value)
                            PotionAlert.db.enabled = value
                            PotionAlert:RefreshConfig()
                        end
                    },
                    enabledInDungeons = {
                        order = 2,
                        type = "toggle",
                        width = 0.7,
                        name = "Enable in m0/m+",
                        get = function(info)
                            return PotionAlert.db.enabledInDungeons
                        end,
                        set = function(info, value)
                            PotionAlert.db.enabledInDungeons = value
                            onChange()
                        end
                    },
                    enabledInRaids = {
                        order = 3,
                        type = "toggle",
                        width = 0.7,
                        name = "Enable in raids",
                        get = function(info)
                            return PotionAlert.db.enabledInRaids
                        end,
                        set = function(info, value)
                            PotionAlert.db.enabledInRaids = value
                            onChange()
                        end
                    },
                }
            },
            displaySettings = {
                type = "group",
                name = "",
                order = 4,
                inline = true,
                args = {
                    displayText = {
                        order = 1,
                        type = "input",
                        name = "Display text",
                        get = function()
                            return PotionAlert.db.displayText
                        end,
                        set = function(_, value)
                            PotionAlert.db.displayText = value
                            onChange()
                        end
                    },
                    color = {
                        order = 2,
                        type = "color",
                        name = "Color",
                        width = 0.4,
                        hasAlpha = true,
                        get = function()
                            local color = PotionAlert.db.color
                            return color.r, color.g, color.b, color.a
                        end,
                        set = function(_, r, g, b, a)
                            PotionAlert.db.color = {
                                r = r,
                                g = g,
                                b = b,
                                a = a
                            }
                            onChange()
                        end
                    },
                }
            },
            fontSettings = {
                type = "group",
                name = "",
                order = 5,
                inline = true,
                args = XerionUIFeatures:createFontOptions(function() return PotionAlert.db.font end, function() 
                    onChange()
                end)
            },
            spacer = {
                type = "description",
                name = " ",
                width = "full",
                order = 6,
            },
            soundGroup = {
                type = "group",
                name = "",
                order = 7,
                inline = true,
                args = {
                    playSound = {
                        order = 1,
                        type = "toggle",
                        name = "Play sound",
                        get = function() 
                            return PotionAlert.db.playSound
                        end,
                        set = function(_, value)
                            PotionAlert.db.playSound = value
                        end,
                    },
                    sound = {
                        order = 2,
                        type = "select",
                        dialogControl = "LSM30_Sound",
                        name = "Sound",
                        values = LSM:HashTable("sound"),
                        get = function()
                            return PotionAlert.db.sound
                        end,
                        set = function(_, value)
                            PotionAlert.db.sound = value
                        end,
                        disabled = function()
                            return not PotionAlert.db.playSound
                        end,
                    },
                },
            },
            ttsGroup = {
                type = "group",
                name = "",
                order = 8,
                inline = true,
                args = {
                    playTTS = {
                        order = 1,
                        type = "toggle",
                        name = "Play TTS",
                        get = function() 
                            return PotionAlert.db.playTTS
                        end,
                        set = function(_, value)
                            PotionAlert.db.playTTS = value
                        end,
                    },
                    tts = {
                        order = 2,
                        type = "input",
                        name = "TTS Message",
                        get = function()
                            return PotionAlert.db.TTS
                        end,
                        set = function(_, value)
                            PotionAlert.db.TTS = value
                        end,
                        disabled = function()
                            return not PotionAlert.db.playTTS
                        end,
                    },
                    ttsPreview = XerionUIFeatures:TTSPreviewButton(3,
                        function() return PotionAlert.db.TTS end,
                        function() return PotionAlert.db.TTSVolume end,
                        function() return PotionAlert.db.TTSVoice end,
                        function() return not PotionAlert.db.playTTS end
                    ),
                    ttsVolume = {
                        order = 4,
                        type = "range",
                        width = 0.75,
                        min = 0,
                        max = 100,
                        step = 1,
                        name = "TTS Volume",
                        get = function()
                            return PotionAlert.db.TTSVolume
                        end,
                        set = function(_, value)
                            PotionAlert.db.TTSVolume = value
                        end,
                        disabled = function()
                            return not PotionAlert.db.playTTS
                        end,
                    },
                    ttsVoice = XerionUIFeatures:TTSVoiceOption(5,
                        function() return PotionAlert.db.TTSVoice end,
                        function(_, value) PotionAlert.db.TTSVoice = value end,
                        function() return not PotionAlert.db.playTTS end
                    ),
                },
                disabled = function()
                    return PotionAlert.db.playSound
                end,
            },
        }
    }
end