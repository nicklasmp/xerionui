local addonName, XerionUIFeatures = ...

local moduleName = "HealerManaIndicator"
local HealerManaIndicator = XerionUIFeatures:GetModule(moduleName)

HealerManaIndicator.EUIPages = { "Display", "Filters" }

function HealerManaIndicator:GetEUIOptions(pageName)
    local function apply() XerionUIFeatures:ApplyModuleStyles(moduleName) end

    if pageName == "Filters" then
        return {
            name = "Healer Mana Indicator",
            rows = {
                {
                    pair = {
                        {
                            type = "toggle",
                            label = "Enable in dungeons",
                            disabled = function()
                                return not HealerManaIndicator.db.enabled
                            end,
                            get = function()
                                return HealerManaIndicator.db.enableInDungeons
                            end,
                            set = function(value)
                                HealerManaIndicator.db.enableInDungeons = value
                                apply()
                            end,
                        },
                        {
                            type = "toggle",
                            label = "Enable in raids",
                            disabled = function()
                                return not HealerManaIndicator.db.enabled
                            end,
                            get = function()
                                return HealerManaIndicator.db.enableInRaids
                            end,
                            set = function(value)
                                HealerManaIndicator.db.enableInRaids = value
                                apply()
                            end,
                        },
                    },
                },
            },
        }
    end

    local displayRow = {
        type = "color",
        label = "Display",
        hasAlpha = true,
        get = function()
            local color = HealerManaIndicator.db.color
            return color.r, color.g, color.b, color.a
        end,
        set = function(r, g, b, a)
            HealerManaIndicator.db.color = {
                r = r,
                g = g,
                b = b,
                a = a,
            }
            apply()
        end,
        cog = {
            title = "Growth",
            -- EllesmereUI's own direction settings ride a directions cog rather
            -- than the plain cogwheel.
            icon = XerionUIFeatures.EUI and XerionUIFeatures.EUI.DIRECTIONS_ICON,
            rows = {
                {
                    type = "toggle",
                    label = "Grow upwards",
                    get = function()
                        return HealerManaIndicator.db.growUpwards
                    end,
                    set = function(value)
                        HealerManaIndicator.db.growUpwards = value
                        apply()
                    end,
                },
            },
        },
    }

    return {
        name = "Healer Mana Indicator",
        rows = XerionUIFeatures:EUIFontRows(function() return HealerManaIndicator.db.font end, apply, nil, { displayRow }),
    }
end
