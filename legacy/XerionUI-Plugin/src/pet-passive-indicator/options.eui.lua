local addonName, XerionUIFeatures = ...

local moduleName = "PetPassiveIndicator"
local PetPassiveIndicator = XerionUIFeatures:GetModule(moduleName)

function PetPassiveIndicator:GetEUIOptions()
    local function apply() XerionUIFeatures:ApplyModuleStyles(moduleName) end

    -- The row's own Enable, because the sidebar switch on a combined row sets both
    -- pet indicators at once. It leads the font settings alongside the colour, so
    -- the page opens on one row of the two things per indicator worth reaching for.
    local enableRow = {
        type = "toggle",
        label = "Enable",
        get = function()
            return PetPassiveIndicator.db.enabled
        end,
        set = function(value)
            PetPassiveIndicator.db.enabled = value
            PetPassiveIndicator:RefreshConfig()
        end,
    }

    local displayRow = {
        type = "color",
        label = "Display",
        hasAlpha = true,
        get = function()
            local color = PetPassiveIndicator.db.color
            return color.r, color.g, color.b, color.a
        end,
        set = function(r, g, b, a)
            PetPassiveIndicator.db.color = {
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
                        return PetPassiveIndicator.db.displayText or ""
                    end,
                    set = function(value)
                        PetPassiveIndicator.db.displayText = value
                        apply()
                    end,
                },
            },
        },
    }

    return {
        name = "Pet Passive",
        rows = XerionUIFeatures:EUIFontRows(function() return PetPassiveIndicator.db.font end, apply, nil, { enableRow, displayRow }),
    }
end
