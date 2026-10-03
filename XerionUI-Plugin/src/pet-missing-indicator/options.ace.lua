local addonName, XerionUIFeatures = ...
local LSM = XerionUIFeatures.LSM

local moduleName = "PetMissingIndicator"
local PetMissingIndicator = XerionUIFeatures:GetModule(moduleName)

function PetMissingIndicator:GetOptions(onChange)
    return {
        order = 2,
        type = "group",
        name = "Pet Missing",
        args = {
            preview = XerionUIFeatures:CreatePreviewOption(PetMissingIndicator),
            description = {
                type = "description",
                name =  "Displays a text when you are a pet spec and your pet is missing\n\n",
                width = "full",
                order = 1,
            },
            enable = {
                order = 2,
                type = "toggle",
                width = "full",
                name = "Enable",
                get = function(info)
                    return PetMissingIndicator.db.enabled
                end,
                set = function(info, value)
                    PetMissingIndicator.db.enabled = value
                    PetMissingIndicator:RefreshConfig()
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
                            return PetMissingIndicator.db.displayText
                        end,
                        set = function(_, value)
                            PetMissingIndicator.db.displayText = value
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
                            local color = PetMissingIndicator.db.color
                            return color.r, color.g, color.b, color.a
                        end,
                        set = function(_, r, g, b, a)
                            PetMissingIndicator.db.color = {
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
                args = XerionUIFeatures:createFontOptions(function() return PetMissingIndicator.db.font end, function() 
                    onChange()
                end)
            }
        }
    }
end