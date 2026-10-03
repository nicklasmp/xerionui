local addonName, XerionUIFeatures = ...
local LSM = XerionUIFeatures.LSM

local moduleName = "CharacterIndicator"
local CharacterIndicator = XerionUIFeatures:GetModule(moduleName)

function CharacterIndicator:GetOptions(onChange)
    return {
        order = 2,
        type = "group",
        name = "Character Indicator",
        args = {
            preview = XerionUIFeatures:CreatePreviewOption(CharacterIndicator),
            description = {
                type = "description",
                name =  "Creates an indicator that is always on during combat indicating where you are\n\n",
                width = "full",
                order = 1,
            },
            enable = {
                order = 2,
                type = "toggle",
                width = "full",
                name = "Enable",
                get = function(info) 
                    return CharacterIndicator.db.enabled
                end,
                set = function(info, value)
                    CharacterIndicator.db.enabled = value
                    CharacterIndicator:RefreshConfig()
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
                            return CharacterIndicator.db.displayText
                        end,
                        set = function(_, value)
                            CharacterIndicator.db.displayText = value
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
                            local color = CharacterIndicator.db.color
                            return color.r, color.g, color.b, color.a
                        end,
                        set = function(_, r, g, b, a)
                            CharacterIndicator.db.color = {
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
                args = XerionUIFeatures:createFontOptions(function() return CharacterIndicator.db.font end, function() 
                    onChange()
                end)
            },
        }
    }
end