local addonName, XerionUIFeatures = ...
local LSM = XerionUIFeatures.LSM

local moduleName = "RaidFrameManager"
local RaidFrameManager = XerionUIFeatures:GetModule(moduleName)

-- A toggle per fixed action, in bar order.
local function actionToggles(onChange)
    local args = {}

    for index, key in ipairs(RaidFrameManager.actionOrder) do
        local action = RaidFrameManager.actions[key]

        args[key] = {
            order = index,
            type = "toggle",
            width = "full",
            name = action.name,
            desc = action.tooltip,
            get = function()
                return RaidFrameManager.db.actions[key]
            end,
            set = function(_, value)
                RaidFrameManager.db.actions[key] = value
                onChange()
            end,
        }
    end

    return args
end

function RaidFrameManager:GetOptions(onChange)
    local function pullTimerValues()
        local values = {}

        for _, seconds in ipairs(RaidFrameManager:GetPullTimers()) do
            values[seconds] = ("%d seconds"):format(seconds)
        end

        return values
    end

    return {
        order = 2,
        type = "group",
        name = "Raid Frame Manager",
        childGroups = "tab",
        args = {
            description = {
                type = "description",
                name = "Replaces Blizzard's raid frame manager with a movable bar of group actions and your own pull timers. The bar hides itself in combat, and while you are in a group without lead or assist, where none of its buttons can be pressed anyway\n\n",
                width = "full",
                order = 1,
            },
            enable = {
                order = 2,
                type = "toggle",
                width = "full",
                name = "Enable",
                get = function()
                    return RaidFrameManager.db.enabled
                end,
                set = function(_, value)
                    RaidFrameManager.db.enabled = value
                    RaidFrameManager:RefreshConfig()
                end
            },
            display = {
                order = 10,
                type = "group",
                name = RaidFrameManager.pageDisplay,
                args = {
                    preview = XerionUIFeatures:CreatePreviewOption(RaidFrameManager, 0, nil, RaidFrameManager.pageDisplay),
                    behaviourSettings = {
                        type = "group",
                        name = "",
                        order = 3,
                        inline = true,
                        args = {
                            onlyInGroup = {
                                order = 1,
                                type = "toggle",
                                width = "full",
                                name = "Only show in a group",
                                get = function()
                                    return RaidFrameManager.db.onlyInGroup
                                end,
                                set = function(_, value)
                                    RaidFrameManager.db.onlyInGroup = value
                                    onChange()
                                end,
                            },
                            onlyInRaid = {
                                order = 2,
                                type = "toggle",
                                width = "full",
                                name = "Only show in a raid",
                                desc = "Hides the bar unless you are in a raid group.",
                                disabled = function()
                                    return not RaidFrameManager.db.onlyInGroup
                                end,
                                get = function()
                                    return RaidFrameManager.db.onlyInRaid
                                end,
                                set = function(_, value)
                                    RaidFrameManager.db.onlyInRaid = value
                                    onChange()
                                end,
                            },
                            mouseover = {
                                order = 3,
                                type = "toggle",
                                width = "full",
                                name = "Show on mouseover only",
                                desc = "Keeps the bar invisible until you move the cursor over it.",
                                get = function()
                                    return RaidFrameManager.db.mouseover
                                end,
                                set = function(_, value)
                                    RaidFrameManager.db.mouseover = value
                                    onChange()
                                end,
                            },
                            mouseoverAlpha = {
                                order = 4,
                                type = "range",
                                width = 0.75,
                                name = "Mouseover alpha",
                                desc = "How visible the bar is while the cursor is over it.",
                                min = 0,
                                max = 1,
                                step = 0.05,
                                isPercent = true,
                                disabled = function()
                                    return not RaidFrameManager.db.mouseover
                                end,
                                get = function()
                                    return RaidFrameManager.db.mouseoverAlpha
                                end,
                                set = function(_, value)
                                    RaidFrameManager.db.mouseoverAlpha = value
                                    onChange()
                                end,
                            },
                            mouseoverFadeAlpha = {
                                order = 5,
                                type = "range",
                                width = 0.75,
                                name = "Faded alpha",
                                desc = "How visible the bar is while the cursor is elsewhere.",
                                min = 0,
                                max = 1,
                                step = 0.05,
                                isPercent = true,
                                disabled = function()
                                    return not RaidFrameManager.db.mouseover
                                end,
                                get = function()
                                    return RaidFrameManager.db.mouseoverFadeAlpha
                                end,
                                set = function(_, value)
                                    RaidFrameManager.db.mouseoverFadeAlpha = value
                                    onChange()
                                end,
                            },
                            showTooltips = {
                                order = 6,
                                type = "toggle",
                                width = "full",
                                name = "Show tooltips",
                                desc = "Shows what a button does, and why it is dimmed, when you hover it.",
                                get = function()
                                    return RaidFrameManager.db.showTooltips
                                end,
                                set = function(_, value)
                                    RaidFrameManager.db.showTooltips = value
                                end,
                            },
                        },
                    },
                    displaySettings = {
                        type = "group",
                        name = "",
                        order = 4,
                        inline = true,
                        args = {
                            orientation = {
                                order = 1,
                                type = "select",
                                width = 0.75,
                                name = "Orientation",
                                values = RaidFrameManager.orientations,
                                get = function()
                                    return RaidFrameManager.db.orientation
                                end,
                                set = function(_, value)
                                    RaidFrameManager.db.orientation = value
                                    onChange()
                                end,
                            },
                            buttonColor = {
                                order = 2,
                                type = "color",
                                width = 0.7,
                                name = "Button color",
                                hasAlpha = true,
                                get = function()
                                    local color = RaidFrameManager.db.buttonColor
                                    return color.r, color.g, color.b, color.a
                                end,
                                set = function(_, r, g, b, a)
                                    RaidFrameManager.db.buttonColor = {
                                        r = r,
                                        g = g,
                                        b = b,
                                        a = a
                                    }
                                    onChange()
                                end,
                            },
                            textColor = {
                                order = 3,
                                type = "color",
                                width = 0.7,
                                name = "Text color",
                                hasAlpha = true,
                                get = function()
                                    local color = RaidFrameManager.db.textColor
                                    return color.r, color.g, color.b, color.a
                                end,
                                set = function(_, r, g, b, a)
                                    RaidFrameManager.db.textColor = {
                                        r = r,
                                        g = g,
                                        b = b,
                                        a = a
                                    }
                                    onChange()
                                end,
                            },
                            paddingX = {
                                order = 10,
                                type = "range",
                                width = 0.75,
                                name = "Side padding",
                                desc = "Space left and right of the label. Button width follows the widest label.",
                                min = 0,
                                max = 40,
                                step = 1,
                                get = function()
                                    return RaidFrameManager.db.paddingX
                                end,
                                set = function(_, value)
                                    RaidFrameManager.db.paddingX = value
                                    onChange()
                                end,
                            },
                            paddingY = {
                                order = 20,
                                type = "range",
                                width = 0.75,
                                name = "Top and bottom padding",
                                desc = "Space above and below the label. Button height follows the font size.",
                                min = 0,
                                max = 40,
                                step = 1,
                                get = function()
                                    return RaidFrameManager.db.paddingY
                                end,
                                set = function(_, value)
                                    RaidFrameManager.db.paddingY = value
                                    onChange()
                                end,
                            },
                            spacing = {
                                order = 30,
                                type = "range",
                                width = 0.75,
                                name = "Spacing",
                                min = 0,
                                max = 20,
                                step = 1,
                                get = function()
                                    return RaidFrameManager.db.spacing
                                end,
                                set = function(_, value)
                                    RaidFrameManager.db.spacing = value
                                    onChange()
                                end,
                            },
                        },
                    },
                    fontSettings = {
                        type = "group",
                        name = "",
                        order = 5,
                        inline = true,
                        args = XerionUIFeatures:createFontOptions(function() return RaidFrameManager.db.font end, function()
                            onChange()
                        end)
                    },
                },
            },
            actions = {
                order = 20,
                type = "group",
                name = RaidFrameManager.pageActions,
                args = {
                    preview = XerionUIFeatures:CreatePreviewOption(RaidFrameManager, 0, nil, RaidFrameManager.pageActions),
                    actionDescription = {
                        type = "description",
                        name = "Pick the buttons the bar shows. Buttons you are not allowed to press right now are dimmed.\n\n",
                        width = "full",
                        order = 1,
                    },
                    actionSettings = {
                        type = "group",
                        name = "",
                        order = 2,
                        inline = true,
                        args = actionToggles(onChange),
                    },
                },
            },
            pullTimers = {
                order = 30,
                type = "group",
                name = RaidFrameManager.pagePullTimers,
                args = {
                    preview = XerionUIFeatures:CreatePreviewOption(RaidFrameManager, 0, nil, RaidFrameManager.pagePullTimers),
                    pullDescription = {
                        type = "description",
                        name = "Each pull timer gets its own button, labelled with its duration in seconds.\n\n",
                        width = "full",
                        order = 1,
                    },
                    timerList = {
                        order = 2,
                        type = "description",
                        width = "full",
                        name = function()
                            local timers = RaidFrameManager:GetPullTimers()

                            if #timers == 0 then
                                return "|cffff8000No pull timers.|r\n"
                            end

                            return "Pull timers: " .. table.concat(timers, ", ") .. "\n"
                        end,
                    },
                    timerSettings = {
                        type = "group",
                        name = "",
                        order = 3,
                        inline = true,
                        args = {
                            addTimer = {
                                order = 1,
                                type = "input",
                                name = "Add pull timer",
                                desc = "Duration in seconds",
                                get = function()
                                    return ""
                                end,
                                set = function(_, value)
                                    RaidFrameManager:AddPullTimer(value)
                                    onChange()
                                end,
                            },
                            removeTimer = {
                                order = 2,
                                type = "select",
                                name = "Remove pull timer",
                                values = pullTimerValues,
                                disabled = function()
                                    return #RaidFrameManager:GetPullTimers() == 0
                                end,
                                get = function()
                                    return nil
                                end,
                                set = function(_, value)
                                    RaidFrameManager:RemovePullTimer(value)
                                    onChange()
                                end,
                            },
                            resetTimers = {
                                order = 3,
                                type = "execute",
                                width = 0.75,
                                name = "Restore defaults",
                                func = function()
                                    RaidFrameManager:ResetPullTimers()
                                    onChange()
                                end,
                            },
                        },
                    },
                    pullSettings = {
                        type = "group",
                        name = "",
                        order = 4,
                        inline = true,
                        args = {
                            cancelPull = {
                                order = 1,
                                type = "toggle",
                                width = "full",
                                name = "Show a cancel button",
                                desc = "Adds a button that stops a running pull timer.",
                                get = function()
                                    return RaidFrameManager.db.cancelPull
                                end,
                                set = function(_, value)
                                    RaidFrameManager.db.cancelPull = value
                                    onChange()
                                end,
                            },
                        },
                    },
                },
            },
        }
    }
end
