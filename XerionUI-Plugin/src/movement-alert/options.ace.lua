local addonName, XerionUIFeatures = ...
local LSM = XerionUIFeatures.LSM

local moduleName = "MovementAlert"
local MovementAlert = XerionUIFeatures:GetModule(moduleName)

local function SpellString(item)
    if not item.icon then
        return item.label
    end

    return string.format("|T%s:16:16:0:0:64:64:5:59:5:59|t %s", item.icon, item.label)
end

local function createTimeSpiralSpellOptions(onChange)
    local args = {}

    for classIndex, class in ipairs(MovementAlert:GetTimeSpiralClasses()) do
        local values = {}
        local order = {}

        for index, item in ipairs(MovementAlert:GetTimeSpiralSpellItems(class)) do
            values[item.key] = SpellString(item)
            order[index] = item.key
        end

        args["class" .. class.classFile] = {
            order = classIndex,
            type = "multiselect",
            dialogControl = "ItruliaMultiselect",
            arg = order,
            name = class.colorString .. class.className .. "|r",
            values = values,
            get = function(_, spellId)
                return MovementAlert:IsTimeSpiralSpellTracked(spellId)
            end,
            set = function(_, spellId, value)
                MovementAlert:SetTimeSpiralSpellTracked(spellId, value)
                onChange()
            end,
            disabled = function()
                return not MovementAlert.db.showTimeSpiral
            end,
        }
    end

    return args
end

-- One group per class, one multiselect per spec, so every spec can be set up from
-- any character rather than only the one that plays it.
local function createTrackedSpellOptions(onChange)
    local args = {}

    for classIndex, class in ipairs(MovementAlert:GetTrackedSpecs()) do
        local specArgs = {}

        for specIndex, spec in ipairs(class.specs) do
            local values = {}
            local order = {}

            for index, item in ipairs(MovementAlert:GetTrackedSpellItems(spec.specId)) do
                values[item.key] = SpellString(item)
                order[index] = item.key
            end

            specArgs["spec" .. spec.specId] = {
                order = specIndex,
                type = "multiselect",
                -- A checkbox dropdown rather than the default row of checkboxes, so
                -- the list stays as compact as the EllesmereUI page's. `arg` is the
                -- entry order it lists them in, which is the priority they alert in.
                dialogControl = "ItruliaMultiselect",
                arg = order,
                name = spec.specName,
                values = values,
                get = function(_, spellId)
                    return MovementAlert:IsSpellTracked(spec.specId, spellId)
                end,
                set = function(_, spellId, value)
                    MovementAlert:SetSpellTracked(spec.specId, spellId, value)
                    onChange()
                end,
            }
        end

        args["class" .. class.classFile] = {
            order = classIndex,
            type = "group",
            name = class.colorString .. class.className .. "|r",
            inline = true,
            args = specArgs,
        }
    end

    return args
end

