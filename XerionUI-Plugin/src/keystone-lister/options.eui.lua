local addonName, XerionUIFeatures = ...

local moduleName = "KeystoneLister"
local KeystoneLister = XerionUIFeatures:GetModule(moduleName)

KeystoneLister.EUIPages = {
    KeystoneLister.pageDisplay,
    KeystoneLister.pageListing,
}

local function displayRows(apply, onChange)
    local buttonColorRow = {
        type = "color",
        label = "Button color",
        hasAlpha = true,
        get = function()
            local color = KeystoneLister.db.buttonColor
            return color.r, color.g, color.b, color.a
        end,
        set = function(r, g, b, a)
            KeystoneLister.db.buttonColor = {r = r, g = g, b = b, a = a}
            apply()
        end,
    }

    local textColorRow = {
        type = "color",
        label = "Text color",
        hasAlpha = true,
        get = function()
            local color = KeystoneLister.db.textColor
            return color.r, color.g, color.b, color.a
        end,
        set = function(r, g, b, a)
            KeystoneLister.db.textColor = {r = r, g = g, b = b, a = a}
            apply()
        end,
    }

    return {
        {
            type = "toggle",
            label = "Show tooltips",
            tooltip = "Shows what the button does, and why it is dimmed, when you hover it.",
            get = function()
                return KeystoneLister.db.showTooltips
            end,
            set = function(value)
                KeystoneLister.db.showTooltips = value
            end,
        },
        {
            type = "toggle",
            label = "Mouseover only",
            tooltip = "Keeps the button invisible until you move the cursor over it.",
            get = function()
                return KeystoneLister.db.mouseover
            end,
            set = function(value)
                KeystoneLister.db.mouseover = value
                onChange()
            end,
            cog = {
                title = "Mouseover Alpha",
                rows = {
                    {
                        type = "slider",
                        label = "Hovered",
                        min = 0,
                        max = 1,
                        step = 0.05,
                        disabled = function()
                            return not KeystoneLister.db.mouseover
                        end,
                        disabledTooltip = "Mouseover only",
                        get = function()
                            return KeystoneLister.db.mouseoverAlpha
                        end,
                        set = function(value)
                            KeystoneLister.db.mouseoverAlpha = value
                            onChange()
                        end,
                    },
                    {
                        type = "slider",
                        label = "Faded",
                        min = 0,
                        max = 1,
                        step = 0.05,
                        disabled = function()
                            return not KeystoneLister.db.mouseover
                        end,
                        disabledTooltip = "Mouseover only",
                        get = function()
                            return KeystoneLister.db.mouseoverFadeAlpha
                        end,
                        set = function(value)
                            KeystoneLister.db.mouseoverFadeAlpha = value
                            onChange()
                        end,
                    },
                },
            },
        },
        {
            type = "slider",
            label = "Padding",
            tooltip = "Space left and right of the label. The button sizes itself around it.",
            min = 0,
            max = 40,
            step = 1,
            get = function()
                return KeystoneLister.db.paddingX
            end,
            set = function(value)
                KeystoneLister.db.paddingX = value
                apply()
            end,
            cog = {
                title = "Padding",
                icon = XerionUIFeatures.EUI and XerionUIFeatures.EUI.RESIZE_ICON,
                rows = {
                    {
                        type = "slider",
                        label = "Top and bottom",
                        min = 0,
                        max = 40,
                        step = 1,
                        get = function()
                            return KeystoneLister.db.paddingY
                        end,
                        set = function(value)
                            KeystoneLister.db.paddingY = value
                            apply()
                        end,
                    },
                },
            },
        },
        {
            header = "Font",
            rows = XerionUIFeatures:EUIFontRows(function() return KeystoneLister.db.font end, apply, nil, { buttonColorRow, textColorRow }),
        },
    }
end

local function listingRows()
    return {
        { text = "What the listing asks of applicants. Both are capped at your own item level and rating when the listing goes out, since the group finder refuses a listing you would not qualify for yourself." },
        {
            pair = {
                {
                    type = "slider",
                    label = "Item level",
                    tooltip = "0 asks for none.",
                    min = 0,
                    max = 1000,
                    step = 1,
                    get = function()
                        return KeystoneLister.db.itemLevel
                    end,
                    set = function(value)
                        KeystoneLister.db.itemLevel = value
                    end,
                },
                {
                    type = "slider",
                    label = "Mythic+ rating",
                    tooltip = "0 asks for none.",
                    min = 0,
                    max = 5000,
                    step = 10,
                    get = function()
                        return KeystoneLister.db.requiredRating
                    end,
                    set = function(value)
                        KeystoneLister.db.requiredRating = value
                    end,
                },
            },
        },
        {
            type = "select",
            label = "Playstyle",
            tooltip = "The tag applicants see on the listing.",
            values = KeystoneLister:GetPlaystyles(),
            order = KeystoneLister.playstyleOrder,
            get = function()
                return KeystoneLister.db.playstyle
            end,
            set = function(value)
                KeystoneLister.db.playstyle = value
            end,
        },
    }
end

function KeystoneLister:GetEUIOptions(pageName)
    local function apply() XerionUIFeatures:ApplyModuleStyles(moduleName) end

    -- Visibility is not a style, so the rows that change it go through
    -- RefreshConfig the way the ace `set` does.
    local function onChange() KeystoneLister:RefreshConfig() end

    if pageName == KeystoneLister.pageListing then
        return {
            name = "Keystone Lister",
            rows = listingRows(),
        }
    end

    return {
        name = "Keystone Lister",
        rows = displayRows(apply, onChange),
    }
end
