local addonName, XerionUIFeatures = ...

local moduleName = "CombatAlert"
local CombatAlert = XerionUIFeatures:GetModule(moduleName)

function CombatAlert:GetEUIOptions()
    local function apply() XerionUIFeatures:ApplyModuleStyles(moduleName) end

    -- Both alerts are a colour swatch with their text on a cogwheel, leading the
    -- font settings so the two share a row there instead of taking a full-width
    -- line each. The inputs never return nil: the cog popup's refresh feeds them
    -- straight into an EditBox.
    local startsRow = {
        type = "color",
        label = "Combat starts",
        hasAlpha = true,
        get = function()
            local color = CombatAlert.db.combatStartsColor
            return color.r, color.g, color.b, color.a
        end,
        set = function(r, g, b, a)
            CombatAlert.db.combatStartsColor = {
                r = r,
                g = g,
                b = b,
                a = a,
            }
            apply()
        end,
        cog = {
            title = "Combat Starts",
            rows = {
                {
                    type = "input",
                    label = "Text",
                    width = 120,
                    get = function()
                        return CombatAlert.db.combatStartsText or ""
                    end,
                    set = function(value)
                        CombatAlert.db.combatStartsText = value
                        apply()
                    end,
                },
            },
        },
    }

    local endsRow = {
        type = "color",
        label = "Combat ends",
        hasAlpha = true,
        get = function()
            local color = CombatAlert.db.combatEndsColor
            return color.r, color.g, color.b, color.a
        end,
        set = function(r, g, b, a)
            CombatAlert.db.combatEndsColor = {
                r = r,
                g = g,
                b = b,
                a = a,
            }
            apply()
        end,
        cog = {
            title = "Combat Ends",
            rows = {
                {
                    type = "input",
                    label = "Text",
                    width = 120,
                    get = function()
                        return CombatAlert.db.combatEndsText or ""
                    end,
                    set = function(value)
                        CombatAlert.db.combatEndsText = value
                        apply()
                    end,
                },
            },
        },
    }

    return {
        name = "Combat Alert",
        rows = XerionUIFeatures:EUIFontRows(function() return CombatAlert.db.font end, apply, nil, { startsRow, endsRow }),
    }
end
