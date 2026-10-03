local addonName, XerionUIFeatures = ...
local LSM = XerionUIFeatures.LSM

local moduleName = "CombatTimer"
local CombatTimer = XerionUIFeatures:GetModule(moduleName)

function CombatTimer:GetOptions(onChange)
    return {
        order = 2,
        type = "group",
        name = "Combat Timer",
        args = {
            preview = XerionUIFeatures:CreatePreviewOption(CombatTimer),
            description = {
                type = "description",
                name = "Shows a combat timer \n\n",
                width = "full",
                order = 1,
            },
            enable = {
                order = 2,
                type = "toggle",
                width = "full",
                name = "Enable",
                get = function()
                    return CombatTimer.db.enabled
                end,
                set = function(_, value)
                    CombatTimer.db.enabled = value
                    CombatTimer:RefreshConfig()
                end
            },
            displaySettings = {
                type = "group",
                name = "",
                order = 4,
                inline = true,
                args = {
                    timeformat = {
                        order = 1,
                        type = "select",
                        name = "Time format",
                        values = {
                            SECONDS = CombatTimer.timeFormats.SECONDS.display,
                            SECONDS_BRACKET = CombatTimer.timeFormats.SECONDS_BRACKET.display,
                            CLOCK = CombatTimer.timeFormats.CLOCK.display,
                            CLOCK_BRACKET = CombatTimer.timeFormats.CLOCK_BRACKET.display,
                        },
                        get = function()
                            return CombatTimer.db.timeFormat
                        end,
                        set = function(_, value)
                            CombatTimer.db.timeFormat = value
                            onChange()
                        end,
                    },
                    color = {
                        order = 2,
                        type = "color",
                        name = "Combat starts color",
                        hasAlpha = true,
                        get = function()
                            local color = CombatTimer.db.color
                            return color.r, color.g, color.b, color.a
                        end,
                        set = function(_, r, g, b, a)
                            CombatTimer.db.color = {
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
                args = XerionUIFeatures:createFontOptions(function() return CombatTimer.db.font end, function() 
                    onChange()
                end)
            },
        }
    }
end