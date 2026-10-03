local addonName, XerionUIFeatures = ...

local moduleName = "RuneforgeAlert"
local RuneforgeAlert = XerionUIFeatures:GetModule(moduleName)

-- AceConfig has no icon field on a multiselect entry, so the icon is inlined in the
-- label the way the movement alert lists its spells.
local function runeString(item)
    if not item.icon then
        return item.label
    end

    return string.format("|T%s:16:16:0:0:64:64:5:59:5:59|t %s", item.icon, item.label)
end

local function runeValues()
    local values = {}
    local order = {}

    for index, item in ipairs(RuneforgeAlert:GetRuneItems()) do
        values[item.key] = runeString(item)
        order[index] = item.key
    end

    return values, order
end

local function createSetupOptions(onChange)
    local values, order = runeValues()

    local args = {
        description = {
            type = "description",
            name = "Any rune checked here counts as correct, so a build with more than one acceptable runeforge stays quiet either way. A weapon with nothing checked is never checked at all\n\n",
            width = "full",
            order = 0,
        },
    }

    for groupIndex, group in ipairs(RuneforgeAlert:GetSetupGroups()) do
        local controls = {}
        local controlOrder = 0

        for _, row in ipairs(group.rows) do
            for _, control in ipairs(row) do
                controlOrder = controlOrder + 1

                controls[control.key] = {
                    order = controlOrder,
                    type = "multiselect",
                    -- A checkbox dropdown rather than the default row of checkboxes, so
                    -- eight runes stay as compact as the EllesmereUI page's. `arg` is the
                    -- order it lists them in.
                    dialogControl = "ItruliaMultiselect",
                    arg = order,
                    name = control.label,
                    values = values,
                    get = function(_, enchantId)
                        return RuneforgeAlert:IsRuneAccepted(control.setupKey, control.slotKey, enchantId)
                    end,
                    set = function(_, enchantId, value)
                        RuneforgeAlert:SetRuneAccepted(control.setupKey, control.slotKey, enchantId, value)
                        RuneforgeAlert:UpdateVisibility()
                        onChange()
                    end,
                }
            end

            -- A full width nothing after each row, so the flow layout breaks there
            -- instead of fitting a third control in beside the two that belong.
            controlOrder = controlOrder + 1

            controls[row[1].key .. "Spacer"] = {
                order = controlOrder,
                type = "description",
                name = "",
                width = "full",
            }
        end

        args["spec" .. group.specId] = {
            order = groupIndex,
            type = "group",
            name = group.specName,
            inline = true,
            args = controls,
        }
    end

    return args
end

function RuneforgeAlert:GetOptions(onChange)
    return {
        order = 2,
        type = "group",
        name = "Runeforge Alert",
        args = {
            preview = XerionUIFeatures:CreatePreviewOption(RuneforgeAlert),
            description = {
                type = "description",
                name = "Shows an indicator text when your weapons don't have the correct enchants. Does not show mid combat/m+\n\n",
                width = "full",
                order = 1,
            },
            enable = {
                order = 2,
                type = "toggle",
                width = "full",
                name = "Enable",
                get = function()
                    return RuneforgeAlert.db.enabled
                end,
                set = function(_, value)
                    RuneforgeAlert.db.enabled = value
                    RuneforgeAlert:RefreshConfig()
                end
            },
            displaySettings = {
                type = "group",
                name = "",
                order = 4,
                inline = true,
                args = {
                    displayText = {
                        order = 1,
                        type = "input",
                        name = "Display text",
                        get = function()
                            return RuneforgeAlert.db.displayText
                        end,
                        set = function(_, value)
                            RuneforgeAlert.db.displayText = value
                            onChange()
                        end
                    },
                    color = {
                        order = 2,
                        type = "color",
                        name = "Color",
                        width = 0.4,
                        hasAlpha = true,
                        get = function()
                            local color = RuneforgeAlert.db.color
                            return color.r, color.g, color.b, color.a
                        end,
                        set = function(_, r, g, b, a)
                            RuneforgeAlert.db.color = {
                                r = r,
                                g = g,
                                b = b,
                                a = a
                            }
                            onChange()
                        end
                    },
                }
            },
            fontSettings = {
                type = "group",
                name = "",
                order = 5,
                inline = true,
                args = XerionUIFeatures:createFontOptions(function() return RuneforgeAlert.db.font end, function()
                    onChange()
                end)
            },
            runeforges = {
                type = "group",
                name = "Runeforges",
                order = 10,
                inline = true,
                args = createSetupOptions(onChange),
            },
        }
    }
end
