local addonName, XerionUIFeatures = ...

local moduleName = "RaidFrameManager"
local RaidFrameManager = XerionUIFeatures:GetModule(moduleName)

RaidFrameManager.EUIPages = {
    RaidFrameManager.pageDisplay,
    RaidFrameManager.pageActions,
    RaidFrameManager.pagePullTimers,
}

-- Two controls to a row, so a list of same-shaped rows (the action toggles, the
-- remove buttons) reads as a block instead of one tall column.
local function paired(rows)
    local out = {}

    for index = 1, #rows, 2 do
        out[#out + 1] = { pair = { rows[index], rows[index + 1] or { type = "empty" } } }
    end

    return out
end

local function displayRows(apply, onChange)
    local buttonColorRow = {
        type = "color",
        label = "Button color",
        hasAlpha = true,
        get = function()
            local color = RaidFrameManager.db.buttonColor
            return color.r, color.g, color.b, color.a
        end,
        set = function(r, g, b, a)
            RaidFrameManager.db.buttonColor = {
                r = r,
                g = g,
                b = b,
                a = a,
            }
            apply()
        end,
    }

    local textColorRow = {
        type = "color",
        label = "Text color",
        hasAlpha = true,
        get = function()
            local color = RaidFrameManager.db.textColor
            return color.r, color.g, color.b, color.a
        end,
        set = function(r, g, b, a)
            RaidFrameManager.db.textColor = {
                r = r,
                g = g,
                b = b,
                a = a,
            }
            apply()
        end,
    }

    return {
        {
            pair = {
                {
                    type = "toggle",
                    label = "Only in a group",
                    tooltip = "Hides the bar while you are on your own.",
                    refresh = true,
                    get = function()
                        return RaidFrameManager.db.onlyInGroup
                    end,
                    set = function(value)
                        RaidFrameManager.db.onlyInGroup = value
                        onChange()
                    end,
                    -- The stricter form of the same setting, so it rides the group
                    -- row's cogwheel rather than spending a row of its own. It
                    -- narrows what the group toggle hides, so it means nothing
                    -- while that toggle is off.
                    cog = {
                        title = "Group Visibility",
                        disabled = function()
                            return not RaidFrameManager.db.onlyInGroup
                        end,
                        disabledTooltip = "Only in a group has to be on before the bar can be limited to raids.",
                        rows = {
                            {
                                type = "toggle",
                                label = "Only in a raid",
                                tooltip = "Hides the bar unless you are in a raid group.",
                                get = function()
                                    return RaidFrameManager.db.onlyInRaid
                                end,
                                set = function(value)
                                    RaidFrameManager.db.onlyInRaid = value
                                    onChange()
                                end,
                            },
                        },
                    },
                },
                {
                    type = "toggle",
                    label = "Show tooltips",
                    tooltip = "Shows what a button does, and why it is dimmed, when you hover it.",
                    get = function()
                        return RaidFrameManager.db.showTooltips
                    end,
                    set = function(value)
                        RaidFrameManager.db.showTooltips = value
                    end,
                },
            },
        },
        {
            type = "toggle",
            label = "Mouseover only",
            tooltip = "Keeps the bar invisible until you move the cursor over it.",
            get = function()
                return RaidFrameManager.db.mouseover
            end,
            set = function(value)
                RaidFrameManager.db.mouseover = value
                onChange()
            end,
            cog = {
                title = "Mouseover Alpha",
                rows = {
                    {
                        type = "slider",
                        label = "Hovered",
                        tooltip = "How visible the bar is while the cursor is over it.",
                        min = 0,
                        max = 1,
                        step = 0.05,
                        disabled = function()
                            return not RaidFrameManager.db.mouseover
                        end,
                        disabledTooltip = "Mouseover only",
                        get = function()
                            return RaidFrameManager.db.mouseoverAlpha
                        end,
                        set = function(value)
                            RaidFrameManager.db.mouseoverAlpha = value
                            onChange()
                        end,
                    },
                    {
                        type = "slider",
                        label = "Faded",
                        tooltip = "How visible the bar is while the cursor is elsewhere.",
                        min = 0,
                        max = 1,
                        step = 0.05,
                        disabled = function()
                            return not RaidFrameManager.db.mouseover
                        end,
                        disabledTooltip = "Mouseover only",
                        get = function()
                            return RaidFrameManager.db.mouseoverFadeAlpha
                        end,
                        set = function(value)
                            RaidFrameManager.db.mouseoverFadeAlpha = value
                            onChange()
                        end,
                    },
                },
            },
        },
        {
            type = "select",
            label = "Orientation",
            values = RaidFrameManager.orientations,
            order = { "HORIZONTAL", "VERTICAL" },
            get = function()
                return RaidFrameManager.db.orientation
            end,
            set = function(value)
                RaidFrameManager.db.orientation = value
                apply()
            end,
        },
        {
            pair = {
                {
                    type = "slider",
                    label = "Padding",
                    tooltip = "Space left and right of the label. The buttons size themselves around the widest one.",
                    min = 0,
                    max = 40,
                    step = 1,
                    get = function()
                        return RaidFrameManager.db.paddingX
                    end,
                    set = function(value)
                        RaidFrameManager.db.paddingX = value
                        apply()
                    end,
                    -- The vertical half is the one you rarely touch, the height
                    -- already following the font size, so it rides a cog. On the
                    -- expander icon EllesmereUI puts on its own size settings,
                    -- rather than the plain cogwheel.
                    cog = {
                        title = "Padding",
                        icon = XerionUIFeatures.EUI and XerionUIFeatures.EUI.RESIZE_ICON,
                        rows = {
                            {
                                type = "slider",
                                label = "Top and bottom",
                                tooltip = "Space above and below the label.",
                                min = 0,
                                max = 40,
                                step = 1,
                                get = function()
                                    return RaidFrameManager.db.paddingY
                                end,
                                set = function(value)
                                    RaidFrameManager.db.paddingY = value
                                    apply()
                                end,
                            },
                        },
                    },
                },
                {
                    type = "slider",
                    label = "Spacing",
                    min = 0,
                    max = 20,
                    step = 1,
                    get = function()
                        return RaidFrameManager.db.spacing
                    end,
                    set = function(value)
                        RaidFrameManager.db.spacing = value
                        apply()
                    end,
                },
            },
        },
        {
            header = "Font",
            rows = XerionUIFeatures:EUIFontRows(function() return RaidFrameManager.db.font end, apply, nil, { buttonColorRow, textColorRow }),
        },
    }
end

local function actionRows(apply)
    local toggles = {}

    for _, key in ipairs(RaidFrameManager.actionOrder) do
        local action = RaidFrameManager.actions[key]

        toggles[#toggles + 1] = {
            type = "toggle",
            label = action.name,
            tooltip = action.tooltip,
            get = function()
                return RaidFrameManager.db.actions[key]
            end,
            set = function(value)
                RaidFrameManager.db.actions[key] = value
                apply()
            end,
        }
    end

    return paired(toggles)
end

local function pullTimerRows(apply)
    local rows = {
        { header = "Pull Timers" },
    }

    local timers = RaidFrameManager:GetPullTimers()

    if #timers == 0 then
        rows[#rows + 1] = { text = "No pull timers. Each one you add gets its own button, labelled with its duration in seconds." }
    else
        rows[#rows + 1] = { text = "Pull timers: " .. table.concat(timers, ", ") .. " seconds. Each one is a button on the bar." }
    end

    rows[#rows + 1] = {
        type = "input",
        label = "Add pull timer",
        tooltip = "Duration in seconds",
        width = 80,
        rebuild = true,
        get = function()
            return ""
        end,
        set = function(value)
            RaidFrameManager:AddPullTimer(value)
            apply()
        end,
    }

    local removals = {}

    for _, seconds in ipairs(timers) do
        removals[#removals + 1] = {
            type = "execute",
            label = ("Remove %d s"):format(seconds),
            rebuild = true,
            func = function()
                RaidFrameManager:RemovePullTimer(seconds)
                apply()
            end,
        }
    end

    for _, row in ipairs(paired(removals)) do
        rows[#rows + 1] = row
    end

    rows[#rows + 1] = {
        type = "execute",
        label = "Restore default pull timers",
        rebuild = true,
        func = function()
            RaidFrameManager:ResetPullTimers()
            apply()
        end,
    }

    rows[#rows + 1] = { spacer = 8 }
    rows[#rows + 1] = {
        type = "toggle",
        label = "Cancel button",
        tooltip = "Adds a button that stops a running pull timer.",
        get = function()
            return RaidFrameManager.db.cancelPull
        end,
        set = function(value)
            RaidFrameManager.db.cancelPull = value
            apply()
        end,
    }

    return rows
end

function RaidFrameManager:GetEUIOptions(pageName)
    local function apply() XerionUIFeatures:ApplyModuleStyles(moduleName) end

    -- Visibility is not a style, so the rows that change it go through
    -- RefreshConfig the way the ace `set` does.
    local function onChange() RaidFrameManager:RefreshConfig() end

    if pageName == RaidFrameManager.pageActions then
        return {
            name = "Raid Frame Manager",
            rows = actionRows(apply),
        }
    end

    if pageName == RaidFrameManager.pagePullTimers then
        return {
            name = "Raid Frame Manager",
            rows = pullTimerRows(apply),
        }
    end

    return {
        name = "Raid Frame Manager",
        rows = displayRows(apply, onChange),
    }
end
