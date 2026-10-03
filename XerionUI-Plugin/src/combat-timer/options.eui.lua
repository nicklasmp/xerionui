local addonName, XerionUIFeatures = ...

local moduleName = "CombatTimer"
local CombatTimer = XerionUIFeatures:GetModule(moduleName)

function CombatTimer:GetEUIOptions()
    local function apply() XerionUIFeatures:ApplyModuleStyles(moduleName) end

    local displayRow = {
        type = "color",
        label = "Display",
        hasAlpha = true,
        get = function()
            local color = CombatTimer.db.color
            return color.r, color.g, color.b, color.a
        end,
        set = function(r, g, b, a)
            CombatTimer.db.color = {
                r = r,
                g = g,
                b = b,
                a = a,
            }
            apply()
        end,
        cog = {
            title = "Timer Text",
            rows = {
                {
                    type = "select",
                    label = "Time format",
                    values = {
                        SECONDS = CombatTimer.timeFormats.SECONDS.display,
                        SECONDS_BRACKET = CombatTimer.timeFormats.SECONDS_BRACKET.display,
                        CLOCK = CombatTimer.timeFormats.CLOCK.display,
                        CLOCK_BRACKET = CombatTimer.timeFormats.CLOCK_BRACKET.display,
                    },
                    get = function()
                        return CombatTimer.db.timeFormat
                    end,
                    set = function(value)
                        CombatTimer.db.timeFormat = value
                        apply()
                    end,
                },
            },
        },
    }

    return {
        name = "Combat Timer",
        rows = XerionUIFeatures:EUIFontRows(function() return CombatTimer.db.font end, apply, nil, { displayRow }),
    }
end
