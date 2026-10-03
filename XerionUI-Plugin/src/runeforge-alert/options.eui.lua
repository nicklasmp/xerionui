local addonName, XerionUIFeatures = ...

local moduleName = "RuneforgeAlert"
local RuneforgeAlert = XerionUIFeatures:GetModule(moduleName)

RuneforgeAlert.EUIPages = {
    RuneforgeAlert.pageDisplay,
    RuneforgeAlert.pageRuneforges,
}

function RuneforgeAlert:GetEUIOptions(pageName)
    local function apply() XerionUIFeatures:ApplyModuleStyles(moduleName) end

    if pageName == RuneforgeAlert.pageRuneforges then
        -- The rule lives on the controls rather than in a row of its own: a leading
        -- text row is stripped on a tabbed page (its header carries the module's
        -- description already).
        local function runeRow(control)
            return {
                type = "multiselect",
                label = control.label,
                tooltip = "The runeforges you accept on this weapon. Checking none leaves the weapon unchecked",
                items = RuneforgeAlert:GetRuneItems(),
                maxVisible = 8,
                get = function(enchantId)
                    return RuneforgeAlert:IsRuneAccepted(control.setupKey, control.slotKey, enchantId)
                end,
                set = function(enchantId, value)
                    RuneforgeAlert:SetRuneAccepted(control.setupKey, control.slotKey, enchantId, value)
                    RuneforgeAlert:UpdateVisibility()
                    apply()
                end,
            }
        end

        local rows = {}

        for _, group in ipairs(RuneforgeAlert:GetSetupGroups()) do
            rows[#rows + 1] = { header = group.specName }

            -- Paired by GetSetupGroups. An odd one out still takes half a row, so its
            -- dropdown lines up with the column above it rather than the row's edge.
            for _, row in ipairs(group.rows) do
                rows[#rows + 1] = {
                    pair = {
                        runeRow(row[1]),
                        row[2] and runeRow(row[2]) or { type = "empty" },
                    },
                }
            end
        end

        return {
            name = "Runeforge Alert",
            rows = rows,
        }
    end

    -- pageDisplay, and the fallback for any caller that passes no page name
    local displayRow = {
        type = "color",
        label = "Display",
        hasAlpha = true,
        get = function()
            local color = RuneforgeAlert.db.color
            return color.r, color.g, color.b, color.a
        end,
        set = function(r, g, b, a)
            RuneforgeAlert.db.color = {
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
                        return RuneforgeAlert.db.displayText or ""
                    end,
                    set = function(value)
                        RuneforgeAlert.db.displayText = value
                        apply()
                    end,
                },
            },
        },
    }

    return {
        name = "Runeforge Alert",
        rows = XerionUIFeatures:EUIFontRows(function() return RuneforgeAlert.db.font end, apply, nil, { displayRow }),
    }
end
