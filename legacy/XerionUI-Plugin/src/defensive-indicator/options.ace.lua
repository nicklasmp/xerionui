local addonName, XerionUIFeatures = ...

local moduleName = "DefensiveIndicator"
local DefensiveIndicator = XerionUIFeatures:GetModule(moduleName)

local LSM = XerionUIFeatures.LSM

local function spellString(item)
    if not item.icon then
        return item.label
    end

    return string.format("|T%s:16:16:0:0:64:64:5:59:5:59|t %s", item.icon, item.label)
end

-- A group per class holding one checkbox dropdown per tier, so every class can be set
-- up from any character rather than only the one that plays it. Four dropdowns two to
-- a row, matching how the EllesmereUI page pairs them.
local function createDefensiveOptions(onChange)
    local args = {}

    for classIndex, class in ipairs(DefensiveIndicator:GetDefensiveClasses()) do
        local columns = {}
        local columnOrder = 0

        for _, category in ipairs(DefensiveIndicator:GetColumnCategories()) do
            local spellIds = class.categories[category]

            if #spellIds > 0 then
                local values = {}
                local order = {}

                for index, item in ipairs(DefensiveIndicator:GetAuraItems(spellIds)) do
                    values[item.key] = spellString(item)
                    order[index] = item.key
                end

                columnOrder = columnOrder + 1

                columns[category] = {
                    order = columnOrder,
                    type = "multiselect",
                    -- A checkbox dropdown rather than the default row of checkboxes,
                    -- so a long class list stays as compact as EllesmereUI's page.
                    dialogControl = "ItruliaMultiselect",
                    arg = order,
                    width = 1,
                    name = DefensiveIndicator.CategorySettings[category],
                    desc = category == DefensiveIndicator.categoryExternal
                        and "Defensives other people cast on you. The same list on every class, since what you can be given has nothing to do with what you play"
                        or "The ring colours itself by tier, and a higher tier takes the display off a lower one",
                    values = values,
                    get = function(_, spellId)
                        return DefensiveIndicator:IsAuraTracked(spellId)
                    end,
                    set = function(_, spellId, value)
                        DefensiveIndicator:SetAuraTracked(spellId, value)
                        DefensiveIndicator:UpdateVisibility()
                        onChange()
                    end,
                }

                -- A full width nothing after every second dropdown, so the flow
                -- layout breaks into pairs rather than fitting what it can.
                if columnOrder % 2 == 0 then
                    columnOrder = columnOrder + 1

                    columns[category .. "Spacer"] = {
                        order = columnOrder,
                        type = "description",
                        name = "",
                        width = "full",
                    }
                end
            end
        end

        args["class" .. class.classFile] = {
            order = classIndex,
            type = "group",
            name = class.colorString .. class.className .. "|r",
            inline = true,
            args = columns,
        }
    end

    return args
end

-- One picker per tier, so which kind of defensive is up reads off the ring's colour.
local function createColorOptions(onChange)
    local args = {}

    for index, category in ipairs(DefensiveIndicator:GetColumnCategories()) do
        args[category] = {
            order = index,
            type = "color",
            width = 0.6,
            name = DefensiveIndicator.CategorySettings[category],
            hasAlpha = true,
            get = function()
                local color = DefensiveIndicator:GetColor(category)
                return color.r, color.g, color.b, color.a
            end,
            set = function(_, r, g, b, a)
                DefensiveIndicator.db.colors[category] = {
                    r = r,
                    g = g,
                    b = b,
                    a = a
                }
                onChange()
            end
        }
    end

    return args
end

