local addonName, XerionUIFeatures = ...
local LSM = XerionUIFeatures.LSM

local moduleName = "RepairIndicator"
local RepairIndicator = XerionUIFeatures:GetModule(moduleName)

function RepairIndicator:GetOptions(onChange)
    return {
        order = 2,
        type = "group",
        name = "Repair Indicator",
        args = {
            preview = XerionUIFeatures:CreatePreviewOption(RepairIndicator),
            description = {
                type = "description",
                name =  "Displays a text when one of your items is broken or about to be\n\n",
                width = "full",
                order = 1,
            },
            enable = {
                order = 2,
                type = "toggle",
                width = "full",
                name = "Enable",
                get = function(info)
                    return RepairIndicator.db.enabled
                end,
                set = function(info, value)
                    RepairIndicator.db.enabled = value
                    RepairIndicator:RefreshConfig()
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
                            return RepairIndicator.db.displayText
                        end,
                        set = function(_, value)
                            RepairIndicator.db.displayText = value
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
                            local color = RepairIndicator.db.color
                            return color.r, color.g, color.b, color.a
                        end,
                        set = function(_, r, g, b, a)
                            RepairIndicator.db.color = {
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
                args = XerionUIFeatures:createFontOptions(function() return RepairIndicator.db.font end, function() 
                    onChange()
                end)
            }
        }
    }
end