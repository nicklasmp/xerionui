local addonName, XerionUIFeatures = ...

local moduleName = "SelfDispelAlert"
local SelfDispelAlert = XerionUIFeatures:GetModule(moduleName)

local function sourceValues()
    local values = {}
    local order = {}

    for index, item in ipairs(SelfDispelAlert:GetSourceItems()) do
        values[item.key] = item.label
        order[index] = item.key
    end

    return values, order
end

function SelfDispelAlert:GetOptions(onChange)
    local values, order = sourceValues()

    return {
        order = 2,
        type = "group",
        name = "Self Dispel Alert",
        args = {
            preview = XerionUIFeatures:CreatePreviewOption(SelfDispelAlert),
            description = {
                type = "description",
                name = "Shows a reminder to press your self dispel while you carry a debuff it can remove, per type: class dispels first, Feign Death with Emergency Salve on hunters, and the dwarf racials for whatever is left\n\n",
                width = "full",
                order = 1,
            },
            enable = {
                order = 2,
                type = "toggle",
                width = "full",
                name = "Enable",
                get = function()
                    return SelfDispelAlert.db.enabled
                end,
                set = function(_, value)
                    SelfDispelAlert.db.enabled = value
                    SelfDispelAlert:RefreshConfig()
                end
            },
            displaySettings = {
                type = "group",
                name = "",
                order = 4,
                inline = true,
                args = {
                    showText = {
                        order = 1,
                        type = "toggle",
                        width = 0.75,
                        name = "Show text",
                        desc = "The reminder text, next to the icon",
                        get = function()
                            return SelfDispelAlert.db.showText
                        end,
                        set = function(_, value)
                            SelfDispelAlert.db.showText = value
                            onChange()
                        end
                    },
                    displayText = {
                        order = 2,
                        type = "input",
                        name = "Display text",
                        desc = "Leave this empty to use the name of the dispel that answers each debuff",
                        disabled = function()
                            return not SelfDispelAlert.db.showText
                        end,
                        get = function()
                            return SelfDispelAlert.db.displayText
                        end,
                        set = function(_, value)
                            SelfDispelAlert.db.displayText = value
                            onChange()
                        end
                    },
                    color = {
                        order = 3,
                        type = "color",
                        name = "Color",
                        width = 0.4,
                        hasAlpha = true,
                        get = function()
                            local color = SelfDispelAlert.db.color
                            return color.r, color.g, color.b, color.a
                        end,
                        set = function(_, r, g, b, a)
                            SelfDispelAlert.db.color = {
                                r = r,
                                g = g,
                                b = b,
                                a = a
                            }
                            onChange()
                        end
                    },
                    spacer = {
                        order = 4,
                        type = "description",
                        name = "",
                        width = "full",
                    },
                    showIcon = {
                        order = 5,
                        type = "toggle",
                        width = 0.75,
                        name = "Show icon",
                        desc = "The dispel's own icon, to the left of the text",
                        get = function()
                            return SelfDispelAlert.db.showIcon
                        end,
                        set = function(_, value)
                            SelfDispelAlert.db.showIcon = value
                            onChange()
                        end
                    },
                    iconSize = {
                        order = 6,
                        type = "range",
                        width = 0.75,
                        name = "Icon size",
                        min = 8,
                        max = 120,
                        step = 1,
                        disabled = function()
                            return not SelfDispelAlert.db.showIcon
                        end,
                        get = function()
                            return SelfDispelAlert.db.iconSize
                        end,
                        set = function(_, value)
                            SelfDispelAlert.db.iconSize = value
                            onChange()
                        end
                    },
                    hideOnCooldown = {
                        order = 7,
                        type = "toggle",
                        width = "full",
                        name = "Hide while on cooldown",
                        desc = "Keeps the alert quiet while the dispel is not something you could press anyway",
                        get = function()
                            return SelfDispelAlert.db.hideOnCooldown
                        end,
                        set = function(_, value)
                            SelfDispelAlert.db.hideOnCooldown = value
                            SelfDispelAlert:UpdateVisibility()
                            onChange()
                        end
                    },
                    disableInRaid = {
                        order = 8,
                        type = "toggle",
                        width = "full",
                        name = "Disable in raids",
                        desc = "Keeps the alert quiet inside raid instances",
                        get = function()
                            return SelfDispelAlert.db.disableInRaid
                        end,
                        set = function(_, value)
                            SelfDispelAlert.db.disableInRaid = value
                            SelfDispelAlert:UpdateVisibility()
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
                args = XerionUIFeatures:createFontOptions(function() return SelfDispelAlert.db.font end, function()
                    onChange()
                end)
            },
            sources = {
                type = "group",
                name = "Dispels",
                order = 10,
                inline = true,
                args = {
                    description = {
                        type = "description",
                        name = "Which dispels the alert may ask for. Each debuff type follows the first ticked dispel the character actually has that can remove it\n\n",
                        width = "full",
                        order = 1,
                    },
                    enabledSources = {
                        order = 2,
                        type = "multiselect",
                        -- `arg` is the order ItruliaMultiselect lists the values in.
                        dialogControl = "ItruliaMultiselect",
                        arg = order,
                        name = "Dispels",
                        values = values,
                        get = function(_, key)
                            return SelfDispelAlert:IsSourceEnabled(key)
                        end,
                        set = function(_, key, value)
                            SelfDispelAlert:SetSourceEnabled(key, value)
                            SelfDispelAlert:UpdateVisibility()
                            onChange()
                        end,
                    },
                }
            },
        }
    }
end
