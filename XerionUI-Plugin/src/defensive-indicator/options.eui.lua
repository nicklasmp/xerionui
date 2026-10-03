local addonName, XerionUIFeatures = ...

local moduleName = "DefensiveIndicator"
local DefensiveIndicator = XerionUIFeatures:GetModule(moduleName)

DefensiveIndicator.EUIPages = {
    DefensiveIndicator.pageDisplay,
    DefensiveIndicator.pageDefensives,
}

function DefensiveIndicator:GetEUIOptions(pageName)
    local function apply() XerionUIFeatures:ApplyModuleStyles(moduleName) end

    if pageName == DefensiveIndicator.pageDefensives then
        local externalTip = "Defensives other people cast on you. The same list on every class, since what you can be given has nothing to do with what you play"

        local function categoryColumn(class, category)
            local spellIds = class.categories[category]

            if #spellIds == 0 then
                return { type = "empty" }
            end

            local isExternal = category == DefensiveIndicator.categoryExternal

            return {
                type = "multiselect",
                label = DefensiveIndicator.CategorySettings[category],
                tooltip = isExternal and externalTip
                    or "The ring colours itself by tier, and a higher tier takes the display off a lower one",
                items = DefensiveIndicator:GetAuraItems(spellIds),
                width = 150,
                maxVisible = 9,
                get = function(spellId)
                    return DefensiveIndicator:IsAuraTracked(spellId)
                end,
                set = function(spellId, value)
                    DefensiveIndicator:SetAuraTracked(spellId, value)
                    DefensiveIndicator:UpdateVisibility()
                    apply()
                end,
            }
        end

        local rows = {}
        local columns = DefensiveIndicator:GetColumnCategories()

        for _, class in ipairs(DefensiveIndicator:GetDefensiveClasses()) do
            rows[#rows + 1] = { header = class.colorString .. class.className .. "|r" }

            -- Four tiers laid out two to a row, since EllesmereUI pairs controls and
            -- has nothing wider.
            for index = 1, #columns, 2 do
                rows[#rows + 1] = {
                    pair = {
                        categoryColumn(class, columns[index]),
                        categoryColumn(class, columns[index + 1]),
                    },
                }
            end
        end

        return {
            name = "Defensive Indicator",
            rows = rows,
        }
    end

    local function categoryColorRow(category)
        return {
            type = "color",
            label = DefensiveIndicator.CategorySettings[category],
            hasAlpha = true,
            get = function()
                local color = DefensiveIndicator:GetColor(category)
                return color.r, color.g, color.b, color.a
            end,
            set = function(r, g, b, a)
                DefensiveIndicator.db.colors[category] = {
                    r = r,
                    g = g,
                    b = b,
                    a = a,
                }
                apply()
            end,
        }
    end

    -- The ring's unfilled remainder. No toggle beside it: the alpha is the switch, so
    -- a track nobody wants is one turned transparent. Circle only, since the bar's
    -- background is what gives it its shape and always draws.
    local trackRow = {
        type = "color",
        label = "Track color",
        tooltip = "The unfilled part behind the countdown. Drop the opacity to hide it",
        hasAlpha = true,
        get = function()
            local color = DefensiveIndicator.db.backgroundColor
            return color.r, color.g, color.b, color.a
        end,
        set = function(r, g, b, a)
            DefensiveIndicator.db.backgroundColor = {
                r = r,
                g = g,
                b = b,
                a = a,
            }
            apply()
        end,
    }

    -- Everything about the chosen display sits behind its own cogwheel, so the page
    -- spends one row on it whichever display that is. Which rows the cog holds changes
    -- with the display, which is a rebuild rather than a refresh.
    local function displayCog()
        local mode = DefensiveIndicator.db.display
        local rows = {}

        if mode == DefensiveIndicator.displayBar then
            rows[#rows + 1] = XerionUIFeatures:EUIStatusbarRow({
                label = "Texture",
                get = function()
                    return DefensiveIndicator.db.barTexture
                end,
                set = function(value)
                    DefensiveIndicator.db.barTexture = value
                    apply()
                end,
            })

            rows[#rows + 1] = {
                type = "slider",
                label = "Width",
                min = 20,
                max = 400,
                step = 1,
                get = function()
                    return DefensiveIndicator.db.barWidth
                end,
                set = function(value)
                    DefensiveIndicator.db.barWidth = value
                    apply()
                end,
            }

            rows[#rows + 1] = {
                type = "slider",
                label = "Height",
                min = 4,
                max = 60,
                step = 1,
                get = function()
                    return DefensiveIndicator.db.barHeight
                end,
                set = function(value)
                    DefensiveIndicator.db.barHeight = value
                    apply()
                end,
            }
        elseif mode == DefensiveIndicator.displayCircle then
            rows[#rows + 1] = {
                type = "select",
                label = "Thickness",
                values = DefensiveIndicator.RingTextures,
                order = DefensiveIndicator.RingTextureOrder,
                get = function()
                    return DefensiveIndicator.db.ringTexture
                end,
                set = function(value)
                    DefensiveIndicator.db.ringTexture = value
                    apply()
                end,
            }

            rows[#rows + 1] = {
                type = "slider",
                label = "Size",
                min = 16,
                max = 200,
                step = 1,
                get = function()
                    return DefensiveIndicator.db.size
                end,
                set = function(value)
                    DefensiveIndicator.db.size = value
                    apply()
                end,
            }

            rows[#rows + 1] = trackRow
        else
            -- Text only draws nothing, so it gets no cogwheel at all.
            return nil
        end

        return {
            title = DefensiveIndicator.DisplaySettings[mode],
            icon = XerionUIFeatures.EUI and XerionUIFeatures.EUI.RESIZE_ICON,
            rows = rows,
        }
    end

    -- Leads the font block rather than standing on its own: it is what the name and the
    -- duration are coloured with, and it joins the same two-to-a-row flow as the font
    -- pickers. Position rides its cog, since both lines move together.
    local textColorRow = {
        type = "color",
        label = "Text color",
        hasAlpha = true,
        get = function()
            local color = DefensiveIndicator.db.textColor
            return color.r, color.g, color.b, color.a
        end,
        set = function(r, g, b, a)
            DefensiveIndicator.db.textColor = {
                r = r,
                g = g,
                b = b,
                a = a,
            }
            apply()
        end,
        cog = {
            title = "Text Position",
            icon = XerionUIFeatures.EUI and XerionUIFeatures.EUI.DIRECTIONS_ICON,
            rows = {
                {
                    type = "slider",
                    label = "X Offset",
                    min = -200,
                    max = 200,
                    step = 1,
                    get = function()
                        return DefensiveIndicator.db.textOffset.x
                    end,
                    set = function(value)
                        DefensiveIndicator.db.textOffset.x = value
                        apply()
                    end,
                },
                {
                    type = "slider",
                    label = "Y Offset",
                    min = -200,
                    max = 200,
                    step = 1,
                    get = function()
                        return DefensiveIndicator.db.textOffset.y
                    end,
                    set = function(value)
                        DefensiveIndicator.db.textOffset.y = value
                        apply()
                    end,
                },
            },
        },
    }

    -- pageDisplay, and the fallback for any caller that passes no page name
    return {
        name = "Defensive Indicator",
        rows = {
            {
                pair = {
                    {
                        type = "select",
                        label = "Display",
                        tooltip = "Text only leaves just the name and the duration, with nothing drawn behind them",
                        values = DefensiveIndicator.DisplaySettings,
                        order = DefensiveIndicator.DisplayOrder,
                        rebuild = true,
                        get = function()
                            return DefensiveIndicator.db.display
                        end,
                        set = function(value)
                            DefensiveIndicator.db.display = value
                            apply()
                        end,
                        cog = displayCog(),
                    },
                    {
                        type = "empty",
                    },
                },
            },
            { header = "Colors" },
            {
                pair = {
                    categoryColorRow(DefensiveIndicator.categoryMassive),
                    categoryColorRow(DefensiveIndicator.categoryMajor),
                },
            },
            {
                pair = {
                    categoryColorRow(DefensiveIndicator.categoryMinor),
                    categoryColorRow(DefensiveIndicator.categoryExternal),
                },
            },
            {
                pair = {
                    {
                        type = "toggle",
                        label = "Show name",
                        tooltip = "The defensive's name, above the duration",
                        get = function()
                            return DefensiveIndicator.db.showName
                        end,
                        set = function(value)
                            DefensiveIndicator.db.showName = value
                            apply()
                        end,
                    },
                    {
                        type = "toggle",
                        label = "Show duration",
                        refresh = true,
                        get = function()
                            return DefensiveIndicator.db.showDuration
                        end,
                        set = function(value)
                            DefensiveIndicator.db.showDuration = value
                            apply()
                        end,
                        cog = {
                            title = "Duration",
                            disabled = function()
                                return not DefensiveIndicator.db.showDuration
                            end,
                            disabledTooltip = "Show duration has to be on before its precision means anything.",
                            rows = {
                                {
                                    type = "slider",
                                    label = "Decimal precision",
                                    min = 0,
                                    max = 1,
                                    step = 1,
                                    get = function()
                                        return DefensiveIndicator.db.precision
                                    end,
                                    set = function(value)
                                        DefensiveIndicator.db.precision = value
                                        apply()
                                    end,
                                },
                            },
                        },
                    },
                },
            },
            {
                header = "Font",
                rows = XerionUIFeatures:EUIFontRows(function() return DefensiveIndicator.db.font end, apply, nil, {textColorRow}),
            },
        },
    }
end