function MovementAlert:GetOptions(onChange)
    return {
        order = 2,
        type = "group",
        name = "Movement Alert",
        childGroups = "tab",
        args = {
            description = {
                type = "description",
                name =  "Displays a text when your most important movement ability is on cooldown or time spiral is active\n\n",
                width = "full",
                order = 1,
            },
            enable = {
                order = 2,
                type = "toggle",
                width = "full",
                name = "Enable",
                get = function(info)
                    return MovementAlert.db.enabled
                end,
                set = function(info, value)
                    MovementAlert.db.enabled = value
                    MovementAlert:RefreshConfig()
                end
            },
            display = {
                order = 10,
                type = "group",
                name = MovementAlert.pageDisplay,
                args = {
                    preview = XerionUIFeatures:CreatePreviewOption(MovementAlert, 0, nil, MovementAlert.pageDisplay),
                    displaySettings = {
                        type = "group",
                        name = "",
                        order = 4,
                        inline = true,
                        args = {
                            color = {
                                order = 2,
                                type = "color",
                                name = "Color",
                                width = 0.4,
                                hasAlpha = true,
                                get = function()
                                    local color = MovementAlert.db.color
                                    return color.r, color.g, color.b, color.a
                                end,
                                set = function(_, r, g, b, a)
                                    MovementAlert.db.color = {
                                        r = r,
                                        g = g,
                                        b = b,
                                        a = a
                                    }
                                    onChange()
                                end
                            },
                            decimals = {
                                order = 3,
                                type = "range",
                                width = 0.75,
                                min = 0,
                                max = 1,
                                step = 1,
                                name = "Decimal precision",
                                get = function()
                                    return MovementAlert.db.precision
                                end,
                                set = function(_, value)
                                    MovementAlert.db.precision = value
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
                        args = XerionUIFeatures:createFontOptions(function() return MovementAlert.db.font end, function()
                            onChange()
                        end)
                    },
                }
            },
            trackedSpells = {
                order = 15,
                type = "group",
                name = MovementAlert.pageTrackedSpells,
                args = {
                    description = {
                        type = "description",
                        name = "The alert shows the first ability a spec has that is checked here, so the order of a spec's abilities is its priority\n\n",
                        width = "full",
                        order = 1,
                    },
                    classes = {
                        type = "group",
                        name = "",
                        order = 2,
                        inline = true,
                        args = createTrackedSpellOptions(onChange),
                    },
                }
            },
            timeSpiral = {
                order = 20,
                type = "group",
                name = MovementAlert.pageTimeSpiral,
                args = {
                    preview = XerionUIFeatures:CreatePreviewOption(MovementAlert, 0, nil, MovementAlert.pageTimeSpiral),
                    showTimeSpiral = {
                        order = 1,
                        type = "toggle",
                        width = "full",
                        name = "Enable",
                        get = function(info)
                            return MovementAlert.db.showTimeSpiral
                        end,
                        set = function(info, value)
                            MovementAlert.db.showTimeSpiral = value
                            onChange()
                        end
                    },
                    timeSpiralText = {
                        order = 2,
                        type = "input",
                        name = "Time spiral text",
                        get = function()
                            return MovementAlert.db.timeSpiralText
                        end,
                        set = function(_, value)
                            MovementAlert.db.timeSpiralText = value
                            onChange()
                        end,
                        disabled = function()
                            return not MovementAlert.db.showTimeSpiral
                        end,
                    },
                    timeSpiralColor = {
                        order = 3,
                        type = "color",
                        name = "Time spiral color",
                        hasAlpha = true,
                        get = function()
                            local color = MovementAlert.db.timeSpiralColor
                            return color.r, color.g, color.b, color.a
                        end,
                        set = function(_, r, g, b, a)
                            MovementAlert.db.timeSpiralColor = {
                                r = r,
                                g = g,
                                b = b,
                                a = a,
                            }
                            onChange()
                        end,
                        disabled = function()
                            return not MovementAlert.db.showTimeSpiral
                        end,
                    },
                    soundGroup = {
                        type = "group",
                        name = "",
                        order = 4,
                        inline = true,
                        args = {
                            timeSpiralPlaySound = {
                                order = 1,
                                type = "toggle",
                                name = "Play sound when time spiral becomes active",
                                get = function()
                                    return MovementAlert.db.timeSpiralPlaySound
                                end,
                                set = function(_, value)
                                    MovementAlert.db.timeSpiralPlaySound = value
                                    onChange()
                                end,
                            },
                            timeSpiralSound = {
                                order = 2,
                                type = "select",
                                dialogControl = "LSM30_Sound",
                                name = "Sound",
                                values = LSM:HashTable("sound"),
                                get = function()
                                    return MovementAlert.db.timeSpiralSound
                                end,
                                set = function(_, value)
                                    MovementAlert.db.timeSpiralSound = value
                                    onChange()
                                end,
                                disabled = function()
                                    return not MovementAlert.db.timeSpiralPlaySound
                                end,
                            },
                        },
                        disabled = function()
                            return not MovementAlert.db.showTimeSpiral
                        end,
                    },
                    ttsGroup = {
                        type = "group",
                        name = "",
                        order = 5,
                        inline = true,
                        args = {
                            timeSpiralPlayTTS = {
                                order = 1,
                                type = "toggle",
                                name = "Play TTS when time spiral becomes active",
                                get = function()
                                    return MovementAlert.db.timeSpiralPlayTTS
                                end,
                                set = function(_, value)
                                    MovementAlert.db.timeSpiralPlayTTS = value
                                    onChange()
                                end,
                            },
                            timeSpiralTTS = {
                                order = 2,
                                type = "input",
                                name = "TTS Message",
                                get = function()
                                    return MovementAlert.db.timeSpiralTTS
                                end,
                                set = function(_, value)
                                    MovementAlert.db.timeSpiralTTS = value
                                    onChange()
                                end,
                                disabled = function()
                                    return not MovementAlert.db.timeSpiralPlayTTS
                                end,
                            },
                            timeSpiralTTSPreview = XerionUIFeatures:TTSPreviewButton(3,
                                function() return MovementAlert.db.timeSpiralTTS end,
                                function() return MovementAlert.db.timeSpiralTTSVolume end,
                                function() return MovementAlert.db.timeSpiralTTSVoice end,
                                function() return not MovementAlert.db.timeSpiralPlayTTS end
                            ),
                            timeSpiralTTSVolume = {
                                order = 4,
                                type = "range",
                                width = 0.75,
                                min = 0,
                                max = 100,
                                step = 1,
                                name = "TTS Volume",
                                get = function()
                                    return MovementAlert.db.timeSpiralTTSVolume
                                end,
                                set = function(_, value)
                                    MovementAlert.db.timeSpiralTTSVolume = value
                                end,
                                disabled = function()
                                    return not MovementAlert.db.timeSpiralPlayTTS
                                end,
                            },
                            timeSpiralTTSVoice = XerionUIFeatures:TTSVoiceOption(5,
                                function() return MovementAlert.db.timeSpiralTTSVoice end,
                                function(_, value) MovementAlert.db.timeSpiralTTSVoice = value end,
                                function() return not MovementAlert.db.timeSpiralPlayTTS end
                            ),
                        },
                        disabled = function()
                            return not MovementAlert.db.showTimeSpiral or MovementAlert.db.timeSpiralPlaySound
                        end,
                    },
                }
            },
            timeSpiralSpells = {
                order = 25,
                type = "group",
                name = MovementAlert.pageTimeSpiralSpells,
                args = {
                    description = {
                        type = "description",
                        name = "The abilities whose proc counts as time spiral. Every class is listed, so a spec can be set up from any character\n\n",
                        width = "full",
                        order = 1,
                    },
                    classes = {
                        type = "group",
                        name = "",
                        order = 2,
                        inline = true,
                        args = createTimeSpiralSpellOptions(onChange),
                    },
                }
            }
        }
    }
end
