local addonName, XerionUIFeatures = ...
local LSM = XerionUIFeatures.LSM

local moduleName = "PetPassiveIndicator"
local PetPassiveIndicator = XerionUIFeatures:GetModule(moduleName)

function PetPassiveIndicator:GetOptions(onChange)
    return {
        order = 2,
        type = "group",
        name = "Pet Passive",
        args = {
            preview = XerionUIFeatures:CreatePreviewOption(PetPassiveIndicator),
            description = {
                type = "description",
                name =  "Displays a text when you have a pet and it's set to passive\n\n",
                width = "full",
                order = 1,
            },
            enable = {
                order = 2,
                type = "toggle",
                width = "full",
                name = "Enable",
                get = function(info)
                    return PetPassiveIndicator.db.enabled
                end,
                set = function(info, value)
                    PetPassiveIndicator.db.enabled = value
                    PetPassiveIndicator:RefreshConfig()
                end
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
                            return PetPassiveIndicator.db.displayText
                        end,
                        set = function(_, value)
                            PetPassiveIndicator.db.displayText = value
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
                            local color = PetPassiveIndicator.db.color
                            return color.r, color.g, color.b, color.a
                        end,
                        set = function(_, r, g, b, a)
                            PetPassiveIndicator.db.color = {
                                r = r,
                                g = g,
                                b = b,
                                a = a
                            }
                            onChange()
                        end
                    }
                }
            },
            fontSettings = {
                type = "group",
                name = "",
                order = 5,
                inline = true,
                args = XerionUIFeatures:createFontOptions(function() return PetPassiveIndicator.db.font end, function() 
                    onChange()
                end)
            }
        }
    }
end