function DefensiveIndicator:GetOptions(onChange)
    return {
        order = 2,
        type = "group",
        name = "Defensive Indicator",
        childGroups = "tab",
        args = {
            description = {
                type = "description",
                name = "Shows a ring counting down the defensive you have active\n\n",
                width = "full",
                order = 1,
            },
            enable = {
                order = 2,
                type = "toggle",
                width = "full",
                name = "Enable",
                get = function()
                    return DefensiveIndicator.db.enabled
                end,
                set = function(_, value)
                    DefensiveIndicator.db.enabled = value
                    DefensiveIndicator:RefreshConfig()
                end
            },
            display = {
                order = 10,
                type = "group",
                name = DefensiveIndicator.pageDisplay,
                args = {
                    preview = XerionUIFeatures:CreatePreviewOption(DefensiveIndicator, 0, nil, DefensiveIndicator.pageDisplay),
                    ringSettings = {
                        type = "group",
                        name = "",
                        order = 4,
                        inline = true,
                        args = {
                            display = {
                                order = 1,
                                type = "select",
                                width = 0.75,
                                name = "Display",
                                desc = "Text only leaves just the name and the duration, with nothing drawn behind them",
                                values = DefensiveIndicator.DisplaySettings,
                                sorting = DefensiveIndicator.DisplayOrder,
                                get = function()
                                    return DefensiveIndicator.db.display
                                end,
                                set = function(_, value)
                                    DefensiveIndicator.db.display = value
                                    onChange()
                                end,
                            },
                            barTexture = {
                                order = 4,
                                type = "select",
                                width = 0.75,
                                dialogControl = "LSM30_Statusbar",
                                name = "Bar texture",
                                values = LSM:HashTable("statusbar"),
                                hidden = function()
                                    return DefensiveIndicator.db.display ~= DefensiveIndicator.displayBar
                                end,
                                get = function()
                                    return DefensiveIndicator.db.barTexture
                                end,
                                set = function(_, value)
                                    DefensiveIndicator.db.barTexture = value
                                    onChange()
                                end,
                            },
                            barWidth = {
                                order = 5,
                                type = "range",
                                width = 0.75,
                                name = "Bar width",
                                min = 20,
                                max = 400,
                                step = 1,
                                hidden = function()
                                    return DefensiveIndicator.db.display ~= DefensiveIndicator.displayBar
                                end,
                                get = function()
                                    return DefensiveIndicator.db.barWidth
                                end,
                                set = function(_, value)
                                    DefensiveIndicator.db.barWidth = value
                                    onChange()
                                end,
                            },
                            barHeight = {
                                order = 6,
                                type = "range",
                                width = 0.75,
                                name = "Bar height",
                                min = 4,
                                max = 60,
                                step = 1,
                                hidden = function()
                                    return DefensiveIndicator.db.display ~= DefensiveIndicator.displayBar
                                end,
                                get = function()
                                    return DefensiveIndicator.db.barHeight
                                end,
                                set = function(_, value)
                                    DefensiveIndicator.db.barHeight = value
                                    onChange()
                                end,
                            },
                            ringTexture = {
                                order = 2,
                                type = "select",
                                width = 0.75,
                                name = "Thickness",
                                values = DefensiveIndicator.RingTextures,
                                sorting = DefensiveIndicator.RingTextureOrder,
                                get = function()
                                    return DefensiveIndicator.db.ringTexture
                                end,
                                set = function(_, value)
                                    DefensiveIndicator.db.ringTexture = value
                                    onChange()
                                end,
                            },
                            size = {
                                order = 3,
                                type = "range",
                                width = 0.75,
                                name = "Size",
                                min = 16,
                                max = 200,
                                step = 1,
                                get = function()
                                    return DefensiveIndicator.db.size
                                end,
                                set = function(_, value)
                                    DefensiveIndicator.db.size = value
                                    onChange()
                                end,
                            },
                            spacer = {
                                type = "description",
                                name = "",
                                width = "full",
                                order = 9,
                            },
                            colors = {
                                order = 10,
                                type = "group",
                                name = "",
                                inline = true,
                                args = createColorOptions(onChange),
                            },
                            backgroundColor = {
                                order = 12,
                                type = "color",
                                width = 0.7,
                                name = "Track color",
                                desc = "The unfilled part behind the countdown. Drop the opacity to hide it",
                                hasAlpha = true,
                                hidden = function()
                                    return DefensiveIndicator.db.display ~= DefensiveIndicator.displayCircle
                                end,
                                get = function()
                                    local color = DefensiveIndicator.db.backgroundColor
                                    return color.r, color.g, color.b, color.a
                                end,
                                set = function(_, r, g, b, a)
                                    DefensiveIndicator.db.backgroundColor = {
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
                    textSettings = {
                        type = "group",
                        name = "",
                        order = 5,
                        inline = true,
                        args = {
                            description = {
                                type = "description",
                                name = "The name and the duration are one text, so they move and style together\n",
                                width = "full",
                                order = 1,
                            },
                            showName = {
                                order = 2,
                                type = "toggle",
                                width = 0.75,
                                name = "Show name",
                                get = function()
                                    return DefensiveIndicator.db.showName
                                end,
                                set = function(_, value)
                                    DefensiveIndicator.db.showName = value
                                    onChange()
                                end,
                            },
                            showDuration = {
                                order = 3,
                                type = "toggle",
                                width = 0.75,
                                name = "Show duration",
                                get = function()
                                    return DefensiveIndicator.db.showDuration
                                end,
                                set = function(_, value)
                                    DefensiveIndicator.db.showDuration = value
                                    onChange()
                                end,
                            },
                            precision = {
                                order = 4,
                                type = "range",
                                width = 0.75,
                                name = "Decimal precision",
                                min = 0,
                                max = 1,
                                step = 1,
                                disabled = function()
                                    return not DefensiveIndicator.db.showDuration
                                end,
                                get = function()
                                    return DefensiveIndicator.db.precision
                                end,
                                set = function(_, value)
                                    DefensiveIndicator.db.precision = value
                                    onChange()
                                end,
                            },
                            spacer = {
                                type = "description",
                                name = "",
                                width = "full",
                                order = 9,
                            },
                            textX = {
                                order = 11,
                                type = "range",
                                width = 0.75,
                                name = "Text X offset",
                                min = -200,
                                max = 200,
                                step = 1,
                                get = function()
                                    return DefensiveIndicator.db.textOffset.x
                                end,
                                set = function(_, value)
                                    DefensiveIndicator.db.textOffset.x = value
                                    onChange()
                                end,
                            },
                            textY = {
                                order = 12,
                                type = "range",
                                width = 0.75,
                                name = "Text Y offset",
                                min = -200,
                                max = 200,
                                step = 1,
                                get = function()
                                    return DefensiveIndicator.db.textOffset.y
                                end,
                                set = function(_, value)
                                    DefensiveIndicator.db.textOffset.y = value
                                    onChange()
                                end,
                            },
                        }
                    },
                    fontSettings = {
                        type = "group",
                        name = "",
                        order = 6,
                        inline = true,
                        args = XerionUIFeatures:createFontOptions(function() return DefensiveIndicator.db.font end, function()
                            onChange()
                        end, {
                            -- With the font, since it is what the name and the duration
                            -- are coloured with. Matches where EllesmereUI puts it.
                            textColor = {
                                order = 5,
                                type = "color",
                                width = 0.7,
                                name = "Text color",
                                hasAlpha = true,
                                get = function()
                                    local color = DefensiveIndicator.db.textColor
                                    return color.r, color.g, color.b, color.a
                                end,
                                set = function(_, r, g, b, a)
                                    DefensiveIndicator.db.textColor = {
                                        r = r,
                                        g = g,
                                        b = b,
                                        a = a
                                    }
                                    onChange()
                                end
                            },
                        })
                    },
                }
            },
            defensives = {
                order = 15,
                type = "group",
                name = DefensiveIndicator.pageDefensives,
                args = {
                    description = {
                        type = "description",
                        name = "The buffs that count as a defensive, split into the tiers the ring colours itself by. A higher tier takes the display off a lower one, and inside a tier the one that went up last wins. Externals are what other people cast on you, so they are tracked whatever you play\n\n",
                        width = "full",
                        order = 1,
                    },
                    classes = {
                        type = "group",
                        name = "",
                        order = 2,
                        inline = true,
                        args = createDefensiveOptions(onChange),
                    },
                }
            },
        }
    }
end
