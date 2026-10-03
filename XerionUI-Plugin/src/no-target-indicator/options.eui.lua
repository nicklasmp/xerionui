local addonName, XerionUIFeatures = ...

local moduleName = "NoTargetIndicator"
local NoTargetIndicator = XerionUIFeatures:GetModule(moduleName)

function NoTargetIndicator:GetEUIOptions()
    local function apply() XerionUIFeatures:ApplyModuleStyles(moduleName) end

    local displayRow = {
        type = "color",
        label = "Display",
        hasAlpha = true,
        get = function()
            local color = NoTargetIndicator.db.color
            return color.r, color.g, color.b, color.a
        end,
        set = function(r, g, b, a)
            NoTargetIndicator.db.color = {
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
                        return NoTargetIndicator.db.displayText or ""
                    end,
                    set = function(value)
                        NoTargetIndicator.db.displayText = value
                        apply()
                    end,
                },
            },
        },
    }

    -- The friendly-target rule keeps a full-width row of its own: its label is far
    -- too long for a half, and it is a behaviour setting rather than one of the
    -- appearance pairs below it.
    local rows = {
        {
            type = "toggle",
            label = "Include friendly target as valid target",
            get = function()
                return NoTargetIndicator.db.friendlyisValidTarget
            end,
            set = function(value)
                NoTargetIndicator.db.friendlyisValidTarget = value
            end,
        },
    }

    for _, row in ipairs(XerionUIFeatures:EUIFontRows(function() return NoTargetIndicator.db.font end, apply, nil, { displayRow })) do
        rows[#rows + 1] = row
    end

    return {
        name = "No Target Indicator",
        rows = rows,
    }
end
