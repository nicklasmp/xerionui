local addonName, XerionUIFeatures = ...

local moduleName = "CursorCircle"
local CursorCircle = XerionUIFeatures:GetModule(moduleName)

function CursorCircle:GetEUIOptions()
    local function apply() 
        XerionUIFeatures:ApplyModuleStyles(moduleName)
    end

    return {
        name = "Cursor Circle",
        rows = {
            {
                text = "Puts a circle arounds your cursor",
            },
            {
                type = "toggle",
                label = "Only during combat",
                get = function()
                    return CursorCircle.db.onlyDuringCombat
                end,
                set = function(value)
                    CursorCircle.db.onlyDuringCombat = value
                    apply()
                end,
            },
            {
                pair = {
                    {
                        type = "select",
                        label = "Thickness & Size",
                        values = CursorCircle.CursorTextures,
                        get = function()
                            return CursorCircle.db.displayTexture
                        end,
                        set = function(value)
                            CursorCircle.db.displayTexture = value
                            apply()
                        end,
                        cog = {
                            title = "Circle Size",
                            rows = {
                                {
                                    type = "slider",
                                    label = "Size",
                                    min = 10,
                                    max = 100,
                                    step = 1,
                                    get = function()
                                        return CursorCircle.db.size
                                    end,
                                    set = function(value)
                                        CursorCircle.db.size = value
                                        apply()
                                    end,
                                },
                            },
                        },
                    },
                    {
                        type = "color",
                        label = "Color",
                        hasAlpha = true,
                        get = function()
                            local color = CursorCircle.db.color
                            return color.r, color.g, color.b, color.a
                        end,
                        set = function(r, g, b, a)
                            CursorCircle.db.color = {
                                r = r,
                                g = g,
                                b = b,
                                a = a,
                            }
                            apply()
                        end,
                    },
                },
            },
        },
    }
end
