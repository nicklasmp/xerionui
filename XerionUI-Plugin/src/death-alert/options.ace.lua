local addonName, XerionUIFeatures = ...
local LSM = XerionUIFeatures.LSM

local moduleName = "DeathAlert"
local DeathAlert = XerionUIFeatures:GetModule(moduleName)

local function optionsForRole(role) 
    return {
        showAlert = {
            order = 1,
            type = "toggle",
            width = "full",
            name = "Show alert",
            get = function()
                return DeathAlert.db.byRole.display[role].enabled
            end,
            set = function(_, value)
                DeathAlert.db.byRole.display[role].enabled = value
            end
        },
        soundGroup = {
            order = 2,
            type = "group",
            name = "",
            inline = true,
            args = {
                playSound = {
                    order = 1,
                    type = "toggle",
                    name = "Play sound",
                    get = function() 
                        return DeathAlert.db.byRole.sound[role].enabled
                    end,
                    set = function(_, value)
                        DeathAlert.db.byRole.sound[role].enabled = value
                    end,
                    disabled = function()
                        return not DeathAlert.db.playSound
                    end
                },
                sound = {
                    order = 2,
                    type = "select",
                    dialogControl = "LSM30_Sound", 
                    name = "Sound",
                    values = LSM:HashTable("sound"),
                    get = function()
                        return DeathAlert.db.byRole.sound[role].sound
                    end,
                    set = function(_, value)
                        DeathAlert.db.byRole.sound[role].sound = value
                    end,
                    disabled = function()
                        return not DeathAlert.db.playSound or not DeathAlert.db.byRole.sound[role].enabled
                    end
                },
                clear = {
                    order = 3,
                    type = "execute",
                    name = "Clear",
                    width = 0.5,
                    func = function()
                        DeathAlert.db.byRole.sound[role].sound = nil
                    end,
                    disabled = function()
                        return not DeathAlert.db.playSound or not DeathAlert.db.byRole.sound[role].enabled
                    end
                },
            }
        },
        ttsGroup = {
            order = 3,
            type = "group",
            name = "",
            inline = true,
            args = {
                playTTS = {
                    order = 1,
                    type = "toggle",
                    name = "Play TTS",
                    get = function() 
                        return DeathAlert.db.byRole.tts[role].enabled
                    end,
                    set = function(_, value)
                        DeathAlert.db.byRole.tts[role].enabled = value
                    end,
                    disabled = function()
                        return DeathAlert.db.playSound or not DeathAlert.db.playTTS
                    end
                },
                TTS = {
                    order = 2,
                    type = "input",
                    name = "TTS Message",
                    get = function()
                        return DeathAlert.db.byRole.tts[role].TTS
                    end,
                    set = function(_, value)
                        if value == "" then
                            value = nil
                        end

                        DeathAlert.db.byRole.tts[role].TTS = value
                    end,
                    disabled = function()
                        return DeathAlert.db.playSound or not DeathAlert.db.playTTS or not DeathAlert.db.byRole.tts[role].enabled
                    end
                },
                ttsPreview = XerionUIFeatures:TTSPreviewButton(3,
                    function() return DeathAlert.db.byRole.tts[role].TTS end,
                    function() return DeathAlert.db.TTSVolume end,
                    function() return DeathAlert.db.TTSVoice end,
                    function() return DeathAlert.db.playSound or not DeathAlert.db.playTTS or not DeathAlert.db.byRole.tts[role].enabled end
                ),
            }
        }
    }
end

