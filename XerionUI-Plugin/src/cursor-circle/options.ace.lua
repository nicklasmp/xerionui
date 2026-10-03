local addonName, XerionUIFeatures = ...
local LSM = XerionUIFeatures.LSM

local moduleName = "CursorCircle"
local CursorCircle = XerionUIFeatures:GetModule(moduleName)

function CursorCircle:GetOptions(onChange)
    return {
        order = 2,
        type = "group",
        name = "Cursor Circle",
        args = {
            preview = XerionUIFeatures:CreatePreviewOption(CursorCircle),
            description = {
                type = "description",
                name = "Puts a circle arounds your cursor \n\n",
                width = "full",
                order = 1,
            },
            enableGroup = {
                order = 2,
                type = "group",
                name = "",
                inline = true,
                args = {
                    enable = {
                        order = 1,
                        type = "toggle",
                        width = 0.4,
                        name = "Enable",
                        get = function()
                            return CursorCircle.db.enabled
                        end,
                        set = function(_, value)
                            CursorCircle.db.enabled = value
                            CursorCircle:RefreshConfig()
                        end
                    },
                    onlyDuringCombat = {
                        order = 2,
                        type = "toggle",
                        width = 1,
                        name = "Only during combat",
                        get = function()
                            return CursorCircle.db.onlyDuringCombat
                        end,
                        set = function(_, value)
                            CursorCircle.db.onlyDuringCombat = value
                            onChange()
                        end
                    },
                }
            },
            displaySettings = {
                type = "group",
                name = "",
                order = 4,
                inline = true,
                args = {
                    displayTexture = {
                        order = 1,
                        type = "select",
                        values = CursorCircle.CursorTextures,
                        name = "Display texture",
                        get = function()
                            return CursorCircle.db.displayTexture
                        end,
                        set = function(_, value)
                            CursorCircle.db.displayTexture = value
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
                            local color = CursorCircle.db.color
                            return color.r, color.g, color.b, color.a
                        end,
                        set = function(_, r, g, b, a)
                            CursorCircle.db.color = {
                                r = r,
                                g = g,
                                b = b,
                                a = a
                            }
                            onChange()
                        end
                    },
                    size = {
                        order = 3,
                        type = "range",
                        width = 0.75,
                        name = "Size",
                        min = 10,
                        max = 100,
                        step = 1,
                        get = function()
                            return CursorCircle.db.size
                        end,
                        set = function(_, value)
                            CursorCircle.db.size = value
                            
                            if onChange then
                                onChange()
                            end
                        end
                    },
                }
            },
        }
    }
end