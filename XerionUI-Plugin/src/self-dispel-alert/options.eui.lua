local addonName, XerionUIFeatures = ...

local moduleName = "SelfDispelAlert"
local SelfDispelAlert = XerionUIFeatures:GetModule(moduleName)

function SelfDispelAlert:GetEUIOptions()
    local function apply() XerionUIFeatures:ApplyModuleStyles(moduleName) end

    local displayRow = {
        type = "color",
        label = "Display",
        hasAlpha = true,
        get = function()
            local color = SelfDispelAlert.db.color
            return color.r, color.g, color.b, color.a
        end,
        set = function(r, g, b, a)
            SelfDispelAlert.db.color = {
                r = r,
                g = g,
                b = b,
                a = a,
            }
            apply()
        end,
        cog = {
            title = "Alert Text",
            rows = {
                {
                    type = "toggle",
                    label = "Show text",
                    tooltip = "The reminder text, next to the icon",
                    refresh = true,
                    get = function()
                        return SelfDispelAlert.db.showText
                    end,
                    set = function(value)
                        SelfDispelAlert.db.showText = value
                        apply()
                    end,
                },
                {
                    type = "input",
                    label = "Text",
                    tooltip = "Leave this empty to use the name of the dispel that answers each debuff",
                    width = 120,
                    disabled = function()
                        return not SelfDispelAlert.db.showText
                    end,
                    get = function()
                        return SelfDispelAlert.db.displayText or ""
                    end,
                    set = function(value)
                        SelfDispelAlert.db.displayText = value
                        apply()
                    end,
                },
            },
        },
    }

    local iconRow = {
        type = "toggle",
        label = "Show icon",
        tooltip = "The dispel's own icon, to the left of the text",
        refresh = true,
        get = function()
            return SelfDispelAlert.db.showIcon
        end,
        set = function(value)
            SelfDispelAlert.db.showIcon = value
            apply()
        end,
        cog = {
            title = "Icon",
            icon = XerionUIFeatures.EUI and XerionUIFeatures.EUI.RESIZE_ICON,
            disabled = function()
                return not SelfDispelAlert.db.showIcon
            end,
            disabledTooltip = "Show icon has to be on before its size means anything.",
            rows = {
                {
                    type = "slider",
                    label = "Size",
                    min = 8,
                    max = 120,
                    step = 1,
                    get = function()
                        return SelfDispelAlert.db.iconSize
                    end,
                    set = function(value)
                        SelfDispelAlert.db.iconSize = value
                        apply()
                    end,
                },
            },
        },
    }

    local cooldownRow = {
        type = "toggle",
        label = "Hide while on cooldown",
        tooltip = "Keeps the alert quiet while the dispel is not something you could press anyway",
        get = function()
            return SelfDispelAlert.db.hideOnCooldown
        end,
        set = function(value)
            SelfDispelAlert.db.hideOnCooldown = value
            SelfDispelAlert:UpdateVisibility()
            apply()
        end,
    }

    local raidRow = {
        type = "toggle",
        label = "Disable in raids",
        tooltip = "Keeps the alert quiet inside raid instances",
        get = function()
            return SelfDispelAlert.db.disableInRaid
        end,
        set = function(value)
            SelfDispelAlert.db.disableInRaid = value
            SelfDispelAlert:UpdateVisibility()
            apply()
        end,
    }

    local sourcesRow = {
        type = "multiselect",
        label = "Dispels",
        tooltip = "Which dispels the alert may ask for. Each debuff type follows the first ticked dispel the character actually has that can remove it",
        items = SelfDispelAlert:GetSourceItems(),
        get = function(key)
            return SelfDispelAlert:IsSourceEnabled(key)
        end,
        set = function(key, value)
            SelfDispelAlert:SetSourceEnabled(key, value)
            SelfDispelAlert:UpdateVisibility()
            apply()
        end,
    }

    return {
        name = "Self Dispel Alert",
        rows = XerionUIFeatures:EUIFontRows(function() return SelfDispelAlert.db.font end, apply, nil, { displayRow, iconRow, cooldownRow, raidRow, sourcesRow }),
    }
end
