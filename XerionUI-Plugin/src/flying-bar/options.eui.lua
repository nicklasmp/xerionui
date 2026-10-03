local addonName, XerionUIFeatures = ...

local moduleName = "FlyingBar"
local FlyingBar = XerionUIFeatures:GetModule(moduleName)

function FlyingBar:GetEUIOptions()
    local function apply() XerionUIFeatures:ApplyModuleStyles(moduleName) end

    -- One row per bar: its colour beside its texture, with the bar's height on the
    -- texture's cogwheel.
    local function statusbarRows(key)
        local textureRow = XerionUIFeatures:EUIStatusbarRow({
            label = "Texture",
            get = function()
                return FlyingBar.db[key].statusbarTexture
            end,
            set = function(value)
                FlyingBar.db[key].statusbarTexture = value
                apply()
            end,
        })

        textureRow.cog = {
            title = "Bar Size",
            rows = {
                {
                    type = "slider",
                    label = "Height",
                    min = 3,
                    max = 20,
                    step = 1,
                    get = function()
                        return FlyingBar.db[key].height
                    end,
                    set = function(value)
                        FlyingBar.db[key].height = value
                        apply()
                    end,
                },
            },
        }

        return {
            {
                pair = {
                    {
                        type = "color",
                        label = "Color",
                        hasAlpha = true,
                        get = function()
                            local color = FlyingBar.db[key].color
                            return color.r, color.g, color.b, color.a
                        end,
                        set = function(r, g, b, a)
                            FlyingBar.db[key].color = {
                                r = r,
                                g = g,
                                b = b,
                                a = a,
                            }
                            apply()
                        end,
                    },
                    textureRow,
                },
            },
        }
    end

    return {
        name = "Flying Bar",
        rows = {
            {
                text = "Dragonflying bar",
            },
            {
                pair = {
                    {
                        type = "slider",
                        label = "Width",
                        min = 10,
                        max = 500,
                        step = 1,
                        get = function()
                            return FlyingBar.db.width
                        end,
                        set = function(value)
                            FlyingBar.db.width = value
                            apply()
                        end,
                    },
                    {
                        type = "select",
                        label = "Frame strata",
                        values = XerionUIFeatures.FrameStrataSettings,
                        get = function()
                            return FlyingBar.db.frameStrata or XerionUIFeatures.FrameStrataSettings.BACKGROUND
                        end,
                        set = function(value)
                            FlyingBar.db.frameStrata = value
                            apply()
                        end,
                        cog = {
                            title = "Frame Settings",
                            rows = {
                                {
                                    type = "slider",
                                    label = "Frame level",
                                    min = 1,
                                    max = 10,
                                    step = 1,
                                    get = function()
                                        return FlyingBar.db.frameLevel or 1
                                    end,
                                    set = function(value)
                                        FlyingBar.db.frameLevel = value
                                        apply()
                                    end,
                                },
                            },
                        },
                    },
                },
            },
            {
                header = "Vigor",
                rows = statusbarRows("vigor"),
            },
            {
                header = "Second Wind",
                rows = statusbarRows("secondWind"),
            },
            {
                header = "Speed",
                rows = statusbarRows("speed"),
            },
        },
    }
end
