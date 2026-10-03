local addonName, XerionUIFeatures = ...

local moduleName = "StanceAlert"
local StanceAlert = XerionUIFeatures:GetModule(moduleName)

function StanceAlert:GetEUIOptions()
    local function apply() XerionUIFeatures:ApplyModuleStyles(moduleName) end

    local displayRow = {
        type = "color",
        label = "Display",
        hasAlpha = true,
        get = function()
            local color = StanceAlert.db.color
            return color.r, color.g, color.b, color.a
        end,
        set = function(r, g, b, a)
            StanceAlert.db.color = {
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
                        return StanceAlert.db.displayText or ""
                    end,
                    set = function(value)
                        StanceAlert.db.displayText = value
                        apply()
                    end,
                },
            },
        },
    }

    return {
        name = "Stance Alert",
        rows = XerionUIFeatures:EUIFontRows(function() return StanceAlert.db.font end, apply, nil, { displayRow }),
    }
end
