local addonName, XerionUIFeatures = ...
local LSM = XerionUIFeatures.LSM

local moduleName = "NoTargetIndicator"
local NoTargetIndicator = XerionUIFeatures:GetModule(moduleName)

function NoTargetIndicator:GetOptions(onChange)
    return {
        order = 2,
        type = "group",
        name = "No Target Indicator",
        args = {
            preview = XerionUIFeatures:CreatePreviewOption(NoTargetIndicator),
            description = {
                type = "description",
                name = "Shows an indicator text when player doesn't have a target when in combat \n\n",
                width = "full",
                order = 1,
            },
            enable = {
                order = 2,
                type = "toggle",
                width = "full",
                name = "Enable",
                get = function()
                    return NoTargetIndicator.db.enabled
                end,
                set = function(_, value)
                    NoTargetIndicator.db.enabled = value
                    NoTargetIndicator:RefreshConfig()
                end
            },
            friendlyisValidTarget = {
                order = 3,
                type = "toggle",
                width = "full",
                name = "Include friendly target as valid target",
                get = function()
                    return NoTargetIndicator.db.friendlyisValidTarget
                end,
                set = function(_, value)
                    NoTargetIndicator.db.friendlyisValidTarget = value
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
                            return NoTargetIndicator.db.displayText
                        end,
                        set = function(_, value)
                            NoTargetIndicator.db.displayText = value
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
                            local color = NoTargetIndicator.db.color
                            return color.r, color.g, color.b, color.a
                        end,
                        set = function(_, r, g, b, a)
                            NoTargetIndicator.db.color = {
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
                args = XerionUIFeatures:createFontOptions(function() return NoTargetIndicator.db.font end, function() 
                    onChange()
                end)
            },
        }
    }
end