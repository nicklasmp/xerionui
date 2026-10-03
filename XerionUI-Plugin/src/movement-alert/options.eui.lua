local addonName, XerionUIFeatures = ...

local moduleName = "MovementAlert"
local MovementAlert = XerionUIFeatures:GetModule(moduleName)

MovementAlert.EUIPages = {
    MovementAlert.pageDisplay,
    MovementAlert.pageTrackedSpells,
    MovementAlert.pageTimeSpiral,
    MovementAlert.pageTimeSpiralSpells,
}

function MovementAlert:GetEUIOptions(pageName)
    local function apply() XerionUIFeatures:ApplyModuleStyles(moduleName) end

    if pageName == MovementAlert.pageTimeSpiralSpells then
        local function spiralOff()
            return not MovementAlert.db.showTimeSpiral
        end

        local rows = {}

        for _, class in ipairs(MovementAlert:GetTimeSpiralClasses()) do
            rows[#rows + 1] = {
                type = "multiselect",
                label = class.colorString .. class.className .. "|r",
                tooltip = "A proc of one of these is what the alert reports as time spiral",
                items = MovementAlert:GetTimeSpiralSpellItems(class),
                disabled = spiralOff,
                disabledTooltip = "Time spiral",
                get = function(spellId)
                    return MovementAlert:IsTimeSpiralSpellTracked(spellId)
                end,
                set = function(spellId, value)
                    MovementAlert:SetTimeSpiralSpellTracked(spellId, value)
                    apply()
                end,
            }
        end

        return {
            name = "Movement Alert",
            rows = rows,
        }
    end

    if pageName == MovementAlert.pageTrackedSpells then
        local rows = {}

        for _, class in ipairs(MovementAlert:GetTrackedSpecs()) do
            rows[#rows + 1] = { header = class.colorString .. class.className .. "|r" }

            for _, spec in ipairs(class.specs) do
                rows[#rows + 1] = {
                    type = "multiselect",
                    label = spec.specName,
                    tooltip = "The alert shows the first of these abilities this spec has, so their order is the priority",
                    items = MovementAlert:GetTrackedSpellItems(spec.specId),
                    get = function(spellId)
                        return MovementAlert:IsSpellTracked(spec.specId, spellId)
                    end,
                    set = function(spellId, value)
                        MovementAlert:SetSpellTracked(spec.specId, spellId, value)
                        apply()
                    end,
                }
            end
        end

        return {
            name = "Movement Alert",
            rows = rows,
        }
    end

    if pageName == MovementAlert.pageTimeSpiral then
        local function spiralOff()
            return not MovementAlert.db.showTimeSpiral
        end

        return {
            name = "Movement Alert",
            rows = {
                {
                    pair = {
                        {
                            type = "toggle",
                            label = "Enable",
                            refresh = true,
                            get = function()
                                return MovementAlert.db.showTimeSpiral
                            end,
                            set = function(value)
                                MovementAlert.db.showTimeSpiral = value
                                apply()
                            end,
                        },
                        {
                            type = "color",
                            label = "Display",
                            hasAlpha = true,
                            disabled = spiralOff,
                            disabledTooltip = "Time spiral",
                            get = function()
                                local color = MovementAlert.db.timeSpiralColor
                                return color.r, color.g, color.b, color.a
                            end,
                            set = function(r, g, b, a)
                                MovementAlert.db.timeSpiralColor = {
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
                                        disabled = spiralOff,
                                        disabledTooltip = "Time spiral",
                                        get = function()
                                            return MovementAlert.db.timeSpiralText or ""
                                        end,
                                        set = function(value)
                                            MovementAlert.db.timeSpiralText = value
                                            apply()
                                        end,
                                    },
                                },
                            },
                        },
                    },
                },
                {
                    header = "Sound",
                },
                {
                    type = "toggle",
                    label = "Play sound when time spiral becomes active",
                    refresh = true,
                    disabled = spiralOff,
                    disabledTooltip = "Time spiral",
                    get = function()
                        return MovementAlert.db.timeSpiralPlaySound
                    end,
                    set = function(value)
                        MovementAlert.db.timeSpiralPlaySound = value
                        apply()
                    end,
                },
                XerionUIFeatures:EUISoundRow({
                    disabled = function()
                        return spiralOff() or not MovementAlert.db.timeSpiralPlaySound
                    end,
                    get = function()
                        return MovementAlert.db.timeSpiralSound
                    end,
                    set = function(value)
                        MovementAlert.db.timeSpiralSound = value
                        apply()
                    end,
                }),
                {
                    header = "Text-to-Speech",
                },
                {
                    type = "toggle",
                    label = "Play TTS when time spiral becomes active",
                    refresh = true,
                    disabled = function()
                        return spiralOff() or MovementAlert.db.timeSpiralPlaySound
                    end,
                    disabledTooltip = "Time spiral",
                    get = function()
                        return MovementAlert.db.timeSpiralPlayTTS
                    end,
                    set = function(value)
                        MovementAlert.db.timeSpiralPlayTTS = value
                        apply()
                    end,
                },
                XerionUIFeatures:EUITTSRow({
                    disabled = function()
                        return spiralOff() or MovementAlert.db.timeSpiralPlaySound or not MovementAlert.db.timeSpiralPlayTTS
                    end,
                    get = function()
                        return MovementAlert.db.timeSpiralTTS
                    end,
                    set = function(value)
                        MovementAlert.db.timeSpiralTTS = value
                        apply()
                    end,
                    volume = {
                        get = function() return MovementAlert.db.timeSpiralTTSVolume end,
                        set = function(value) MovementAlert.db.timeSpiralTTSVolume = value end,
                    },
                    voice = {
                        get = function() return MovementAlert.db.timeSpiralTTSVoice end,
                        set = function(value) MovementAlert.db.timeSpiralTTSVoice = value end,
                    },
                }),
            },
        }
    end

    -- pageDisplay, and the fallback for any caller that passes no page name
    local displayRow = {
        type = "color",
        label = "Display",
        hasAlpha = true,
        get = function()
            local color = MovementAlert.db.color
            return color.r, color.g, color.b, color.a
        end,
        set = function(r, g, b, a)
            MovementAlert.db.color = {
                r = r,
                g = g,
                b = b,
                a = a,
            }
            apply()
        end,
        cog = {
            title = "Timer Text",
            rows = {
                {
                    type = "slider",
                    label = "Decimal precision",
                    min = 0,
                    max = 1,
                    step = 1,
                    get = function()
                        return MovementAlert.db.precision
                    end,
                    set = function(value)
                        MovementAlert.db.precision = value
                        apply()
                    end,
                },
            },
        },
    }

    return {
        name = "Movement Alert",
        rows = XerionUIFeatures:EUIFontRows(function() return MovementAlert.db.font end, apply, nil, { displayRow }),
    }
end
