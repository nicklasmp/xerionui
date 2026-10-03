local addonName, XerionUIFeatures = ...

local moduleName = "StealthIndicator"
local StealthIndicator = XerionUIFeatures:GetModule(moduleName)

function StealthIndicator:GetEUIOptions()
    local function apply() XerionUIFeatures:ApplyModuleStyles(moduleName) end

    local displayRow = {
        type = "color",
        label = "Display",
        hasAlpha = true,
        get = function()
            local color = StealthIndicator.db.color
            return color.r, color.g, color.b, color.a
        end,
        set = function(r, g, b, a)
            StealthIndicator.db.color = {
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
                    type = "input",
                    label = "Text",
                    width = 120,
                    get = function()
                        return StealthIndicator.db.displayText or ""
                    end,
                    set = function(value)
                        StealthIndicator.db.displayText = value
                        apply()
                    end,
                },
            },
        },
    }

    return {
        name = "Stealth Indicator",
        rows = XerionUIFeatures:EUIFontRows(function() return StealthIndicator.db.font end, apply, nil, { displayRow }),
    }
end
