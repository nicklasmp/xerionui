local addonName, XerionUIFeatures = ...

local moduleName = "KeystoneLister"
local KeystoneLister = XerionUIFeatures:GetModule(moduleName)

function KeystoneLister:GetOptions(onChange)
    return {
        order = 3,
        type = "group",
        name = "Keystone Lister",
        childGroups = "tab",
        args = {
            description = {
                type = "description",
                name = "A movable button that lists a keystone in the group finder without opening it. Clicking it opens a menu of every key in the group; the listing goes up and Blizzard's edit screen opens on it, since the title is the one field no addon may set. Once you are listed the same button delists. Group members only appear if they run an addon that shares keystones, and listing needs you solo or leading the group\n\n",
                width = "full",
                order = 1,
            },
            enable = {
                order = 2,
                type = "toggle",
                width = "full",
                name = "Enable",
                get = function()
                    return KeystoneLister.db.enabled
                end,
                set = function(_, value)
                    KeystoneLister.db.enabled = value
                    KeystoneLister:RefreshConfig()
                end
            },
            display = {
                order = 10,
                type = "group",
                name = KeystoneLister.pageDisplay,
                args = {
                    preview = XerionUIFeatures:CreatePreviewOption(KeystoneLister, 0, nil, KeystoneLister.pageDisplay),
                    behaviourSettings = {
                        type = "group",
                        name = "",
                        order = 3,
                        inline = true,
                        args = {
                            mouseover = {
                                order = 3,
                                type = "toggle",
                                width = "full",
                                name = "Show on mouseover only",
                                desc = "Keeps the button invisible until you move the cursor over it.",
                                get = function()
                                    return KeystoneLister.db.mouseover
                                end,
                                set = function(_, value)
                                    KeystoneLister.db.mouseover = value
                                    onChange()
                                end,
                            },
                            mouseoverAlpha = {
                                order = 4,
                                type = "range",
                                width = 0.75,
                                name = "Mouseover alpha",
                                min = 0,
                                max = 1,
                                step = 0.05,
                                isPercent = true,
                                disabled = function()
                                    return not KeystoneLister.db.mouseover
                                end,
                                get = function()
                                    return KeystoneLister.db.mouseoverAlpha
                                end,
                                set = function(_, value)
                                    KeystoneLister.db.mouseoverAlpha = value
                                    onChange()
                                end,
                            },
                            mouseoverFadeAlpha = {
                                order = 5,
                                type = "range",
                                width = 0.75,
                                name = "Faded alpha",
                                min = 0,
                                max = 1,
                                step = 0.05,
                                isPercent = true,
                                disabled = function()
                                    return not KeystoneLister.db.mouseover
                                end,
                                get = function()
                                    return KeystoneLister.db.mouseoverFadeAlpha
                                end,
                                set = function(_, value)
                                    KeystoneLister.db.mouseoverFadeAlpha = value
                                    onChange()
                                end,
                            },
                            showTooltips = {
                                order = 6,
                                type = "toggle",
                                width = "full",
                                name = "Show tooltips",
                                get = function()
                                    return KeystoneLister.db.showTooltips
                                end,
                                set = function(_, value)
                                    KeystoneLister.db.showTooltips = value
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
                            buttonColor = {
                                order = 1,
                                type = "color",
                                width = 0.7,
                                name = "Button color",
                                hasAlpha = true,
                                get = function()
                                    local color = KeystoneLister.db.buttonColor
                                    return color.r, color.g, color.b, color.a
                                end,
                                set = function(_, r, g, b, a)
                                    KeystoneLister.db.buttonColor = {r = r, g = g, b = b, a = a}
                                    onChange()
                                end,
                            },
                            textColor = {
                                order = 2,
                                type = "color",
                                width = 0.7,
                                name = "Text color",
                                hasAlpha = true,
                                get = function()
                                    local color = KeystoneLister.db.textColor
                                    return color.r, color.g, color.b, color.a
                                end,
                                set = function(_, r, g, b, a)
                                    KeystoneLister.db.textColor = {r = r, g = g, b = b, a = a}
                                    onChange()
                                end,
                            },
                            paddingX = {
                                order = 10,
                                type = "range",
                                width = 0.75,
                                name = "Side padding",
                                min = 0,
                                max = 40,
                                step = 1,
                                get = function()
                                    return KeystoneLister.db.paddingX
                                end,
                                set = function(_, value)
                                    KeystoneLister.db.paddingX = value
                                    onChange()
                                end,
                            },
                            paddingY = {
                                order = 20,
                                type = "range",
                                width = 0.75,
                                name = "Top and bottom padding",
                                min = 0,
                                max = 40,
                                step = 1,
                                get = function()
                                    return KeystoneLister.db.paddingY
                                end,
                                set = function(_, value)
                                    KeystoneLister.db.paddingY = value
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
                        args = XerionUIFeatures:createFontOptions(function() return KeystoneLister.db.font end, function()
                            onChange()
                        end)
                    },
                },
            },
            listing = {
                order = 20,
                type = "group",
                name = KeystoneLister.pageListing,
                args = {
                    preview = XerionUIFeatures:CreatePreviewOption(KeystoneLister, 0, nil, KeystoneLister.pageListing),
                    requirementDescription = {
                        type = "description",
                        name = "What the listing asks of applicants. Both are capped at your own item level and rating when the listing goes out, since the group finder refuses a listing you would not qualify for yourself.\n\n",
                        width = "full",
                        order = 1,
                    },
                    listingSettings = {
                        type = "group",
                        name = "",
                        order = 2,
                        inline = true,
                        args = {
                            itemLevel = {
                                order = 1,
                                type = "range",
                                width = 0.9,
                                name = "Required item level",
                                desc = "0 asks for none.",
                                min = 0,
                                max = 1000,
                                step = 1,
                                get = function()
                                    return KeystoneLister.db.itemLevel
                                end,
                                set = function(_, value)
                                    KeystoneLister.db.itemLevel = value
                                end,
                            },
                            requiredRating = {
                                order = 2,
                                type = "range",
                                width = 0.9,
                                name = "Required mythic+ rating",
                                desc = "0 asks for none.",
                                min = 0,
                                max = 5000,
                                step = 10,
                                get = function()
                                    return KeystoneLister.db.requiredRating
                                end,
                                set = function(_, value)
                                    KeystoneLister.db.requiredRating = value
                                end,
                            },
                            playstyle = {
                                order = 10,
                                type = "select",
                                width = 1.2,
                                name = "Playstyle",
                                desc = "The tag applicants see on the listing.",
                                values = function()
                                    return KeystoneLister:GetPlaystyles()
                                end,
                                sorting = KeystoneLister.playstyleOrder,
                                get = function()
                                    return KeystoneLister.db.playstyle
                                end,
                                set = function(_, value)
                                    KeystoneLister.db.playstyle = value
                                end,
                            },
                        },
                    },
                },
            },
        }
    }
end
