local addonName, XerionUIFeatures = ...

local moduleName = "SummonHelper"
local SummonHelper = XerionUIFeatures:GetModule(moduleName)

function SummonHelper:GetOptions(onChange)
    return {
        order = 2,
        type = "group",
        name = "Summon Helper",
        args = {
            preview = XerionUIFeatures:CreatePreviewOption(SummonHelper),
            description = {
                type = "description",
                name = "Highlight raid frames when someone asks for a summon and tells the Warlock to put up a Summon Stone\n\n",
                width = "full",
                order = 1,
            },
            enable = {
                order = 2,
                type = "toggle",
                width = "full",
                name = "Enable",
                get = function()
                    return SummonHelper.db.enabled
                end,
                set = function(_, value)
                    SummonHelper.db.enabled = value
                    SummonHelper:RefreshConfig()
                end,
            },
            highlight = {
                order = 3,
                type = "group",
                name = "Highlight",
                inline = true,
                args = {
                    phrases = {
                        order = 1,
                        type = "input",
                        width = "full",
                        name = "Phrases",
                        desc = "Comma separated. A chat message containing any of these counts as asking for a summon",
                        get = function()
                            return SummonHelper.db.phrases
                        end,
                        set = function(_, value)
                            SummonHelper.db.phrases = value
                            SummonHelper.phrases = nil
                        end,
                    },
                    duration = {
                        order = 2,
                        type = "range",
                        name = "Duration",
                        desc = "For how many seconds the highlight and the reminder stay on screen",
                        min = 5,
                        max = 60,
                        step = 1,
                        get = function()
                            return SummonHelper.db.duration
                        end,
                        set = function(_, value)
                            SummonHelper.db.duration = value
                        end,
                    },
                    style = {
                        order = 3,
                        type = "select",
                        name = "Style",
                        values = {
                            BORDER = "Border",
                            PIXEL = "Pixel Glow",
                            AUTOCAST = "Auto-Cast Shine",
                        },
                        sorting = {"BORDER", "PIXEL", "AUTOCAST"},
                        get = function()
                            return SummonHelper.db.style
                        end,
                        set = function(_, value)
                            SummonHelper.db.style = value
                            onChange()
                        end,
                    },
                    spacing = {
                        order = 4,
                        type = "range",
                        name = "Spacing",
                        desc = "Grows the highlight past the frame's edge, negative pulls it inside",
                        min = -5,
                        max = 5,
                        step = 1,
                        get = function()
                            return SummonHelper.db.spacing
                        end,
                        set = function(_, value)
                            SummonHelper.db.spacing = value
                            onChange()
                        end,
                    },
                    borderThickness = {
                        order = 5,
                        type = "range",
                        name = "Thickness",
                        min = 1,
                        max = 8,
                        step = 1,
                        hidden = function()
                            return SummonHelper.db.style ~= "BORDER"
                        end,
                        get = function()
                            return SummonHelper.db.border.thickness
                        end,
                        set = function(_, value)
                            SummonHelper.db.border.thickness = value
                            onChange()
                        end,
                    },
                    borderColor = {
                        order = 6,
                        type = "color",
                        name = "Color",
                        hasAlpha = true,
                        hidden = function()
                            return SummonHelper.db.style ~= "BORDER"
                        end,
                        get = function()
                            local color = SummonHelper.db.border.color

                            return color.r, color.g, color.b, color.a
                        end,
                        set = function(_, r, g, b, a)
                            SummonHelper.db.border.color = {r = r, g = g, b = b, a = a}
                            onChange()
                        end,
                    },
                    pixelLines = {
                        order = 7,
                        type = "range",
                        name = "Lines",
                        min = 4,
                        max = 16,
                        step = 1,
                        hidden = function()
                            return SummonHelper.db.style ~= "PIXEL"
                        end,
                        get = function()
                            return SummonHelper.db.pixel.lines
                        end,
                        set = function(_, value)
                            SummonHelper.db.pixel.lines = value
                            onChange()
                        end,
                    },
                    pixelThickness = {
                        order = 8,
                        type = "range",
                        name = "Thickness",
                        min = 1,
                        max = 8,
                        step = 1,
                        hidden = function()
                            return SummonHelper.db.style ~= "PIXEL"
                        end,
                        get = function()
                            return SummonHelper.db.pixel.thickness
                        end,
                        set = function(_, value)
                            SummonHelper.db.pixel.thickness = value
                            onChange()
                        end,
                    },
                    pixelSpeed = {
                        order = 9,
                        type = "range",
                        name = "Speed",
                        desc = "Seconds for a full march around the frame, lower is faster",
                        min = 1,
                        max = 10,
                        step = 0.5,
                        hidden = function()
                            return SummonHelper.db.style ~= "PIXEL"
                        end,
                        get = function()
                            return SummonHelper.db.pixel.speed
                        end,
                        set = function(_, value)
                            SummonHelper.db.pixel.speed = value
                            onChange()
                        end,
                    },
                    pixelColor = {
                        order = 10,
                        type = "color",
                        name = "Color",
                        hidden = function()
                            return SummonHelper.db.style ~= "PIXEL"
                        end,
                        get = function()
                            local color = SummonHelper.db.pixel.color

                            return color.r, color.g, color.b, color.a
                        end,
                        set = function(_, r, g, b)
                            SummonHelper.db.pixel.color = {r = r, g = g, b = b, a = 1}
                            onChange()
                        end,
                    },
                },
            },
            stone = {
                order = 4,
                type = "group",
                name = "Summoning Stone",
                inline = true,
                args = XerionUIFeatures:createFontOptions(function() return SummonHelper.db.font end, function()
                    onChange()
                end, {
                    stoneReminder = {
                        order = 1,
                        type = "toggle",
                        width = "full",
                        name = "Remind me to put down a summoning stone",
                        desc = "Warlock only. Shown when someone asks for a summon, unless the stone is on cooldown or the reminder already showed in the last 5 minutes",
                        get = function()
                            return SummonHelper.db.stoneReminder
                        end,
                        set = function(_, value)
                            SummonHelper.db.stoneReminder = value
                        end,
                    },
                    messageText = {
                        order = 2,
                        type = "input",
                        width = "full",
                        name = "Message",
                        get = function()
                            return SummonHelper.db.messageText
                        end,
                        set = function(_, value)
                            SummonHelper.db.messageText = value
                            onChange()
                        end,
                    },
                    textColor = {
                        order = 3,
                        type = "color",
                        name = "Message color",
                        hasAlpha = true,
                        get = function()
                            local color = SummonHelper.db.textColor

                            return color.r, color.g, color.b, color.a
                        end,
                        set = function(_, r, g, b, a)
                            SummonHelper.db.textColor = {r = r, g = g, b = b, a = a}
                            onChange()
                        end,
                    },
                }),
            },
        }
    }
end
