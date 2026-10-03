local addonName, XerionUIFeatures = ...
local LSM = XerionUIFeatures.LSM

local moduleName = "MeleeIndicator"
local MeleeIndicator = XerionUIFeatures:GetModule(moduleName)

function MeleeIndicator:GetOptions(onChange)
    return {
        order = 2,
        type = "group",
        name = "Melee Indicator",
        args = {
            preview = XerionUIFeatures:CreatePreviewOption(MeleeIndicator),
            description = {
                type = "description",
                name =  "Creates an indicator that shows up when you not in melee range as a melee spec\n\n",
                width = "full",
                order = 1,
            },
            enable = {
                order = 2,
                type = "toggle",
                width = "full",
                name = "Enable",
                get = function(info) 
                    return MeleeIndicator.db.enabled
                end,
                set = function(info, value)
                    MeleeIndicator.db.enabled = value
                    MeleeIndicator:RefreshConfig()
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
                            return MeleeIndicator.db.displayText
                        end,
                        set = function(_, value)
                            MeleeIndicator.db.displayText = value
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
                            local color = MeleeIndicator.db.color
                            return color.r, color.g, color.b, color.a
                        end,
                        set = function(_, r, g, b, a)
                            MeleeIndicator.db.color = {
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
                args = XerionUIFeatures:createFontOptions(function() return MeleeIndicator.db.font end, function() 
                    onChange()
                end)
            },
        }
    }
end