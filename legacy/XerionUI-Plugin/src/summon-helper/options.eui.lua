local addonName, XerionUIFeatures = ...

local moduleName = "SummonHelper"
local SummonHelper = XerionUIFeatures:GetModule(moduleName)

function SummonHelper:GetEUIOptions()
    local function apply()
        XerionUIFeatures:ApplyModuleStyles(moduleName)
    end

    -- The cog follows the selected style, which is why the style select carries
    -- rebuild: only Border and Pixel Glow have settings of their own.
    local function buildStyleCog()
        if SummonHelper.db.style == "PIXEL" then
            return {
                title = "Pixel Glow",
                rows = {
                    {
                        type = "slider",
                        label = "Lines",
                        min = 4,
                        max = 16,
                        step = 1,
                        get = function()
                            return SummonHelper.db.pixel.lines
                        end,
                        set = function(value)
                            SummonHelper.db.pixel.lines = value
                            apply()
                        end,
                    },
                    {
                        type = "slider",
                        label = "Thickness",
                        min = 1,
                        max = 8,
                        step = 1,
                        get = function()
                            return SummonHelper.db.pixel.thickness
                        end,
                        set = function(value)
                            SummonHelper.db.pixel.thickness = value
                            apply()
                        end,
                    },
                    {
                        type = "slider",
                        label = "Speed",
                        tooltip = "Seconds for a full march around the frame, lower is faster",
                        min = 1,
                        max = 10,
                        step = 0.5,
                        get = function()
                            return SummonHelper.db.pixel.speed
                        end,
                        set = function(value)
                            SummonHelper.db.pixel.speed = value
                            apply()
                        end,
                    },
                    {
                        type = "color",
                        label = "Color",
                        get = function()
                            local color = SummonHelper.db.pixel.color

                            return color.r, color.g, color.b, color.a
                        end,
                        set = function(r, g, b)
                            SummonHelper.db.pixel.color = {r = r, g = g, b = b, a = 1}
                            apply()
                        end,
                    },
                },
            }
        end

        return {
            title = "Border",
            disabled = function()
                return SummonHelper.db.style ~= "BORDER"
            end,
            disabledTooltip = "Only Border and Pixel Glow have settings of their own.",
            rows = {
                {
                    type = "slider",
                    label = "Thickness",
                    min = 1,
                    max = 8,
                    step = 1,
                    get = function()
                        return SummonHelper.db.border.thickness
                    end,
                    set = function(value)
                        SummonHelper.db.border.thickness = value
                        apply()
                    end,
                },
                {
                    type = "color",
                    label = "Color",
                    hasAlpha = true,
                    get = function()
                        local color = SummonHelper.db.border.color

                        return color.r, color.g, color.b, color.a
                    end,
                    set = function(r, g, b, a)
                        SummonHelper.db.border.color = {r = r, g = g, b = b, a = a}
                        apply()
                    end,
                },
            },
        }
    end

    local textColorRow = {
        type = "color",
        label = "Message color",
        hasAlpha = true,
        get = function()
            local color = SummonHelper.db.textColor

            return color.r, color.g, color.b, color.a
        end,
        set = function(r, g, b, a)
            SummonHelper.db.textColor = {r = r, g = g, b = b, a = a}
            apply()
        end,
    }

    return {
        name = "Summon Helper",
        rows = {
            {
                type = "toggle",
                label = "Enable",
                get = function()
                    return SummonHelper.db.enabled
                end,
                set = function(value)
                    SummonHelper.db.enabled = value
                    SummonHelper:RefreshConfig()
                end,
            },
            { header = "Highlight" },
            {
                type = "input",
                label = "Phrases",
                tooltip = "Comma separated. A chat message containing any of these counts as asking for a summon",
                get = function()
                    return SummonHelper.db.phrases
                end,
                set = function(value)
                    SummonHelper.db.phrases = value
                    SummonHelper.phrases = nil
                end,
            },
            {
                pair = {
                    {
                        type = "slider",
                        label = "Duration",
                        tooltip = "For how many seconds the highlight and the reminder stay on screen",
                        min = 5,
                        max = 60,
                        step = 1,
                        get = function()
                            return SummonHelper.db.duration
                        end,
                        set = function(value)
                            SummonHelper.db.duration = value
                        end,
                    },
                    {
                        type = "select",
                        label = "Style",
                        rebuild = true,
                        values = {
                            BORDER = "Border",
                            PIXEL = "Pixel Glow",
                            AUTOCAST = "Auto-Cast Shine",
                        },
                        order = {"BORDER", "PIXEL", "AUTOCAST"},
                        get = function()
                            return SummonHelper.db.style
                        end,
                        set = function(value)
                            SummonHelper.db.style = value
                            apply()
                        end,
                        cog = buildStyleCog(),
                    },
                },
            },
            {
                pair = {
                    {
                        type = "slider",
                        label = "Spacing",
                        tooltip = "Grows the highlight past the frame's edge, negative pulls it inside",
                        min = -5,
                        max = 5,
                        step = 1,
                        get = function()
                            return SummonHelper.db.spacing
                        end,
                        set = function(value)
                            SummonHelper.db.spacing = value
                            apply()
                        end,
                    },
                    { type = "empty" },
                },
            },
            {
                header = "Summoning Stone",
                rows = XerionUIFeatures:EUIFontRows(function() return SummonHelper.db.font end, apply, nil, {
                    {
                        type = "toggle",
                        label = "Stone reminder",
                        tooltip = "Warlock only. Shown when someone asks for a summon, unless the stone is on cooldown or the reminder already showed in the last 5 minutes",
                        get = function()
                            return SummonHelper.db.stoneReminder
                        end,
                        set = function(value)
                            SummonHelper.db.stoneReminder = value
                        end,
                    },
                    {
                        type = "input",
                        label = "Message",
                        get = function()
                            return SummonHelper.db.messageText
                        end,
                        set = function(value)
                            SummonHelper.db.messageText = value
                            apply()
                        end,
                    },
                    textColorRow,
                }),
            },
        },
    }
end
