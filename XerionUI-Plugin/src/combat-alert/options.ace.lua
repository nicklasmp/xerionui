local addonName, XerionUIFeatures = ...
local LSM = XerionUIFeatures.LSM

local moduleName = "CombatAlert"
local CombatAlert = XerionUIFeatures:GetModule(moduleName)

function CombatAlert:GetOptions(onChange)
    return {
        order = 2,
        type = "group",
        name = "Combat Alert",
        args = {
            preview = XerionUIFeatures:CreatePreviewOption(CombatAlert),
            description = {
                type = "description",
                name = "Shows an alert when entering or leaving combat \n\n",
                width = "full",
                order = 1,
            },
            enable = {
                order = 2,
                type = "toggle",
                width = "full",
                name = "Enable",
                get = function()
                    return CombatAlert.db.enabled
                end,
                set = function(_, value)
                    CombatAlert.db.enabled = value
                    CombatAlert:RefreshConfig()
                end
            },
            displaySettings = {
                type = "group",
                name = "",
                order = 4,
                inline = true,
                args = {
                    combatStartsText = {
                        order = 1,
                        type = "input",
                        name = "Combat starts text",
                        get = function()
                            return CombatAlert.db.combatStartsText
                        end,
                        set = function(_, value)
                            CombatAlert.db.combatStartsText = value
                            onChange()
                        end
                    },
                    combatStartsColor = {
                        order = 2,
                        type = "color",
                        name = "Combat starts color",
                        hasAlpha = true,
                        get = function()
                            local color = CombatAlert.db.combatStartsColor
                            return color.r, color.g, color.b, color.a
                        end,
                        set = function(_, r, g, b, a)
                            CombatAlert.db.combatStartsColor = {
                                r = r,
                                g = g,
                                b = b,
                                a = a
                            }
                            onChange()
                        end
                    },
                    spacer = {
                        type = "description",
                        name = "",
                        width = "full",
                        order = 3,
                    },
                    combatEndsText = {
                        order = 3,
                        type = "input",
                        name = "Combat ends text",
                        get = function()
                            return CombatAlert.db.combatEndsText
                        end,
                        set = function(_, value)
                            CombatAlert.db.combatEndsText = value
                            onChange()
                        end
                    },
                    combatEndsColor = {
                        order = 4,
                        type = "color",
                        name = "Combat ends color",
                        hasAlpha = true,
                        get = function()
                            local color = CombatAlert.db.combatEndsColor
                            return color.r, color.g, color.b, color.a
                        end,
                        set = function(_, r, g, b, a)
                            CombatAlert.db.combatEndsColor = {
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
                args = XerionUIFeatures:createFontOptions(function() return CombatAlert.db.font end, function() 
                    onChange()
                end)
            },
        }
    }
end