function DeathAlert:GetOptions(onChange)
    return {
        order = 2,
        type = "group",
        name = "Death Alert",
        args = {
            preview = XerionUIFeatures:CreatePreviewOption(DeathAlert),
            description = {
                type = "description",
                name = "Shows an alert when someone in your party or raid dies \n\n",
                width = "full",
                order = 1,
            },
            enable = {
                order = 2,
                type = "toggle",
                width = "full",
                name = "Enable",
                get = function()
                    return DeathAlert.db.enabled
                end,
                set = function(_, value)
                    DeathAlert.db.enabled = value
                    DeathAlert:RefreshConfig()
                end
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
                        name = "Suffix",
                        get = function()
                            return DeathAlert.db.displayText
                        end,
                        set = function(_, value)
                            DeathAlert.db.displayText = value
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
                            local color = DeathAlert.db.color
                            return color.r, color.g, color.b, color.a
                        end,
                        set = function(_, r, g, b, a)
                            DeathAlert.db.color = {
                                r = r,
                                g = g,
                                b = b,
                                a = a
                            }
                            onChange()
                        end
                    },
                    messageDuration = {
                        order = 3,
                        type = "range",
                        width = 0.75,
                        min = 1,
                        max = 10,
                        step = 1,
                        name = "Display duration",
                        get = function()
                            return DeathAlert.db.messageDuration
                        end,
                        set = function(_, value)
                            DeathAlert.db.messageDuration = value
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
                args = XerionUIFeatures:createFontOptions(function() return DeathAlert.db.font end, function() 
                    onChange()
                end)
            },
            soundGroup = {
                type = "group",
                name = "",
                order = 6,
                inline = true,
                args = {
                    playSound = {
                        order = 1,
                        type = "toggle",
                        name = "Play sound",
                        get = function() 
                            return DeathAlert.db.playSound
                        end,
                        set = function(_, value)
                            DeathAlert.db.playSound = value
                        end,
                    },
                    sound = {
                        order = 2,
                        type = "select",
                        dialogControl = "LSM30_Sound",
                        name = "Sound",
                        values = LSM:HashTable("sound"),
                        get = function()
                            return DeathAlert.db.sound
                        end,
                        set = function(_, value)
                            DeathAlert.db.sound = value
                        end,
                        disabled = function()
                            return not DeathAlert.db.playSound
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
                            return DeathAlert.db.playTTS
                        end,
                        set = function(_, value)
                            DeathAlert.db.playTTS = value
                        end,
                    },
                    TTS = {
                        order = 2,
                        type = "input",
                        name = "TTS Message",
                        get = function()
                            return DeathAlert.db.TTS
                        end,
                        set = function(_, value)
                            DeathAlert.db.TTS = value
                        end,
                        disabled = function()
                            return not DeathAlert.db.playTTS
                        end,
                    },
                    ttsPreview = XerionUIFeatures:TTSPreviewButton(3,
                        function() return DeathAlert.db.TTS end,
                        function() return DeathAlert.db.TTSVolume end,
                        function() return DeathAlert.db.TTSVoice end,
                        function() return not DeathAlert.db.playTTS end
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
                            return DeathAlert.db.TTSVolume
                        end,
                        set = function(_, value)
                            DeathAlert.db.TTSVolume = value
                        end,
                        disabled = function()
                            return not DeathAlert.db.playTTS
                        end,
                    },
                    TTSVoice = XerionUIFeatures:TTSVoiceOption(5,
                        function() return DeathAlert.db.TTSVoice end,
                        function(_, value) DeathAlert.db.TTSVoice = value end,
                        function() return not DeathAlert.db.playTTS end
                    ),
                },
                disabled = function()
                    return DeathAlert.db.playSound
                end,
            },
            boosterSettings = {
                type = "group",
                name = "",
                order = 8,
                inline = true,
                args = {
                    whitelist = {
                        order = 1,
                        type = "input",
                        multiline = true,
                        name = "Whitelist names",
                        desc = "Comma seperated list of names",
                        get = function()
                            return DeathAlert.db.whitelist
                        end,
                        set = function(_, value)
                            DeathAlert.db.whitelist = value
                        end
                    },
                    spacer = {
                        type = "description",
                        name = " ",
                        width = 0.1,
                        order = 2,
                    },
                    blacklist = {
                        order = 3,
                        type = "input",
                        multiline = true,
                        name = "Blacklist names",
                        desc = "Comma seperated list of names",
                        get = function()
                            return DeathAlert.db.blacklist
                        end,
                        set = function(_, value)
                            DeathAlert.db.blacklist = value
                        end,
                        disabled = function()
                            return DeathAlert.db.whitelist and DeathAlert.db.whitelist ~= ""
                        end
                    },
                }
            },
            byRole = {
                type = "group",
                name = "Settings based on dead player's role",
                order = 9,
                inline = true,
                args = {
                    description = {
                        type = "description",
                        name = "These settings only work while in a raid as you might not care about a dps standing in fire ;) \n" 
                        .. "Empty settings will fallback to the settings above \n\n",
                        width = "full",
                        order = 1,
                    },
                    dpsConfig = {
                        type = "group",
                        name = "DPS",
                        order = 2,
                        inline = true,
                        args = optionsForRole("DAMAGER")
                    },
                    healerConfig = {
                        type = "group",
                        name = "Healer",
                        order = 3,
                        inline = true,
                        args = optionsForRole("HEALER")
                    },
                    tankConfig = {
                        type = "group",
                        name = "Tank",
                        order = 4,
                        inline = true,
                        args = optionsForRole("TANK")
                    }
                },
            },
        }
    }
end