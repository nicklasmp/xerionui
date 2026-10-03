local addonName, XerionUIFeatures = ...
local LSM = XerionUIFeatures.LSM

local moduleName = "StealthIndicator"
local StealthIndicator = XerionUIFeatures:GetModule(moduleName)

function StealthIndicator:GetOptions(onChange)
    return {
        order = 2,
        type = "group",
        name = "Stealth Indicator",
        args = {
            preview = XerionUIFeatures:CreatePreviewOption(StealthIndicator),
            description = {
                type = "description",
                name = "Shows an indicator text when stealthed (not invisible) \n\n",
                width = "full",
                order = 1,
            },
            enable = {
                order = 2,
                type = "toggle",
                width = "full",
                name = "Enable",
                get = function()
                    return StealthIndicator.db.enabled
                end,
                set = function(_, value)
                    StealthIndicator.db.enabled = value
                    StealthIndicator:RefreshConfig()
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
                        name = "Display text",
                        get = function()
                            return StealthIndicator.db.displayText
                        end,
                        set = function(_, value)
                            StealthIndicator.db.displayText = value
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
                            local color = StealthIndicator.db.color
                            return color.r, color.g, color.b, color.a
                        end,
                        set = function(_, r, g, b, a)
                            StealthIndicator.db.color = {
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
                args = XerionUIFeatures:createFontOptions(function() return StealthIndicator.db.font end, function() 
                    onChange()
                end)
            },
        }
    }
end