local addonName, XerionUIFeatures = ...

local moduleName = "RepairIndicator"
local RepairIndicator = XerionUIFeatures:GetModule(moduleName)

function RepairIndicator:GetEUIOptions()
    local function apply() XerionUIFeatures:ApplyModuleStyles(moduleName) end

    local displayRow = {
        type = "color",
        label = "Display",
        hasAlpha = true,
        get = function()
            local color = RepairIndicator.db.color
            return color.r, color.g, color.b, color.a
        end,
        set = function(r, g, b, a)
            RepairIndicator.db.color = {
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
                        return RepairIndicator.db.displayText or ""
                    end,
                    set = function(value)
                        RepairIndicator.db.displayText = value
                        apply()
                    end,
                },
            },
        },
    }

    return {
        name = "Repair Indicator",
        rows = XerionUIFeatures:EUIFontRows(function() return RepairIndicator.db.font end, apply, nil, { displayRow }),
    }
end
